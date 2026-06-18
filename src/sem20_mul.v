// sem20_mul.v  -  SEM20 20-bit Floating-Point Multiplier
// Converted from SystemVerilog to Verilog-2005 for Yosys/OpenLane compatibility
//
// SEM20: [19]=sign [18:13]=exp(bias=31) [12:0]=mantissa(implicit leading 1)
//
// Pipeline: 5 stages
//   Stage 1 FF : latch unpacked fields + 8 Booth groups
//   Stage 2 FF : CSA tree levels 1+2  (9->4 operands)
//   Stage 3 FF : final CSA + 28-bit CPA
//   Stage 4 FF : normalise, extract GRS
//   Stage 5 FF : round-to-nearest-even + pack + clip
//
// Radix-4 Booth encoding on 14-bit mantissas.
// Automatic function 'bdec' replaced with explicit wire assignments.
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// 3-to-2 Carry-Save Adder
// ---------------------------------------------------------------------------
module csa_3to2 #(parameter W = 44) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire [W-1:0] c,
    output wire [W-1:0] sum,
    output wire [W-1:0] carry
);
    assign sum   = a ^ b ^ c;
    assign carry = (a & b) | (b & c) | (a & c);
endmodule

// ---------------------------------------------------------------------------
// SEM20 Multiplier
// ---------------------------------------------------------------------------
module sem20_mul #(parameter W = 20) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output reg  [W-1:0] product,
    output reg          valid_out
);
    localparam PW = 44;

    // =========================================================
    // STAGE 0 — COMBINATIONAL: UNPACK + BOOTH ENCODE
    // =========================================================
    wire        s_a  = a[19];
    wire [5:0]  ea_w = a[18:13];
    wire [5:0]  eb_w = b[18:13];
    wire        s_b  = b[19];

    wire [13:0] ma_w = (ea_w == 6'd0) ? 14'd0 : {1'b1, a[12:0]};
    wire [13:0] mb_w = (eb_w == 6'd0) ? 14'd0 : {1'b1, b[12:0]};

    wire za = (ea_w == 6'd0);
    wire zb = (eb_w == 6'd0);

    // Padded B for Booth: {2'b00, mb_w, 1'b0} = 17 bits
    wire [16:0] bpad = {2'b00, mb_w, 1'b0};

    wire [2:0] g0 = bpad[ 2: 0];
    wire [2:0] g1 = bpad[ 4: 2];
    wire [2:0] g2 = bpad[ 6: 4];
    wire [2:0] g3 = bpad[ 8: 6];
    wire [2:0] g4 = bpad[10: 8];
    wire [2:0] g5 = bpad[12:10];
    wire [2:0] g6 = bpad[14:12];
    wire [2:0] g7 = bpad[16:14];

    // =========================================================
    // STAGE 1 REGISTERS
    // =========================================================
    reg        s1v, s1sgn, s1z;
    reg [7:0]  s1ea, s1eb;
    reg [13:0] s1ma;
    reg [2:0]  s1g0,s1g1,s1g2,s1g3,s1g4,s1g5,s1g6,s1g7;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1v <= 1'b0;
        end else begin
            s1v   <= in_valid;
            s1sgn <= s_a ^ s_b;
            s1z   <= za | zb;
            s1ea  <= {2'b00, ea_w};
            s1eb  <= {2'b00, eb_w};
            s1ma  <= ma_w;
            s1g0 <= g0; s1g1 <= g1; s1g2 <= g2; s1g3 <= g3;
            s1g4 <= g4; s1g5 <= g5; s1g6 <= g6; s1g7 <= g7;
        end
    end

    // =========================================================
    // STAGE 2A — BOOTH DECODE (combinational, replaces function)
    //
    // For each group gi, decode to a 16-bit signed partial product
    // and a carry bit. Encoding:
    //   000,111 ->  0,      carry=0
    //   001,010 -> +A,      carry=0
    //   011     -> +2A,     carry=0
    //   100     -> ~(2A),   carry=1
    //   101,110 -> ~A,      carry=1
    //
    // Outputs: r_i[16]=carry, r_i[15:0]=partial product (16-bit signed)
    // =========================================================

    // Pre-compute A multiples for Stage 1 registered ma
    wire [15:0] pos_A  = {2'b00, s1ma};
    wire [15:0] pos_2A = {1'b0, s1ma, 1'b0};
    wire [15:0] neg_A  = ~pos_A;
    wire [15:0] neg_2A = ~pos_2A;

    // Booth decode per group — explicit mux, no function, no return
    // r_i = {carry, pp[15:0]}
    function [16:0] bdec_fn;
        input [2:0]  grp;
        input [15:0] pa;
        input [15:0] p2a;
        input [15:0] na;
        input [15:0] n2a;
        reg [15:0] v;
        reg        c;
        begin
            case (grp)
                3'b000, 3'b111: begin v = 16'd0; c = 1'b0; end
                3'b001, 3'b010: begin v = pa;    c = 1'b0; end
                3'b011:         begin v = p2a;   c = 1'b0; end
                3'b100:         begin v = n2a;   c = 1'b1; end
                3'b101, 3'b110: begin v = na;    c = 1'b1; end
                default:        begin v = 16'd0; c = 1'b0; end
            endcase
            bdec_fn = {c, v};
        end
    endfunction

    wire [16:0] r0 = bdec_fn(s1g0, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r1 = bdec_fn(s1g1, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r2 = bdec_fn(s1g2, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r3 = bdec_fn(s1g3, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r4 = bdec_fn(s1g4, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r5 = bdec_fn(s1g5, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r6 = bdec_fn(s1g6, pos_A, pos_2A, neg_A, neg_2A);
    wire [16:0] r7 = bdec_fn(s1g7, pos_A, pos_2A, neg_A, neg_2A);

    // Sign-extend each pp[15:0] to PW bits, shifted left by 2i
    wire [PW-1:0] pp0 = {{(PW-16){r0[15]}}, r0[15:0]};
    wire [PW-1:0] pp1 = {{(PW-18){r1[15]}}, r1[15:0], 2'b00};
    wire [PW-1:0] pp2 = {{(PW-20){r2[15]}}, r2[15:0], 4'b0};
    wire [PW-1:0] pp3 = {{(PW-22){r3[15]}}, r3[15:0], 6'b0};
    wire [PW-1:0] pp4 = {{(PW-24){r4[15]}}, r4[15:0], 8'b0};
    wire [PW-1:0] pp5 = {{(PW-26){r5[15]}}, r5[15:0], 10'b0};
    wire [PW-1:0] pp6 = {{(PW-28){r6[15]}}, r6[15:0], 12'b0};
    wire [PW-1:0] pp7 = {{(PW-30){r7[15]}}, r7[15:0], 14'b0};

    // Carry-correction word
    wire [PW-1:0] bcorr =
        ( {{(PW-1){1'b0}},  r0[16]        } ) |
        ( {{(PW-3){1'b0}},  r1[16], 2'b0  } ) |
        ( {{(PW-5){1'b0}},  r2[16], 4'b0  } ) |
        ( {{(PW-7){1'b0}},  r3[16], 6'b0  } ) |
        ( {{(PW-9){1'b0}},  r4[16], 8'b0  } ) |
        ( {{(PW-11){1'b0}}, r5[16], 10'b0 } ) |
        ( {{(PW-13){1'b0}}, r6[16], 12'b0 } ) |
        ( {{(PW-15){1'b0}}, r7[16], 14'b0 } );

    // CSA level 1: 9->6
    wire [PW-1:0] l1s0, l1c0, l1s1, l1c1, l1s2, l1c2;
    csa_3to2 #(PW) c1a (.a(pp0), .b(pp1),   .c(pp2),   .sum(l1s0), .carry(l1c0));
    csa_3to2 #(PW) c1b (.a(pp3), .b(pp4),   .c(pp5),   .sum(l1s1), .carry(l1c1));
    csa_3to2 #(PW) c1c (.a(pp6), .b(pp7),   .c(bcorr), .sum(l1s2), .carry(l1c2));

    // CSA level 2: 6->4
    wire [PW-1:0] l2s0, l2c0, l2s1, l2c1;
    csa_3to2 #(PW) c2a (.a(l1s0), .b({l1c0[PW-2:0],1'b0}), .c(l1s1),               .sum(l2s0), .carry(l2c0));
    csa_3to2 #(PW) c2b (.a({l1c1[PW-2:0],1'b0}), .b(l1s2), .c({l1c2[PW-2:0],1'b0}), .sum(l2s1), .carry(l2c1));

    // Stage 2 registers
    reg [PW-1:0] s2w0, s2w1, s2w2, s2w3;
    reg [7:0]    s2ea, s2eb;
    reg          s2v, s2sgn, s2z;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2v <= 1'b0;
        end else begin
            s2v   <= s1v;
            s2w0  <= l2s0;
            s2w1  <= {l2c0[PW-2:0], 1'b0};
            s2w2  <= l2s1;
            s2w3  <= {l2c1[PW-2:0], 1'b0};
            s2ea  <= s1ea; s2eb <= s1eb;
            s2sgn <= s1sgn; s2z <= s1z;
        end
    end

    // =========================================================
    // STAGE 3 — FINAL CSA + 28-bit CPA
    // =========================================================
    wire [PW-1:0] l3s, l3c;
    csa_3to2 #(PW) c3 (.a(s2w0), .b(s2w1), .c(s2w2), .sum(l3s), .carry(l3c));

    wire [27:0] cpa = l3s[27:0] + {l3c[26:0], 1'b0} + s2w3[27:0];

    reg [27:0] s3prod;
    reg [7:0]  s3ea, s3eb;
    reg        s3v, s3sgn, s3z;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3v <= 1'b0;
        end else begin
            s3v    <= s2v;
            s3prod <= cpa;
            s3ea   <= s2ea; s3eb <= s2eb;
            s3sgn  <= s2sgn; s3z <= s2z;
        end
    end

    // =========================================================
    // STAGE 4 — NORMALISE + GRS EXTRACTION
    // product in [2^26, 2^28)
    //   bit27=0: leading 1 at bit26, no shift; E = Ea+Eb-31
    //   bit27=1: leading 1 at bit27, right-shift; E = Ea+Eb-31+1
    // =========================================================
    wire        ovf4  = s3prod[27];
    wire [9:0]  ebase = {2'b00, s3ea} + {2'b00, s3eb} - 10'd31;
    wire [9:0]  enorm = ebase + {9'b0, ovf4};

    wire [12:0] mant4 = ovf4 ? s3prod[26:14] : s3prod[25:13];
    wire        grd4  = ovf4 ? s3prod[13]    : s3prod[12];
    wire        rnd4  = ovf4 ? s3prod[12]    : s3prod[11];
    wire        st4   = ovf4 ? |s3prod[11:0] : |s3prod[10:0];

    reg [12:0] s4mant;
    reg [9:0]  s4esum;
    reg        s4v, s4sgn, s4z;
    reg        s4g, s4r, s4st;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4v <= 1'b0;
        end else begin
            s4v    <= s3v;
            s4mant <= mant4; s4esum <= enorm;
            s4sgn  <= s3sgn; s4z    <= s3z;
            s4g    <= grd4;  s4r    <= rnd4; s4st <= st4;
        end
    end

    // =========================================================
    // STAGE 5 — ROUND-TO-NEAREST-EVEN + PACK + CLIP
    // =========================================================
    wire        rndup  = s4g & (s4r | s4st | s4mant[0]);
    wire [13:0] mantr  = {1'b0, s4mant} + {13'b0, rndup};
    wire        mcarry = mantr[13];

    wire [9:0]  efin = s4esum + {9'b0, mcarry};
    wire [12:0] mfin = mcarry ? 13'd0 : mantr[12:0];

    wire uflow = s4z | efin[9] | (efin == 10'd0);
    wire oflow = (~efin[9]) & (efin >= 10'd63);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            product   <= 20'd0;
        end else begin
            valid_out <= s4v;
            if (uflow)
                product <= {s4sgn, 19'd0};
            else if (oflow)
                product <= {s4sgn, 6'd62, 13'h1FFF};
            else
                product <= {s4sgn, efin[5:0], mfin};
        end
    end

endmodule
