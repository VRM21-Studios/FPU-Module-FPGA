# Verification

## Regression

`scripts/run_sim.ps1` compiles `rtl/*.v` as Verilog and `tb/*.sv` as SystemVerilog with the AMD Vivado simulator and runs these tests:

| Test | Testbench | Device under test | Vectors | PASS line |
| --- | --- | --- | --- | --- |
| native | `tb_vrm_fpu_native_64` | dispatcher | `integration_smoke.mem` (1,200) | `QUAL_SUMMARY,1200,0` |
| axi | `tb_vrm_fpu_axi_64` | AXI wrapper + dispatcher | `integration_smoke.mem` (1,200) | `AXI_SUMMARY,1527,4323,0` |
| conv | `tb_vrm_fpu_lanes_64`, KIND 0 | `vrm_fpu_conv_64` | `conv.mem` (12,835) | `QUAL_SUMMARY,12835,0` |
| misc | `tb_vrm_fpu_lanes_64`, KIND 1 | `vrm_fpu_misc_64` | `misc.mem` (1,428) | `QUAL_SUMMARY,1428,0` |
| mul | `tb_vrm_fpu_lanes_64`, KIND 2 | `vrm_fpu_mul_64` | `mul.mem` (3,132) | `QUAL_SUMMARY,3132,0` |
| add_sub | `tb_vrm_fpu_arith_64`, KIND 3 | `vrm_fpu_add_sub_64` | `add_sub.mem` (6,380) | `QUAL_SUMMARY,6380,0` |
| div | `tb_vrm_fpu_arith_64`, KIND 4 | `vrm_fpu_div_64` | `div.mem` (3,134) | `QUAL_SUMMARY,3134,0` |
| sqrt | `tb_vrm_fpu_arith_64`, KIND 5 | `vrm_fpu_sqrt_64` | `sqrt.mem` (3,091) | `QUAL_SUMMARY,3091,0` |
| lane_stream | `tb_vrm_fpu_lane_stream` | all six lanes in parallel | `lanes-0.mem` (30,000) | `STREAM_SUMMARY,30000,0` |
| round | `tb_vrm_fpu_round_64` | `vrm_fpu_round_64` | `round.mem` (15,872) | `ROUND_SUMMARY,15872,0` |
| prenorm | `tb_vrm_fpu_prenorm_64` | `vrm_fpu_prenorm_64` | generated in the testbench | `PRENORM_PASS finite=4196 specials=3` |
| lane_reset | `tb_vrm_fpu_lane_reset` | all six lanes | fixed in the testbench | `V2_RESET_PASS modes=5 lanes=6` |

A test passes only when its PASS line appears and its log contains no `$fatal` message, error, or `FPU_ASSERT_*` line from the RTL simulation checks. The script exits with a non-zero code when any test fails and writes `build/sim/summary.txt` and one log per test.

## What the testbenches check

- **Bit-exact results and flags.** Every record compares the 64-bit result and the 5 flags with the expected values using four-state comparison, so an X or Z also fails.
- **Exact latency and throughput.** Records are issued back to back with periodic bubbles; every result must arrive exactly L edges after its input, and no result may be lost, duplicated or invented.
- **AXI behavior.** Register access orders, SLVERR, byte strobes, W1C, illegal tuples, the tuple snapshot at operand A, all 64 slots full with the output stalled, a 256-operation burst at one beat per cycle, framing errors, the watchdog, abort and reset at every packet boundary, and stable output under backpressure.
- **Reset.** In-flight operations are discarded, and results after reset carry no stale data or flags.

## Expected values

The expected results and flags were generated with Berkeley SoftFloat 3e (RISC-V specialization, tininess after rounding, flags reset before every operation), with Berkeley TestFloat 3e level 2 cases among the inputs. For FMIN, FMAX and FCLASS, whose RISC-V semantics SoftFloat does not fully cover, the reference applies the rules in [latency_and_data_format.md](latency_and_data_format.md) explicitly. NaN results are compared bit for bit with the canonical quiet NaN.

The vector files cover every operation in every rounding mode: random operands over all classes, operands at exponent and rounding boundaries, subnormal, zero, infinity and NaN inputs (quiet and signaling), and TestFloat cases. `conv`, `misc`, `mul`, `add_sub`, `div` and `sqrt.mem` are the records of `lanes-0.mem` filtered by operation, with their expected values unchanged.

## Negative control

To confirm that the checks can fail, flip one bit of an expected result in a copy of a vector file and run the test on that copy: the test must report FAIL. The native and lane testbenches also have a `CORRUPT_ACTUAL_FLAGS` parameter that flips one flag bit of the device output for the same purpose.

## Scope

This regression is a bounded set of 78,272 vector records plus the generated prenorm and reset cases, chosen to run in about two minutes. The larger development campaign and the board test are described in [validation_notes.md](validation_notes.md). Neither is an exhaustive proof over all binary64 inputs.
