/*----------------------------------------------------------------------------
 * File                 : vole_hash_datapath.v
 * Author               : Claude
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Datapath của bộ tăng tốc vole_hash_128 FAEST-128S.
 *                        5 luồng Horner song song (y_j = y_j * s_j + x_i) dùng
 *                        5 bộ nhân PolyMult (nhân GF(2^128), 16 bit mỗi chu kỳ),
 *                        sau đó tính 4 đầu ra h_i = r_i * y_0 + y_{i+1} + x_tail_i.
 *                        S_in, R_in được chốt tại chu kỳ Start_in; riêng S4_in
 *                        chỉ lấy nửa thấp (t 64 bit), nửa cao ép về 0 như trong
 *                        mã C gốc (zero-padding).
 * Modification history :
 *     31.10.2026 - Chuyển sang rule code: port <n>_in/<n>_out, RST tích cực
 *                  mức thấp, hậu tố _r/_w, tên instance = tên module.
 *                  Datapath nhận tín hiệu pha (Idle, Load_x, Fetch_x, Tail_x,
 *                  Wait, Fin_sel, Fin_wait) thay vì giải mã state_in bằng số.
 *                  Bộ đếm bước và bộ đếm tail nằm ở datapath, xuất Step_last,
 *                  Tail_last cho controller. DEG_MAX là tham số của datapath.
 *----------------------------------------------------------------------------*/

module vole_hash_datapath #(
    parameter DATA_WIDTH = 128,
    parameter CNT_WIDTH  = 16,
    parameter DEG_MAX    = 22533,   // số bước Horner = ell' - 1 (ell' = ell + d_zk - 1), DEG_MAX >= 1
    parameter MUL_D      = 16,      // số bit xử lý mỗi chu kỳ của PolyMult
    parameter MUL_G      = 4        // số nhóm pipeline cây XOR của PolyMult
) (
    input  wire                  CLK,
    input  wire                  RST,

    input  wire                  Start_in,
    input  wire                  Idle_in,
    input  wire                  Load_x_in,
    input  wire                  Fetch_x_in,
    input  wire                  Tail_x_in,
    input  wire                  Mul_start_in,
    input  wire                  Wait_in,
    input  wire                  Fin_sel_in,
    input  wire                  Fin_wait_in,

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

    output wire                  Mul_done_out,
    output wire                  Step_last_out,
    output wire                  Tail_last_out,
    output wire [DATA_WIDTH-1:0] H0_out,
    output wire [DATA_WIDTH-1:0] H1_out,
    output wire [DATA_WIDTH-1:0] H2_out,
    output wire [DATA_WIDTH-1:0] H3_out
);

    //------------------------------------------------------------------//
    // Tham số                                                          //
    //------------------------------------------------------------------//
    parameter TAIL_NUM   = 4;       // số từ đuôi x_{ell'}..x_{ell'+3}
    parameter TAIL_WIDTH = 2;       // độ rộng bộ đếm tail, đủ chứa 0..TAIL_NUM-1

    //------------------------------------------------------------------//
    // Wire                                                             //
    //------------------------------------------------------------------//
    wire                  rst_poly_w;       // PolyMult dùng reset tích cực mức cao
    wire                  mul_done0_w;
    wire                  mul_done1_w;
    wire                  mul_done2_w;
    wire                  mul_done3_w;
    wire                  mul_done4_w;
    wire [DATA_WIDTH-1:0] mul_y0_w;
    wire [DATA_WIDTH-1:0] mul_y1_w;
    wire [DATA_WIDTH-1:0] mul_y2_w;
    wire [DATA_WIDTH-1:0] mul_y3_w;
    wire [DATA_WIDTH-1:0] mul_y4_w;

    wire                  xfer_load_w;      // nhận x0
    wire                  xfer_fetch_w;     // nhận x_i của bước Horner
    wire                  xfer_tail_w;      // nhận một từ đuôi
    wire                  update_y_w;       // cập nhật y sau mỗi bước Horner
    wire                  update_h_w;       // chốt h sau phép nhân cuối
    wire                  latch_w;          // chốt S, R tại chu kỳ Start

    //------------------------------------------------------------------//
    // Reg                                                              //
    //------------------------------------------------------------------//
    reg [DATA_WIDTH-1:0]  mul_a0_r;         // toán hạng bộ nhân (mạch tổ hợp)
    reg [DATA_WIDTH-1:0]  mul_a1_r;
    reg [DATA_WIDTH-1:0]  mul_a2_r;
    reg [DATA_WIDTH-1:0]  mul_a3_r;
    reg [DATA_WIDTH-1:0]  mul_a4_r;
    reg [DATA_WIDTH-1:0]  mul_b0_r;
    reg [DATA_WIDTH-1:0]  mul_b1_r;
    reg [DATA_WIDTH-1:0]  mul_b2_r;
    reg [DATA_WIDTH-1:0]  mul_b3_r;
    reg [DATA_WIDTH-1:0]  mul_b4_r;

    reg [DATA_WIDTH-1:0]  s0_r;
    reg [DATA_WIDTH-1:0]  s1_r;
    reg [DATA_WIDTH-1:0]  s2_r;
    reg [DATA_WIDTH-1:0]  s3_r;
    reg [DATA_WIDTH-1:0]  s4_r;
    reg [DATA_WIDTH-1:0]  r0_r;
    reg [DATA_WIDTH-1:0]  r1_r;
    reg [DATA_WIDTH-1:0]  r2_r;
    reg [DATA_WIDTH-1:0]  r3_r;

    reg [DATA_WIDTH-1:0]  y0_r;
    reg [DATA_WIDTH-1:0]  y1_r;
    reg [DATA_WIDTH-1:0]  y2_r;
    reg [DATA_WIDTH-1:0]  y3_r;
    reg [DATA_WIDTH-1:0]  y4_r;
    reg [DATA_WIDTH-1:0]  x_r;              // x_i đã nhận, giữ đến khi bộ nhân xong
    reg [DATA_WIDTH-1:0]  tail0_r;
    reg [DATA_WIDTH-1:0]  tail1_r;
    reg [DATA_WIDTH-1:0]  tail2_r;
    reg [DATA_WIDTH-1:0]  tail3_r;
    reg [DATA_WIDTH-1:0]  h0_r;
    reg [DATA_WIDTH-1:0]  h1_r;
    reg [DATA_WIDTH-1:0]  h2_r;
    reg [DATA_WIDTH-1:0]  h3_r;

    reg [CNT_WIDTH-1:0]   step_cnt_r;
    reg [TAIL_WIDTH-1:0]  tail_cnt_r;

    //------------------------------------------------------------------//
    // Mạch tổ hợp                                                      //
    //------------------------------------------------------------------//
    assign rst_poly_w   = ~RST;

    assign xfer_load_w  = X_valid_in & Load_x_in;
    assign xfer_fetch_w = X_valid_in & Fetch_x_in;
    assign xfer_tail_w  = X_valid_in & Tail_x_in;
    assign update_y_w   = Wait_in & mul_done0_w;
    assign update_h_w   = Fin_wait_in & mul_done0_w;
    assign latch_w      = Idle_in & Start_in;

    assign Mul_done_out  = mul_done0_w;
    assign Step_last_out = (step_cnt_r == DEG_MAX);
    assign Tail_last_out = (tail_cnt_r == (TAIL_NUM - 1));
    assign H0_out        = h0_r;
    assign H1_out        = h1_r;
    assign H2_out        = h2_r;
    assign H3_out        = h3_r;

    // Chọn toán hạng: bước Horner nhân y_j * s_j, bước cuối nhân y_0 * r_i
    always @(*) begin
        mul_a0_r = y0_r;
        mul_b0_r = s0_r;
        mul_a1_r = y1_r;
        mul_b1_r = s1_r;
        mul_a2_r = y2_r;
        mul_b2_r = s2_r;
        mul_a3_r = y3_r;
        mul_b3_r = s3_r;
        mul_a4_r = y4_r;
        mul_b4_r = s4_r;
        if (Fin_sel_in) begin
            mul_a0_r = y0_r;
            mul_b0_r = r0_r;
            mul_a1_r = y0_r;
            mul_b1_r = r1_r;
            mul_a2_r = y0_r;
            mul_b2_r = r2_r;
            mul_a3_r = y0_r;
            mul_b3_r = r3_r;
            mul_a4_r = y0_r;
            mul_b4_r = {DATA_WIDTH{1'b0}};      // luồng thứ 5 không dùng ở bước cuối
        end
    end

    //---- 5 bộ nhân PolyMult chạy song song ----//
    PolyMult #(
        .WIDTH(DATA_WIDTH),
        .D(MUL_D),
        .G(MUL_G)
    ) polymult0 (
        .clk(CLK),
        .rst(rst_poly_w),
        .start(Mul_start_in),
        .A(mul_a0_r),
        .B(mul_b0_r),
        .Y(mul_y0_w),
        .done(mul_done0_w)
    );

    PolyMult #(
        .WIDTH(DATA_WIDTH),
        .D(MUL_D),
        .G(MUL_G)
    ) polymult1 (
        .clk(CLK),
        .rst(rst_poly_w),
        .start(Mul_start_in),
        .A(mul_a1_r),
        .B(mul_b1_r),
        .Y(mul_y1_w),
        .done(mul_done1_w)
    );

    PolyMult #(
        .WIDTH(DATA_WIDTH),
        .D(MUL_D),
        .G(MUL_G)
    ) polymult2 (
        .clk(CLK),
        .rst(rst_poly_w),
        .start(Mul_start_in),
        .A(mul_a2_r),
        .B(mul_b2_r),
        .Y(mul_y2_w),
        .done(mul_done2_w)
    );

    PolyMult #(
        .WIDTH(DATA_WIDTH),
        .D(MUL_D),
        .G(MUL_G)
    ) polymult3 (
        .clk(CLK),
        .rst(rst_poly_w),
        .start(Mul_start_in),
        .A(mul_a3_r),
        .B(mul_b3_r),
        .Y(mul_y3_w),
        .done(mul_done3_w)
    );

    PolyMult #(
        .WIDTH(DATA_WIDTH),
        .D(MUL_D),
        .G(MUL_G)
    ) polymult4 (
        .clk(CLK),
        .rst(rst_poly_w),
        .start(Mul_start_in),
        .A(mul_a4_r),
        .B(mul_b4_r),
        .Y(mul_y4_w),
        .done(mul_done4_w)
    );

    //------------------------------------------------------------------//
    // Mạch tuần tự                                                     //
    //------------------------------------------------------------------//
    // Chốt S, R tại chu kỳ Start (S4 chỉ lấy nửa thấp, nửa cao = 0)
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            s0_r <= {DATA_WIDTH{1'b0}};
            s1_r <= {DATA_WIDTH{1'b0}};
            s2_r <= {DATA_WIDTH{1'b0}};
            s3_r <= {DATA_WIDTH{1'b0}};
            s4_r <= {DATA_WIDTH{1'b0}};
            r0_r <= {DATA_WIDTH{1'b0}};
            r1_r <= {DATA_WIDTH{1'b0}};
            r2_r <= {DATA_WIDTH{1'b0}};
            r3_r <= {DATA_WIDTH{1'b0}};
        end else if (latch_w) begin
            s0_r <= S0_in;
            s1_r <= S1_in;
            s2_r <= S2_in;
            s3_r <= S3_in;
            s4_r <= {{(DATA_WIDTH/2){1'b0}}, S4_in[DATA_WIDTH/2-1:0]};
            r0_r <= R0_in;
            r1_r <= R1_in;
            r2_r <= R2_in;
            r3_r <= R3_in;
        end else begin
            s0_r <= s0_r;
            s1_r <= s1_r;
            s2_r <= s2_r;
            s3_r <= s3_r;
            s4_r <= s4_r;
            r0_r <= r0_r;
            r1_r <= r1_r;
            r2_r <= r2_r;
            r3_r <= r3_r;
        end
    end

    // Bộ đếm bước Horner: IDLE về 0, bước đầu tiên (x1) có chỉ số 1
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            step_cnt_r <= {CNT_WIDTH{1'b0}};
        end else if (Idle_in) begin
            step_cnt_r <= {CNT_WIDTH{1'b0}};
        end else if (Load_x_in) begin
            step_cnt_r <= {{(CNT_WIDTH-1){1'b0}}, 1'b1};
        end else if (update_y_w) begin
            if (Step_last_out) begin
                step_cnt_r <= {CNT_WIDTH{1'b0}};
            end else begin
                step_cnt_r <= step_cnt_r + 1'b1;
            end
        end else begin
            step_cnt_r <= step_cnt_r;
        end
    end

    // Bộ đếm từ đuôi: IDLE về 0, tăng khi nhận một từ, dừng ở TAIL_NUM-1
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            tail_cnt_r <= {TAIL_WIDTH{1'b0}};
        end else if (Idle_in) begin
            tail_cnt_r <= {TAIL_WIDTH{1'b0}};
        end else if (xfer_tail_w && !Tail_last_out) begin
            tail_cnt_r <= tail_cnt_r + 1'b1;
        end else begin
            tail_cnt_r <= tail_cnt_r;
        end
    end

    // Nhận x: x0 nạp vào cả 5 luồng y, x_i (i >= 1) giữ trong x_r đến khi bộ nhân xong
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            x_r <= {DATA_WIDTH{1'b0}};
        end else if (xfer_load_w || xfer_fetch_w) begin
            x_r <= X_data_in;
        end else begin
            x_r <= x_r;
        end
    end

    // Cập nhật 5 luồng y: nạp x0, hoặc y_j = (y_j * s_j) + x_i sau mỗi bước Horner
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            y0_r <= {DATA_WIDTH{1'b0}};
            y1_r <= {DATA_WIDTH{1'b0}};
            y2_r <= {DATA_WIDTH{1'b0}};
            y3_r <= {DATA_WIDTH{1'b0}};
            y4_r <= {DATA_WIDTH{1'b0}};
        end else if (xfer_load_w) begin
            y0_r <= X_data_in;
            y1_r <= X_data_in;
            y2_r <= X_data_in;
            y3_r <= X_data_in;
            y4_r <= X_data_in;
        end else if (update_y_w) begin
            y0_r <= mul_y0_w ^ x_r;
            y1_r <= mul_y1_w ^ x_r;
            y2_r <= mul_y2_w ^ x_r;
            y3_r <= mul_y3_w ^ x_r;
            y4_r <= mul_y4_w ^ x_r;
        end else begin
            y0_r <= y0_r;
            y1_r <= y1_r;
            y2_r <= y2_r;
            y3_r <= y3_r;
            y4_r <= y4_r;
        end
    end

    // Lưu 4 từ đuôi theo thứ tự đến
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            tail0_r <= {DATA_WIDTH{1'b0}};
            tail1_r <= {DATA_WIDTH{1'b0}};
            tail2_r <= {DATA_WIDTH{1'b0}};
            tail3_r <= {DATA_WIDTH{1'b0}};
        end else if (xfer_tail_w) begin
            case (tail_cnt_r)
                2'd0: begin
                    tail0_r <= X_data_in;
                end
                2'd1: begin
                    tail1_r <= X_data_in;
                end
                2'd2: begin
                    tail2_r <= X_data_in;
                end
                default: begin
                    tail3_r <= X_data_in;
                end
            endcase
        end else begin
            tail0_r <= tail0_r;
            tail1_r <= tail1_r;
            tail2_r <= tail2_r;
            tail3_r <= tail3_r;
        end
    end

    // Chốt 4 đầu ra h_i = (r_i * y0) + y_{i+1} + x_tail_i, giữ đến lần Start kế tiếp
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            h0_r <= {DATA_WIDTH{1'b0}};
            h1_r <= {DATA_WIDTH{1'b0}};
            h2_r <= {DATA_WIDTH{1'b0}};
            h3_r <= {DATA_WIDTH{1'b0}};
        end else if (update_h_w) begin
            h0_r <= mul_y0_w ^ y1_r ^ tail0_r;
            h1_r <= mul_y1_w ^ y2_r ^ tail1_r;
            h2_r <= mul_y2_w ^ y3_r ^ tail2_r;
            h3_r <= mul_y3_w ^ y4_r ^ tail3_r;
        end else begin
            h0_r <= h0_r;
            h1_r <= h1_r;
            h2_r <= h2_r;
            h3_r <= h3_r;
        end
    end

endmodule
