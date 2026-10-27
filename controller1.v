module controller (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire zc,
    output reg  load,
    output reg  en,
    output reg  enc,
    output reg  done
);

    localparam S_WAIT    = 2'b00;
    localparam S_LOAD    = 2'b01;
    localparam S_COMPUTE = 2'b10; // Đảm bảo đúng 2'b10
    localparam S_DONE    = 2'b11;

    reg [1:0] current_state, next_state;

    always @(posedge clk or posedge rst) begin
        if (rst)
            current_state <= S_WAIT;
        else
            current_state <= next_state;
    end

    always @(*) begin
        case (current_state)
            S_WAIT:    next_state = start ? S_LOAD : S_WAIT;
            S_LOAD:    next_state = S_COMPUTE;
            S_COMPUTE: next_state = zc ? S_DONE : S_COMPUTE;
            S_DONE:    next_state = S_WAIT;
            default:   next_state = S_WAIT;
        endcase
    end

    always @(*) begin
        load = 1'b0;
        en   = 1'b0;
        enc  = 1'b0;
        done = 1'b0;

        case (current_state)
            S_LOAD:    load = 1'b1;
            S_COMPUTE: begin
                en  = 1'b1;
                enc = 1'b1;
            end
            S_DONE:    done = 1'b1;
            default: ;
        endcase
    end

endmodule