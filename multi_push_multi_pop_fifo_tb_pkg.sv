
/*
 * Description : Testbench package for FIFO with multiple simultaneous pushes and pops
 * Author      : Deltsov Ignatiy
 */


package multi_push_multi_pop_fifo_tb_pkg;


    class packet #(parameter integer DATA_WIDTH = 8, parameter integer N = 3);
        localparam DW = DATA_WIDTH;
        localparam NW = $clog2 (N + 1);
        rand logic [ N-1:0] [DW-1:0] push_data_l;
        rand logic [NW-1:0]          push_l;
        rand logic [NW-1:0]          pop_l;
             logic [ N-1:0] [DW-1:0] pop_data_l;
        rand int                     pkt_delay = 0;
        constraint push_pop_c {
            push_l inside {[0:N]};
            pop_l inside {[0:N]};
        }
        constraint pkt_delay_c {
            pkt_delay inside {[0:5]};
        }
    endclass


    class configuration;
        int pkt_amount     = 2000;
        int timeout_cycles = 100000;
    endclass


    class monitor #(parameter integer DATA_WIDTH = 8, parameter integer N = 3);

        packet #(DATA_WIDTH, N) p_push;
        packet #(DATA_WIDTH, N) p_pop;
        mailbox #(packet#(DATA_WIDTH, N)) mon_push;
        mailbox #(packet#(DATA_WIDTH, N)) mon_pop;
        virtual multi_push_multi_pop_fifo_iface #(DATA_WIDTH, N) vif;

        function new(input mailbox #(packet#(DATA_WIDTH, N)) mon_push,
                input mailbox #(packet#(DATA_WIDTH, N)) mon_pop,
                input virtual multi_push_multi_pop_fifo_iface vif);
            this.mon_push = mon_push;
            this.mon_pop  = mon_pop;
            this.vif      = vif;
        endfunction

        virtual task run_push();
            wait ( vif.rst_i);
            wait (~vif.rst_i);
            forever begin
                @(posedge vif.clk_i);
                if (|vif.push_l && (vif.can_push_w >= vif.push_l)) begin
                    p_push             = new();
                    p_push.push_data_l = vif.push_data_l;
                    p_push.push_l      = vif.push_l;
                    mon_push.put(p_push);
                end
            end
        endtask

        virtual task run_pop();
            wait ( vif.rst_i);
            wait (~vif.rst_i);
            forever begin
                @(posedge vif.clk_i);
                if (|vif.pop_l && (vif.can_pop_w >= vif.pop_l)) begin
                    p_pop            = new();
                    p_pop.pop_data_l = vif.pop_data_w;
                    p_pop.pop_l      = vif.pop_l;
                    mon_pop.put(p_pop);
                end
            end
        endtask

    endclass


    class scoreboard #(parameter integer DATA_WIDTH = 8,
        parameter integer FIFO_DEPTH = 10, parameter integer N = 3);

        packet #(DATA_WIDTH, N) p_push;
        packet #(DATA_WIDTH, N) p_pop;
        mailbox #(packet#(DATA_WIDTH, N)) mon_push;
        mailbox #(packet#(DATA_WIDTH, N)) mon_pop;
        virtual multi_push_multi_pop_fifo_iface #(DATA_WIDTH, N) vif;
        logic [DATA_WIDTH-1:0] q_fifo [$:FIFO_DEPTH];
        logic [DATA_WIDTH-1:0] pop_data_l;
        integer i;

        function new(input mailbox #(packet#(DATA_WIDTH, N)) mon_push,
                input mailbox #(packet#(DATA_WIDTH, N)) mon_pop,
                input virtual multi_push_multi_pop_fifo_iface vif);
            this.mon_push = mon_push;
            this.mon_pop  = mon_pop;
            this.vif      = vif;
        endfunction

        virtual task run();
            wait ( vif.rst_i);
            wait (~vif.rst_i);
            forever begin
                @(posedge vif.clk_i);
                p_push = new();
                p_pop  = new();
                if (q_fifo.size() < FIFO_DEPTH && mon_push.try_get(p_push)) begin
                    i = 0;
                    while (i < p_push.push_l) begin
                        q_fifo.push_back(p_push.push_data_l[i]);
                        $display("[T=%0t] Value %h pushed to fifo model", $time, p_push.push_data_l[i]);
                        i += 1;
                    end
                end
                if (q_fifo.size() > 0 && mon_pop.try_get(p_pop)) begin
                    i = 0;
                    while (i < p_pop.pop_l) begin
                        pop_data_l = q_fifo.pop_front();
                        if (pop_data_l != p_pop.pop_data_l[i]) begin
                            $error("[T=%0t] Fifo model data = %h, Fifo uut data = %h", $time,
                                    pop_data_l, p_pop.pop_data_l[i]);
                            $stop();
                        end else begin
                            $display("[T=%0t] Fifo model data = %h, Fifo uut data = %h", $time,
                                    pop_data_l, p_pop.pop_data_l[i]);
                        end
                        i += 1;
                    end
                end
            end
        endtask

    endclass


    class generator #(parameter integer DATA_WIDTH = 8, parameter integer N = 3);

        packet #(DATA_WIDTH, N) p;
        configuration cfg;
        mailbox #(packet#(DATA_WIDTH, N)) gen2drv;

        function new(input mailbox #(packet#(DATA_WIDTH, N)) gen2drv, input configuration cfg);
            this.gen2drv = gen2drv;
            this.cfg     = cfg;
        endfunction

        virtual task run();
            repeat (cfg.pkt_amount) begin
                p = new();
                p.randomize();
                gen2drv.put(p);
            end
        endtask

    endclass


    class driver #(parameter integer DATA_WIDTH = 8, parameter integer N = 3);

        packet #(DATA_WIDTH, N) p;
        configuration cfg;
        mailbox #(packet#(DATA_WIDTH, N)) gen2drv;
        virtual multi_push_multi_pop_fifo_iface #(DATA_WIDTH, N) vif;
        integer pkt_counter;

        function new(input mailbox #(packet#(DATA_WIDTH, N)) gen2drv,
                input configuration cfg,
                input virtual multi_push_multi_pop_fifo_iface vif);
            this.gen2drv = gen2drv;
            this.vif     = vif;
            this.cfg     = cfg;
        endfunction

        virtual task run();
            vif.push_data_l <= 'h0;
            vif.push_l      <= 1'b0;
            vif.pop_l       <= 1'b0;
            pkt_counter      = 0;
            wait ( vif.rst_i);
            wait (~vif.rst_i);
            while (pkt_counter < cfg.pkt_amount) begin
                p = new();
                gen2drv.get(p);
                @(posedge vif.clk_i);
                vif.push_data_l <= p.push_data_l;
                vif.push_l      <= p.push_l;
                vif.pop_l       <= p.pop_l;
                pkt_counter      += 1;
                if (p.pkt_delay) begin
                    @(posedge vif.clk_i);
                    vif.push_l <= 1'b0;
                    vif.pop_l  <= 1'b0;
                    repeat (p.pkt_delay - 1) @(posedge vif.clk_i);
                end
            end
        endtask

    endclass


    class environment #(parameter integer DATA_WIDTH = 8,
        parameter integer FIFO_DEPTH = 10, parameter integer N = 3);

        mailbox #(packet#(DATA_WIDTH, N)) gen2drv;
        mailbox #(packet#(DATA_WIDTH, N)) mon_push;
        mailbox #(packet#(DATA_WIDTH, N)) mon_pop;

        virtual multi_push_multi_pop_fifo_iface #(DATA_WIDTH, N) vif;

        configuration                              cfg;
        generator     #(DATA_WIDTH, N)             gen;
        driver        #(DATA_WIDTH, N)             drv;
        monitor       #(DATA_WIDTH, N)             mon;
        scoreboard    #(DATA_WIDTH, FIFO_DEPTH, N) scb;

        function new(virtual multi_push_multi_pop_fifo_iface vif);
            this.vif = vif;
            gen2drv  = new();
            mon_push = new();
            mon_pop  = new();
            cfg      = new();
            if (!cfg.randomize()) begin
                $error("Can't randomize test configuration");
                $finish();
            end
            gen = new(gen2drv, cfg);
            drv = new(gen2drv, cfg, vif);
            mon = new(mon_push, mon_pop, vif);
            scb = new(mon_push, mon_pop, vif);
        endfunction

        virtual task timeout();
            repeat (cfg.timeout_cycles) @(posedge vif.clk_i);
            $display("Timeout!");
            $stop();
        endtask

        virtual task run();
            fork
                mon.run_push();
                mon.run_pop();
                scb.run();
                timeout();
            join_none
            fork
                gen.run();
                drv.run();
            join
            repeat (20) @(posedge vif.clk_i);
            $display("Check!");
            $finish;
        endtask

    endclass


endpackage
