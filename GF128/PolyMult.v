/*----------------------------------------------------------------------------
 * File                 : PolyMult.v
 * Author               : Hardware Team
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Bộ nhân GF(2^DATA_WIDTH), mặc định GF(2^128) với đa
 *                        thức x^128 + x^7 + x^2 + x + 1. Xử lý D bit của B mỗi
 *                        chu kỳ (digit-serial), cây XOR chia G nhóm có thanh
 *                        ghi pipeline. Top chỉ nối datapath và controller.
 *                        Độ trễ (từ cạnh lấy mẫu Start_in đến cạnh làm Done_out
 *                        bằng 1) = L + 2 chu kỳ, L = DATA_WIDTH/D; bằng 10 chu kỳ
 *                        với DATA_WIDTH = 128, D = 16 (đã đo bằng mô phỏng).
 * Modification history :
 *     31.10.2026 - Chuyển sang rule code: port <n>_in/<n>_out, CLK/RST (RST
 *                  tích cực mức thấp), tham số WIDTH đổi thành DATA_WIDTH,
 *                  dây nối hậu tố _w, tên instance = tên module.
 *----------------------------------------------------------------------------*/

module PolyMult #(
    parameter DATA_WIDTH = 128,
    parameter D          = 16,      // số bit xử lý mỗi chu kỳ (DATA_WIDTH chia hết cho D)
    parameter G          = 4        // số nhóm pipeline cây XOR (D chia hết cho G)
) (
    input  wire                  CLK,
    input  wire                  RST,

    input  wire                  Start_in,
    input  wire [DATA_WIDTH-1:0] A_in,
    input  wire [DATA_WIDTH-1:0] B_in,

    output wire [DATA_WIDTH-1:0] Y_out,
    output wire                  Done_out
);

    //------------------------------------------------------------------//
    // Wire                                                             //
    //------------------------------------------------------------------//
    wire load_w;
    wire en_w;
    wire enc_w;
    wire zc_w;

    //------------------------------------------------------------------//
    // Datapath                                                         //
    //------------------------------------------------------------------//
    datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .L(DATA_WIDTH / D),
        .D(D),
        .G(G)
    ) datapath (
        .CLK(CLK),
        .RST(RST),
        .A_in(A_in),
        .B_in(B_in),
        .Load_in(load_w),
        .En_in(en_w),
        .Enc_in(enc_w),
        .Zc_out(zc_w),
        .Y_out(Y_out)
    );

    //------------------------------------------------------------------//
    // Controller                                                       //
    //------------------------------------------------------------------//
    controller controller (
        .CLK(CLK),
        .RST(RST),
        .Start_in(Start_in),
        .Zc_in(zc_w),
        .Load_out(load_w),
        .En_out(en_w),
        .Enc_out(enc_w),
        .Done_out(Done_out)
    );

endmodule
