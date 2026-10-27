module PolyMult #(
    parameter WIDTH = 128,
    parameter D     = 16,   // bit xu ly moi chu ky (WIDTH phai chia het cho D)
    parameter G     = 4     // so nhom pipeline cay XOR (D phai chia het cho G)
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    output wire [WIDTH-1:0] Y,
    output wire             done
);
    wire load;
    wire en;
    wire enc;
    wire zc;

    datapath #(
        .WIDTH(WIDTH),
        .L(WIDTH / D),
        .D(D),
        .G(G)
    ) u_datapath (
        .clk(clk), .rst(rst),
        .A(A), .B(B),
        .load(load), .en(en), .enc(enc), .zc(zc),
        .Y(Y)
    );

    controller u_controller (
        .clk(clk), .rst(rst),
        .start(start), .zc(zc),
        .load(load), .en(en), .enc(enc), .done(done)
    );
endmodule
