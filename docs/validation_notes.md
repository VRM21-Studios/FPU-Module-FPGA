# Validation Notes

Validation status: **FPGA-validated**, Kria KR260 at 100 MHz. Gap: the board run is linked to the RTL by recorded file hashes, not by a synthesis log (see the board section).

## 1. Simulation

### Repository regression

| Item | Value |
| --- | --- |
| Command | `pwsh -File scripts/run_sim.ps1` |
| Simulator | AMD Vivado Simulator 2025.2 (xvlog, xelab, xsim) |
| RTL language | Verilog (Verilog-2001 source) |
| Testbench language | SystemVerilog |
| Date | 2026-11-24 |
| Result | 12 tests, 0 failed |

| Test | PASS line |
| --- | --- |
| native | `QUAL_SUMMARY,1200,0` |
| axi | `AXI_SUMMARY,1527,4323,0` |
| conv | `QUAL_SUMMARY,12835,0` |
| misc | `QUAL_SUMMARY,1428,0` |
| mul | `QUAL_SUMMARY,3132,0` |
| add_sub | `QUAL_SUMMARY,6380,0` |
| div | `QUAL_SUMMARY,3134,0` |
| sqrt | `QUAL_SUMMARY,3091,0` |
| lane_stream | `STREAM_SUMMARY,30000,0` |
| round | `ROUND_SUMMARY,15872,0` |
| prenorm | `PRENORM_PASS finite=4196 specials=3` |
| lane_reset | `V2_RESET_PASS modes=5 lanes=6` |

A negative control (one expected-result bit flipped in a copy of `integration_smoke.mem`) made both `native` and `axi` fail, and the script exited with code 1.

### Development qualification campaign

Before publication, each lane was qualified separately against the same reference in a larger campaign. The campaign generated temporary vector batches; only the summaries are kept, not the vectors.

| Item | Value |
| --- | --- |
| Simulator | Icarus Verilog 13.0, four-state; RTL compiled as Verilog-2001, testbenches as SystemVerilog-2012 |
| Reference | Berkeley SoftFloat 3e, RISC-V specialization, tininess after rounding, flags reset before every operation; an exact-integer model in addition for the conversion and comparison lane |
| Inputs | per operation and rounding mode, 1 million constrained-random records over three seeds, Berkeley TestFloat 3e level 2 cases, and directed boundary cases |
| Checks per record | result and flags bit-exact, exact lane latency, one input per cycle with bubbles, no lost or duplicated result |

| Operations | Records | Result |
| --- | ---: | --- |
| int32/uint32 conversions, FEQ, FLT, FLE, FMIN, FMAX, FCLASS | 18,877,022 | 0 mismatches |
| MUL | 5,503,380 | 0 mismatches |
| ADD, SUB | 11,217,600 | 0 mismatches |
| DIV, SQRT | 11,221,500 | 0 mismatches |
| **Total** | **46,819,502** | **0 mismatches** |

For the conversions, the complete TestFloat level 2 sets of all four conversion functions in all five modes were included (416,120 cases). For MUL, ADD/SUB, DIV and SQRT, the first 100,000 TestFloat level 2 cases per function and mode were included, not the complete level 2 sets. Record counts include intentional repetition in boundary classes; they are not counts of distinct operands. The same campaign also ran the dispatcher (104,056 records, fixed 56-edge latency) and the AXI wrapper test of this repository.

The published RTL differs from the RTL used in the campaign and on the board only in comments: after removing comments and whitespace, all 13 files are token for token identical.

## 2. Implementation

| Item | Value |
| --- | --- |
| Tool | Vivado 2025.2 (win64), build 6299465 |
| Device | xck26-sfvc784-2LV-c, speed file -2LV PRODUCTION 1.30 |
| Design | block design with PS, AXI DMA (HP0 read, HP1 write) and `vrm_fpu_axi_64`, state Routed |
| Clock | clk_pl_0, period 10.000 ns (100 MHz) |
| Setup | WNS +0.114 ns, TNS 0.000 ns, 0 failing of 42,804 endpoints |
| Hold | WHS +0.010 ns, THS 0.000 ns, 0 failing endpoints |
| Pulse width | WPWS +3.500 ns |
| Summary | All user specified timing constraints are met |

### Resource utilization

Routed design, whole block design (FPU, AXI DMA, AXI interconnect, SmartConnects, reset and PS wrapper logic); the report is not broken down per module.

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| CLB LUTs | 20,665 | 117,120 | 17.64 % |
| of which LUT as logic | 19,267 | 117,120 | 16.45 % |
| of which LUT as memory (distributed RAM 508, shift registers 890) | 1,398 | 57,600 | 2.43 % |
| CLB registers (flip-flops) | 16,385 | 234,240 | 6.99 % |
| CARRY8 | 1,191 | 14,640 | 8.14 % |
| Block RAM tiles | 3 | 144 | 2.08 % |
| URAM | 0 | 64 | 0.00 % |
| DSP48E2 | 10 | 1,248 | 0.80 % |

The Vivado power report of the same routed design estimates 2.940 W total on-chip power (2.638 W dynamic, 0.302 W device static) with confidence level Medium; this is a tool estimate, not a measurement.

The timing, utilization and power reports were produced on 2026-11-24 from the routed design of the board build project. They are not linked by a checksum to the bitstream used on the board.

## 3. Board

| Item | Value |
| --- | --- |
| Board | AMD Kria KR260 (KR260 SOM, board part revision 1.1) |
| Bitstream | built with Vivado 2025.2, hardware handoff dated 2026-11-20 |
| PL clock | pl_clk0 requested 100 MHz, achieved 99.999001 MHz |
| Memory ports | DMA MM2S on HP0, S2MM on HP1, 128-bit |
| Addresses | FPU 0xA000_0000, AXI DMA 0xA001_0000 |
| Host | PYNQ on Linux 5.15 (Xilinx Zynq MPSoC kernel), Python 3.10.12, aarch64 |
| Transport | AXI DMA simple mode, one 16-byte packet each way per operation, polled with timeouts |
| Date | 2026-11-21 |

| Measure | Value |
| --- | --- |
| Operations | 584,212 planned, 584,212 completed |
| Mismatches (result or flags) | 0 |
| Coverage | all 15 operations x all 5 rounding modes (75 pairs); every flag bit and every FCLASS class observed |
| Register checks | LAST_FLAGS and FFLAGS compared after every operation (584,212 each); W1C of FFLAGS checked with masks 0, 1, 2, 4, 8, 16, 31 (15,918 checks) |
| Duration | 486.8 s, about 1,200 operations per second |
| Cleanup | complete (DMA quiesced, buffers released) |

The board vectors were generated with the same reference as the simulation vectors. They consist of the 503,672 records of the development lane set (of which `tb/mem/lanes-0.mem` is the first 30,000) and 80,540 directed records; they are not included in this repository because the host program that runs them is not published.

### Link between the board run and the published RTL

- The board report records the SHA-256 of the 13 RTL files expected in the bitstream; they match the RTL from which this repository was prepared, and that RTL differs from the published files only in comments.
- The board report records the MD5 and SHA-256 of the bitstream and hardware handoff that were loaded; they match the build artifacts kept by the author (bitstream SHA-256 `5b5087e75d174cb533318929eae78c8401492af045ef4d3cc55e222918dec6a6`).
- No synthesis log links that bitstream to the RTL, so this link rests on the recorded hashes and the build history, not on a reproducible build record.

## 4. Not yet measured

- Resource utilization of the FPU core alone, separate from the DMA and interconnect.
- Measured board power.
- A board run of a bitstream built with `bd/vrm_fpu_bd.tcl` from this repository. The script reproduces the board-tested topology but was written for publication.
- Throughput with scatter-gather DMA or a TLAST inserter (several operations per transfer).
- Operation outside 100 MHz, other devices, and other Vivado versions.
- Exhaustive or formal verification over all binary64 inputs.
