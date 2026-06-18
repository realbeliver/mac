// sem20_inference_top.v  -  SEM20 Inference Pipeline Top
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
//
//  Flow: Q8.8 -> enc(3cy) -> MAC(12cy) -> dec(3cy) -> Q8.8   Total: 18 cycles
//  clr_acc is delayed 3 cycles via shift register to align with encoded operands.
`timescale 1ns/1ps

module sem20_inference_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire signed [15:0] a_q8p8,
    input  wire signed [15:0] b_q8p8,
    input  wire        in_valid,
    input  wire        clr_acc,
    output wire signed [15:0] out_q8p8,
    output wire        out_valid
);

    // Stage 1: dual Q8.8 -> SEM20 encoders (3 cycles each)
    wire [19:0] sem_a, sem_b;
    wire        enc_a_valid, enc_b_valid;

    q8p8_to_sem20 enc_a (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_q8p8  (a_q8p8),
        .in_valid (in_valid),
        .out_sem20(sem_a),
        .out_valid(enc_a_valid)
    );

    q8p8_to_sem20 enc_b (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_q8p8  (b_q8p8),
        .in_valid (in_valid),
        .out_sem20(sem_b),
        .out_valid(enc_b_valid)
    );

    wire mac_in_valid = enc_a_valid & enc_b_valid;

    // clr_acc 3-cycle delay to align with encoder latency
    reg [2:0] clr_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clr_pipe <= 3'b000;
        else        clr_pipe <= {clr_pipe[1:0], clr_acc};
    end
    wire mac_clr = clr_pipe[2];

    // Stage 2: SEM20 MAC (12 cycles: mul5 + add6 + outFF1)
    wire [19:0] mac_result;
    wire        mac_valid;

    sem20_mac #(.W(20)) mac_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (mac_in_valid),
        .a        (sem_a),
        .b        (sem_b),
        .clr_acc  (mac_clr),
        .out_valid(mac_valid),
        .result   (mac_result)
    );

    // Stage 3: SEM20 -> Q8.8 decoder (3 cycles)
    sem20_to_q8p8_pipelined dec_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .sem_in   (mac_result),
        .in_valid (mac_valid),
        .q88_out  (out_q8p8),
        .out_valid(out_valid)
    );

endmodule
