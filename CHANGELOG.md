# Changelog

## v2.0.0 - 2026-11-24

New design. Not compatible with v1.0.0: the operation set, the register map and the output packet changed.

### Added

- Correctly rounded binary64 ADD, SUB, MUL, DIV and SQRT, bit-exact with Berkeley SoftFloat 3e in all tested cases, including subnormal inputs and results.
- Five rounding modes (RNE, RTZ, RDN, RUP, RMM) selected by the new RM register.
- IEEE 754 exception flags {NV, DZ, OF, UF, NX} per operation, returned as a second output beat, with sticky (W1C) and last-result flag registers.
- int32 and uint32 conversions in both directions with range checks and saturating invalid results.
- FEQ, FLT, FLE, FMIN, FMAX and FCLASS with RISC-V F/D semantics.
- Fully pipelined lanes: one operation per cycle for any mix of operations, fixed 56-edge core latency, in-order results.
- AXI wrapper with 64 operations in flight and no result loss under output backpressure, framing and watchdog error detection, abort, status and error registers.
- Self-checking testbenches, test vectors, and a one-command simulation runner (`scripts/run_sim.ps1`).
- Block-design script for the Kria KR260 (`bd/vrm_fpu_bd.tcl`).
- Documentation set under `docs/`, including validation notes for simulation, timing at 100 MHz, and a 584,212-operation board run on a Kria KR260.

### Removed

- LOG2, LN, EXP2, EXP, SIN, COS, SIGMOID and TANH. Their polynomial approximations were not correctly rounded. OP 8 is now an illegal operation.

### Changed

- Output packet: two beats per operation (result, then flags with TLAST) instead of one.
- Register map: see `docs/address_map.md`. OP and FUNCT3 keep their offsets (0x08, 0x0C); OP 5 and 6 now use FUNCT3 0/1 to select signed or unsigned int32.

## v1.0.0

First published design: FP64 arithmetic, conversion and comparison, plus approximated transcendental and activation functions, tested on a Kria KV260 through PYNQ. Its documented limitations include incorrect results for subnormal and underflow cases and no rounding-mode selection or exception flags.
