// ============================================================================
// controller - FSM dieu khien, dau ra la thanh ghi (khong co logic giai ma
// giua state va cac tin hieu fanout lon load/en).
// IDLE -> LOAD -> COMPUTE (L chu ky) -> FLUSH (1 chu ky) -> DONE -> IDLE
// ============================================================================
module controller (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire zc,
    (* max_fanout = 32 *) output reg load,
    (* max_fanout = 32 *) output reg en,
    output reg  enc,
    output reg  done
);
    localparam S_IDLE    = 3'd0,
               S_LOAD    = 3'd1,
               S_COMPUTE = 3'd2,
               S_FLUSH   = 3'd3,
               S_DONE    = 3'd4;

    reg [2:0] state, nstate;

    always @(*) begin
        case (state)
            S_IDLE:    nstate = start ? S_LOAD : S_IDLE;
            S_LOAD:    nstate = S_COMPUTE;
            S_COMPUTE: nstate = zc ? S_FLUSH : S_COMPUTE;
            S_FLUSH:   nstate = S_DONE;
            S_DONE:    nstate = S_IDLE;
            default:   nstate = S_IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            load  <= 1'b0;
            en    <= 1'b0;
            enc   <= 1'b0;
            done  <= 1'b0;
        end else begin
            state <= nstate;
            load  <= (nstate == S_LOAD);
            en    <= (nstate == S_COMPUTE);
            enc   <= (nstate == S_COMPUTE);
            done  <= (nstate == S_DONE);
        end
    end
endmodule
