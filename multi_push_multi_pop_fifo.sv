
/*
 * Description : FIFO with multiple simultaneous pushes and pops
 * Author      : Deltsov Ignatiy
 */


interface multi_push_multi_pop_fifo_iface
    #(
        parameter DATA_WIDTH = 13,
        parameter N          = 3,
        parameter NW         = $clog2 (N + 1),
        parameter DW         = DATA_WIDTH
    )
    (
        input wire clk_i,
        input wire rst_i
    );

    logic [NW-1:0]         push_l;
    logic [ N-1:0][DW-1:0] push_data_l;
    logic [NW-1:0]         pop_l;
    wire  [ N-1:0][DW-1:0] pop_data_w;
    wire  [NW-1:0]         can_push_w;
    wire  [NW-1:0]         can_pop_w;

endinterface


module multi_push_multi_pop_fifo
    #(
        parameter DATA_WIDTH = 13,                // Размер слова данных ФИФО
        parameter FIFO_DEPTH = 19,                // Глубина ФИФО
        parameter N          = 3,                 // Максимальное количество одновременных операций чтения и/или записи,
                                                  // подразумевается, что FIFO_DEPTH > N
        parameter NW         = $clog2 (N + 1),
        parameter DW         = DATA_WIDTH
    )
    (
        input  wire                  clk_i,       // Сигнал тактирования
        input  wire                  rst_i,       // Сигнал сброса

        input  wire [NW-1:0]         push_i,      // Запсиать слова данных в ФИФО
        input  wire [ N-1:0][DW-1:0] push_data_i, // Записываемые в ФИФО слова данных

        input  wire [NW-1:0]         pop_i,       // Прочитать слова данных из ФИФО
        output wire [ N-1:0][DW-1:0] pop_data_o,  // Читаемые из ФИФО слова данных

        output wire [NW-1:0]         can_push_o,  // Доступное для записи количество слов данных
        output wire [NW-1:0]         can_pop_o    // Доступное для чтения количество слов данных
    );


    localparam PW    = $clog2(FIFO_DEPTH); // FIFO POINTER WIDTH
    localparam PTHRS = FIFO_DEPTH - 1'b1;  // FIFO POINTER THRESHOLD


    wire           dont_push_w;
    wire           dont_pop_w;
    wire           do_push_w;
    wire           do_pop_w;

    logic [PW-1:0] counter_l;
    wire  [PW-1:0] counter_next_w;
    wire  [PW-1:0] counter_remainder_w;

    wire  [NW-1:0] wr_update_w;
    wire  [NW-1:0] rd_update_w;

    logic [PW-1:0] wr_ptr_l;
    wire  [PW-1:0] wr_ptr_remainder_w;
    wire  [PW-1:0] wr_ptr_next_w;
    wire           wr_ptr_edge_cross_w;

    logic [PW-1:0] rd_ptr_l;
    wire  [PW-1:0] rd_ptr_remainder_w;
    wire  [PW-1:0] rd_ptr_next_w;
    wire           rd_ptr_edge_cross_w;

    logic [NW-1:0] can_push_l;
    wire  [NW-1:0] can_push_next_w;
    wire           can_push_use_rem_w;

    logic [NW-1:0] can_pop_l;
    wire  [NW-1:0] can_pop_next_w;
    wire           can_pop_use_def_w;

    wire           push_en_w        [N];
    wire  [PW-1:0] push_base_w      [N];
    wire           push_cross_edge_w[N];
    wire  [PW-1:0] push_index_w     [N];
    wire  [PW-1:0] pop_base_w       [N];
    wire           pop_cross_edge_w [N];
    wire  [PW-1:0] pop_index_w      [N];

    logic [DW-1:0] fifo_l               [FIFO_DEPTH];
    wire  [DW-1:0] fifo_next_w          [FIFO_DEPTH];
    wire           fifo_en_w            [FIFO_DEPTH][N];
    wire  [DW-1:0] fifo_data_mask_w     [FIFO_DEPTH][N];
    wire  [DW-1:0] fifo_push_data_w     [FIFO_DEPTH][N];
    logic [DW-1:0] fifo_assembled_data_w[FIFO_DEPTH];
    logic          fifo_assembled_en_w  [FIFO_DEPTH];


    // Определяем, доступно ли чтение и запись запрашиваемого количества данных
    assign dont_push_w         = (can_push_l < push_i);
    assign dont_pop_w          = (can_pop_l  < pop_i );
    assign do_push_w           = ~dont_push_w;
    assign do_pop_w            = ~dont_pop_w;

    // Маскируем изменение счётчиков, если операция недоступна
    assign wr_update_w         = push_i & {NW{do_push_w}};
    assign rd_update_w         = pop_i  & {NW{do_pop_w}};

    // Обновляем значение счётчика данных в ФИФО
    assign counter_next_w      = counter_l + wr_update_w - rd_update_w;
    assign counter_remainder_w = FIFO_DEPTH - counter_next_w;

    // Обновляем значение указателя на запись данных в ФИФО
    assign wr_ptr_remainder_w  = PTHRS - wr_ptr_l;
    assign wr_ptr_edge_cross_w = wr_update_w > wr_ptr_remainder_w;
    assign wr_ptr_next_w       = (wr_ptr_edge_cross_w) ? (wr_update_w - wr_ptr_remainder_w - 1'b1) :
                                                         (wr_update_w + wr_ptr_l);

    // Обновляем значение указателя на чтение данных из ФИФО
    assign rd_ptr_remainder_w  = PTHRS - rd_ptr_l;
    assign rd_ptr_edge_cross_w = rd_update_w > rd_ptr_remainder_w;
    assign rd_ptr_next_w       = (rd_ptr_edge_cross_w) ? (rd_update_w - rd_ptr_remainder_w - 1'b1) :
                                                         (rd_update_w + rd_ptr_l);

    // Обновляем значение доступных для записи слотов данных в ФИФО
    assign can_push_use_rem_w  = (counter_remainder_w < N);
    assign can_push_next_w     = (can_push_use_rem_w) ? counter_remainder_w[NW-1:0] : N;

    // Оновляем значение доступных для чтения слотов данных ФИФО
    assign can_pop_use_def_w   = (counter_next_w > N);
    assign can_pop_next_w      = (can_pop_use_def_w) ? N : counter_next_w[NW-1:0];

    always_ff @(posedge clk_i)
        if (rst_i) begin
            counter_l  <= {PW{1'b0}};
            wr_ptr_l   <= {PW{1'b0}};
            rd_ptr_l   <= {PW{1'b0}};
            can_push_l <= N;
            can_pop_l  <= {NW{1'b0}};
        end else begin
            counter_l  <= counter_next_w;
            wr_ptr_l   <= wr_ptr_next_w;
            rd_ptr_l   <= rd_ptr_next_w;
            can_push_l <= can_push_next_w;
            can_pop_l  <= can_pop_next_w;
        end

    generate

        // Для каждого порта записи и чтения генерируем логику
        for (genvar p = 0; p < N; p = p + 1) begin: port

            /* Порт записи включён в зависимости от значения сигнала push_i,
             * ("нулевой" порт соответствует первому слову данных) */
            assign push_en_w        [p] = wr_update_w > p;

            // Вычисляем указатель порта на ячейку ФИФО для записи данных
            assign push_base_w      [p] = wr_ptr_l + p;
            assign push_cross_edge_w[p] = (push_base_w[p] > PTHRS);
            assign push_index_w     [p] = (push_cross_edge_w[p]) ? (push_base_w[p] - FIFO_DEPTH) : push_base_w[p];

            // Вычисляем указатель порта на ячейку ФИФО для чтения данных
            assign pop_base_w       [p] = rd_ptr_l + p;
            assign pop_cross_edge_w [p] = (pop_base_w[p] > PTHRS);
            assign pop_index_w      [p] = (pop_cross_edge_w[p] ) ? (pop_base_w[p] - FIFO_DEPTH ) : pop_base_w[p];

            // Обновляем выходные данные порта чтения в зависимости от текущего значения её указателя
            assign pop_data_o       [p] = fifo_l[pop_index_w[p]];

        end

        // Для каждого слота ФИФО генерируем логику
        for (genvar f = 0; f < FIFO_DEPTH; f = f + 1) begin: fifo

            for (genvar p = 0; p < N; p = p + 1) begin
                // Порт записи обращается к слоту ФИФО в случае, если указатель порта указывает на слот, а сам порт активен
                assign fifo_en_w       [f][p] = (f == push_index_w[p]) && push_en_w[p];
                // Создаём маску для входных данных, для активного порта маска состоит из всех "1", для неактивного — "0"
                assign fifo_data_mask_w[f][p] = {DW{fifo_en_w[f][p]}};
                // Совершаем операции побитовго "AND" c данными порта и его маской
                assign fifo_push_data_w[f][p] = push_data_i[p] & fifo_data_mask_w[f][p];
            end

            // Собираем вместе маскированные данные портов для каждого слота ФИФО, определяя была ли запись в данный слот
            integer n;
            always_comb begin
                n = 0;
                fifo_assembled_data_w[f] = {DW{1'b0}};
                fifo_assembled_en_w  [f] = 1'b0;
                while (n < N) begin
                    fifo_assembled_data_w[f] = fifo_assembled_data_w[f] | fifo_push_data_w[f][n];
                    fifo_assembled_en_w  [f] = fifo_assembled_en_w  [f] | fifo_en_w       [f][n];
                    n = n + 1;
                end
            end

            // Формируем следующее значение слота ФИФО
            assign fifo_next_w[f] = (fifo_assembled_en_w[f]) ? fifo_assembled_data_w[f] : fifo_l[f];

            always_ff @(posedge clk_i)
                fifo_l[f] <= fifo_next_w[f];

        end

    endgenerate


    assign can_push_o = can_push_l;
    assign can_pop_o  = can_pop_l;


    property reset;
        @(posedge clk_i)
            rst_i |=> (wr_ptr_l == PW'(0)) && (rd_ptr_l == PW'(0)) && (can_push_o == N) && !can_pop_o;
    endproperty

    property push_not_over_edge;
        logic [NW-1:0] check_push_l;
        @(posedge clk_i) disable iff (rst_i)
            (|push_i && (can_push_o >= push_i) && ((PTHRS - wr_ptr_l) >= push_i), check_push_l = push_i)
            |=>
            (wr_ptr_l == ($past(wr_ptr_l) + check_push_l));
    endproperty

    property push_over_edge;
        logic [NW-1:0] check_push_l;
        @(posedge clk_i) disable iff (rst_i)
            (|push_i && (can_push_o >= push_i) && ((PTHRS - wr_ptr_l) < push_i), check_push_l = push_i)
            |=>
            (wr_ptr_l == ($past(wr_ptr_l) + check_push_l - FIFO_DEPTH));
    endproperty

    property pop_not_over_edge;
        logic [NW-1:0] check_pop_l;
        @(posedge clk_i) disable iff (rst_i)
            (|pop_i && (can_pop_o >= pop_i) && ((PTHRS - rd_ptr_l) >= pop_i), check_pop_l = pop_i)
            |=>
            (rd_ptr_l == ($past(rd_ptr_l) + check_pop_l));
    endproperty

    property pop_over_edge;
        logic [NW-1:0] check_pop_l;
        @(posedge clk_i) disable iff (rst_i)
            (|pop_i && (can_pop_o >= pop_i) && ((PTHRS - rd_ptr_l) < pop_i), check_pop_l = pop_i)
            |=>
            (rd_ptr_l == ($past(rd_ptr_l) + check_pop_l - FIFO_DEPTH));
    endproperty

    property dont_push_if_full(local logic [NW-1:0] i);
        logic [PW-1:0] check_index;
        logic [DW-1:0] check_data;
        @(posedge clk_i) disable iff (rst_i)
            (|push_i && (can_push_o < push_i) && (push_i > i),
            check_index = push_index_w[i], check_data = fifo_l[check_index])
            |=>
            (fifo_l[check_index] == check_data) && (wr_ptr_l == $past(wr_ptr_l));
    endproperty

    property dont_pop_if_empty(local logic [NW-1:0] i);
        logic [DW-1:0] check_data;
        @(posedge clk_i) disable iff (rst_i || $isunknown(pop_data_o[i]))
            (|pop_i && (can_pop_o < pop_i) && (pop_i > i), check_data = pop_data_o[i])
            |->
            (pop_data_o[i] == check_data) ##1 (rd_ptr_l == $past(rd_ptr_l));
    endproperty

    property data_push_check(local logic [NW-1:0] i);
        logic [PW-1:0] check_index;
        logic [DW-1:0] check_data;
        @(posedge clk_i) disable iff (rst_i)
            (|push_i && (can_push_o >= push_i) && (push_i > i),
            check_index = push_index_w[i], check_data = push_data_i[i],
            $display("[T=%0t] i=%h, push_i=%h, push_index_w=%h, push_data_i=%h",
                    $time, i, push_i, push_index_w[i], push_data_i[i]))
            |=>
            (fifo_l[check_index] == check_data);
    endproperty

    property data_pop_check(local logic [NW-1:0] i);
        @(posedge clk_i) disable iff (rst_i)
            (|pop_i && (can_pop_o >= pop_i) && (pop_i > i),
            $display("[T=%0t] i=%h, pop_i =%h, pop_index_w =%h, pop_data_o =%h",
                    $time, i, pop_i, pop_index_w[i], pop_data_o[i]))
            |->
            (fifo_l[pop_index_w[i]] == pop_data_o[i]);
    endproperty


    reset_assertion:
        assert property (reset);

    push_not_over_edge_assertion:
        assert property (push_not_over_edge);

    push_over_edge_assertion:
        assert property (push_over_edge);

    pop_not_over_edge_assertion:
        assert property (pop_not_over_edge);

    pop_over_edge_assertion:
        assert property (pop_over_edge);

    generate
        for (genvar a = 0; a < N; a = a + 1) begin

            dont_push_if_full_assertion:
                assert property (dont_push_if_full(a));

            dont_pop_if_empty_assertion:
                assert property (dont_pop_if_empty(a));

            data_push_check_assertion:
                assert property (data_push_check(a));

            data_pop_check_assertion:
                assert property (data_pop_check(a));

        end
    endgenerate


endmodule
