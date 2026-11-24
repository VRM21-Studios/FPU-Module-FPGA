# Limitations

## Scope of IEEE 754

The unit implements a selected set of IEEE 754-2019 binary64 operations with default exception handling (no traps). For those operations, results and flags match the reference bit for bit in all tested cases. It is not a complete IEEE 754 implementation:

- No fused multiply-add, remainder, roundToIntegral, nextUp/nextDown, scaleB/logB, or conversions to and from decimal strings.
- binary64 only; no binary32 or other formats.
- Integer conversions are 32-bit only (int32 and uint32); no 64-bit integers.
- No sign-injection, absolute value, negate or raw move operations (they are bit manipulations that software can do).
- NaN results are always the canonical quiet NaN `7ff8000000000000`; input NaN payloads and signs are not propagated. IEEE 754 recommends, but does not require, payload propagation.
- Comparison, minimum/maximum and classification follow the RISC-V F/D extension. FMIN/FMAX return the number when one operand is NaN, and FCLASS uses the RISC-V 10-bit mask.
- Tininess is detected after rounding. A system that expects tininess before rounding will see different UF flags in a few boundary cases.

## Verification limits

- Correctness is shown by testing against Berkeley SoftFloat 3e, not by formal proof. The tests cover every operation and rounding mode with random, boundary and TestFloat inputs, but not every binary64 input.
- For MUL, ADD/SUB, DIV and SQRT, the TestFloat level 2 sets were used in part (the first 100,000 cases per function and mode), not completely.
- The repository regression is a bounded subset; the larger campaign and the board vectors are not published.

## Interface and system limits

- The dispatcher `vrm_fpu_native_64` has no output backpressure. A caller other than `vrm_fpu_axi_64` must accept every result 56 edges after issuing it.
- One operation needs two input beats, so the wrapper accepts at most one operation every two clock cycles from a continuous stream.
- With AXI DMA in simple mode, each operation needs its own DMA transfers; throughput is limited by software (about 1,200 operations per second measured on a KR260).
- The AXI DMA uses 32-bit addresses: buffers must be in the low 2 GB of DDR.
- One clock domain; the core was timed at 100 MHz only.

## Implementation

- Division and square root are unrolled over 56 stages each, which trades logic and registers for one result per cycle. The complete KR260 block design uses about 17.6 % of the LUTs and 7.0 % of the flip-flops (see [validation_notes.md](validation_notes.md)); a per-module breakdown is not published.
- Timing was met at 100 MHz with a small margin (WNS +0.114 ns, WHS +0.010 ns). A different device, speed grade, clock or tool version needs its own timing check.
- The multiplier carries Vivado `use_dsp` and retiming attributes; other tools may map it differently.
