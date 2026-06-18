// sem20_add.v  -  SEM20 Floating-Point Adder  (6-stage pipeline)
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
//
// Format: [19]=sign [18:13]=exp(bias=31) [12:0]=mantissa(implicit 1)
// No * operator, No DSP, No vendor IP

`timescale 1ns/1ps

module sem20_add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [19:0] a,
    input  wire [19:0] b,
    output wire        out_valid,
    output wire [19:0] result
);

    // =========================================================
    // STAGE 0 FF: UNPACK
    // =========================================================
    reg        s0_valid;
    reg        s0_sign_a, s0_sign_b;
    reg [5:0]  s0_exp_a,  s0_exp_b;
    reg [13:0] s0_mant_a, s0_mant_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_valid  <= 1'b0;
            s0_sign_a <= 1'b0; s0_sign_b <= 1'b0;
            s0_exp_a  <= 6'h0; s0_exp_b  <= 6'h0;
            s0_mant_a <= 14'h0; s0_mant_b <= 14'h0;
        end else begin
            s0_valid  <= in_valid;
            s0_sign_a <= a[19];
            s0_sign_b <= b[19];
            s0_exp_a  <= a[18:13];
            s0_exp_b  <= b[18:13];
            s0_mant_a <= (a[18:13]==6'h0 && a[12:0]==13'h0) ? 14'h0 : {1'b1, a[12:0]};
            s0_mant_b <= (b[18:13]==6'h0 && b[12:0]==13'h0) ? 14'h0 : {1'b1, b[12:0]};
        end
    end

    // =========================================================
    // STAGE 1 COMB: ALIGNMENT
    // Pick big/small by exponent; right-shift smaller mantissa.
    // Barrel shift done with explicit case (no * operator).
    // =========================================================
    reg [5:0]  c1_exp_big;
    reg [13:0] c1_mant_big, c1_mant_sml_pre;
    reg        c1_sign_big, c1_sign_sml;
    reg [5:0]  c1_shamt;
    reg [27:0] c1_extended, c1_shifted;
    reg [13:0] c1_mant_sml_aligned;
    reg        c1_sticky;
    reg        c1_sign_a_r, c1_sign_b_r;   // original signs for stage 2

    always @(*) begin
        if (s0_exp_a >= s0_exp_b) begin
            c1_exp_big      = s0_exp_a;
            c1_mant_big     = s0_mant_a;
            c1_sign_big     = s0_sign_a;
            c1_mant_sml_pre = s0_mant_b;
            c1_sign_sml     = s0_sign_b;
            c1_shamt        = ((s0_exp_a - s0_exp_b) > 6'd14) ? 6'd14 : (s0_exp_a - s0_exp_b);
        end else begin
            c1_exp_big      = s0_exp_b;
            c1_mant_big     = s0_mant_b;
            c1_sign_big     = s0_sign_b;
            c1_mant_sml_pre = s0_mant_a;
            c1_sign_sml     = s0_sign_a;
            c1_shamt        = ((s0_exp_b - s0_exp_a) > 6'd14) ? 6'd14 : (s0_exp_b - s0_exp_a);
        end

        c1_extended = {c1_mant_sml_pre, 14'h0};

        case (c1_shamt)
            6'd0:    c1_shifted = c1_extended;
            6'd1:    c1_shifted = c1_extended >> 1;
            6'd2:    c1_shifted = c1_extended >> 2;
            6'd3:    c1_shifted = c1_extended >> 3;
            6'd4:    c1_shifted = c1_extended >> 4;
            6'd5:    c1_shifted = c1_extended >> 5;
            6'd6:    c1_shifted = c1_extended >> 6;
            6'd7:    c1_shifted = c1_extended >> 7;
            6'd8:    c1_shifted = c1_extended >> 8;
            6'd9:    c1_shifted = c1_extended >> 9;
            6'd10:   c1_shifted = c1_extended >> 10;
            6'd11:   c1_shifted = c1_extended >> 11;
            6'd12:   c1_shifted = c1_extended >> 12;
            6'd13:   c1_shifted = c1_extended >> 13;
            default: c1_shifted = c1_extended >> 14;
        endcase

        c1_mant_sml_aligned = c1_shifted[27:14];
        c1_sticky           = |c1_shifted[13:0];
        c1_sign_a_r         = s0_sign_a;
        c1_sign_b_r         = s0_sign_b;
    end

    reg        s1_valid;
    reg [5:0]  s1_exp_res;
    reg [13:0] s1_mant_big, s1_mant_sml;
    reg        s1_sticky;
    reg        s1_sign_big, s1_sign_sml;
    reg        s1_sign_a, s1_sign_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid    <= 1'b0;
            s1_exp_res  <= 6'h0;
            s1_mant_big <= 14'h0; s1_mant_sml <= 14'h0;
            s1_sticky   <= 1'b0;
            s1_sign_big <= 1'b0; s1_sign_sml <= 1'b0;
            s1_sign_a   <= 1'b0; s1_sign_b   <= 1'b0;
        end else begin
            s1_valid    <= s0_valid;
            s1_exp_res  <= c1_exp_big;
            s1_mant_big <= c1_mant_big;
            s1_mant_sml <= c1_mant_sml_aligned;
            s1_sticky   <= c1_sticky;
            s1_sign_big <= c1_sign_big;
            s1_sign_sml <= c1_sign_sml;
            s1_sign_a   <= c1_sign_a_r;
            s1_sign_b   <= c1_sign_b_r;
        end
    end

    // =========================================================
    // STAGE 2 COMB+FF: ADD / SUBTRACT
    // =========================================================
    wire        c2_same_sign    = (s1_sign_a == s1_sign_b);
    wire [14:0] c2_sum          = {1'b0, s1_mant_big} + {1'b0, s1_mant_sml};
    wire [14:0] c2_sub_big_sml  = {1'b0, s1_mant_big} - {1'b0, s1_mant_sml};
    wire [14:0] c2_sub_sml_big  = {1'b0, s1_mant_sml} - {1'b0, s1_mant_big};
    wire        c2_big_ge_sml   = (s1_mant_big >= s1_mant_sml);

    wire [14:0] c2_mant_res = c2_same_sign   ? c2_sum :
                              c2_big_ge_sml  ? c2_sub_big_sml : c2_sub_sml_big;
    wire        c2_sign_res = c2_same_sign   ? s1_sign_big :
                              c2_big_ge_sml  ? s1_sign_big : s1_sign_sml;

    reg        s2_valid;
    reg        s2_sign_res;
    reg [5:0]  s2_exp_res;
    reg [14:0] s2_mant_res;
    reg        s2_sticky;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid    <= 1'b0;
            s2_sign_res <= 1'b0;
            s2_exp_res  <= 6'h0;
            s2_mant_res <= 15'h0;
            s2_sticky   <= 1'b0;
        end else begin
            s2_valid    <= s1_valid;
            s2_sign_res <= c2_sign_res;
            s2_exp_res  <= s1_exp_res;
            s2_mant_res <= c2_mant_res;
            s2_sticky   <= s1_sticky;
        end
    end

    // =========================================================
    // STAGE 3 COMB+FF: NORMALIZE
    // lzd15: find leading zeros in 15-bit value
    // Replaced 'function automatic' (SV) with plain Verilog function.
    // =========================================================
    function [3:0] lzd15;
        input [14:0] x;
        begin
            casez (x)
                15'b1??????????????: lzd15 = 4'd0;
                15'b01?????????????: lzd15 = 4'd1;
                15'b001????????????: lzd15 = 4'd2;
                15'b0001???????????: lzd15 = 4'd3;
                15'b00001??????????: lzd15 = 4'd4;
                15'b000001?????????: lzd15 = 4'd5;
                15'b0000001????????: lzd15 = 4'd6;
                15'b00000001???????: lzd15 = 4'd7;
                15'b000000001??????: lzd15 = 4'd8;
                15'b0000000001?????: lzd15 = 4'd9;
                15'b00000000001????: lzd15 = 4'd10;
                15'b000000000001???: lzd15 = 4'd11;
                15'b0000000000001??: lzd15 = 4'd12;
                15'b00000000000001?: lzd15 = 4'd13;
                15'b000000000000001: lzd15 = 4'd14;
                default:             lzd15 = 4'd15;
            endcase
        end
    endfunction

    // All intermediate signals at module scope (Yosys requirement)
    reg        c3_is_zero;
    reg [3:0]  c3_lz;
    reg [3:0]  c3_shift_left;
    reg [3:0]  c3_raw_shift;
    reg [6:0]  c3_exp_tmp;
    reg [28:0] c3_left_ext, c3_left_shifted;
    reg [13:0] c3_mant_norm;
    reg [6:0]  c3_exp_norm;
    reg        c3_guard, c3_round_bit, c3_sticky;

    always @(*) begin
        c3_is_zero      = (s2_mant_res == 15'h0);
        c3_lz           = lzd15(s2_mant_res);
        c3_exp_tmp      = {1'b0, s2_exp_res};
        // defaults
        c3_mant_norm    = 14'h0;
        c3_exp_norm     = 7'h0;
        c3_guard        = 1'b0;
        c3_round_bit    = 1'b0;
        c3_sticky       = s2_sticky;
        c3_shift_left   = 4'h0;
        c3_raw_shift    = 4'h0;
        c3_left_ext     = 29'h0;
        c3_left_shifted = 29'h0;

        if (c3_is_zero) begin
            c3_exp_norm  = 7'h0;
            c3_mant_norm = 14'h0;
            c3_guard     = 1'b0;
            c3_round_bit = 1'b0;
            c3_sticky    = 1'b0;
        end else if (s2_mant_res[14]) begin
            // Carry out: right-shift 1, exp++
            c3_exp_norm  = c3_exp_tmp + 7'h1;
            c3_mant_norm = s2_mant_res[14:1];
            c3_guard     = s2_mant_res[0];
            c3_round_bit = 1'b0;
            c3_sticky    = s2_sticky;
        end else begin
            // Left-shift to normalize
            c3_raw_shift = (c3_lz > 4'd0) ? (c3_lz - 4'd1) : 4'd0;

            if (c3_exp_tmp <= 7'h1) begin
                c3_shift_left = 4'd0;
            end else if ({3'b0, c3_raw_shift} >= c3_exp_tmp) begin
                c3_shift_left = (c3_exp_tmp - 7'h1) > 7'hF
                                ? 4'hF : c3_exp_tmp[3:0] - 4'd1;
            end else begin
                c3_shift_left = c3_raw_shift;
            end

            c3_left_ext = {s2_mant_res, 14'h0};

            case (c3_shift_left)
                4'd0:    c3_left_shifted = c3_left_ext;
                4'd1:    c3_left_shifted = c3_left_ext << 1;
                4'd2:    c3_left_shifted = c3_left_ext << 2;
                4'd3:    c3_left_shifted = c3_left_ext << 3;
                4'd4:    c3_left_shifted = c3_left_ext << 4;
                4'd5:    c3_left_shifted = c3_left_ext << 5;
                4'd6:    c3_left_shifted = c3_left_ext << 6;
                4'd7:    c3_left_shifted = c3_left_ext << 7;
                4'd8:    c3_left_shifted = c3_left_ext << 8;
                4'd9:    c3_left_shifted = c3_left_ext << 9;
                4'd10:   c3_left_shifted = c3_left_ext << 10;
                4'd11:   c3_left_shifted = c3_left_ext << 11;
                4'd12:   c3_left_shifted = c3_left_ext << 12;
                4'd13:   c3_left_shifted = c3_left_ext << 13;
                default: c3_left_shifted = c3_left_ext << 14;
            endcase

            c3_mant_norm = c3_left_shifted[27:14];
            c3_guard     = c3_left_shifted[13];
            c3_round_bit = c3_left_shifted[12];
            c3_sticky    = |c3_left_shifted[11:0] | s2_sticky;
            c3_exp_norm  = c3_exp_tmp - {3'b0, c3_shift_left};
        end
    end

    reg        s3_valid;
    reg        s3_sign_res;
    reg [6:0]  s3_exp_res;
    reg [13:0] s3_mant_norm;
    reg        s3_guard, s3_round_bit, s3_sticky;
    reg        s3_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid     <= 1'b0;
            s3_sign_res  <= 1'b0;
            s3_exp_res   <= 7'h0;
            s3_mant_norm <= 14'h0;
            s3_guard     <= 1'b0;
            s3_round_bit <= 1'b0;
            s3_sticky    <= 1'b0;
            s3_zero      <= 1'b0;
        end else begin
            s3_valid     <= s2_valid;
            s3_sign_res  <= s2_sign_res;
            s3_exp_res   <= c3_exp_norm;
            s3_mant_norm <= c3_mant_norm;
            s3_guard     <= c3_guard;
            s3_round_bit <= c3_round_bit;
            s3_sticky    <= c3_sticky;
            s3_zero      <= c3_is_zero;
        end
    end

    // =========================================================
    // STAGE 4 COMB+FF: ROUNDING (Round to Nearest Even)
    // =========================================================
    wire        c4_lsb      = s3_mant_norm[0];
    wire        c4_round_up = s3_guard & (s3_round_bit | s3_sticky | c4_lsb);
    wire [14:0] c4_mant_inc = {1'b0, s3_mant_norm} + {14'h0, c4_round_up};

    wire [6:0]  c4_exp_out  = c4_mant_inc[14] ? (s3_exp_res + 7'h1) : s3_exp_res;
    wire [13:0] c4_mant_out = c4_mant_inc[14]  ? 14'h2000 : c4_mant_inc[13:0];

    reg        s4_valid;
    reg        s4_sign_res;
    reg [6:0]  s4_exp_res;
    reg [13:0] s4_mant_rnd;
    reg        s4_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid    <= 1'b0;
            s4_sign_res <= 1'b0;
            s4_exp_res  <= 7'h0;
            s4_mant_rnd <= 14'h0;
            s4_zero     <= 1'b0;
        end else begin
            s4_valid    <= s3_valid;
            s4_sign_res <= s3_sign_res;
            s4_exp_res  <= c4_exp_out;
            s4_mant_rnd <= c4_mant_out;
            s4_zero     <= s3_zero;
        end
    end

    // =========================================================
    // STAGE 5 FF: PACK OUTPUT
    // exp > 63 -> overflow; exp == 0 -> underflow/flush to zero
    // =========================================================
    wire c5_overflow  = s4_exp_res[6] && !s4_zero;
    wire c5_underflow = (s4_exp_res == 7'h0) && !s4_zero;

    wire [19:0] c5_result =
        s4_zero       ? 20'h0 :
        c5_overflow   ? {s4_sign_res, 6'h3F, 13'h1FFF} :
        c5_underflow  ? 20'h0 :
                        {s4_sign_res, s4_exp_res[5:0], s4_mant_rnd[12:0]};

    reg        s5_valid;
    reg [19:0] s5_result;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5_valid  <= 1'b0;
            s5_result <= 20'h0;
        end else begin
            s5_valid  <= s4_valid;
            s5_result <= c5_result;
        end
    end

    assign out_valid = s5_valid;
    assign result    = s5_result;

endmodule
