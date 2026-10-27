module PolyMult #(
    parameter WIDTH = 128
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    output wire [WIDTH-1:0] Y,
    output wire             done
);

    // Tín hiệu dây liên kết nội bộ giữa Controller và Datapath
    wire load;
    wire en;
    wire enc;
    wire zc;

    // Instance của Datapath
    datapath #(
        .WIDTH(WIDTH),
        .L(8) // 128 bit / 16 bit-per-cycle = 8 chu kỳ
    ) u_datapath (
        .clk(clk),
        .rst(rst),
        .A(A),
        .B(B),
        .load(load),
        .en(en),
        .enc(enc),
        .zc(zc),
        .Y(Y)
    );

    // Instance của Controller (FSM)
    controller u_controller (
        .clk(clk),
        .rst(rst),
        .start(start),
        .zc(zc),
        .load(load),
        .en(en),
        .enc(enc),
        .done(done)
    );

endmodule