# Streaming Contract

This document describes how software and the AXI DMA must drive `vrm_fpu_axi_64`.

## Packets

| Direction | Beat 1 | Beat 2 |
| --- | --- | --- |
| Input (`s_axis`) | operand A, TLAST = 0 | operand B, TLAST = 1 |
| Output (`m_axis`) | result, TLAST = 0 | flags in bits [4:0], other bits 0, TLAST = 1 |

Every operation uses exactly one 16-byte input packet and produces exactly one 16-byte output packet, also for unary operations (SQRT, conversions, FCLASS), where operand B is sent but ignored. Results leave in the order the operations were accepted.

## Configuration

1. Write OP, FUNCT3 and RM (address map in [address_map.md](address_map.md)).
2. Write CTRL = 1 to enable.
3. Send input packets. OP, FUNCT3 and RM are captured when operand A is accepted. Changing them later, or clearing ENABLE, does not affect an operation whose A was already accepted; its B is still accepted.

Operand A is accepted only when ENABLE is set, the OP/FUNCT3/RM tuple is legal, and fewer than 64 operations are in flight. An illegal tuple holds `s_axis_tready` low and sets ERR bit 0, but does not halt; writing a legal tuple lets the stream continue.

## Flow control

- `s_axis_tready` may stay low while 64 operations are in flight. A slot is freed when the flags beat of a result is accepted.
- The output holds its data and TLAST stable while `m_axis_tready` is low; results are never dropped.
- The idle output drives TDATA and TLAST to zero.
- With the output stalled, the FPU keeps computing until every slot holds a finished result.

## Errors and recovery

| Event | Effect |
| --- | --- |
| TLAST on operand A, or no TLAST on operand B | ERR bit 1, HALTED set, all operations in flight discarded, no output for them |
| Operand B not received within WATCHDOG cycles after A | ERR bit 2, HALTED set, all operations in flight discarded |
| Output stalled for any time | No error; the watchdog only counts while waiting for operand B |
| Write CTRL bit 1 (ABORT) | All operations in flight and any partial packet discarded, HALTED and ENABLE cleared; OP, FUNCT3, RM, WATCHDOG, FFLAGS and ERR are kept |
| `aresetn` low | Everything returns to the reset state |

After a halt, write CTRL = 2 (abort), clear ERR by writing 1s to its bits, and enable again. AXI4-Lite reads and writes work in every state.

## Flags

LAST_FLAGS holds the flags of the most recently delivered result, and FFLAGS accumulates them. Both update when the flags beat is accepted, not when the result is computed, so FFLAGS reflects only results that software has received. A W1C write to FFLAGS in the same cycle as a delivery keeps the newly delivered flags.

## AXI DMA in simple mode

AXI DMA in simple (non scatter-gather) mode asserts TLAST only at the end of a transfer. Therefore:

- Issue one MM2S transfer of 16 bytes (A, then B) per operation.
- Issue one S2MM transfer of 16 bytes per result, and arm it before starting the MM2S transfer.
- A single MM2S transfer of 2N words is not N operations: it carries TLAST only on the last word and causes a framing error.
- With 32-bit DMA addresses, buffers must be in the low 2 GB of DDR. Buffers must be flushed before MM2S and invalidated after S2MM when the CPU caches them.
- Bound every wait on the DMA with a timeout, and on a timeout reset the DMA and abort the FPU before the next operation.

Batching several operations per DMA transfer would need scatter-gather or a TLAST inserter; neither is part of this repository.
