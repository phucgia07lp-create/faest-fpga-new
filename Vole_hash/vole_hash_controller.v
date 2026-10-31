/*----------------------------------------------------------------------------
 * File                 : vole_hash_controller.v
 * Author               : Claude
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Khối điều khiển (FSM) của bộ tăng tốc vole_hash_128
 *                        FAEST-128S. Thứ tự dữ liệu x vào: x0, x1..x_DEG_MAX
 *                        (vòng Horner), sau đó 4 từ đuôi (tail). Mọi ngõ ra
 *                        đều là ngõ ra đăng ký (registered), căn đúng theo
 *                        trạng thái hiện tại.
 * Modification history :
 *     31.10.2026 - Chuyển sang rule code: port <n>_in/<n>_out, RST tích cực
 *                  mức thấp, hậu tố _r/_w, FSM 3 khối, ngõ ra registered.
 *                  Bỏ cờ final_started (thay bằng trạng thái FIN_START),
 *                  bỏ bộ đếm tail trùng lặp (dùng Tail_last_in từ datapath).
 *----------------------------------------------------------------------------*/

module vole_hash_controller #(
    parameter STATE_WIDTH = 4
) (
    input  wire CLK,
    input  wire RST,

    input  wire Start_in,
    input  wire X_valid_in,
    input  wire Mul_done_in,
    input  wire Step_last_in,
    input  wire Tail_last_in,

    output wire Idle_out,
    output wire Load_x_out,
    output wire Fetch_x_out,
    output wire Tail_x_out,
    output wire Mul_start_out,
    output wire Wait_out,
    output wire Fin_sel_out,
    output wire Fin_wait_out,
    output wire X_ready_out,
    output wire Done_out
);

    //------------------------------------------------------------------//
    // Tham số trạng thái                                               //
    //------------------------------------------------------------------//
    parameter IDLE      = 0;    // chờ Start_in
    parameter LOAD_X0   = 1;    // nhận x0, nạp vào cả 5 luồng y
    parameter FETCH_X   = 2;    // nhận x_i cho bước Horner hiện tại
    parameter MUL_START = 3;    // phát xung start cho 5 bộ nhân
    parameter MUL_WAIT  = 4;    // chờ bộ nhân xong, cập nhật y
    parameter FIN_TAIL  = 5;    // nhận 4 từ đuôi x_{ell'}..x_{ell'+3}
    parameter FIN_START = 6;    // phát xung start cho 4 phép nhân r_i * y0
    parameter FIN_WAIT  = 7;    // chờ bộ nhân xong, tính h_i
    parameter DONE      = 8;    // báo xong, H_out hợp lệ

    //------------------------------------------------------------------//
    // Wire                                                             //
    //------------------------------------------------------------------//
    wire xfer_w;                // có một giao dịch x (valid và ready)

    //------------------------------------------------------------------//
    // Reg                                                              //
    //------------------------------------------------------------------//
    reg [STATE_WIDTH-1:0] state_r;
    reg [STATE_WIDTH-1:0] next_state_r;

    reg idle_r;
    reg load_x_r;
    reg fetch_x_r;
    reg tail_x_r;
    reg mul_start_r;
    reg wait_r;
    reg fin_sel_r;
    reg fin_wait_r;
    reg x_ready_r;
    reg done_r;

    //------------------------------------------------------------------//
    // Mạch tổ hợp                                                      //
    //------------------------------------------------------------------//
    // Giao dịch x xảy ra khi bên ngoài báo valid và FSM đang ready
    assign xfer_w = X_valid_in & x_ready_r;

    assign Idle_out      = idle_r;
    assign Load_x_out    = load_x_r;
    assign Fetch_x_out   = fetch_x_r;
    assign Tail_x_out    = tail_x_r;
    assign Mul_start_out = mul_start_r;
    assign Wait_out      = wait_r;
    assign Fin_sel_out   = fin_sel_r;
    assign Fin_wait_out  = fin_wait_r;
    assign X_ready_out   = x_ready_r;
    assign Done_out      = done_r;

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
                    next_state_r = LOAD_X0;
                end else begin
                    next_state_r = IDLE;
                end
            end
            LOAD_X0: begin
                if (xfer_w) begin
                    next_state_r = FETCH_X;
                end else begin
                    next_state_r = LOAD_X0;
                end
            end
            FETCH_X: begin
                if (xfer_w) begin
                    next_state_r = MUL_START;
                end else begin
                    next_state_r = FETCH_X;
                end
            end
            MUL_START: begin
                next_state_r = MUL_WAIT;
            end
            MUL_WAIT: begin
                if (Mul_done_in) begin
                    if (Step_last_in) begin
                        next_state_r = FIN_TAIL;
                    end else begin
                        next_state_r = FETCH_X;
                    end
                end else begin
                    next_state_r = MUL_WAIT;
                end
            end
            FIN_TAIL: begin
                if (xfer_w && Tail_last_in) begin
                    next_state_r = FIN_START;
                end else begin
                    next_state_r = FIN_TAIL;
                end
            end
            FIN_START: begin
                next_state_r = FIN_WAIT;
            end
            FIN_WAIT: begin
                if (Mul_done_in) begin
                    next_state_r = DONE;
                end else begin
                    next_state_r = FIN_WAIT;
                end
            end
            DONE: begin
                next_state_r = IDLE;
            end
            default: begin
                next_state_r = IDLE;
            end
        endcase
    end

    // 3. Ngõ ra registered, giải mã từ next_state_r nên trùng khớp trạng thái
    always @(posedge CLK or negedge RST) begin
        if (RST == 0) begin
            idle_r      <= 1'b1;
            load_x_r    <= 1'b0;
            fetch_x_r   <= 1'b0;
            tail_x_r    <= 1'b0;
            mul_start_r <= 1'b0;
            wait_r      <= 1'b0;
            fin_sel_r   <= 1'b0;
            fin_wait_r  <= 1'b0;
            x_ready_r   <= 1'b0;
            done_r      <= 1'b0;
        end else begin
            idle_r      <= (next_state_r == IDLE);
            load_x_r    <= (next_state_r == LOAD_X0);
            fetch_x_r   <= (next_state_r == FETCH_X);
            tail_x_r    <= (next_state_r == FIN_TAIL);
            mul_start_r <= (next_state_r == MUL_START) || (next_state_r == FIN_START);
            wait_r      <= (next_state_r == MUL_WAIT);
            fin_sel_r   <= (next_state_r == FIN_START) || (next_state_r == FIN_WAIT);
            fin_wait_r  <= (next_state_r == FIN_WAIT);
            x_ready_r   <= (next_state_r == LOAD_X0) || (next_state_r == FETCH_X) ||
                           (next_state_r == FIN_TAIL);
            done_r      <= (next_state_r == DONE);
        end
    end

endmodule
