/*---- File: vole_hash_128_top.v / Author: Hardware Team / Description: Top module instantiating controller and datapath with fetch_x wiring. ----*/

module vole_hash_128_top #(
    parameter DATA_WIDTH = 128,
    parameter DEG_MAX    = 3
)(
    input  wire                      CLK,
    input  wire                      RST_N,
    input  wire                      start_in,
    input  wire [DATA_WIDTH-1:0]     s_in_0,
    input  wire [DATA_WIDTH-1:0]     s_in_1,
    input  wire [DATA_WIDTH-1:0]     s_in_2,
    input  wire [DATA_WIDTH-1:0]     s_in_3,
    input  wire [DATA_WIDTH-1:0]     s_in_4,
    input  wire [DATA_WIDTH-1:0]     r_in_0,
    input  wire [DATA_WIDTH-1:0]     r_in_1,
    input  wire [DATA_WIDTH-1:0]     r_in_2,
    input  wire [DATA_WIDTH-1:0]     r_in_3,
    input  wire [DATA_WIDTH-1:0]     x_data_in,
    input  wire                      x_valid_in,
    output wire                      x_ready_out,
    output wire [DATA_WIDTH-1:0]     h_out_0,
    output wire [DATA_WIDTH-1:0]     h_out_1,
    output wire [DATA_WIDTH-1:0]     h_out_2,
    output wire [DATA_WIDTH-1:0]     h_out_3,
    output wire                      done_out
);

    //---- Intermediate Wires ----//
    wire        load_x_w;
    wire        fetch_x_w;  // Dây k?t n?i fetch_x t? Controller sang Datapath
    wire        mul_start_w;
    wire        update_y_w;
    wire        update_h_w;
    wire        mul_done_w;
    wire [15:0] step_cnt_w;
    wire [2:0]  state_w;

    //---- Controller Instance ----//
    vole_hash_controller #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_controller (
        .CLK(CLK),
        .RST_N(RST_N),
        .start_in(start_in),
        .x_valid_in(x_valid_in),
        .mul_done_in(mul_done_w),
        .step_cnt_in(step_cnt_w),
        .deg_max_in(DEG_MAX[15:0]),
        .load_x_out(load_x_w),
        .fetch_x_out(fetch_x_w), // N?i ??u ra fetch_x
        .mul_start_out(mul_start_w),
        .update_y_out(update_y_w),
        .update_h_out(update_h_w),
        .x_ready_out(x_ready_out),
        .done_out(done_out),
        .state_out(state_w)
    );

    //---- Datapath Instance ----//
    vole_hash_datapath #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_datapath (
        .CLK(CLK),
        .RST_N(RST_N),
        .load_x_in(load_x_w),
        .fetch_x_in(fetch_x_w),   // N?i ??u vào fetch_x
        .mul_start_in(mul_start_w),
        .update_y_in(update_y_w),
        .update_h_in(update_h_w),
        .start_in(start_in),
        .s_in_0(s_in_0),
        .s_in_1(s_in_1),
        .s_in_2(s_in_2),
        .s_in_3(s_in_3),
        .s_in_4(s_in_4),
        .r_in_0(r_in_0),
        .r_in_1(r_in_1),
        .r_in_2(r_in_2),
        .r_in_3(r_in_3),
        .x_data_in(x_data_in),
        .state_in(state_w),
        .deg_max_in(DEG_MAX[15:0]),
        .step_cnt_out(step_cnt_w),
        .mul_done_out(mul_done_w),
        .h_out_0(h_out_0),
        .h_out_1(h_out_1),
        .h_out_2(h_out_2),
        .h_out_3(h_out_3)
    );

endmodule
