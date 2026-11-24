# FPU Module FPGA

**Repository profile: B (multi-module streaming IP).** A pipelined IEEE 754 binary64 floating-point unit for FPGA, with an AXI4-Lite / AXI4-Stream wrapper, verified in simulation against Berkeley SoftFloat and run on a Kria KR260.

## Overview

This repository contains a double-precision (binary64) floating-point unit written in Verilog-2001 for AMD FPGAs. It provides correctly rounded addition, subtraction, multiplication, division and square root, conversions between binary64 and 32-bit integers, and the comparison, minimum/maximum and classification operations of the RISC-V F/D extension. Every rounding operation supports the five IEEE 754 rounding modes, and every result is returned together with its five IEEE 754 exception flags.

Version 2 replaces the earlier version of this repository. The earlier design added transcendental and activation functions (LOG2, LN, EXP2, EXP, SIN, COS, SIGMOID, TANH) built from polynomial approximations, but its own characterization recorded wrong results for subnormal numbers, underflow and NaN cases in the basic arithmetic, and it had no rounding-mode selection or exception flags. Version 2 removes the approximated functions and concentrates on a core whose results are bit-exact with an IEEE 754 reference for the supported operations, including subnormal numbers, signed zeros, infinities, NaNs and exception flags. The earlier design remains available under the `v1.0.0` tag; see [CHANGELOG.md](CHANGELOG.md).

The unit is a numerical building block. It is intended for hardware acceleration through a processor such as the Zynq UltraScale+ PS, and as the arithmetic core of a future RISC-V floating-point extension.

### Supported operations

| OP | FUNCT3 | Operation | Result |
| ---: | ---: | --- | --- |
| 0 | - | ADD: A + B | binary64 |
| 1 | - | SUB: A - B | binary64 |
| 2 | - | MUL: A x B | binary64 |
| 3 | - | DIV: A / B | binary64 |
| 4 | - | SQRT: square root of A | binary64 |
| 5 | 0 / 1 | int32 / uint32 to binary64 | binary64 |
| 6 | 0 / 1 | binary64 to int32 / uint32 | 32-bit integer, zero-extended |
| 7 | 0 / 1 / 2 | FEQ / FLT / FLE | 0 or 1 |
| 7 | 3 / 4 | FMIN / FMAX | binary64 |
| 7 | 5 | FCLASS | 10-bit one-hot class mask |

Rounding modes (RM): 0 RNE (nearest, ties to even), 1 RTZ (toward zero), 2 RDN (toward negative infinity), 3 RUP (toward positive infinity), 4 RMM (nearest, ties away from zero). Flags: {NV, DZ, OF, UF, NX} = {invalid, divide by zero, overflow, underflow, inexact}.

The unit implements a selected set of operations, not the complete IEEE 754 standard. Fused multiply-add, remainder, roundToIntegral, binary32 and 64-bit integer conversions are not provided. See [docs/limitations.md](docs/limitations.md).

## Architecture

The design has three layers. Six independent, fully pipelined lanes perform the arithmetic: add/subtract, multiply, divide, square root, integer conversion, and compare/min/max/class. Each lane accepts a new operation every clock cycle. The dispatcher `vrm_fpu_native_64` sends each request to its lane and delays the faster lanes so that every operation takes exactly 56 clock edges; results therefore leave in issue order and never collide, and any mix of operations can be issued back to back. The AXI wrapper `vrm_fpu_axi_64` adds the AXI4-Lite register file, the AXI4-Stream packet format, and flow control that reserves an output slot for every admitted operation, so a stalled output stream never loses a result.

```text
              AXI4-Lite (control, flags, status)
                         |
 AXI4-Stream  +----------v-------------------------------------------+  AXI4-Stream
 A, B+TLAST ->| vrm_fpu_axi_64                                       |-> result, flags+TLAST
              |  request FIFO (64) -> vrm_fpu_native_64 -> result FIFO (64)
              |                       |  A add/sub  2  + delay 54     |
              |                       |  B mul      5  + delay 51     |
              |                       |  C div     56                 |
              |                       |  D sqrt    56                 |
              |                       |  E conv     1  + delay 55     |
              |                       |  F misc     0  + delay 56     |
              +------------------------------------------------------+
```

Division and square root use restoring algorithms unrolled in space, one step per pipeline stage, so they also accept one operation per cycle. Subnormal operands are normalized before every arithmetic operation, and each result is rounded exactly once by a shared round-and-pack block that detects tininess after rounding.

Details: [architecture](docs/architecture.md), [design rationale](docs/design_rationale.md), [latency and data format](docs/latency_and_data_format.md).

## Interface

- `aclk`, `aresetn`: single clock domain, active-low synchronous reset.
- `s_axi_*`: AXI4-Lite slave, 8-bit address, 32-bit data. Register map in [docs/address_map.md](docs/address_map.md).
- `s_axis_*`: 64-bit input stream. One operation is two beats: operand A, then operand B with TLAST. Unary operations ignore B.
- `m_axis_*`: 64-bit output stream. One result is two beats: the result, then the flags in bits [4:0] with TLAST.

The operation (OP, FUNCT3, RM) is set through AXI4-Lite and captured with operand A. The packet rules, error handling and abort are described in [docs/streaming_contract.md](docs/streaming_contract.md).

## Simulation

All testbenches are self-checking. Run the full regression with the AMD Vivado simulator (Vivado 2025.2 was used):

```powershell
pwsh -File scripts/run_sim.ps1
pwsh -File scripts/run_sim.ps1 -Test native,axi     # selected tests
```

The script compiles `rtl/*.v` as Verilog and `tb/*.sv` as SystemVerilog, runs 12 tests, writes logs to `build/sim/`, and exits with a non-zero code if any test fails. It finds Vivado through `-VivadoBin`, `scripts/local_settings.ps1` (not committed), `XILINX_VIVADO`, or the `PATH`. The test vectors are in `tb/mem/`. See [docs/verification.md](docs/verification.md).

## Build

`bd/vrm_fpu_bd.tcl` builds a Vivado block design for the Kria KR260 (Zynq UltraScale+ PS, AXI DMA in simple mode, the FPU as a module reference) and makes its HDL wrapper the top. Create an RTL project for part `xck26-sfvc784-2LV-c` with the KR260 board in Vivado 2025.2, then in the Tcl Console:

```tcl
source <repository>/bd/vrm_fpu_bd.tcl
```

Then run synthesis, implementation and bitstream generation. Clock, memory ports and address map are in [docs/build_overview.md](docs/build_overview.md).

## Validation Status

**FPGA-validated** on a Kria KR260 at 100 MHz. One documented gap: the board run is linked to the published RTL by recorded source hashes rather than by a synthesis log. Evidence is in [docs/validation_notes.md](docs/validation_notes.md):

- **Simulation:** the 12-test regression of this repository passes in the Vivado 2025.2 simulator. During development, the six lanes were checked against Berkeley SoftFloat 3e on 46.8 million transactions in all five rounding modes, including TestFloat level 2 cases.
- **Timing and resources:** the routed KR260 design meets timing at 100 MHz (WNS +0.114 ns, WHS +0.010 ns) and uses 20,665 LUTs (17.6 %), 16,385 flip-flops (7.0 %), 10 DSP48E2 and 3 block RAM tiles, including the AXI DMA and interconnect.
- **Board:** 584,212 operations through AXI DMA on a KR260 with zero result or flag mismatches, covering every operation and rounding mode.

This is bounded testing against a reference, not an exhaustive proof over all binary64 inputs and not a formal IEEE 754 certification.

## Credits

Expected results in `tb/mem/` were generated with [Berkeley SoftFloat 3e](https://github.com/ucb-bar/berkeley-softfloat-3) and [Berkeley TestFloat 3e](https://github.com/ucb-bar/berkeley-testfloat-3) by John R. Hauser, copyright The Regents of the University of California, BSD 3-Clause license. Neither tool is included in this repository, and no endorsement is implied. `rtl/vrm_fpu_record_fifo.v` is adapted from [VRM21-RTL-Utilities](https://github.com/VRM21-Studios/VRM21-RTL-Utilities) (MIT) and keeps its notice.

## License

MIT; see [LICENSE](LICENSE). The license covers the source code. A bitstream built from it is not distributed with this repository; if you distribute one, it contains AMD IP (Zynq PS, AXI DMA, SmartConnect) subject to the AMD license terms of your Vivado installation.
