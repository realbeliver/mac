// q8p8_to_sem20.v  -  Q8.8 signed -> SEM20 20-bit float encoder
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
//
// 3-cycle pipeline:
//   Stage 0: sign extraction + abs value
//   Stage 1: LZD (leading-zero detect) -> registered
//   Stage 2: normalize + pack
//
// SEM20: [19]=sign [18:13]=exp(bias=31) [12:0]=mantissa(implicit 1)

`timescale 1ns/1ps

module q8p8_to_sem20 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire signed [15:0] in_q8p8,
    input  wire        in_valid,
    output wire [19:0] out_sem20,
    output wire        out_valid
);

    // -------------------------------------------------------
    // Stage 0: sign + abs
    // -------------------------------------------------------
    reg        s0_sign;
    reg [15:0] s0_abs;
    reg        s0_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_valid <= 1'b0;
            s0_sign  <= 1'b0;
            s0_abs   <= 16'h0000;
        end else begin
            s0_valid <= in_valid;
            s0_sign  <= in_q8p8[15];
            if (in_q8p8 == 16'sh8000)
                s0_abs <= 16'h8000;
            else
                s0_abs <= in_q8p8[15] ? (-in_q8p8) : in_q8p8;
        end
    end

    // -------------------------------------------------------
    // LZD (combinational) on s0_abs
    // Returns position of highest set bit (0-15), valid=0 if all zero
    // -------------------------------------------------------
    reg [3:0] lzd_pos;
    reg       lzd_valid;

    always @(*) begin
        casez (s0_abs)
            16'b1???_????_????_????: begin lzd_pos = 4'd15; lzd_valid = 1'b1; end
            16'b01??_????_????_????: begin lzd_pos = 4'd14; lzd_valid = 1'b1; end
            16'b001?_????_????_????: begin lzd_pos = 4'd13; lzd_valid = 1'b1; end
            16'b0001_????_????_????: begin lzd_pos = 4'd12; lzd_valid = 1'b1; end
            16'b0000_1???_????_????: begin lzd_pos = 4'd11; lzd_valid = 1'b1; end
            16'b0000_01??_????_????: begin lzd_pos = 4'd10; lzd_valid = 1'b1; end
            16'b0000_001?_????_????: begin lzd_pos = 4'd9;  lzd_valid = 1'b1; end
            16'b0000_0001_????_????: begin lzd_pos = 4'd8;  lzd_valid = 1'b1; end
            16'b0000_0000_1???_????: begin lzd_pos = 4'd7;  lzd_valid = 1'b1; end
            16'b0000_0000_01??_????: begin lzd_pos = 4'd6;  lzd_valid = 1'b1; end
            16'b0000_0000_001?_????: begin lzd_pos = 4'd5;  lzd_valid = 1'b1; end
            16'b0000_0000_0001_????: begin lzd_pos = 4'd4;  lzd_valid = 1'b1; end
            16'b0000_0000_0000_1???: begin lzd_pos = 4'd3;  lzd_valid = 1'b1; end
            16'b0000_0000_0000_01??: begin lzd_pos = 4'd2;  lzd_valid = 1'b1; end
            16'b0000_0000_0000_001?: begin lzd_pos = 4'd1;  lzd_valid = 1'b1; end
            16'b0000_0000_0000_0001: begin lzd_pos = 4'd0;  lzd_valid = 1'b1; end
            default:                 begin lzd_pos = 4'd0;  lzd_valid = 1'b0; end
        endcase
    end

    // -------------------------------------------------------
    // Stage 1: register LZD output + abs + sign
    // -------------------------------------------------------
    reg        s1_sign;
    reg [15:0] s1_abs;
    reg        s1_valid;
    reg [3:0]  s1_msb;
    reg        s1_nonzero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid   <= 1'b0;
            s1_sign    <= 1'b0;
            s1_abs     <= 16'h0000;
            s1_msb     <= 4'h0;
            s1_nonzero <= 1'b0;
        end else begin
            s1_valid   <= s0_valid;
            s1_sign    <= s0_sign;
            s1_abs     <= s0_abs;
            s1_msb     <= lzd_pos;
            s1_nonzero <= lzd_valid;
        end
    end

    // -------------------------------------------------------
    // Stage 2: normalize + pack
    // exp_unbiased = msb - 8  (Q8.8: integer part starts at bit 8)
    // biased exp   = exp_unbiased + 31
    // Combined:    E = msb - 8 + 31 = msb + 23
    //
    // Normalize: shift abs so leading 1 lands at bit 13
    //   if msb > 13: right-shift by (msb-13)
    //   if msb < 13: left-shift  by (13-msb)
    //
    // All variables declared at module scope (Yosys requirement)
    // -------------------------------------------------------
    reg [19:0] s2_out;
    reg        s2_valid;

    // Intermediate wires for Stage 2 combinational logic
    wire [5:0]  s2_E;
    wire [15:0] s2_norm;
    wire [3:0]  s2_shift_r;   // right shift amount (msb > 13)
    wire [3:0]  s2_shift_l;   // left  shift amount (msb < 13)

    // E = msb + 23  (= msb - 8 + 31)
    assign s2_E = s1_msb + 6'd23;

    // Shift amounts
    assign s2_shift_r = s1_msb - 4'd13;   // valid when s1_msb > 13
    assign s2_shift_l = 4'd13 - s1_msb;   // valid when s1_msb < 13

    // Normalized mantissa (16-bit, leading 1 at bit 13)
    assign s2_norm = (s1_msb > 4'd13) ? (s1_abs >> s2_shift_r) :
                     (s1_msb < 4'd13) ? (s1_abs << s2_shift_l) :
                                         s1_abs;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_out   <= 20'h00000;
        end else begin
            s2_valid <= s1_valid;
            if (!s1_nonzero)
                s2_out <= 20'h00000;
            else
                s2_out <= {s1_sign, s2_E, s2_norm[12:0]};
        end
    end

    assign out_sem20 = s2_out;
    assign out_valid = s2_valid;

endmodule
