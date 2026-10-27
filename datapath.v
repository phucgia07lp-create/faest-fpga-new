module datapath #(
    parameter WIDTH = 128,
    parameter L = 8 // 128 bit / 16 bit-per-cyclea
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

    // Pipeline Registers cho chuỗi MultX (mỗi 4 stage)
    reg [WIDTH-1:0] A_pipe1; // Sau 4 MultX
    reg [WIDTH-1:0] A_pipe2; // Sau 8 MultX
    reg [WIDTH-1:0] A_pipe3; // Sau 12 MultX

    // Pipeline Registers cho Pb để đồng bộ nhịp với A_stage
    reg [11:0] Pb_stage1_pipe; // Delay Pb[15:4] 1 cycle
    reg [7:0]  Pb_stage2_pipe; // Delay Pb[15:8] 2 cycles
    reg [3:0]  Pb_stage3_pipe; // Delay Pb[15:12] 3 cycles

    // Reg cho cây MUX XOR
    reg [WIDTH-1:0] xor_sum_reg;

    // 1. Nạp & Dịch dữ liệu
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            Pa_reg <= {WIDTH{1'b0}};
            Pb_reg <= {WIDTH{1'b0}};
        end else if (load) begin
            Pa_reg <= A;
            Pb_reg <= B;
        end else if (en) begin
            Pa_reg <= A_stage[16];
            Pb_reg <= {Pb_reg[15:0], Pb_reg[WIDTH-1:16]};
        end
    end

    // --- MultX Part 1 (0..3) ---
    assign A_stage[0] = Pa_reg;
    genvar k1;
    generate
        for (k1 = 0; k1 < 4; k1 = k1 + 1) begin : gen_multx_p1
            wire msb = A_stage[k1][WIDTH-1];
            assign A_stage[k1+1] = (A_stage[k1] << 1) ^ (msb ? 128'h87 : 128'h0);
        end
    endgenerate

    // Pipeline Stage 1
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            A_pipe1        <= {WIDTH{1'b0}};
            Pb_stage1_pipe <= 12'd0;
        end else if (en) begin
            A_pipe1        <= A_stage[4];
            Pb_stage1_pipe <= Pb_reg[15:4];
        end
    end

    // --- MultX Part 2 (4..7) ---
    assign A_stage[4] = A_pipe1;
    genvar k2;
    generate
        for (k2 = 4; k2 < 8; k2 = k2 + 1) begin : gen_multx_p2
            wire msb = A_stage[k2][WIDTH-1];
            assign A_stage[k2+1] = (A_stage[k2] << 1) ^ (msb ? 128'h87 : 128'h0);
        end
    endgenerate

    // Pipeline Stage 2
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            A_pipe2        <= {WIDTH{1'b0}};
            Pb_stage2_pipe <= 8'd0;
        end else if (en) begin
            A_pipe2        <= A_stage[8];
            Pb_stage2_pipe <= Pb_stage1_pipe[11:4];
        end
    end

    // --- MultX Part 3 (8..11) ---
    assign A_stage[8] = A_pipe2;
    genvar k3;
    generate
        for (k3 = 8; k3 < 12; k3 = k3 + 1) begin : gen_multx_p3
            wire msb = A_stage[k3][WIDTH-1];
            assign A_stage[k3+1] = (A_stage[k3] << 1) ^ (msb ? 128'h87 : 128'h0);
        end
    endgenerate

    // Pipeline Stage 3
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            A_pipe3        <= {WIDTH{1'b0}};
            Pb_stage3_pipe <= 4'd0;
        end else if (en) begin
            A_pipe3        <= A_stage[12];
            Pb_stage3_pipe <= Pb_stage2_pipe[7:4];
        end
    end

    // --- MultX Part 4 (12..15) ---
    assign A_stage[12] = A_pipe3;
    genvar k4;
    generate
        for (k4 = 12; k4 < 16; k4 = k4 + 1) begin : gen_multx_p4
            wire msb = A_stage[k4][WIDTH-1];
            assign A_stage[k4+1] = (A_stage[k4] << 1) ^ (msb ? 128'h87 : 128'h0);
        end
    endgenerate

    // Cây XOR MUX combinational
    reg [WIDTH-1:0] xor_sum_comb;
    integer i;
    always @(*) begin
        xor_sum_comb = {WIDTH{1'b0}};
        for (i = 0; i < 4; i = i + 1) begin
            if (Pb_reg[i])               xor_sum_comb = xor_sum_comb ^ A_stage[i];
            if (Pb_stage1_pipe[i])       xor_sum_comb = xor_sum_comb ^ A_stage[i+4];
            if (Pb_stage2_pipe[i])       xor_sum_comb = xor_sum_comb ^ A_stage[i+8];
            if (Pb_stage3_pipe[i])       xor_sum_comb = xor_sum_comb ^ A_stage[i+12];
        end
    end

    // Pipeline Register ngắt đường accum
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            xor_sum_reg <= {WIDTH{1'b0}};
        end else if (en) begin
            xor_sum_reg <= xor_sum_comb;
        end
    end

    // Accumulator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_reg <= {WIDTH{1'b0}};
        end else if (load) begin
            accum_reg <= {WIDTH{1'b0}};
        end else if (en) begin
            accum_reg <= accum_reg ^ xor_sum_reg;
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