![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Super-Simple-SPI CPU

This repository contains a tiny **4‑bit microcoded CPU** designed for **TinyTapeout (GF180MCU)** that fetches its program over **SPI** from external memory (e.g., an RP2040 emulating 23LC512‑style RAM). The demo configuration runs a microcoded **4×4‑bit → 8‑bit multiplier**.

At a glance, this project showcases:
* A compact **single-cycle datapath** (register file, ALU, shift register, accumulator)
* An instruction stream fetched from **external SPI memory**
* A complete **TinyTapeout‑ready top level** with tests and simulation setup

---

## Hardware Pin Mapping

| TinyTapeout Pins | Signal Name | Type | Description |
| :--- | :--- | :--- | :--- |
| `ui_in[7:4]` | Operand **A** | Input | 4‑bit input multiplicand |
| `ui_in[3:0]` | Operand **B** | Input | 4‑bit input multiplier |
| `uo_out[7:0]` | Register **O** | Output | 8-bit output product |

*(Note: For explicit SPI pin assignments including SCLK, CS, MOSI, and MISO, please refer to the complete pinout in `docs/info.md`.)*

---

## Quick Start - Running the Tests

1. Clone the repository and ensure your simulation dependencies (`Python`, `cocotb`, `Icarus Verilog`) are installed.
2. Navigate to the test directory and execute the testbench sweep:

```sh
cd test
make -B results.xml
