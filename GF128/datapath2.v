// ============================================================================
// datapath - bo nhan GF(2^128), da thuc x^128 + x^7 + x^2 + x + 1
// Ban toi uu Fmax:
//   (1) Cay XOR 16 bit chia thanh G nhom, moi nhom co thanh ghi pipeline
//       (stage 1: nhom -> grp_reg, stage 2: accum ^= XOR cac nhom)
//   (2) Bo reset async tren Pa/Pb/accum/sum (da duoc load xoa/khoi tao)
//   (3) zc la thanh ghi (so sanh counter duoc tinh truoc 1 chu ky)
//   (4) en_d (en tre 1 chu ky) dieu khien accumulator, co max_fanout
// Tham so: D = so bit xu ly moi chu ky (mac dinh 16), G = so nhom pipeline
// Latency: load + L chu ky tinh + 1 chu ky flush (them 1 chu ky so voi ban cu)
// ============================================================================
module datapath #(
    parameter WIDTH = 128,
    parameter L     = 8,                 // so chu ky tinh = WIDTH / D
    parameter D     = 16,                // digit size (bit / chu ky)
    parameter G     = 4,                 // so nhom pipeline, D phai chia het cho G
    parameter [WIDTH-1:0] POLY = 128'h87 // phan rut gon cua da thuc
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    input  wire             load,
    input  wire             en,
    input  wire             enc,
    output wire             zc,
    output wire [WIDTH-1:0] Y
);
    localparam GS = D / G;               // so bit Pb moi nhom

    reg [WIDTH-1:0] Pa_reg;
    reg [WIDTH-1:0] Pb_reg;
    reg [WIDTH-1:0] accum_reg;
    reg [7:0]       counter;
    reg             zc_r;

    (* max_fanout = 32 *) reg en_d;

    // ---------------- Nap & dich du lieu (khong reset, load khoi tao) -------
    wire [(D+1)*WIDTH-1:0] A_flat;       // A_flat[k*WIDTH +: WIDTH] = Pa * x^k

    always @(posedge clk) begin
        if (load) begin
            Pa_reg <= A;
            Pb_reg <= B;
        end else if (en) begin
            Pa_reg <= A_flat[D*WIDTH +: WIDTH];
            Pb_reg <= Pb_reg >> D;
        end
    end

    // ---------------- Chuoi D tang MultX ------------------------------------
    assign A_flat[0 +: WIDTH] = Pa_reg;
    genvar k;
    generate
        for (k = 0; k < D; k = k + 1) begin : gen_multx
            wire [WIDTH-1:0] cur = A_flat[k*WIDTH +: WIDTH];
            assign A_flat[(k+1)*WIDTH +: WIDTH] =
                   {cur[WIDTH-2:0], 1'b0} ^ ({WIDTH{cur[WIDTH-1]}} & POLY);
        end
    endgenerate

    // ---------------- Stage 1: G nhom XOR, moi nhom co thanh ghi ------------
    reg [G*WIDTH-1:0] grp_reg;
    genvar g;
    generate
        for (g = 0; g < G; g = g + 1) begin : gen_grp
            reg [WIDTH-1:0] t;
            integer j;
            always @(*) begin
                t = {WIDTH{1'b0}};
                for (j = 0; j < GS; j = j + 1)
                    if (Pb_reg[g*GS + j])
                        t = t ^ A_flat[(g*GS + j)*WIDTH +: WIDTH];
            end
            always @(posedge clk)
                grp_reg[g*WIDTH +: WIDTH] <= t;
        end
    endgenerate

    // ---------------- Stage 2: accumulator ----------------------------------
    reg [WIDTH-1:0] acc_next;
    integer q;
    always @(*) begin
        acc_next = accum_reg;
        for (q = 0; q < G; q = q + 1)
            acc_next = acc_next ^ grp_reg[q*WIDTH +: WIDTH];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) en_d <= 1'b0;
        else     en_d <= en;
    end

    always @(posedge clk) begin
        if (load)      accum_reg <= {WIDTH{1'b0}};
        else if (en_d) accum_reg <= acc_next;
    end

    // ---------------- Counter va co zc (thanh ghi) --------------------------
    // zc_r = 1 khi counter == L-1
    always @(posedge clk) begin
        if (load) begin
            counter <= 8'd0;
            zc_r    <= (L == 1);
        end else if (enc) begin
            counter <= counter + 8'd1;
            zc_r    <= (counter == L - 2);
        end
    end

    assign zc = zc_r;
    assign Y  = accum_reg;
endmodule
