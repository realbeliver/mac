![GDS Badge](../../workflows/gds/badge.svg)
![Docs Badge](../../workflows/docs/badge.svg)
![Test Badge](../../workflows/test/badge.svg)
![FPGA Badge](../../workflows/fpga/badge.svg)
# SEM20 Floating-Point MAC — TinyTapeout

An 18-cycle pipelined **Multiply-Accumulate (MAC)** unit using a custom 20-bit floating-point format called **SEM20**.

## Format

**SEM20** (1 sign / 6 exponent / 13 mantissa, bias = 31):
```
[19]    Sign
[18:13] Exponent (bias = 31)
[12:0]  Mantissa (implicit leading 1)
```

Operands enter and exit as **Q8.8 signed fixed-point** (range −128.0 to +127.996).  
Overflow saturates; underflow flushes to zero.

## Pipeline

```
Q8.8 input → q8p8_to_sem20 (3 cyc) → sem20_mul (5 cyc) → sem20_add (6 cyc) → output FF (1 cyc) → sem20_to_q8p8 (3 cyc) → Q8.8 output
                                                                    ↑
                                                             sem20_acc_ip (accumulator feedback)
Total: 18 cycles
```

## IO Protocol

| Pin | Dir | Function |
|-----|-----|----------|
| `ui[7:0]` | IN | 8-bit data bus |
| `uo[7:0]` | OUT | Result byte |
| `uio[0]` | OUT | `out_valid` — 1-cycle pulse when result ready |
| `uio[1]` | OUT | `busy` — pipeline in flight |
| `uio[3:2]` | IN | `CMD` — 00=NOP, 01=LOAD\_A, 10=LOAD\_B, 11=FIRE |
| `uio[4]` | IN | `BYTE_SEL` — 0=low byte, 1=high byte |
| `uio[5]` | IN | `CLR_ACC` — clear accumulator before this MAC |
| `uio[6]` | IN | `RESULT_HI` — select result byte to output |

### Host sequence (one MAC)
```
cycle 1: CMD=LOAD_A, BYTE_SEL=0, ui=a[7:0]
cycle 2: CMD=LOAD_A, BYTE_SEL=1, ui=a[15:8]
cycle 3: CMD=LOAD_B, BYTE_SEL=0, ui=b[7:0]
cycle 4: CMD=LOAD_B, BYTE_SEL=1, ui=b[15:8]
cycle 5: CMD=FIRE, CLR_ACC=<0|1>
         ... wait ~18 cycles for out_valid pulse ...
read:    RESULT_HI=0 → uo_out = result[7:0]
         RESULT_HI=1 → uo_out = result[15:8]
```

Set `CLR_ACC=0` on consecutive FIREs to accumulate (dot product, FIR filter tap, etc.).

## Use Cases

- Weighted sum / dot product
- FIR filter taps
- Neural network neuron accumulation

## Tile Size

**1×2** — the 18-stage deep pipeline with Radix-4 Booth multiplier and CSA tree requires more area than a single 1×1 tile.
