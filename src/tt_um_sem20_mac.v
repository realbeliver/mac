// tt_um_sem20_mac.v  —  TinyTapeout top-level
// SEM20 20-bit Floating-Point MAC (Multiply-Accumulate)
// Plain Verilog-2005, Yosys/OpenLane compatible
//
//  PINOUT
//  ------
//  ui_in[7:0]  : 8-bit data bus (operand bytes)
//  uo_out[7:0] : result byte output
//  uio[0]      : out_valid — 1-cycle pulse when result ready  (OUTPUT)
//  uio[1]      : busy      — pipeline in flight               (OUTPUT)
//  uio[3:2]    : CMD[1:0]  — 00=NOP 01=LOAD_A 10=LOAD_B 11=FIRE (INPUT)
//  uio[4]      : BYTE_SEL  — 0=low byte, 1=high byte          (INPUT)
//  uio[5]      : CLR_ACC   — clear accumulator on FIRE        (INPUT)
//  uio[6]      : RESULT_HI — 0=uo_out=result[7:0], 1=[15:8]  (INPUT)
//  uio[7]      : unused                                        (INPUT)
//
//  Host sequence (one MAC):
//    cycle 1: CMD=LOAD_A, BYTE_SEL=0, ui_in=a[7:0]
//    cycle 2: CMD=LOAD_A, BYTE_SEL=1, ui_in=a[15:8]
//    cycle 3: CMD=LOAD_B, BYTE_SEL=0, ui_in=b[7:0]
//    cycle 4: CMD=LOAD_B, BYTE_SEL=1, ui_in=b[15:8]
//    cycle 5: CMD=FIRE, CLR_ACC=<0|1>
//             ... wait ~18 cycles for uio[0] pulse ...
//    read:    RESULT_HI=0 -> uo_out=result[7:0]
//             RESULT_HI=1 -> uo_out=result[15:8]
`default_nettype none
`timescale 1ns/1ps

module tt_um_sem20_mac (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // uio[1:0] = outputs, uio[7:2] = inputs
    assign uio_oe = 8'b0000_0011;

    // Command decode
    wire [1:0] cmd       = uio_in[3:2];
    wire       byte_sel  = uio_in[4];
    wire       clr_acc_i = uio_in[5];
    wire       result_hi = uio_in[6];

    localparam CMD_NOP    = 2'b00;
    localparam CMD_LOAD_A = 2'b01;
    localparam CMD_LOAD_B = 2'b10;
    localparam CMD_FIRE   = 2'b11;

    // Operand registers (Q8.8 signed, 16-bit)
    reg signed [15:0] a_reg, b_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg <= 16'sh0000;
            b_reg <= 16'sh0000;
        end else begin
            case (cmd)
                CMD_LOAD_A: begin
                    if (!byte_sel) a_reg[7:0]  <= ui_in;
                    else           a_reg[15:8] <= ui_in;
                end
                CMD_LOAD_B: begin
                    if (!byte_sel) b_reg[7:0]  <= ui_in;
                    else           b_reg[15:8] <= ui_in;
                end
                default: ; // NOP / FIRE
            endcase
        end
    end

    // Control pulses
    wire in_valid = (cmd == CMD_FIRE);
    wire clr_acc  = (cmd == CMD_FIRE) && clr_acc_i;

    // SEM20 inference pipeline (18-cycle latency)
    wire signed [15:0] out_q8p8;
    wire               out_valid;

    sem20_inference_top mac_pipe (
        .clk      (clk),
        .rst_n    (rst_n),
        .a_q8p8   (a_reg),
        .b_q8p8   (b_reg),
        .in_valid (in_valid),
        .clr_acc  (clr_acc),
        .out_q8p8 (out_q8p8),
        .out_valid(out_valid)
    );

    // Result register
    reg signed [15:0] result_reg;
    reg               busy_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_reg <= 16'sh0000;
            busy_reg   <= 1'b0;
        end else begin
            if (in_valid)  busy_reg <= 1'b1;
            if (out_valid) begin
                result_reg <= out_q8p8;
                busy_reg   <= 1'b0;
            end
        end
    end

    assign uo_out       = result_hi ? result_reg[15:8] : result_reg[7:0];
    assign uio_out[0]   = out_valid;
    assign uio_out[1]   = busy_reg;
    assign uio_out[7:2] = 6'b000000;

    wire _unused = &{ena, uio_in[7], uio_in[1:0], 1'b0};

endmodule
