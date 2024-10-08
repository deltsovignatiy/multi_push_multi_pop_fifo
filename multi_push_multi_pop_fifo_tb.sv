
/*
 * Description : Testbench for FIFO with multiple simultaneous pushes and pops
 * Author      : Deltsov Ignatiy
 */


`timescale 1ns/1ns


import multi_push_multi_pop_fifo_tb_pkg::*;


module multi_push_multi_pop_fifo_tb;


    parameter CLK_FREQUENCY_MHZ = 1;
    parameter DATA_WIDTH        = 13;
    parameter FIFO_DEPTH        = 19;
    parameter N                 = 3;


    localparam CLK_PERIOD_NS = 1000 / CLK_FREQUENCY_MHZ;


    bit clk_l;
    bit rst_l;

    environment #(DATA_WIDTH, FIFO_DEPTH, N) env;


    multi_push_multi_pop_fifo_iface
        #(
            .DATA_WIDTH (DATA_WIDTH          ),
            .N          (N                   )
        )
        uut_intf
        (
            .clk_i      (clk_l               ),
            .rst_i      (rst_l               )
        );

    multi_push_multi_pop_fifo
        #(
            .FIFO_DEPTH (FIFO_DEPTH          ),
            .DATA_WIDTH (DATA_WIDTH          ),
            .N          (N                   )
        )
        uut
        (
            .clk_i      (uut_intf.clk_i      ),
            .rst_i      (uut_intf.rst_i      ),
            .push_i     (uut_intf.push_l     ),
            .push_data_i(uut_intf.push_data_l),
            .pop_i      (uut_intf.pop_l      ),
            .pop_data_o (uut_intf.pop_data_w ),
            .can_push_o (uut_intf.can_push_w ),
            .can_pop_o  (uut_intf.can_pop_w  )
        );


    always #(CLK_PERIOD_NS / 2)
        clk_l <= ~clk_l;


    initial begin
        clk_l <= 1'b0;
        rst_l <= 1'b1;
        repeat (4) @(posedge clk_l);
        rst_l <= 1'b0;
    end

    initial begin
        env = new(uut_intf);
        env.run();
    end

    initial begin
        $timeformat(-9, 2, " ns", 10);
        $dumpfile("multi_push_multi_pop_fifo_tb.vcd");
        $dumpvars(0, multi_push_multi_pop_fifo_tb);
    end


    covergroup covergroup_1 @(posedge uut_intf.clk_i);
        can_push_cover: coverpoint uut_intf.can_push_w iff (~uut_intf.rst_i) {
            bins b1[N+1] = {[0:N]};
        }
        can_pop_cover:  coverpoint uut_intf.can_pop_w iff (~uut_intf.rst_i) {
            bins b1[N+1] = {[0:N]};
        }
        push_cover:     coverpoint uut_intf.push_l    iff (~uut_intf.rst_i) {
            bins b1[N+1] = {[0:N]};
        }
        pop_cover:      coverpoint uut_intf.pop_l     iff (~uut_intf.rst_i) {
            bins b1[N+1] = {[0:N]};
        }
        can_push_can_pop_cross: cross can_push_cover, can_pop_cover;
        push_pop_cross:         cross push_cover, pop_cover;
        push_can_push_cross:    cross can_push_cover, push_cover;
        pop_can_pop_cross:      cross can_pop_cover, pop_cover;
    endgroup

    covergroup_1 cover_inst_1 = new();


endmodule
