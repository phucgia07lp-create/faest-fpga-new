/*----------------------------------------------------------------------------
 * File                 : vole_hash_128_top_tb.v
 * Author               : Claude
 * Created              : 31.10.2026
 * Last modified        : 31.10.2026
 * Description          : Testbench của vole_hash_128_top. Gồm: (1) vector đã
 *                        biết kết quả từ mã C (vole_hash_128_3_tv, ell = 5,
 *                        d_zk = 3, chỉ chạy khi DEG_MAX = 6), (2) các test ngẫu
 *                        nhiên so với golden model viết ngay trong testbench
 *                        (nhân GF(2^128) dịch-cộng, vòng Horner như mã C),
 *                        (3) test toàn 0 và toàn 1. Giao diện x dùng ready/valid.
 * Modification history :
 *     31.10.2026 - Viết lại theo rule testbench: CLK #5, task run_test đồng bộ
 *                  cạnh lên, wait (Done_out == 1), so sánh ===, watchdog,
 *                  $dumpfile/$dumpvars. Bỏ $fatal (SystemVerilog).
 *----------------------------------------------------------------------------*/

`timescale 1ns/1ps

module vole_hash_128_top_tb;

    parameter DATA_WIDTH = 128;
    parameter CNT_WIDTH  = 16;
    parameter DEG_MAX    = 6;               // ell' - 1; KAT của mã C có ell' = 7
    parameter NUM_RANDOM = 20;              // số test ngẫu nhiên
    parameter TIMEOUT    = 200000000;       // watchdog (ns)
    parameter [DATA_WIDTH-1:0] POLY = 8'h87; // phần rút gọn x^7 + x^2 + x + 1

    // Ngõ vào của uut
    reg                   CLK;
    reg                   RST;
    reg                   Start_in;
    reg [DATA_WIDTH-1:0]  S0_in;
    reg [DATA_WIDTH-1:0]  S1_in;
    reg [DATA_WIDTH-1:0]  S2_in;
    reg [DATA_WIDTH-1:0]  S3_in;
    reg [DATA_WIDTH-1:0]  S4_in;
    reg [DATA_WIDTH-1:0]  R0_in;
    reg [DATA_WIDTH-1:0]  R1_in;
    reg [DATA_WIDTH-1:0]  R2_in;
    reg [DATA_WIDTH-1:0]  R3_in;
    reg [DATA_WIDTH-1:0]  X_data_in;
    reg                   X_valid_in;

    // Ngõ ra của uut
    wire                  X_ready_out;
    wire [DATA_WIDTH-1:0] H0_out;
    wire [DATA_WIDTH-1:0] H1_out;
    wire [DATA_WIDTH-1:0] H2_out;
    wire [DATA_WIDTH-1:0] H3_out;
    wire                  Done_out;

    // Dữ liệu test và giá trị kỳ vọng
    reg [DATA_WIDTH-1:0]  x_mem [0:DEG_MAX+4];  // DEG_MAX+1 từ Horner + 4 từ đuôi
    reg [DATA_WIDTH-1:0]  s_g [0:4];            // điểm đánh giá s_0..s_4 cho golden model
    reg [DATA_WIDTH-1:0]  y_g [0:4];            // 5 luồng Horner của golden model
    reg [DATA_WIDTH-1:0]  exp_h0;
    reg [DATA_WIDTH-1:0]  exp_h1;
    reg [DATA_WIDTH-1:0]  exp_h2;
    reg [DATA_WIDTH-1:0]  exp_h3;

    integer seed;
    integer test_cnt;
    integer pass_cnt;
    integer fail_cnt;
    integer cycle_cnt;

    //------------------------------------------------------------------//
    // uut                                                              //
    //------------------------------------------------------------------//
    vole_hash_128_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(CNT_WIDTH),
        .DEG_MAX(DEG_MAX)
    ) uut (
        .CLK(CLK),
        .RST(RST),
        .Start_in(Start_in),
        .S0_in(S0_in),
        .S1_in(S1_in),
        .S2_in(S2_in),
        .S3_in(S3_in),
        .S4_in(S4_in),
        .R0_in(R0_in),
        .R1_in(R1_in),
        .R2_in(R2_in),
        .R3_in(R3_in),
        .X_data_in(X_data_in),
        .X_valid_in(X_valid_in),
        .X_ready_out(X_ready_out),
        .H0_out(H0_out),
        .H1_out(H1_out),
        .H2_out(H2_out),
        .H3_out(H3_out),
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
        $dumpfile("vole_hash_128_top_tb.vcd");
        $dumpvars(0, vole_hash_128_top_tb);
    end

    initial begin
        #(TIMEOUT);
        $display("TIMEOUT: testbench chay qua %0d ns", TIMEOUT);
        $finish;
    end

    //------------------------------------------------------------------//
    // Golden model                                                     //
    //------------------------------------------------------------------//
    // Nhân GF(2^128): dịch-cộng, rút gọn theo POLY (giống bf128_mul trong mã C)
    function [DATA_WIDTH-1:0] gf_mul;
        input [DATA_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] b;
        integer k;
        reg [DATA_WIDTH-1:0] acc;
        reg [DATA_WIDTH-1:0] t;
        begin
            acc = {DATA_WIDTH{1'b0}};
            t   = a;
            for (k = 0; k < DATA_WIDTH; k = k + 1) begin
                if (b[k]) begin
                    acc = acc ^ t;
                end
                if (t[DATA_WIDTH-1]) begin
                    t = {t[DATA_WIDTH-2:0], 1'b0} ^ POLY;
                end else begin
                    t = {t[DATA_WIDTH-2:0], 1'b0};
                end
            end
            gf_mul = acc;
        end
    endfunction

    // Tính h kỳ vọng từ S, R, x_mem đã nạp (S4 chỉ lấy nửa thấp, nửa cao = 0)
    task golden_calc;
        integer i;
        integer j;
        begin
            s_g[0] = S0_in;
            s_g[1] = S1_in;
            s_g[2] = S2_in;
            s_g[3] = S3_in;
            s_g[4] = {{(DATA_WIDTH/2){1'b0}}, S4_in[DATA_WIDTH/2-1:0]};
            for (j = 0; j < 5; j = j + 1) begin
                y_g[j] = x_mem[0];
            end
            for (i = 1; i <= DEG_MAX; i = i + 1) begin
                for (j = 0; j < 5; j = j + 1) begin
                    y_g[j] = gf_mul(y_g[j], s_g[j]) ^ x_mem[i];
                end
            end
            exp_h0 = gf_mul(R0_in, y_g[0]) ^ y_g[1] ^ x_mem[DEG_MAX+1];
            exp_h1 = gf_mul(R1_in, y_g[0]) ^ y_g[2] ^ x_mem[DEG_MAX+2];
            exp_h2 = gf_mul(R2_in, y_g[0]) ^ y_g[3] ^ x_mem[DEG_MAX+3];
            exp_h3 = gf_mul(R3_in, y_g[0]) ^ y_g[4] ^ x_mem[DEG_MAX+4];
        end
    endtask

    //------------------------------------------------------------------//
    // Tạo dữ liệu                                                      //
    //------------------------------------------------------------------//
    task rand_word;
        output [DATA_WIDTH-1:0] w;
        integer q;
        begin
            for (q = 0; q < DATA_WIDTH/32; q = q + 1) begin
                w[q*32 +: 32] = $random(seed);
            end
        end
    endtask

    task load_random;
        integer i;
        begin
            rand_word(S0_in);
            rand_word(S1_in);
            rand_word(S2_in);
            rand_word(S3_in);
            rand_word(S4_in);
            rand_word(R0_in);
            rand_word(R1_in);
            rand_word(R2_in);
            rand_word(R3_in);
            for (i = 0; i < DEG_MAX + 5; i = i + 1) begin
                rand_word(x_mem[i]);
            end
        end
    endtask

    task load_const;
        input [DATA_WIDTH-1:0] value;
        integer i;
        begin
            S0_in = value;
            S1_in = value;
            S2_in = value;
            S3_in = value;
            S4_in = value;
            R0_in = value;
            R1_in = value;
            R2_in = value;
            R3_in = value;
            for (i = 0; i < DEG_MAX + 5; i = i + 1) begin
                x_mem[i] = value;
            end
        end
    endtask

    // Vector đã biết kết quả từ mã C: vole_hash_128_3_tv (ell = 5, d_zk = 3)
    // Chuyển byte sang vector theo bf128_load trên máy little-endian
    task load_kat;
        begin
            R0_in = 128'h87f2e59a42f1435339b4c257468133ab;
            R1_in = 128'h526d5ba6c7713e8d4972742dc3409970;
            R2_in = 128'h2f0896cd2cea0659e54133e5f83c54ff;
            R3_in = 128'he0cea86df1a286b8834d4631b2e82f54;
            S0_in = 128'h36b7a1f09706ba955ba46d015da6cf61;
            S1_in = 128'he1d1ae2a2e3c45dcabab19f2b6509a09;
            S2_in = 128'h5e50747c689be838ed85bcbe72a9dd02;
            S3_in = 128'h6a549b0c1e0677b1779f0712733a8315;
            S4_in = 128'h00000000000000008a41bc9ab03ed310;  // t 8 byte, zero-padding
            x_mem[0]  = 128'h3b9113d940790b080dea844240877973;
            x_mem[1]  = 128'h2644598fec28fbe575bee31e66f3591d;
            x_mem[2]  = 128'hfd7d217b18724247a32bf53da4c34774;
            x_mem[3]  = 128'ha8049cbe30caf010d00629d04472da68;
            x_mem[4]  = 128'h50514577f8e3669ca3a2acabe8d9b47d;
            x_mem[5]  = 128'hb0140cb295f27d08f9f76c0639c3b7c7;
            x_mem[6]  = 128'h56deb1c36795d3e0c1b932bac9077b50;
            x_mem[7]  = 128'h28ddc78972c816ef16fac439b81e1da0;  // x tail 0
            x_mem[8]  = 128'hb8a3ecb69ec1e122543a4a4c3d1f6200;  // x tail 1
            x_mem[9]  = 128'h50e46444a96a5deb3809670f93429dc8;  // x tail 2
            x_mem[10] = 128'h421dec67c22ba13fbbfcb756a07c71b7;  // x tail 3
        end
    endtask

    //------------------------------------------------------------------//
    // Giao tiếp với uut                                                //
    //------------------------------------------------------------------//
    // Gửi một từ x theo ready/valid: DUT lấy mẫu tại cạnh lên CLK khi valid và ready cùng 1
    task send_x;
        input [DATA_WIDTH-1:0] value;
        reg sent;
        begin
            X_data_in  = value;
            X_valid_in = 1'b1;
            sent       = 1'b0;
            while (!sent) begin
                @(posedge CLK);
                if (X_ready_out === 1'b1) begin
                    sent = 1'b1;
                end
            end
            #1;
            X_valid_in = 1'b0;
        end
    endtask

    // Chạy một test: phát Start, gửi x, chờ Done_out, so sánh H_out (===)
    // use_kat = 1: so với giá trị kỳ vọng nạp sẵn trong exp_h*, không tính golden
    task run_test;
        input integer test_id;
        input         use_kat;
        integer       w;
        integer       t_start;
        reg           ok;
        begin
            if (!use_kat) begin
                golden_calc;
            end
            t_start = cycle_cnt;

            @(posedge CLK);
            #1;
            Start_in = 1'b1;
            @(posedge CLK);
            #1;
            Start_in = 1'b0;

            for (w = 0; w < DEG_MAX + 5; w = w + 1) begin
                send_x(x_mem[w]);
            end

            wait (Done_out == 1'b1);
            #1;
            ok = (H0_out === exp_h0) && (H1_out === exp_h1) &&
                 (H2_out === exp_h2) && (H3_out === exp_h3);

            test_cnt = test_cnt + 1;
            if (ok) begin
                pass_cnt = pass_cnt + 1;
                $display("Test %0d PASSED (%0d chu ky)", test_id, cycle_cnt - t_start);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("Test %0d FAILED", test_id);
                $display("  h0 nhan duoc %032h, ky vong %032h", H0_out, exp_h0);
                $display("  h1 nhan duoc %032h, ky vong %032h", H1_out, exp_h1);
                $display("  h2 nhan duoc %032h, ky vong %032h", H2_out, exp_h2);
                $display("  h3 nhan duoc %032h, ky vong %032h", H3_out, exp_h3);
            end

            // Chờ controller về IDLE trước test kế tiếp
            @(posedge CLK);
            @(posedge CLK);
        end
    endtask

    //------------------------------------------------------------------//
    // Kịch bản test                                                    //
    //------------------------------------------------------------------//
    integer n;

    initial begin
        CLK        = 1'b0;
        RST        = 1'b0;
        Start_in   = 1'b0;
        X_data_in  = {DATA_WIDTH{1'b0}};
        X_valid_in = 1'b0;
        S0_in = 0; S1_in = 0; S2_in = 0; S3_in = 0; S4_in = 0;
        R0_in = 0; R1_in = 0; R2_in = 0; R3_in = 0;
        seed      = 32'h1F2E3D4C;
        test_cnt  = 0;
        pass_cnt  = 0;
        fail_cnt  = 0;
        cycle_cnt = 0;

        // Giữ reset 4 chu kỳ rồi nhả
        repeat (4) @(posedge CLK);
        #1;
        RST = 1'b1;
        repeat (2) @(posedge CLK);

        // Test KAT từ mã C (chỉ hợp lệ khi DEG_MAX = 6)
        if (DEG_MAX == 6) begin
            load_kat;
            golden_calc;
            if ((exp_h0 !== 128'hc564b540e13f1d89597d5b48e0c48324) ||
                (exp_h1 !== 128'hd0512212a5457cfde092188bc2cbfcc9) ||
                (exp_h2 !== 128'h1e1c01e6fb83d6a0bcce2f4be62b6363) ||
                (exp_h3 !== 128'h6f1ec0223ac05b3cbb447bf5d67f26a5)) begin
                $display("CANH BAO: golden model KHONG khop vector C, kiem tra lai testbench");
            end
            exp_h0 = 128'hc564b540e13f1d89597d5b48e0c48324;
            exp_h1 = 128'hd0512212a5457cfde092188bc2cbfcc9;
            exp_h2 = 128'h1e1c01e6fb83d6a0bcce2f4be62b6363;
            exp_h3 = 128'h6f1ec0223ac05b3cbb447bf5d67f26a5;
            run_test(1, 1'b1);
        end

        // Test toàn 0 và toàn 1
        load_const({DATA_WIDTH{1'b0}});
        run_test(test_cnt + 1, 1'b0);
        load_const({DATA_WIDTH{1'b1}});
        run_test(test_cnt + 1, 1'b0);

        // Test ngẫu nhiên so với golden model
        for (n = 0; n < NUM_RANDOM; n = n + 1) begin
            load_random;
            run_test(test_cnt + 1, 1'b0);
        end

        $display("----------------------------------------------");
        $display("Tong so test: %0d, PASSED: %0d, FAILED: %0d", test_cnt, pass_cnt, fail_cnt);
        if (fail_cnt == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
        end
        $finish;
    end

endmodule
