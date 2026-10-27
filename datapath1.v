module datapath #(
    parameter WIDTH = 128,
    parameter L = 8
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

    reg [WIDTH-1:0] Pa_reg;
    reg [WIDTH-1:0] Pb_reg;
    reg [WIDTH-1:0] accum_reg;
    reg [3:0]       counter;

    wire [WIDTH-1:0] A_stage [0:16];

    // Nạp & Dịch dữ liệu
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            Pa_reg <= {WIDTH{1'b0}};
            Pb_reg <= {WIDTH{1'b0}};
        end else if (load) begin
            Pa_reg <= A;
            Pb_reg <= B;
        end else if (en) begin
            Pa_reg <= A_stage[16];
            Pb_reg <= Pb_reg >> 16; // Dịch phải 16-bit
        end
    end

    // Chuỗi 16 tầng MultX
    assign A_stage[0] = Pa_reg;
    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin : gen_multx
            wire msb = A_stage[k][WIDTH-1];
            assign A_stage[k+1] = (A_stage[k] << 1) ^ (msb ? 128'h87 : 128'h0);
        end
    endgenerate

    // Cây XOR MUX combinational cho 16 bit
    reg [WIDTH-1:0] xor_sum_comb;
    integer i;
    always @(*) begin
        xor_sum_comb = {WIDTH{1'b0}};
        for (i = 0; i < 16; i = i + 1) begin
            if (Pb_reg[i]) xor_sum_comb = xor_sum_comb ^ A_stage[i];
        end
    end

    // Accumulator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_reg <= {WIDTH{1'b0}};
        end else if (load) begin
            accum_reg <= {WIDTH{1'b0}};
        end else if (en) begin
            accum_reg <= accum_reg ^ xor_sum_comb;
        end
    end

    assign Y = accum_reg;

    // Counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 4'd0;
        end else if (load) begin
            counter <= 4'd0;
        end else if (enc) begin
            counter <= counter + 1'b1;
        end
    end

    assign zc = (counter == (L - 1));

endmodule