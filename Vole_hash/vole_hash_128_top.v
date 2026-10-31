/*----------------------------------------------------------------------------
 * File                 : vole_hash_128_top.v
 * Author               : Claude
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Top của bộ tăng tốc vole_hash_128 FAEST-128S: nối
 *                        khối điều khiển (vole_hash_controller) với datapath
 *                        (vole_hash_datapath). Giao diện x dùng ready/valid:
 *                        một từ x được nhận khi X_valid_in và X_ready_out
 *                        cùng bằng 1 tại cạnh lên CLK. Thứ tự gửi: x0, x1..
 *                        x_DEG_MAX, rồi 4 từ đuôi. H_out hợp lệ khi Done_out = 1
 *                        và được giữ đến lần Start_in kế tiếp.
 * Modification history :
 *     31.10.2026 - Chuyển sang rule code: port <n>_in/<n>_out, RST tích cực
 *                  mức thấp, top chỉ instantiate và dây nối _w, bỏ
 *                  DEG_MAX[15:0] (part-select trên parameter).
 *----------------------------------------------------------------------------*/

module vole_hash_128_top #(
    parameter DATA_WIDTH = 128,
    parameter CNT_WIDTH  = 16,
    parameter DEG_MAX    = 22533,
    parameter MUL_D      = 16,
    parameter MUL_G      = 4
) (
    input  wire                  CLK,
    input  wire                  RST,

    input  wire                  Start_in,
    input  wire [DATA_WIDTH-1:0] S0_in,
    input  wire [DATA_WIDTH-1:0] S1_in,
    input  wire [DATA_WIDTH-1:0] S2_in,
    input  wire [DATA_WIDTH-1:0] S3_in,
    input  wire [DATA_WIDTH-1:0] S4_in,
    input  wire [DATA_WIDTH-1:0] R0_in,
    input  wire [DATA_WIDTH-1:0] R1_in,
    input  wire [DATA_WIDTH-1:0] R2_in,
    input  wire [DATA_WIDTH-1:0] R3_in,

    input  wire [DATA_WIDTH-1:0] X_data_in,
    input  wire                  X_valid_in,
    output wire                  X_ready_out,

    output wire [DATA_WIDTH-1:0] H0_out,
    output wire [DATA_WIDTH-1:0] H1_out,
    output wire [DATA_WIDTH-1:0] H2_out,
    output wire [DATA_WIDTH-1:0] H3_out,
    output wire                  Done_out
);

    //------------------------------------------------------------------//
    // Wire                                                             //
    //------------------------------------------------------------------//
    wire idle_w;
    wire load_x_w;
    wire fetch_x_w;
    wire tail_x_w;
    wire mul_start_w;
    wire wait_w;
    wire fin_sel_w;
    wire fin_wait_w;
    wire mul_done_w;
    wire step_last_w;
    wire tail_last_w;

    //------------------------------------------------------------------//
    // Controller                                                       //
    //------------------------------------------------------------------//
    vole_hash_controller vole_hash_controller (
        .CLK(CLK),
        .RST(RST),

        .Start_in(Start_in),
        .X_valid_in(X_valid_in),
        .Mul_done_in(mul_done_w),
        .Step_last_in(step_last_w),
        .Tail_last_in(tail_last_w),

        .Idle_out(idle_w),
        .Load_x_out(load_x_w),
        .Fetch_x_out(fetch_x_w),
        .Tail_x_out(tail_x_w),
        .Mul_start_out(mul_start_w),
        .Wait_out(wait_w),
        .Fin_sel_out(fin_sel_w),
        .Fin_wait_out(fin_wait_w),
        .X_ready_out(X_ready_out),
        .Done_out(Done_out)
    );

    //------------------------------------------------------------------//
    // Datapath                                                         //
    //------------------------------------------------------------------//
    vole_hash_datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .DEG_MAX(DEG_MAX),
        .MUL_D(MUL_D),
        .MUL_G(MUL_G)
    ) vole_hash_datapath (
        .CLK(CLK),
        .RST(RST),

        .Start_in(Start_in),
        .Idle_in(idle_w),
        .Load_x_in(load_x_w),
        .Fetch_x_in(fetch_x_w),
        .Tail_x_in(tail_x_w),
        .Mul_start_in(mul_start_w),
        .Wait_in(wait_w),
        .Fin_sel_in(fin_sel_w),
        .Fin_wait_in(fin_wait_w),

        .S0_in(S0_in),
        .S1_in(S1_in),
        .S2_in(S2_in),
        .S3_in(S3_in),
        .S4_in(S4_in),
        .R0_in(R0_in),
        .R1_in(R1_in),
        .R2_in(R2_in),
        .R3_in(R3_in),
        .X_data_in(X_data_in),
        .X_valid_in(X_valid_in),

        .Mul_done_out(mul_done_w),
        .Step_last_out(step_last_w),
        .Tail_last_out(tail_last_w),
        .H0_out(H0_out),
        .H1_out(H1_out),
        .H2_out(H2_out),
        .H3_out(H3_out)
    );

endmodule
