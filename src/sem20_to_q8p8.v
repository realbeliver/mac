// sem20_to_q8p8.v  -  SEM20 -> Q8.8 pipelined decoder
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
//
// 3-cycle pipeline:
//   Stage 1: unpack + compute shift = exp - 36
//   Stage 2: barrel shift (arithmetic) + sign application
//   Stage 3: saturate to [-32768, +32767] and pack
//
// Shift formula derivation:
//   SEM20 value = 1.M * 2^(E-31)
//   Q8.8 representation: value * 2^8 = 1.M * 2^(E-31+8) = 1.M * 2^(E-23)
//   We hold 1.M in a 14-bit word with implied bit at position 13.
//   So actual shift needed = (E - 23) - 13 = E - 36
//   Positive shift = left shift, negative = right shift

`timescale 1ns/1ps

module sem20_to_q8p8_pipelined (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [19:0] sem_in,
    input  wire        in_valid,
    output wire signed [15:0] q88_out,
    output wire        out_valid
);

    // -------------------------------------------------------
    // Stage 1: decode + compute shift amount
    // -------------------------------------------------------
    reg        s1_valid;
    reg        s1_sign;
    reg        s1_is_zero;
    reg [13:0] s1_norm;       // 1.M in Q13 fixed point
    reg signed [7:0] s1_shift; // E - 36, signed

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid   <= 1'b0;
            s1_sign    <= 1'b0;
            s1_is_zero <= 1'b0;
            s1_norm    <= 14'h0000;
            s1_shift   <= 8'sh00;
        end else begin
            s1_valid   <= in_valid;
            s1_sign    <= sem_in[19];
            s1_is_zero <= (sem_in[18:0] == 19'd0);
            s1_norm    <= {1'b1, sem_in[12:0]};
            // shift = exp - 36; exp is 6-bit unsigned, bias already in SEM20
            s1_shift   <= $signed({2'b00, sem_in[18:13]}) - 8'sd36;
        end
    end

    // -------------------------------------------------------
    // Stage 2: arithmetic barrel shift + sign
    // Replace <<< / >>> with explicit signed shift using $signed
    // Yosys handles >> / << on signed wires as arithmetic when reg is signed
    // -------------------------------------------------------
    reg        s2_valid;
    reg        s2_is_zero;
    reg signed [47:0] s2_result;

    // Shift magnitude and direction
    wire        shift_left    = ~s1_shift[7];          // positive = left
    wire [6:0]  shift_mag     = s1_shift[7] ? (-s1_shift[6:0] - 7'd0) : s1_shift[6:0];
    // For right shift we need proper magnitude of negative number
    wire [7:0]  shift_mag_neg = (~s1_shift) + 8'sh01; // two's complement of negative shift
    wire [6:0]  shift_r_amt   = shift_mag_neg[6:0];

    // Extend norm to 48 bits signed, then shift
    wire signed [47:0] norm_ext = {{34{1'b0}}, s1_norm};

    // Shifted value (unsigned magnitude — sign applied after)
    // Use explicit barrel by doing arithmetic shift on signed value
    // Yosys supports >> on reg, and <<  on reg fine.
    // For arithmetic right shift we sign-extend and use >>>
    // Since norm_ext is always positive (it's a magnitude), >> == >>> here.
    wire [47:0] shifted_left  = norm_ext << s1_shift[5:0];
    wire [47:0] shifted_right = norm_ext >> shift_r_amt[5:0];
    wire [47:0] shifted_val   = shift_left ? shifted_left : shifted_right;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid   <= 1'b0;
            s2_is_zero <= 1'b0;
            s2_result  <= 48'sh000000000000;
        end else begin
            s2_valid   <= s1_valid;
            s2_is_zero <= s1_is_zero;
            if (s1_valid) begin
                if (s1_sign)
                    s2_result <= -$signed({1'b0, shifted_val});
                else
                    s2_result <=  $signed({1'b0, shifted_val});
            end else begin
                s2_result <= 48'sh000000000000;
            end
        end
    end

    // -------------------------------------------------------
    // Stage 3: saturate to Q8.8 range [-32768, +32767]
    // -------------------------------------------------------
    reg        s3_valid;
    reg signed [15:0] s3_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
            s3_out   <= 16'sd0;
        end else begin
            s3_valid <= s2_valid;
            if (s2_is_zero)
                s3_out <= 16'sd0;
            else if (s2_result > 48'sd32767)
                s3_out <= 16'h7FFF;
            else if (s2_result < -48'sd32768)
                s3_out <= 16'h8000;
            else
                s3_out <= s2_result[15:0];
        end
    end

    assign out_valid = s3_valid;
    assign q88_out   = s3_out;

endmodule
