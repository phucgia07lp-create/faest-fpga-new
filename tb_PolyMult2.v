`timescale 1ns / 1ps

module tb_PolyMult;

    // 1. Khai báo thông số hệ thống
    parameter WIDTH      = 128;
    parameter D          = 16;   // số bit xử lý mỗi chu kỳ (khớp với PolyMult)
    parameter G          = 4;    // số nhóm pipeline cây XOR (khớp với PolyMult)
    parameter CLK_PERIOD = 10;   // Xung clock 10ns (100 MHz)
    parameter NUM_RANDOM = 100;  // Số test vector ngẫu nhiên

    // 2. Khai báo tín hiệu giao tiếp với PolyMult
    reg               clk;
    reg               rst;
    reg               start;
    reg  [WIDTH-1:0]  A;
    reg  [WIDTH-1:0]  B;
    wire [WIDTH-1:0]  Y;
    wire              done;

    // Biến lưu số lượng lỗi và độ trễ
    integer error_count = 0;
    integer test_count  = 0;
    integer latency     = 0;
    integer k;
    time    t_start;

    // 3. Khai báo Instance Top-Level Module
    PolyMult #(
        .WIDTH(WIDTH),
        .D(D),
        .G(G)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .A(A),
        .B(B),
        .Y(Y),
        .done(done)
    );

    // 4. Tạo xung Clock
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Mô hình tham chiếu: nhân GF(2^128), đa thức x^128 + x^7 + x^2 + x + 1
    function [WIDTH-1:0] ref_mul(input [WIDTH-1:0] a, input [WIDTH-1:0] b);
        reg [WIDTH-1:0] x, r;
        integer i;
        begin
            x = a;
            r = {WIDTH{1'b0}};
            for (i = 0; i < WIDTH; i = i + 1) begin
                if (b[i]) r = r ^ x;
                x = {x[WIDTH-2:0], 1'b0} ^ ({WIDTH{x[WIDTH-1]}} & 128'h87);
            end
            ref_mul = r;
        end
    endfunction

    // Task thực thi một phép nhân: cấp A, B, bật Start, chờ Done
    task run_mult(input [WIDTH-1:0] test_A, input [WIDTH-1:0] test_B);
        begin
            A = test_A;
            B = test_B;

            // Bật tín hiệu Start trong 1 chu kỳ clock
            start   = 1;
            t_start = $time;
            #(CLK_PERIOD);
            start = 0;

            // Chờ tín hiệu Done báo hoàn tất tính toán
            wait(done);
            latency = ($time - t_start) / CLK_PERIOD;
            #(CLK_PERIOD / 2); // Chờ nửa chu kỳ để dữ liệu ra Y ổn định
        end
    endtask

    // Task kiểm tra test vector của tác giả (có kết quả mong đợi cho sẵn)
    task run_author_test(
        input [WIDTH-1:0] test_A,
        input [WIDTH-1:0] test_B,
        input [WIDTH-1:0] expected_Y,
        input integer     set_num
    );
        begin
            $display("------------------------------------------------------------------");
            $display("[SET %0d] Chạy test vector tác giả...", set_num);

            run_mult(test_A, test_B);
            test_count = test_count + 1;

            $display("  -> Input A : 0x%h", A);
            $display("  -> Input B : 0x%h", B);
            $display("  -> Real Y  : 0x%h", Y);
            $display("  -> Exp  Y  : 0x%h", expected_Y);
            $display("  -> Latency : %0d chu kỳ (từ Start đến Done)", latency);

            // Tự động kiểm tra kết quả
            if (Y === expected_Y) begin
                $display("  => KẾT QUẢ: [PASS] Trùng khớp với Test Vector tác giả!");
            end else begin
                $display("  => KẾT QUẢ: [FAIL] Sai khác so với kết quả mong đợi!");
                error_count = error_count + 1;
            end
            $display("------------------------------------------------------------------\n");
        end
    endtask

    // Task kiểm tra với mô hình tham chiếu (trường hợp biên và ngẫu nhiên)
    task run_ref_test(
        input [WIDTH-1:0] test_A,
        input [WIDTH-1:0] test_B,
        input integer     set_num
    );
        reg [WIDTH-1:0] expected_Y;
        begin
            expected_Y = ref_mul(test_A, test_B);
            run_mult(test_A, test_B);
            test_count = test_count + 1;

            if (Y !== expected_Y) begin
                $display("[SET %0d] [FAIL] A=0x%h B=0x%h", set_num, test_A, test_B);
                $display("          Real Y=0x%h  Exp Y=0x%h", Y, expected_Y);
                error_count = error_count + 1;
            end
            #(CLK_PERIOD * 2);
        end
    endtask

    // 5. Kịch bản mô phỏng chính
    initial begin
        // Khởi tạo trạng thái ban đầu
        clk         = 0;
        rst         = 1;
        start       = 0;
        A           = {WIDTH{1'b0}};
        B           = {WIDTH{1'b0}};
        error_count = 0;

        // Giữ Reset trong 20ns
        #20;
        rst = 0;
        #10;

        $display("\n==================================================================");
        $display("     Verify   (D = %0d, G = %0d)", D, G);
        $display("==================================================================\n");

        // --- SET 1 (Tác giả) ---
        run_author_test(
            128'h67FCE141A13EE970966BDCEA977E013E, // A
            128'h09E0C5F854C4B5CB59731A224A9A9FFC, // B
            128'h0897FAF94D6ACDA7B28B0879266EA79A, // Y
            1
        );
        #30;

        // --- SET 2 (Tác giả) ---
        run_author_test(
            128'h2D04924F09601ECB25EC275D754A4D8C, // A
            128'h3AB1805D5BE290F8818C57FA899B6056, // B
            128'hC1773D31D0F0BAF912EAAA37D83C9FF0, // Y
            2
        );
        #30;

        // --- Các trường hợp biên (so với mô hình tham chiếu) ---
        $display("Chạy các trường hợp biên...");
        run_ref_test(128'h0, 128'h0, 3);
        run_ref_test(128'h1, 128'h1, 4);
        run_ref_test({WIDTH{1'b1}}, {WIDTH{1'b1}}, 5);
        run_ref_test({WIDTH{1'b1}}, 128'h1, 6);
        run_ref_test({1'b1, {(WIDTH-1){1'b0}}}, 128'h2, 7);
        run_ref_test({(WIDTH/2){2'b01}}, {(WIDTH/2){2'b10}}, 8);

        // --- Test ngẫu nhiên ---
        $display("Chạy %0d test vector ngẫu nhiên...", NUM_RANDOM);
        for (k = 0; k < NUM_RANDOM; k = k + 1) begin
            run_ref_test({$random, $random, $random, $random},
                         {$random, $random, $random, $random}, 9 + k);
        end

        // TỔNG KẾT
        $display("\n==================================================================");
        $display("  Số test: %0d | Số lỗi: %0d | Latency: %0d chu kỳ", test_count, error_count, latency);
        if (error_count == 0) begin
            $display("  PASS");
        end else begin
            $display("  => CÓ %0d KẾT QUẢ BỊ LỖI! [FAILED]", error_count);
        end
        $display("==================================================================\n");

        #50;
        $finish;
    end

endmodule
