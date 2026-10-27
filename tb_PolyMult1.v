`timescale 1ns / 1ps

module tb_PolyMult;

    // 1. Khai báo thông số hệ thống
    parameter WIDTH = 128;
    parameter CLK_PERIOD = 10; // Xung clock 10ns (100 MHz)

    // 2. Khai báo tín hiệu giao tiếp với PolyMult
    reg               clk;
    reg               rst;
    reg               start;
    reg  [WIDTH-1:0]  A;
    reg  [WIDTH-1:0]  B;
    wire [WIDTH-1:0]  Y;
    wire              done;

    // Biến lưu số lượng lỗi
    integer error_count = 0;

    // 3. Khai báo Instance Top-Level Module
    PolyMult #(
        .WIDTH(WIDTH)
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

    // Task thực thi và kiểm tra từng Test Case
    task run_author_test(
        input [128-1:0] test_A,
        input [128-1:0] test_B,
        input [128-1:0] expected_Y,
        input integer   set_num
    );
        begin
            $display("------------------------------------------------------------------");
            $display("[SET %0d] Chạy test vector tác giả...", set_num);
            
            A = test_A;
            B = test_B;

            // Bật tín hiệu Start trong 1 chu kỳ clock
            start = 1;
            #(CLK_PERIOD);
            start = 0;

            // Chờ tín hiệu Done báo hoàn tất tính toán
            wait(done);
            #(CLK_PERIOD / 2); // Chờ nửa chu kỳ để dữ liệu ra Y ổn định

            $display("  -> Input A : 0x%h", A);
            $display("  -> Input B : 0x%h", B);
            $display("  -> Real Y  : 0x%h", Y);
            $display("  -> Exp  Y  : 0x%h", expected_Y);

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

    // 5. Kịch bản mô phỏng chính
    initial begin
        // Khởi tạo trạng thái ban đầu
        clk         = 0;
        rst         = 1;
        start       = 0;
        A           = 128'h0;
        B           = 128'h0;
        error_count = 0;

        // Giữ Reset trong 20ns
        #20;
        rst = 0;
        #10;

        $display("\n==================================================================");
        $display("     Verify             ");
        $display("==================================================================\n");

        // --- SET 1 (Tác giả) ---[cite: 5]
        run_author_test(
            128'h67FCE141A13EE970966BDCEA977E013E, // A[cite: 5]
            128'h09E0C5F854C4B5CB59731A224A9A9FFC, // B[cite: 5]
            128'h0897FAF94D6ACDA7B28B0879266EA79A, // Y[cite: 5]
            1
        );
        #30;

        // --- SET 2 (Tác giả) ---[cite: 5]
        run_author_test(
            128'h2D04924F09601ECB25EC275D754A4D8C, // A[cite: 5]
            128'h3AB1805D5BE290F8818C57FA899B6056, // B[cite: 5]
            128'hC1773D31D0F0BAF912EAAA37D83C9FF0, // Y[cite: 5]
            2
        );
        #30;

        // TỔNG KẾT
        $display("==================================================================");
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