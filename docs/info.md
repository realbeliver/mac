<!--- Info - TinyTapeout SEM20 Floating-Point MAC --->

## How it Works

This project implements an **18-cycle pipelined Multiply-Accumulate (MAC)** unit for the **TinyTapeout (GF180MCU)** platform. Operands enter as **signed Q8.8 fixed-point**, are internally converted to a custom 20-bit floating-point format called **SEM20**, passed through a fully-pipelined MAC datapath, and the result is decoded back to **Q8.8** for output. The accumulator persists across firings, enabling dot-product and FIR filter computations.

The entire design is implemented in **plain Verilog-2005** with no vendor IP, no DSP blocks, and no `*` operator — synthesisable cleanly by Yosys/OpenLane on GF180MCU.

---

### SEM20 Floating-Point Format

SEM20 is a custom 20-bit float designed to give sufficient dynamic range and precision for inference-style multiply-accumulate workloads:

| Field | Bits | Width | Description |
|-------|------|-------|-------------|
| Sign | `[19]` | 1 bit | 0 = positive, 1 = negative |
| Exponent | `[18:13]` | 6 bits | Biased, bias = 31 |
| Mantissa | `[12:0]` | 13 bits | Stored fraction, implicit leading 1 for normals |

- **Zero**: all bits zero
- **Overflow**: saturates to `{sign, 6'd62, 13'h1FFF}`
- **Underflow**: flushes to zero
- **No NaN, no Inf**

---

### Hardware Architecture

The design is composed of six pipeline stages across three functional blocks:

**Block 1 — Q8.8 → SEM20 Encoder (`q8p8_to_sem20`, 3 cycles)**
- Stage 0: Extract sign, compute absolute value (handles `0x8000` edge case)
- Stage 1: 16-bit Leading-Zero Detect (LZD) — registers MSB position
- Stage 2: Normalize mantissa, pack SEM20 word `{sign, E, mant[12:0]}`

**Block 2 — SEM20 MAC (`sem20_mac`, 12 cycles)**
- `sem20_mul` (5 cycles): Radix-4 Modified Booth multiplier on 14-bit mantissas, with a 3-level CSA tree reducing 9 partial products to 3, followed by a 28-bit carry-propagate adder. Exponents are summed; result is normalised and rounded-to-nearest-even.
- `sem20_acc_ip`: Accumulator register — captures adder output on `add_valid`; feeds back to adder input B. Cleared synchronously via `clr_acc`.
- `sem20_add` (6 cycles): Alignment shift, signed add/subtract, normalise with LZD, round-to-nearest-even, saturate.
- Output FF (1 cycle): Registered output.

**Block 3 — SEM20 → Q8.8 Decoder (`sem20_to_q8p8_pipelined`, 3 cycles)**
- Stage 1: Unpack exponent/mantissa, compute shift amount = `exp − 36`
- Stage 2: Barrel shift (magnitude) + sign application
- Stage 3: Saturate to Q8.8 range `[−128.0, +127.996]`

```
ui_in (Q8.8 bytes)
      │
      ▼
q8p8_to_sem20 ──(3 cy)──► sem20_mul ──(5 cy)──► sem20_add ──(6 cy)──► output FF ──(1 cy)──► sem20_to_q8p8 ──(3 cy)──► uo_out
 (×2 encoders)                                        ▲                                                               (Q8.8)
                                                 sem20_acc_ip
                                                 (accumulator)
                                    Total pipeline latency: 18 cycles
```

The `clr_acc` signal from the top-level is delayed 3 cycles via a shift register in `sem20_inference_top` so it arrives at the MAC aligned with the encoded operands.

---

### IO Protocol

The design uses a **byte-serial command protocol** over `ui_in` and `uio_in` to overcome the 8-bit input pin limit of TinyTapeout while still passing full 16-bit Q8.8 operands.

#### Pin Map

| Pin | Direction | Function |
|-----|-----------|----------|
| `ui[7:0]` | Input | 8-bit data bus (operand bytes) |
| `uo[7:0]` | Output | Result byte (selected by `RESULT_HI`) |
| `uio[0]` | Output | `out_valid` — 1-cycle pulse when result is ready |
| `uio[1]` | Output | `busy` — high while pipeline has an in-flight computation |
| `uio[3:2]` | Input | `CMD[1:0]` — command select (see below) |
| `uio[4]` | Input | `BYTE_SEL` — `0` = load low byte, `1` = load high byte |
| `uio[5]` | Input | `CLR_ACC` — clear accumulator before this MAC (on `FIRE`) |
| `uio[6]` | Input | `RESULT_HI` — `0` = `uo_out = result[7:0]`, `1` = `result[15:8]` |
| `uio[7]` | Input | unused |

#### CMD Encoding (`uio[3:2]`)

| Value | Name | Action |
|-------|------|--------|
| `2'b00` | NOP | No operation |
| `2'b01` | LOAD_A | Load A operand byte: `BYTE_SEL=0` → `a[7:0]`, `BYTE_SEL=1` → `a[15:8]` |
| `2'b10` | LOAD_B | Load B operand byte: same byte select logic |
| `2'b11` | FIRE | Launch pipeline with latched A and B; if `CLR_ACC=1`, accumulator is reset first |

---

## How to Test

### Dependencies

Ensure your environment has Python 3.11+ and the required toolchain:

```sh
pip install cocotb
sudo apt install iverilog
```

### Running the Cocotb Testbench

```sh
cd test
make
```

This runs 6 cocotb tests via Icarus Verilog:

| Test | Description |
|------|-------------|
| `test_basic_multiply` | `1.0 × 2.0` with `CLR_ACC=1` → result = `2.0` |
| `test_accumulation` | Three sequential MACs: `2.0 + 3.0 − 3.0 = 2.0` |
| `test_saturation` | `100.0 × 100.0` → saturates to `+127.996` |
| `test_zero` | `0.0 × 5.0` → result = `0.0` |
| `test_negative` | `−3.0 × 2.0` → result = `−6.0` |
| `test_dot_product` | `[1,2,3,4]·[1,2,3,4] = 30.0` (4 accumulations, `CLR_ACC=0` after first) |

### Manual Host Sequence (e.g. RP2040)

To perform one MAC operation:

```
cycle 1 : CMD=LOAD_A, BYTE_SEL=0, ui_in = a_q8p8[7:0]
cycle 2 : CMD=LOAD_A, BYTE_SEL=1, ui_in = a_q8p8[15:8]
cycle 3 : CMD=LOAD_B, BYTE_SEL=0, ui_in = b_q8p8[7:0]
cycle 4 : CMD=LOAD_B, BYTE_SEL=1, ui_in = b_q8p8[15:8]
cycle 5 : CMD=FIRE,   CLR_ACC=<0|1>
          ... wait for uio[0] (out_valid) to pulse (~18 cycles) ...
read lo : RESULT_HI=0  →  uo_out = result[7:0]
read hi : RESULT_HI=1  →  uo_out = result[15:8]
```

For **Q8.8** encoding: multiply the float value by 256 and take the signed 16-bit integer representation. For example, `1.5` → `0x0180`, `−3.0` → `0xFD00`.

Set `CLR_ACC=0` on consecutive `FIRE` pulses to accumulate across multiple multiply operations (e.g. dot products). Set `CLR_ACC=1` only on the first FIRE of a new computation.

### External Hardware

No external components required. All computation is on-chip. The host (RP2040 on the TT demo board, or any microcontroller) drives `ui_in` and `uio_in` directly.
