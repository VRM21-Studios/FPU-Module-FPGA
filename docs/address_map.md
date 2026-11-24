# Address Map

## Register file of `vrm_fpu_axi_64`

AXI4-Lite slave, 8-bit byte address, 32-bit registers. All offsets are relative to the base address of the FPU in the block design. Unmapped addresses and rejected writes return SLVERR and set ERR bit 0.

| Offset | Name | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| 0x00 | CTRL | RW | 0 | bit 0 ENABLE: admit new operations. bit 1 ABORT (write 1): flush every operation in flight, clear ENABLE and the halted state. Bits [31:2] must be 0. |
| 0x04 | STATUS | RO | 0 | bit 0 PARTIAL: operand A received, waiting for B. bit 1 BUSY: at least one operation in flight. bit 2 OUT_VALID: an output beat is waiting. bit 3 HALTED: data plane stopped by a framing or watchdog error. |
| 0x08 | OP | RW | 0 | Operation, 0..7 (see below). Writes above 7 are rejected. |
| 0x0C | FUNCT3 | RW | 0 | Sub-operation, 0..5 (see below). Writes above 5 are rejected. |
| 0x10 | RM | RW | 0 | Rounding mode, 0..4. Writes above 4 are rejected. |
| 0x14 | FFLAGS | W1C | 0 | Sticky exception flags {NV, DZ, OF, UF, NX} in bits [4:0]. Set when a result packet is delivered; write 1 to clear a bit. |
| 0x18 | LAST_FLAGS | RO | 0 | Flags of the last delivered result. |
| 0x1C | ABI | RO | 2 | Packet format revision. |
| 0x20 | ERR | W1C | 0 | bit 0 CONFIG: rejected register access, or operand A offered while OP/FUNCT3/RM is an illegal tuple. bit 1 FRAMING: TLAST on operand A or missing on operand B. bit 2 TIMEOUT: operand B did not arrive within WATCHDOG cycles. |
| 0x24 | WATCHDOG | RW | 65536 | Maximum cycles between operand A and operand B. Zero is rejected. |
| 0x28 | SLOTS | RO | 64 | Maximum number of operations in flight. |
| 0x2C | LATENCY | RO | 56 | Latency of the arithmetic core in clock edges. |

Byte strobes are honored on every RW register; a write is checked against the merged 32-bit value.

## Operation codes

| OP | FUNCT3 | Operation | Uses RM |
| ---: | ---: | --- | --- |
| 0 | any | ADD | yes |
| 1 | any | SUB | yes |
| 2 | any | MUL | yes |
| 3 | any | DIV | yes |
| 4 | any | SQRT (operand B ignored) | yes |
| 5 | 0 | int32 to binary64 (A[31:0]) | value checked, result always exact |
| 5 | 1 | uint32 to binary64 (A[31:0]) | value checked, result always exact |
| 6 | 0 | binary64 to int32 | yes |
| 6 | 1 | binary64 to uint32 | yes |
| 7 | 0 | FEQ | no |
| 7 | 1 | FLT | no |
| 7 | 2 | FLE | no |
| 7 | 3 | FMIN | no |
| 7 | 4 | FMAX | no |
| 7 | 5 | FCLASS (operand B ignored) | no |

A tuple is legal when OP is 0..4 with RM 0..4; OP 5 or 6 with FUNCT3 0..1 and RM 0..4; or OP 7 with FUNCT3 0..5 (any RM). Operand A of an illegal tuple is not accepted and ERR bit 0 is set; correcting the registers lets the stream continue without an abort.

## Rounding modes

| RM | Mode | Rule |
| ---: | --- | --- |
| 0 | RNE | Round to nearest, ties to even |
| 1 | RTZ | Round toward zero |
| 2 | RDN | Round toward negative infinity |
| 3 | RUP | Round toward positive infinity |
| 4 | RMM | Round to nearest, ties away from zero |

## Exception flags

| Bit | Flag | Meaning |
| ---: | --- | --- |
| 4 | NV | Invalid operation |
| 3 | DZ | Division of a finite nonzero number by zero |
| 2 | OF | Overflow |
| 1 | UF | Underflow (tiny after rounding and inexact) |
| 0 | NX | Inexact |

## FCLASS mask

| Bit | Class | Bit | Class |
| ---: | --- | ---: | --- |
| 0 | negative infinity | 5 | positive subnormal |
| 1 | negative normal | 6 | positive normal |
| 2 | negative subnormal | 7 | positive infinity |
| 3 | negative zero | 8 | signaling NaN |
| 4 | positive zero | 9 | quiet NaN |

## Block design addresses

`bd/vrm_fpu_bd.tcl` assigns addresses automatically. In the board-tested build, the FPU registers were at 0xA000_0000 (4 KiB) and the AXI DMA registers at 0xA001_0000 (64 KiB). Software should read the actual addresses from the `.hwh` file of its own build.
