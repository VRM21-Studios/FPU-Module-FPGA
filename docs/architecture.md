# Architecture

## Module hierarchy

```text
vrm_fpu_axi_64                 AXI4-Lite registers, AXI4-Stream packets, flow control
 +- vrm_fpu_record_fifo        request FIFO, 64 x 138 bits (OP, FUNCT3, RM, A, B)
 +- vrm_fpu_native_64          dispatcher, fixed 56-edge latency
 |   +- vrm_fpu_add_sub_64     lane A  ADD / SUB
 |   +- vrm_fpu_mul_64         lane B  MUL
 |   +- vrm_fpu_div_64         lane C  DIV
 |   +- vrm_fpu_sqrt_64        lane D  SQRT
 |   +- vrm_fpu_conv_64        lane E  int32/uint32 <-> binary64
 |   +- vrm_fpu_misc_64        lane F  FEQ FLT FLE FMIN FMAX FCLASS
 |   +- vrm_fpu_delay (x6)     latency balancing per lane
 +- vrm_fpu_record_fifo        result FIFO, 64 x 69 bits (flags, result)

shared by the lanes:
 vrm_fpu_prenorm_64            operand normalization (subnormals left-aligned)
 vrm_fpu_round_64              single rounding and packing, OF/UF/NX
 vrm_fpu_unpacker_64           field extraction and classification (lane F)
```

All modules are Verilog-2001 and use one clock and one active-low synchronous reset. There are no clock-domain crossings.

## Lanes

Each lane takes one operation per clock cycle and produces its 64-bit result and 5-bit flags after a fixed number of clock edges.

| Lane | Module | Latency (edges) | Method |
| --- | --- | ---: | --- |
| A | `vrm_fpu_add_sub_64` | 2 | Align the smaller operand with a sticky bit, add or subtract the 56-bit significands, normalize, round once. |
| B | `vrm_fpu_mul_64` | 5 | Full 106-bit significand product (DSP-mapped), normalize, round once. |
| C | `vrm_fpu_div_64` | 56 | Restoring division, one quotient bit per stage, 56 stages unrolled in space. |
| D | `vrm_fpu_sqrt_64` | 56 | Restoring square root, one root bit per stage, 56 stages unrolled in space. |
| E | `vrm_fpu_conv_64` | 1 | Integer to binary64 is exact; binary64 to integer rounds with RM, then checks the range. |
| F | `vrm_fpu_misc_64` | 0 | Comparison on sign and magnitude; NaN, signed zero and class handling per the RISC-V F/D extension. |

Latency is counted as in [latency_and_data_format.md](latency_and_data_format.md): an input sampled at clock edge n gives a result after edge n+L.

Special operands (NaN, infinity, zero, and the invalid cases such as 0 x Inf or 0/0) are detected at the input of each arithmetic lane and travel through the pipeline beside the main datapath, so special cases have the same latency as ordinary results.

## Dispatcher

`vrm_fpu_native_64` decodes OP and FUNCT3, raises the input valid of exactly one lane, and passes the operands and RM to it. A `vrm_fpu_delay` line after each lane pads the latency to 56 clock edges, the latency of division and square root. Because every operation then takes the same time, results leave in issue order and two lanes can never complete in the same cycle, so one OR of the masked lane outputs forms the output. A new operation of any type can be issued every cycle.

The dispatcher has no backpressure: every result appears exactly 56 edges after its request. An illegal OP/FUNCT3/RM tuple must not be issued; in simulation the dispatcher stops with `FPU_ASSERT_NATIVE_CONFIG`.

## AXI wrapper

`vrm_fpu_axi_64` turns the fixed-latency core into a flow-controlled stream peripheral:

1. Operand A is accepted only when the wrapper is enabled, the OP/FUNCT3/RM tuple is legal, and fewer than 64 operations are in flight. Accepting A reserves one result slot and captures OP, FUNCT3 and RM.
2. Operand B (with TLAST) completes the request, which enters the request FIFO and is issued to the core in the next cycle the FIFO presents it.
3. The core result goes into the 64-entry result FIFO. Because every operation in flight already owns a slot, the result FIFO cannot overflow even when `m_axis_tready` stays low.
4. The output sends the result beat, then the flags beat with TLAST. The slot is released when the flags beat is accepted, and the flags are then added to the sticky FFLAGS register.

A framing error, a watchdog timeout or an abort clears the data path (FIFOs, slots, partial packet) through a local data-path reset, while the AXI4-Lite channels keep working. Register details are in [address_map.md](address_map.md) and packet rules in [streaming_contract.md](streaming_contract.md).

## Reset

`aresetn` is synchronous and active low. It clears the register file, the data path and all pipeline valid bits. Pipeline data registers are also cleared, so no stale result or flag can appear after reset; the reset test checks this for every lane and rounding mode. The FIFO storage arrays are not reset; they are never read while empty.
