// sem20_mac.v  -  SEM20 MAC (Multiply-Accumulate)
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
//
// Latency: sem20_mul(5) + sem20_add(6) + output_FF(1) = 12 cycles
`timescale 1ns/1ps

module sem20_mac #(parameter W = 20) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire         clr_acc,
    output reg          out_valid,
    output reg  [W-1:0] result
);

    wire         mul_valid;
    wire [W-1:0] mul_product;
    wire         add_valid;
    wire [W-1:0] add_result;
    wire [W-1:0] acc_out;
    wire         acc_out_valid;

    // Stage 1: multiplier (5 cycles)
    sem20_mul #(.W(W)) mul_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .a         (a),
        .b         (b),
        .product   (mul_product),
        .valid_out (mul_valid)
    );

    // Stage 2: accumulator register (combinational output, registered capture)
    sem20_acc_ip #(.W(W)) acc_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .clr_acc   (clr_acc),
        .in_valid  (add_valid),
        .d_in      (add_result),
        .acc_out   (acc_out),
        .out_valid (acc_out_valid)
    );

    // Stage 3: adder (6 cycles) — product + accumulated sum
    sem20_add add_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (mul_valid),
        .a         (mul_product),
        .b         (acc_out),
        .out_valid (add_valid),
        .result    (add_result)
    );

    // Output register (1 cycle)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            result    <= {W{1'b0}};
        end else begin
            out_valid <= add_valid;
            result    <= add_result;
        end
    end

endmodule
