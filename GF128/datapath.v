/*----------------------------------------------------------------------------
 * File                 : datapath.v
 * Author               : Hardware Team
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Datapath bộ nhân GF(2^128), đa thức x^128 + x^7 + x^2
 *                        + x + 1. Bản tối ưu Fmax:
 *                        (1) Cây XOR D bit chia G nhóm, mỗi nhóm có thanh ghi
 *                            pipeline (stage 1: nhóm -> grp_r, stage 2:
 *                            accum_r ^= XOR các nhóm).
 *                        (2) zc là thanh ghi (so sánh counter tính trước 1 chu kỳ).
 *                        (3) En_d_r (En_in trễ 1 chu kỳ) điều khiển bộ cộng dồn,
 *                            có max_fanout.
 *                        Tham số: D = số bit xử lý mỗi chu kỳ, G = số nhóm
 *                        pipeline. Độ trễ: LOAD + L chu kỳ tính + 1 chu kỳ flush.
 * Modification history :
 *     31.10.2026 - Chuyển sang rule code: port <n>_in/<n>_out, CLK/RST (RST
 *                  tích cực mức thấp), hậu tố _r (reg) và _w (wire), thứ tự
 *                  parameter -> wire -> reg -> tổ hợp -> tuần tự, không hard-
 *                  code độ rộng (CNT_WIDTH, POLY theo DATA_WIDTH).
 *                  LƯU Ý: mọi thanh ghi giờ đều có reset bất đồng bộ theo rule;
 *                  bản cũ bỏ reset trên pa/pb/accum/grp/counter để tối ưu Fmax,
 *                  cần chạy lại phân tích timing để xác nhận.
 *----------------------------------------------------------------------------*/

module datapath #(
    parameter DATA_WIDTH = 128,
    parameter L          = 8,                   // số chu kỳ tính = DATA_WIDTH / D
    parameter D          = 16,                  // digit size (bit mỗi chu kỳ)
    parameter G          = 4,                   // số nhóm pipeline, D chia hết cho G
    parameter CNT_WIDTH  = 8,                   // độ rộng bộ đếm, đủ chứa 0..L-1
    parameter [DATA_WIDTH-1:0] POLY = 8'h87     // phần rút gọn của đa thức
) (
    input  wire                  CLK,
    input  wire                  RST,

    input  wire [DATA_WIDTH-1:0] A_in,
    input  wire [DATA_WIDTH-1:0] B_in,
    input  wire                  Load_in,
    input  wire                  En_in,
    input  wire                  Enc_in,

    output wire                  Zc_out,
    output wire [DATA_WIDTH-1:0] Y_out
);

    //------------------------------------------------------------------//
    // Tham số                                                          //
    //------------------------------------------------------------------//
    parameter GS = D / G;                       // số bit pb_r mỗi nhóm

    //------------------------------------------------------------------//
    // Wire                                                             //
    //------------------------------------------------------------------//
    wire [(D+1)*DATA_WIDTH-1:0] a_flat_w;       // a_flat_w[k*DATA_WIDTH +: DATA_WIDTH] = pa * x^k

    //------------------------------------------------------------------//
    // Reg                                                              //
    //------------------------------------------------------------------//
    reg [DATA_WIDTH-1:0]   pa_r;
    reg [DATA_WIDTH-1:0]   pb_r;
    reg [DATA_WIDTH-1:0]   accum_r;
    reg [G*DATA_WIDTH-1:0] grp_r;               // thanh ghi pipeline của G nhóm XOR
    reg [CNT_WIDTH-1:0]    counter_r;
    reg                    zc_r;
    (* max_fanout = 32 *) reg en_d_r;

    reg [DATA_WIDTH-1:0]   acc_next_r;          // mạch tổ hợp: accum_r ^ XOR các nhóm
    integer                q;

    //------------------------------------------------------------------//
    // Mạch tổ hợp                                                      //
    //------------------------------------------------------------------//
    assign Zc_out = zc_r;
    assign Y_out  = accum_r;

    // Chuỗi D tầng MultX: tầng k+1 = tầng k nhân x rồi rút gọn
    assign a_flat_w[0 +: DATA_WIDTH] = pa_r;

    genvar k;
    generate
        for (k = 0; k < D; k = k + 1) begin : gen_multx
            wire [DATA_WIDTH-1:0] cur_w;
            assign cur_w = a_flat_w[k*DATA_WIDTH +: DATA_WIDTH];
            assign a_flat_w[(k+1)*DATA_WIDTH +: DATA_WIDTH] =
                   {cur_w[DATA_WIDTH-2:0], 1'b0} ^ ({DATA_WIDTH{cur_w[DATA_WIDTH-1]}} & POLY);
        end
    endgenerate

    // Stage 1: G nhóm XOR, mỗi nhóm GS bit của pb_r chọn các tầng MultX
    genvar g;
    generate
        for (g = 0; g < G; g = g + 1) begin : gen_grp
            reg [DATA_WIDTH-1:0] grp_xor_r;     // mạch tổ hợp của nhóm g
            integer              j;

            always @(*) begin
                grp_xor_r = {DATA_WIDTH{1'b0}};
                for (j = 0; j < GS; j = j + 1) begin
                    if (pb_r[g*GS + j]) begin
                        grp_xor_r = grp_xor_r ^ a_flat_w[(g*GS + j)*DATA_WIDTH +: DATA_WIDTH];
                    end
                end
            end

            always @(posedge CLK or negedge RST) begin
                if (RST == 0) begin
                    grp_r[g*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                end else begin
                    grp_r[g*DATA_WIDTH +: DATA_WIDTH] <= grp_xor_r;
                end
            end
        end
    endgenerate

    // Stage 2: cộng dồn XOR của G nhóm vào accum_r
    always @(*) begin
        acc_next_r = accum_r;
        for (q = 0; q < G; q = q + 1) begin
            acc_next_r = acc_next_r ^ grp_r[q*DATA_WIDTH +: DATA_WIDTH];
        end
    end

    //------------------------------------------------------------------//
    // Mạch tuần tự                                                     //
    //------------------------------------------------------------------//
    // Nạp A, B và dịch: pa_r nhân x^D, pb_r dịch phải D bit mỗi chu kỳ tính
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            pa_r <= {DATA_WIDTH{1'b0}};
            pb_r <= {DATA_WIDTH{1'b0}};
        end else if (Load_in) begin
            pa_r <= A_in;
            pb_r <= B_in;
        end else if (En_in) begin
            pa_r <= a_flat_w[D*DATA_WIDTH +: DATA_WIDTH];
            pb_r <= pb_r >> D;
        end else begin
            pa_r <= pa_r;
            pb_r <= pb_r;
        end
    end

    // En_in trễ 1 chu kỳ, cho phép cập nhật bộ cộng dồn sau stage pipeline
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            en_d_r <= 1'b0;
        end else begin
            en_d_r <= En_in;
        end
    end

    // Bộ cộng dồn: xóa khi Load_in, cộng khi en_d_r
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            accum_r <= {DATA_WIDTH{1'b0}};
        end else if (Load_in) begin
            accum_r <= {DATA_WIDTH{1'b0}};
        end else if (en_d_r) begin
            accum_r <= acc_next_r;
        end else begin
            accum_r <= accum_r;
        end
    end

    // Bộ đếm và cờ zc (thanh ghi): zc_r = 1 khi counter_r == L-1
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            counter_r <= {CNT_WIDTH{1'b0}};
            zc_r      <= 1'b0;
        end else if (Load_in) begin
            counter_r <= {CNT_WIDTH{1'b0}};
            zc_r      <= (L == 1);
        end else if (Enc_in) begin
            counter_r <= counter_r + 1'b1;
            zc_r      <= (counter_r == L - 2);
        end else begin
            counter_r <= counter_r;
            zc_r      <= zc_r;
        end
    end

endmodule
