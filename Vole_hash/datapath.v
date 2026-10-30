/*---- File: datapath.v / Author: Hardware Team / Description: Datapath with internal x_reg to prevent data corruption. ----*/

module vole_hash_datapath #(
    parameter DATA_WIDTH = 128
)(
    input  wire                      CLK,
    input  wire                      RST_N,
    input  wire                      load_x_in,
    input  wire                      fetch_x_in,
    input  wire                      mul_start_in,
    input  wire                      update_y_in,
    input  wire                      update_h_in,
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
    input  wire [2:0]                state_in,
    input  wire [15:0]               deg_max_in,

    output wire [15:0]               step_cnt_out,
    output wire                      mul_done_out,
    output wire [DATA_WIDTH-1:0]     h_out_0,
    output wire [DATA_WIDTH-1:0]     h_out_1,
    output wire [DATA_WIDTH-1:0]     h_out_2,
    output wire [DATA_WIDTH-1:0]     h_out_3
);

    reg [15:0]           step_cnt_r, next_step_cnt_r;

    reg [DATA_WIDTH-1:0] s_reg_0, s_reg_1, s_reg_2, s_reg_3, s_reg_4;
    reg [DATA_WIDTH-1:0] r_reg_0, r_reg_1, r_reg_2, r_reg_3;
    reg [DATA_WIDTH-1:0] y_r_0, y_r_1, y_r_2, y_r_3, y_r_4;
    reg [DATA_WIDTH-1:0] next_y_r_0, next_y_r_1, next_y_r_2, next_y_r_3, next_y_r_4;
    reg [DATA_WIDTH-1:0] h_r_0, h_r_1, h_r_2, h_r_3;
    reg [DATA_WIDTH-1:0] x_reg; // Thanh ghi l?u tr? x an toàn
    reg [2:0] tail_count;
    reg [DATA_WIDTH-1:0] tail_0, tail_1, tail_2, tail_3;

    wire                 mul_done_w0, mul_done_w1, mul_done_w2, mul_done_w3, mul_done_w4;
    wire [DATA_WIDTH-1:0] mul_y_w0, mul_y_w1, mul_y_w2, mul_y_w3, mul_y_w4;
    reg [DATA_WIDTH-1:0]  mul_a_w0, mul_a_w1, mul_a_w2, mul_a_w3, mul_a_w4;
    reg [DATA_WIDTH-1:0]  mul_b_w0, mul_b_w1, mul_b_w2, mul_b_w3, mul_b_w4;

    //---- 5 Parallel PolyMult Instances ----//
    PolyMult #(.WIDTH(DATA_WIDTH), .D(16), .G(4)) u_pm0 (
        .clk(CLK), .rst(~RST_N), .start(mul_start_in),
        .A(mul_a_w0), .B(mul_b_w0), .Y(mul_y_w0), .done(mul_done_w0)
    );
    PolyMult #(.WIDTH(DATA_WIDTH), .D(16), .G(4)) u_pm1 (
        .clk(CLK), .rst(~RST_N), .start(mul_start_in),
        .A(mul_a_w1), .B(mul_b_w1), .Y(mul_y_w1), .done(mul_done_w1)
    );
    PolyMult #(.WIDTH(DATA_WIDTH), .D(16), .G(4)) u_pm2 (
        .clk(CLK), .rst(~RST_N), .start(mul_start_in),
        .A(mul_a_w2), .B(mul_b_w2), .Y(mul_y_w2), .done(mul_done_w2)
    );
    PolyMult #(.WIDTH(DATA_WIDTH), .D(16), .G(4)) u_pm3 (
        .clk(CLK), .rst(~RST_N), .start(mul_start_in),
        .A(mul_a_w3), .B(mul_b_w3), .Y(mul_y_w3), .done(mul_done_w3)
    );
    PolyMult #(.WIDTH(DATA_WIDTH), .D(16), .G(4)) u_pm4 (
        .clk(CLK), .rst(~RST_N), .start(mul_start_in),
        .A(mul_a_w4), .B(mul_b_w4), .Y(mul_y_w4), .done(mul_done_w4)
    );

    //---- Multiplexer for Multiplier Inputs ----//
    always @(*) begin
        mul_a_w0 = y_r_0; mul_b_w0 = s_reg_0;
        mul_a_w1 = y_r_1; mul_b_w1 = s_reg_1;
        mul_a_w2 = y_r_2; mul_b_w2 = s_reg_2;
        mul_a_w3 = y_r_3; mul_b_w3 = s_reg_3;
        mul_a_w4 = y_r_4; mul_b_w4 = s_reg_4;

        if (state_in == 3'd6) begin // Final h multiplications, four lanes in parallel
            mul_a_w0 = y_r_0; mul_b_w0 = r_reg_0;
            mul_a_w1 = y_r_0; mul_b_w1 = r_reg_1;
            mul_a_w2 = y_r_0; mul_b_w2 = r_reg_2;
            mul_a_w3 = y_r_0; mul_b_w3 = r_reg_3;
            mul_a_w4 = y_r_0; mul_b_w4 = {DATA_WIDTH{1'b0}};
        end
    end

    //---- Step Counter Logic ----//
    always @(*) begin
        next_step_cnt_r = step_cnt_r;
        if (state_in == 3'd0) begin // S_IDLE
            next_step_cnt_r = 16'd0;
        end else if (state_in == 3'd1) begin // S_LOAD_X0
            next_step_cnt_r = 16'd1;
        end else if (state_in == 3'd4 && mul_done_w0) begin // S_MUL_WAIT
            if (step_cnt_r != deg_max_in) begin
                next_step_cnt_r = step_cnt_r + 16'd1;
            end else begin
                next_step_cnt_r = 16'd0;
            end
        end else if (state_in == 3'd6 && mul_done_w0) begin // S_FIN_WAIT
            if (step_cnt_r != 16'd3) begin
                next_step_cnt_r = step_cnt_r + 16'd1;
            end
        end
    end

    //---- Accumulator Updates ----//
    always @(*) begin
        next_y_r_0 = y_r_0;
        next_y_r_1 = y_r_1;
        next_y_r_2 = y_r_2;
        next_y_r_3 = y_r_3;
        next_y_r_4 = y_r_4;

        if (load_x_in) begin
            next_y_r_0 = x_data_in;
            next_y_r_1 = x_data_in;
            next_y_r_2 = x_data_in;
            next_y_r_3 = x_data_in;
            next_y_r_4 = x_data_in;
        end else if (update_y_in) begin
            next_y_r_0 = mul_y_w0 ^ x_reg;
            next_y_r_1 = mul_y_w1 ^ x_reg;
            next_y_r_2 = mul_y_w2 ^ x_reg;
            next_y_r_3 = mul_y_w3 ^ x_reg;
            next_y_r_4 = mul_y_w4 ^ x_reg;
        end
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            step_cnt_r <= 16'd0;
            y_r_0 <= {DATA_WIDTH{1'b0}};
            y_r_1 <= {DATA_WIDTH{1'b0}};
            y_r_2 <= {DATA_WIDTH{1'b0}};
            y_r_3 <= {DATA_WIDTH{1'b0}};
            y_r_4 <= {DATA_WIDTH{1'b0}};
            h_r_0 <= {DATA_WIDTH{1'b0}};
            h_r_1 <= {DATA_WIDTH{1'b0}};
            h_r_2 <= {DATA_WIDTH{1'b0}};
            h_r_3 <= {DATA_WIDTH{1'b0}};
            x_reg <= {DATA_WIDTH{1'b0}};
            tail_count <= 0;
            tail_0 <= 0; tail_1 <= 0; tail_2 <= 0; tail_3 <= 0;

            s_reg_0 <= {DATA_WIDTH{1'b0}};
            s_reg_1 <= {DATA_WIDTH{1'b0}};
            s_reg_2 <= {DATA_WIDTH{1'b0}};
            s_reg_3 <= {DATA_WIDTH{1'b0}};
            s_reg_4 <= {DATA_WIDTH{1'b0}};
            r_reg_0 <= {DATA_WIDTH{1'b0}};
            r_reg_1 <= {DATA_WIDTH{1'b0}};
            r_reg_2 <= {DATA_WIDTH{1'b0}};
            r_reg_3 <= {DATA_WIDTH{1'b0}};
        end else begin
            step_cnt_r <= next_step_cnt_r;
            y_r_0 <= next_y_r_0;
            y_r_1 <= next_y_r_1;
            y_r_2 <= next_y_r_2;
            y_r_3 <= next_y_r_3;
            y_r_4 <= next_y_r_4;

            if (load_x_in || fetch_x_in) begin
                x_reg <= x_data_in; // L?u x vào thanh ghi n?i b? an toàn
            end

            if (state_in == 3'd5 && fetch_x_in) begin
                case (tail_count)
                    0: tail_0 <= x_data_in;
                    1: tail_1 <= x_data_in;
                    2: tail_2 <= x_data_in;
                    3: tail_3 <= x_data_in;
                endcase
                if (tail_count != 3) tail_count <= tail_count + 1'b1;
            end

            if (state_in == 3'd0 && start_in) begin
                tail_count <= 0;
                s_reg_0 <= s_in_0;
                s_reg_1 <= s_in_1;
                s_reg_2 <= s_in_2;
                s_reg_3 <= s_in_3;
                s_reg_4 <= s_in_4;
                r_reg_0 <= r_in_0;
                r_reg_1 <= r_in_1;
                r_reg_2 <= r_in_2;
                r_reg_3 <= r_in_3;
            end

            if (update_h_in) begin
                h_r_0 <= mul_y_w0 ^ y_r_1 ^ tail_0;
                h_r_1 <= mul_y_w1 ^ y_r_2 ^ tail_1;
                h_r_2 <= mul_y_w2 ^ y_r_3 ^ tail_2;
                h_r_3 <= mul_y_w3 ^ y_r_4 ^ tail_3;
            end
        end
    end

    //---- Outputs ----//
    assign step_cnt_out = step_cnt_r;
    assign mul_done_out = mul_done_w0;
    assign h_out_0      = h_r_0;
    assign h_out_1      = h_r_1;
    assign h_out_2      = h_r_2;
    assign h_out_3      = h_r_3;

endmodule
