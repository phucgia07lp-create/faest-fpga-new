/*----------------------------------------------------------------------------
 * File                 : PolyMult_tb.v
 * Author               : Claude
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Testbench của PolyMult (nhân GF(2^128), đa thức
 *                        x^128 + x^7 + x^2 + x + 1). Gồm: 2 bộ test vector của
 *                        tác giả luận văn (kết quả cho sẵn), các trường hợp
 *                        biên và test ngẫu nhiên so với golden model viết
 *                        ngay trong testbench (nhân dịch-cộng). Độ trễ được đo
 *                        từ cạnh lên lấy mẫu Start_in đến cạnh lên làm Done_out
 *                        bằng 1.
 * Modification history :
 *     31.10.2026 - Viết lại theo rule testbench: CLK #5, RST tích cực mức thấp,
 *                  task run_test đồng bộ cạnh lên, wait (Done_out == 1), so
 *                  sánh ===, watchdog, $dumpfile/$dumpvars. Golden model dùng
 *                  DATA_WIDTH thay cho hằng 128 bit.
 *----------------------------------------------------------------------------*/

`timescale 1ns/1ps

module PolyMult_tb;

    parameter DATA_WIDTH = 128;
    parameter D          = 16;                  // số bit xử lý mỗi chu kỳ (khớp PolyMult)
    parameter G          = 4;                   // số nhóm pipeline (khớp PolyMult)
    parameter NUM_RANDOM = 100;                 // số test ngẫu nhiên
    parameter TIMEOUT    = 10000000;            // watchdog (ns)
    parameter [DATA_WIDTH-1:0] POLY = 8'h87;    // phần rút gọn x^7 + x^2 + x + 1

    // Ngõ vào của uut
    reg                   CLK;
    reg                   RST;
    reg                   Start_in;
    reg [DATA_WIDTH-1:0]  A_in;
    reg [DATA_WIDTH-1:0]  B_in;

    // Ngõ ra của uut
    wire [DATA_WIDTH-1:0] Y_out;
    wire                  Done_out;

    integer seed;
    integer test_cnt;
    integer pass_cnt;
    integer fail_cnt;
    integer cycle_cnt;
    integer latency;
    integer n;

    //------------------------------------------------------------------//
    // uut                                                              //
    //------------------------------------------------------------------//
    PolyMult #(
        .DATA_WIDTH(DATA_WIDTH),
        .D(D),
        .G(G)
    ) uut (
        .CLK(CLK),
        .RST(RST),
        .Start_in(Start_in),
        .A_in(A_in),
        .B_in(B_in),
        .Y_out(Y_out),
        .Done_out(Done_out)
    );

    //------------------------------------------------------------------//
    // Clock, đếm chu kỳ, dump, watchdog                                //
    //------------------------------------------------------------------//
    always #5 CLK = ~CLK;

    always @(posedge CLK) begin
        cycle_cnt = cycle_cnt + 1;
    end

    initial begin
        $dumpfile("PolyMult_tb.vcd");
        $dumpvars(0, PolyMult_tb);
    end

    initial begin
        #(TIMEOUT);
        $display("TIMEOUT: testbench chay qua %0d ns", TIMEOUT);
        $finish;
    end

    //------------------------------------------------------------------//
    // Golden model                                                     //
    //------------------------------------------------------------------//
    // Nhân GF(2^DATA_WIDTH): dịch-cộng, rút gọn theo POLY
    function [DATA_WIDTH-1:0] ref_mul;
        input [DATA_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] b;
        integer i;
        reg [DATA_WIDTH-1:0] x;
        reg [DATA_WIDTH-1:0] r;
        begin
            x = a;
            r = {DATA_WIDTH{1'b0}};
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (b[i]) begin
                    r = r ^ x;
                end
                x = {x[DATA_WIDTH-2:0], 1'b0} ^ ({DATA_WIDTH{x[DATA_WIDTH-1]}} & POLY);
            end
            ref_mul = r;
        end
    endfunction

    task rand_word;
        output [DATA_WIDTH-1:0] w;
        integer q;
        begin
            for (q = 0; q < DATA_WIDTH/32; q = q + 1) begin
                w[q*32 +: 32] = $random(seed);
            end
        end
    endtask

    //------------------------------------------------------------------//
    // Chạy một test                                                    //
    //------------------------------------------------------------------//
    // use_exp = 1: so với exp_in cho sẵn (test vector tác giả)
    // use_exp = 0: so với golden model ref_mul
    task run_test;
        input integer          test_id;
        input [DATA_WIDTH-1:0] test_a;
        input [DATA_WIDTH-1:0] test_b;
        input                  use_exp;
        input [DATA_WIDTH-1:0] exp_in;
        reg   [DATA_WIDTH-1:0] exp_y;
        integer                t_start;
        reg                    ok;
        begin
            if (use_exp) begin
                exp_y = exp_in;
            end else begin
                exp_y = ref_mul(test_a, test_b);
            end

            A_in = test_a;
            B_in = test_b;
            @(posedge CLK);
            #1;
            Start_in = 1'b1;
            t_start  = cycle_cnt + 1;       // cạnh lên kế tiếp lấy mẫu Start_in
            @(posedge CLK);
            #1;
            Start_in = 1'b0;

            wait (Done_out == 1'b1);
            latency = cycle_cnt - t_start;
            #1;

            ok = (Y_out === exp_y);
            test_cnt = test_cnt + 1;
            if (ok) begin
                pass_cnt = pass_cnt + 1;
                $display("Test %0d PASSED (do tre %0d chu ky)", test_id, latency);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("Test %0d FAILED", test_id);
                $display("  A = %032h", test_a);
                $display("  B = %032h", test_b);
                $display("  Y nhan duoc %032h, ky vong %032h", Y_out, exp_y);
            end

            // Chờ về IDLE trước test kế tiếp
            repeat (3) @(posedge CLK);
        end
    endtask

    //------------------------------------------------------------------//
    // Kịch bản test                                                    //
    //------------------------------------------------------------------//
    reg [DATA_WIDTH-1:0] ra;
    reg [DATA_WIDTH-1:0] rb;

    initial begin
        CLK       = 1'b0;
        RST       = 1'b0;
        Start_in  = 1'b0;
        A_in      = {DATA_WIDTH{1'b0}};
        B_in      = {DATA_WIDTH{1'b0}};
        seed      = 32'h1F2E3D4C;
        test_cnt  = 0;
        pass_cnt  = 0;
        fail_cnt  = 0;
        cycle_cnt = 0;
        latency   = 0;

        // Giữ reset 4 chu kỳ rồi nhả
        repeat (4) @(posedge CLK);
        #1;
        RST = 1'b1;
        repeat (2) @(posedge CLK);

        // Test vector của tác giả (kết quả cho sẵn)
        run_test(1, 128'h67FCE141A13EE970966BDCEA977E013E,
                    128'h09E0C5F854C4B5CB59731A224A9A9FFC, 1'b1,
                    128'h0897FAF94D6ACDA7B28B0879266EA79A);
        run_test(2, 128'h2D04924F09601ECB25EC275D754A4D8C,
                    128'h3AB1805D5BE290F8818C57FA899B6056, 1'b1,
                    128'hC1773D31D0F0BAF912EAAA37D83C9FF0);

        // Các trường hợp biên (so với golden model)
        run_test(3, 0, 0, 1'b0, 0);
        run_test(4, 1, 1, 1'b0, 0);
        run_test(5, {DATA_WIDTH{1'b1}}, {DATA_WIDTH{1'b1}}, 1'b0, 0);
        run_test(6, {DATA_WIDTH{1'b1}}, 1, 1'b0, 0);
        run_test(7, {1'b1, {(DATA_WIDTH-1){1'b0}}}, 2, 1'b0, 0);
        run_test(8, {(DATA_WIDTH/2){2'b01}}, {(DATA_WIDTH/2){2'b10}}, 1'b0, 0);

        // Test ngẫu nhiên (so với golden model)
        for (n = 0; n < NUM_RANDOM; n = n + 1) begin
            rand_word(ra);
            rand_word(rb);
            run_test(9 + n, ra, rb, 1'b0, 0);
        end

        $display("----------------------------------------------");
        $display("Tong so test: %0d, PASSED: %0d, FAILED: %0d, do tre: %0d chu ky",
                 test_cnt, pass_cnt, fail_cnt, latency);
        if (fail_cnt == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
        end
        $finish;
    end

endmodule
