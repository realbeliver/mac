"""
test.py — cocotb testbench for tt_um_sem20_mac
SEM20 20-bit Floating-Point MAC, TinyTapeout submission
Pure Verilog-2005 version

Protocol:
  uio_in[3:2] = CMD  (00=NOP, 01=LOAD_A, 10=LOAD_B, 11=FIRE)
  uio_in[4]   = BYTE_SEL  (0=low byte, 1=high byte)
  uio_in[5]   = CLR_ACC
  uio_in[6]   = RESULT_HI (0=result[7:0], 1=result[15:8])
  ui_in[7:0]  = data byte
  uio_out[0]  = out_valid
  uio_out[1]  = busy
  uo_out[7:0] = result byte
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

CMD_NOP    = 0b00
CMD_LOAD_A = 0b01
CMD_LOAD_B = 0b10
CMD_FIRE   = 0b11

def mk_uio(cmd=0, byte_sel=0, clr_acc=0, result_hi=0):
    return (cmd << 2) | (byte_sel << 4) | (clr_acc << 5) | (result_hi << 6)

def to_q88(v):
    raw = int(round(v * 256))
    raw = max(-32768, min(32767, raw))
    return raw & 0xFFFF

def from_q88(raw):
    s = raw if raw < 32768 else raw - 65536
    return s / 256.0

async def reset(dut):
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)

async def load_op(dut, cmd, val_q88):
    await FallingEdge(dut.clk)
    dut.ui_in.value  = val_q88 & 0xFF
    dut.uio_in.value = mk_uio(cmd=cmd, byte_sel=0)
    await FallingEdge(dut.clk)
    dut.ui_in.value  = (val_q88 >> 8) & 0xFF
    dut.uio_in.value = mk_uio(cmd=cmd, byte_sel=1)
    await FallingEdge(dut.clk)
    dut.ui_in.value  = 0
    dut.uio_in.value = mk_uio(cmd=CMD_NOP)

async def fire(dut, clr_acc=False):
    await FallingEdge(dut.clk)
    dut.uio_in.value = mk_uio(cmd=CMD_FIRE, clr_acc=int(clr_acc))
    await FallingEdge(dut.clk)
    dut.uio_in.value = mk_uio(cmd=CMD_NOP)

async def wait_result(dut, timeout=60):
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.uio_out.value.to_unsigned() & 0x1:
            dut.uio_in.value = mk_uio(result_hi=0)
            await RisingEdge(dut.clk)
            lo = dut.uo_out.value.to_unsigned()
            dut.uio_in.value = mk_uio(result_hi=1)
            await RisingEdge(dut.clk)
            hi = dut.uo_out.value.to_unsigned()
            dut.uio_in.value = 0
            return from_q88((hi << 8) | lo)
    raise TimeoutError("out_valid never asserted")

async def run_mac(dut, a, b, clr_acc=True):
    await load_op(dut, CMD_LOAD_A, to_q88(a))
    await load_op(dut, CMD_LOAD_B, to_q88(b))
    await fire(dut, clr_acc=clr_acc)
    return await wait_result(dut)

@cocotb.test()
async def test_basic_multiply(dut):
    """1.0 x 2.0 (clr) = 2.0"""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset(dut)
    r = await run_mac(dut, 1.0, 2.0, clr_acc=True)
    dut._log.info(f"1.0 x 2.0 = {r:.4f}  expect 2.0")
    assert abs(r - 2.0) < 0.1

@cocotb.test()
async def test_accumulation(dut):
    """Sequential accumulation: 2.0 + 3.0 - 3.0 = 2.0"""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset(dut)
    r1 = await run_mac(dut, 1.0, 2.0, clr_acc=True)
    assert abs(r1 - 2.0) < 0.1, f"T1 got {r1}"
    r2 = await run_mac(dut, 1.5, 2.0, clr_acc=False)
    assert abs(r2 - 5.0) < 0.1, f"T2 got {r2}"
    r3 = await run_mac(dut, -1.0, 3.0, clr_acc=False)
    dut._log.info(f"T3 = {r3:.4f}  expect 2.0")
    assert abs(r3 - 2.0) < 0.1, f"T3 got {r3}"

@cocotb.test()
async def test_saturation(dut):
    """100 x 100 saturates to +127.996"""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset(dut)
    r = await run_mac(dut, 100.0, 100.0, clr_acc=True)
    dut._log.info(f"100x100 = {r:.4f}  expect ~127.996")
    assert r >= 127.9

@cocotb.test()
async def test_zero(dut):
    """0.0 x 5.0 = 0.0"""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset(dut)
    r = await run_mac(dut, 0.0, 5.0, clr_acc=True)
    dut._log.info(f"0.0 x 5.0 = {r:.4f}  expect 0.0")
    assert abs(r) < 0.1

@cocotb.test()
async def test_negative(dut):
    """-3.0 x 2.0 = -6.0"""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset(dut)
    r = await run_mac(dut, -3.0, 2.0, clr_acc=True)
    dut._log.info(f"-3.0 x 2.0 = {r:.4f}  expect -6.0")
    assert abs(r - (-6.0)) < 0.1

@cocotb.test()
async def test_dot_product(dut):
    """[1,2,3,4].[1,2,3,4] = 30"""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset(dut)
    pairs = [(1.0,1.0),(2.0,2.0),(3.0,3.0),(4.0,4.0)]
    r = None
    for i,(a,b) in enumerate(pairs):
        r = await run_mac(dut, a, b, clr_acc=(i==0))
    dut._log.info(f"dot product = {r:.4f}  expect 30.0")
    assert abs(r - 30.0) < 0.5
