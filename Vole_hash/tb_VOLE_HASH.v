`timescale 1ns/1ps

module tb_vole_hash_128;
  reg CLK = 1'b0;
  always #1 CLK = ~CLK; // 2 ns clock period (500 MHz)

  reg RST_N = 1'b0;
  reg start_in = 1'b0;
  reg [127:0] s_in_0, s_in_1, s_in_2, s_in_3, s_in_4;
  reg [127:0] r_in_0, r_in_1, r_in_2, r_in_3;
  reg [127:0] x_data_in = 128'b0;
  reg x_valid_in = 1'b0;
  wire x_ready_out;
  wire [127:0] h_out_0, h_out_1, h_out_2, h_out_3;
  wire done_out;

  reg [127:0] x_words [0:10];
  integer i;
  integer cycles;

  vole_hash_128_top #(.DATA_WIDTH(128), .DEG_MAX(6)) dut (
    .CLK(CLK), .RST_N(RST_N), .start_in(start_in),
    .s_in_0(s_in_0), .s_in_1(s_in_1), .s_in_2(s_in_2),
    .s_in_3(s_in_3), .s_in_4(s_in_4),
    .r_in_0(r_in_0), .r_in_1(r_in_1), .r_in_2(r_in_2), .r_in_3(r_in_3),
    .x_data_in(x_data_in), .x_valid_in(x_valid_in),
    .x_ready_out(x_ready_out), .h_out_0(h_out_0), .h_out_1(h_out_1),
    .h_out_2(h_out_2), .h_out_3(h_out_3), .done_out(done_out)
  );

  // Deliver one x word using the ready/valid handshake.
  task send_x;
    input [127:0] value;
    begin
      @(negedge CLK);
      x_data_in = value;
      x_valid_in = 1'b1;
      // Wait for ready at the falling edge, then transfer on the next rising edge.
      while (x_ready_out !== 1'b1) @(negedge CLK);
      @(posedge CLK);
      @(negedge CLK);
      x_valid_in = 1'b0;
    end
  endtask

  initial begin
    // Test vector vole_hash_128_3_tv: ell=5, d_zk=3, ell_prime=7.
    // Byte-to-vector conversion follows bf128_load on little-endian hosts.
    r_in_0 = 128'h87f2e59a42f1435339b4c257468133ab;
    r_in_1 = 128'h526d5ba6c7713e8d4972742dc3409970;
    r_in_2 = 128'h2f0896cd2cea0659e54133e5f83c54ff;
    r_in_3 = 128'he0cea86df1a286b8834d4631b2e82f54;

    s_in_0 = 128'h36b7a1f09706ba955ba46d015da6cf61;
    s_in_1 = 128'he1d1ae2a2e3c45dcabab19f2b6509a09;
    s_in_2 = 128'h5e50747c689be838ed85bcbe72a9dd02;
    s_in_3 = 128'h6a549b0c1e0677b1779f0712733a8315;
    // t is 8 bytes in C and is zero-padded to 128 bits.
    s_in_4 = 128'h00000000000000008a41bc9ab03ed310;

    x_words[0]  = 128'h3b9113d940790b080dea844240877973; // x[0]
    x_words[1]  = 128'h2644598fec28fbe575bee31e66f3591d; // x[1]
    x_words[2]  = 128'hfd7d217b18724247a32bf53da4c34774; // x[2]
    x_words[3]  = 128'ha8049cbe30caf010d00629d04472da68; // x[3]
    x_words[4]  = 128'h50514577f8e3669ca3a2acabe8d9b47d; // x[4]
    x_words[5]  = 128'hb0140cb295f27d08f9f76c0639c3b7c7; // x[5]
    x_words[6]  = 128'h56deb1c36795d3e0c1b932bac9077b50; // x[6]
    x_words[7]  = 128'h28ddc78972c816ef16fac439b81e1da0; // final x term 0
    x_words[8]  = 128'hb8a3ecb69ec1e122543a4a4c3d1f6200; // final x term 1
    x_words[9]  = 128'h50e46444a96a5deb3809670f93429dc8; // final x term 2
    x_words[10] = 128'h421dec67c22ba13fbbfcb756a07c71b7; // final x term 3

    repeat (4) @(negedge CLK);
    RST_N = 1'b1;
    @(negedge CLK);
    start_in = 1'b1;
    @(negedge CLK);
    start_in = 1'b0;

    // Input sequence: x0, x1..x6 (Horner loop), and four tail terms.
    for (i = 0; i < 11; i = i + 1)
      send_x(x_words[i]);

    cycles = 0;
    while (!done_out && cycles < 10000) begin
      @(posedge CLK);
      cycles = cycles + 1;
    end
    if (!done_out) begin
      $display("FAIL: timeout waiting for done_out");
      $fatal(1);
    end
    // Let output registers settle after the done transition.
    @(negedge CLK);

    if (h_out_0 !== 128'hc564b540e13f1d89597d5b48e0c48324) begin
      $display("FAIL h0: got %032h expected c564b540e13f1d89597d5b48e0c48324", h_out_0); $fatal(1);
    end
    if (h_out_1 !== 128'hd0512212a5457cfde092188bc2cbfcc9) begin
      $display("FAIL h1: got %032h expected d0512212a5457cfde092188bc2cbfcc9", h_out_1); $fatal(1);
    end
    if (h_out_2 !== 128'h1e1c01e6fb83d6a0bcce2f4be62b6363) begin
      $display("FAIL h2: got %032h expected 1e1c01e6fb83d6a0bcce2f4be62b6363", h_out_2); $fatal(1);
    end
    if (h_out_3 !== 128'h6f1ec0223ac05b3cbb447bf5d67f26a5) begin
      $display("FAIL h3: got %032h expected 6f1ec0223ac05b3cbb447bf5d67f26a5", h_out_3); $fatal(1);
    end

    $display("PASS: vole_hash_128_3_tv matched all 64 expected output bytes");
    $finish;
  end
endmodule
