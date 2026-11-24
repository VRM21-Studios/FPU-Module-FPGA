# Test Vectors

Each file is ASCII hexadecimal, one 256-bit word per line: the magic word `f7540001`, the record count, then the records. The record layout is in [docs/latency_and_data_format.md](../../docs/latency_and_data_format.md). Expected results and flags were generated with Berkeley SoftFloat 3e (RISC-V specialization, tininess after rounding); see [docs/verification.md](../../docs/verification.md). Do not edit expected values to make a failing test pass.

| File | Records | Used by | Content | SHA-256 |
| --- | ---: | --- | --- | --- |
| `integration_smoke.mem` | 1,200 | native, axi | every operation in every legal rounding mode | `d5b985699bad75b3b917224005d7cded0dac8aace2ddbb97a89a068a0f3bbe9b` |
| `lanes-0.mem` | 30,000 | lane_stream | mixed operations of all six lanes | `f1801aea135c1b89080c8bcaea2256532f3555d3a49bc9ab92270ee2e638729d` |
| `conv.mem` | 12,835 | conv | records of `lanes-0.mem` with OP 5 or 6 | `3c3a4465e9bcc3c682281af3d78d98954c9627eebbab827863a7a4621e7457c0` |
| `misc.mem` | 1,428 | misc | records of `lanes-0.mem` with OP 7 | `a8df5aa14d023bec005498e8ffbfaa4d4f547e751b6da04af36c8bbf93da6ed3` |
| `mul.mem` | 3,132 | mul | records of `lanes-0.mem` with OP 2 | `fd23e7585e5e890141ad0dbbfcac889f3a84f5d638763473177974f059ff9248` |
| `add_sub.mem` | 6,380 | add_sub | records of `lanes-0.mem` with OP 0 or 1 | `85b00ce706d0838ffba4ebc6565e5eb1429055e59a3700aa1ae83356382335f7` |
| `div.mem` | 3,134 | div | records of `lanes-0.mem` with OP 3 | `284524aea9da613f3be02931e935c73b85630afc1cb5eb66bfd1ee6ef43dd758` |
| `sqrt.mem` | 3,091 | sqrt | records of `lanes-0.mem` with OP 4 | `d86338d3cd06dd9609af3903ba02b55cf3ed22016529f95a57ff68c3344ea1fb` |
| `round.mem` | 15,872 | round | round/pack inputs at the overflow, subnormal and underflow boundaries, plus random inputs | `1b2492357dbda82a5d99de9bbb03f0a70826e7d43a916895159101eaa330bfb3` |
