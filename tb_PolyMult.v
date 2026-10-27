`timescale 1ns / 1ps

module tb_PolyMult;

    // 1. Khai báo thông số & Tham số hệ thống
    parameter WIDTH = 128;
    parameter CLK_PERIOD = 10; // Xung clock 10ns (Tương ứng tần số 100 MHz)

    // 2. Khai báo tín hiệu kết nối với module PolyMult
    reg               clk;
    reg               rst;
    reg               start;
    reg  [WIDTH-1:0]  A;
    reg  [WIDTH-1:0]  B;
    wire [WIDTH-1:0]  Y;
    wire              done;

    // 3. Gọi (Instance) Module Top-Level PolyMult
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

    // 4. Tạo Xung Clock (Dao động liên tục với chu kỳ 10ns)
    always #(CLK_PERIOD / 2) clk = ~clk;

    // 5. Kịch bản mô phỏng (Test Scenario)
    initial begin
        // Khoảng thời gian 0ns: Khởi tạo giá trị ban đầu
        clk   = 0;
        rst   = 1;
        start = 0;
        A     = 128'h0;
        B     = 128'h0;

        // Giữ reset trong 20ns rồi thả
        #20;
        rst = 0;
        #10;

        // --- TEST CASE 1: Nạp dữ liệu A và B ---
        $display("--------------------------------------------------");
        $display("[Test Case 1] Nap du lieu va bat dau tinh toán...");
        
        // Giá trị thử nghiệm (Bạn có thể thay đổi tùy ý)
        A = 128'h0123456789ABCDEF0123456789ABCDEF;
        B = 128'hFEDCBA9876543210FEDCBA9876543210;
        
        // Bật tín hiệu start trong 1 chu kỳ clock
        start = 1;
        #(CLK_PERIOD);
        start = 0;

        // Chờ tín hiệu done từ PolyMult kích hoạt (Done = 1)
        wait(done);
        #(CLK_PERIOD / 2); // Chờ nửa chu kỳ để ổn định dữ liệu ngõ ra

        $display("  -> Ket qua Y (HEX): 0x%h", Y);
        $display("  -> Hoan thanh Test Case 1!");
        $display("--------------------------------------------------");

        // --- TEST CASE 2: Kiểm tra tính liên tiếp ---
        #30;
        $display("[Test Case 2] Tinh phep nhan thu hai...");
        
        A = 128'h11112222333344445555666677778888;
        B = 128'h9999AAAABBBBCCCCDDDDEEEEFFFF0000;
        
        start = 1;
        #(CLK_PERIOD);
        start = 0;

        wait(done);
        #(CLK_PERIOD / 2);

        $display("  -> Ket qua Y (HEX): 0x%h", Y);
        $display("  -> Hoan thanh Test Case 2!");
        $display("--------------------------------------------------");

        // Dừng mô phỏng
        #50;
        $finish;
    end

endmodule