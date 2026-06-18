// sem20_acc_ip.v  -  SEM20 Accumulator Register
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
`timescale 1ns/1ps

module sem20_acc_ip #(
    parameter W = 20
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clr_acc,
    input  wire         in_valid,
    input  wire [W-1:0] d_in,
    output wire [W-1:0] acc_out,
    output wire         out_valid
);

    reg [W-1:0] reg_data;
    reg         reg_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_data  <= {W{1'b0}};
            reg_valid <= 1'b0;
        end else begin
            if (clr_acc) begin
                reg_data  <= {W{1'b0}};
                reg_valid <= 1'b0;
            end else if (in_valid) begin
                reg_data  <= d_in;
                reg_valid <= 1'b1;
            end else begin
                reg_valid <= 1'b0;
            end
        end
    end

    assign acc_out   = reg_data;
    assign out_valid = reg_valid;

endmodule
