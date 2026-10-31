/*----------------------------------------------------------------------------
 * File                 : controller.v
 * Author               : Hardware Team
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : FSM điều khiển bộ nhân PolyMult. Ngõ ra là thanh ghi
 *                        (registered), giải mã từ next_state_r nên không có
 *                        logic giải mã giữa state_r và các tín hiệu fanout lớn
 *                        Load_out, En_out.
 *                        IDLE -> LOAD -> COMPUTE (L chu kỳ) -> FLUSH (1 chu kỳ)
 *                        -> DONE -> IDLE.
 * Modification history :
 *     31.10.2026 - Chuyển sang rule code: port <n>_in/<n>_out, CLK/RST (RST
 *                  tích cực mức thấp), bỏ output reg (dùng reg _r + assign),
 *                  FSM tách 3 khối đánh số, tên trạng thái IDLE, LOAD, ...
 *                  Giữ thuộc tính max_fanout trên load_r, en_r.
 *----------------------------------------------------------------------------*/

module controller #(
    parameter STATE_WIDTH = 3
) (
    input  wire CLK,
    input  wire RST,

    input  wire Start_in,
    input  wire Zc_in,

    output wire Load_out,
    output wire En_out,
    output wire Enc_out,
    output wire Done_out
);

    //------------------------------------------------------------------//
    // Tham số trạng thái                                               //
    //------------------------------------------------------------------//
    parameter IDLE    = 0;      // chờ Start_in
    parameter LOAD    = 1;      // nạp A, B, xóa bộ cộng dồn và bộ đếm
    parameter COMPUTE = 2;      // L chu kỳ tính, mỗi chu kỳ xử lý D bit của B
    parameter FLUSH   = 3;      // 1 chu kỳ xả stage pipeline cuối
    parameter DONE    = 4;      // Y_out hợp lệ

    //------------------------------------------------------------------//
    // Reg                                                              //
    //------------------------------------------------------------------//
    reg [STATE_WIDTH-1:0] state_r;
    reg [STATE_WIDTH-1:0] next_state_r;

    (* max_fanout = 32 *) reg load_r;
    (* max_fanout = 32 *) reg en_r;
    reg                    enc_r;
    reg                    done_r;

    //------------------------------------------------------------------//
    // Mạch tổ hợp                                                      //
    //------------------------------------------------------------------//
    assign Load_out = load_r;
    assign En_out   = en_r;
    assign Enc_out  = enc_r;
    assign Done_out = done_r;

    //------------------------------------------------------------------//
    // FSM                                                              //
    //------------------------------------------------------------------//
    // 1. Thanh ghi trạng thái
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            state_r <= IDLE;
        end else begin
            state_r <= next_state_r;
        end
    end

    // 2. Logic trạng thái kế tiếp
    always @(*) begin
        next_state_r = state_r;
        case (state_r)
            IDLE: begin
                if (Start_in) begin
                    next_state_r = LOAD;
                end else begin
                    next_state_r = IDLE;
                end
            end
            LOAD: begin
                next_state_r = COMPUTE;
            end
            COMPUTE: begin
                if (Zc_in) begin
                    next_state_r = FLUSH;
                end else begin
                    next_state_r = COMPUTE;
                end
            end
            FLUSH: begin
                next_state_r = DONE;
            end
            DONE: begin
                next_state_r = IDLE;
            end
            default: begin
                next_state_r = IDLE;
            end
        endcase
    end

    // 3. Ngõ ra registered, căn theo trạng thái kế tiếp
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            load_r <= 1'b0;
            en_r   <= 1'b0;
            enc_r  <= 1'b0;
            done_r <= 1'b0;
        end else begin
            load_r <= (next_state_r == LOAD);
            en_r   <= (next_state_r == COMPUTE);
            enc_r  <= (next_state_r == COMPUTE);
            done_r <= (next_state_r == DONE);
        end
    end

endmodule
