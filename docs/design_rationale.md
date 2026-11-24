# Design Rationale

## One rounding step for every operation

Every arithmetic lane keeps enough of the exact result (three extra bits, the last one sticky) and calls the same round-and-pack block once. Rounding twice, for example once to 53 bits and again when the result turns out to be subnormal, gives wrong results near the underflow boundary. Keeping the signed exponent unclipped until the round-and-pack block decides between normal, subnormal, overflow and zero avoids this. The multiplier keeps the full 106-bit significand product for the same reason.

## Tininess after rounding

IEEE 754 allows underflow to be detected before or after rounding. This design detects it after rounding, the choice made by RISC-V and by the Berkeley SoftFloat reference used for verification. The result is first rounded to 53 bits as if the exponent range were unbounded; it is tiny only if that rounded value is still below the smallest normal number. UF is then raised only when the final result is also inexact.

## Normalize subnormal inputs first

`vrm_fpu_prenorm_64` shifts a subnormal significand left until its leading one is at bit 52 and lowers the exponent accordingly, down to -1074. After that, every lane handles subnormal and normal inputs with the same datapath, and subnormal inputs need no special path.

## Spatially unrolled division and square root

Division and square root use restoring algorithms with one quotient or root bit per pipeline stage, unrolled over 56 stages. This costs area but gives one result per clock cycle and a fixed latency, with no iterative state machine and no variable-latency handshake. A restoring step is a subtract and a compare, which maps directly to carry chains.

## Fixed latency instead of a completion buffer

The lanes have very different natural latencies (0 to 56 edges). Padding every lane to 56 edges with delay lines makes the dispatcher trivially in order and collision free, so it needs no reorder buffer, arbitration, or tags. The cost is register area for the delay lines of the fast lanes.

## Credit-based admission

The dispatcher cannot stall its output. The AXI wrapper therefore reserves an output slot before it admits operand A, and frees it only when the result packet has been delivered. With 64 slots, enough to cover the 56-cycle core plus the FIFO handshakes, a fully stalled output can never cause a lost result, and a free-running input stream keeps the core busy.

## Packet framing checked in hardware

A wrong TLAST would otherwise pair operand B of one operation with operand A of the next and silently produce wrong results. The wrapper halts on any framing error and discards the operations in flight, so software sees an error instead of misaligned numbers.

## Plain ports

The top-level ports use conventional names (`aclk`, `aresetn`, `s_axi_*`, `s_axis_*`, `m_axis_*`) without interface attributes. Vivado infers the AXI interfaces and their association from the names, and the clock frequency comes from the clock connected in the block design, so the module is not tied to a specific frequency.

## RISC-V semantics for comparison and min/max

IEEE 754 leaves some details of minimum, maximum and classification open. The lane follows the RISC-V F/D extension (minimumNumber-style FMIN/FMAX, the 10-bit FCLASS mask, NaN rules of FEQ/FLT/FLE), so the unit can later serve as the floating-point core of a RISC-V processor without changing these results.
