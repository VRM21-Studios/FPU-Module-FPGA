# Build Overview

## Target

| Item | Value |
| --- | --- |
| Board | AMD Kria KR260 |
| Device | xck26-sfvc784-2LV-c |
| Tool | Vivado 2025.2 |
| Clock | PS pl_clk0, 100 MHz nominal (99.999 MHz achieved in the tested build) |
| RTL top in the block design | `vrm_fpu_axi_64` (module reference) |

## Block design

`bd/vrm_fpu_bd.tcl` creates the block design `VrmFpu`:

```text
 Zynq UltraScale+ PS
   M_AXI_HPM0_FPD --> AXI interconnect --> vrm_fpu_axi_64_0/s_axi
                                      \--> axi_dma_0/S_AXI_LITE
   S_AXI_HP0_FPD  <-- axi_smc_hp0 <-- axi_dma_0/M_AXI_MM2S   (operand reads)
   S_AXI_HP1_FPD  <-- axi_smc_hp1 <-- axi_dma_0/M_AXI_S2MM   (result writes)
   pl_clk0, pl_resetn0 --> rst_pl0 (proc_sys_reset) --> every PL clock / reset pin

 axi_dma_0/M_AXIS_MM2S --> vrm_fpu_axi_64_0/s_axis
 vrm_fpu_axi_64_0/m_axis --> axi_dma_0/S_AXIS_S2MM
```

| Block | Configuration |
| --- | --- |
| AXI DMA | simple mode (no scatter-gather), 26-bit length, 32-bit addresses, 64-bit streams and memory masters, burst 16, no interrupts |
| HP0, HP1 | 128-bit, one SmartConnect each |
| Address map | assigned by `assign_bd_address`; the DMA maps DDR_LOW only |

The script checks its own steps and stops with a message starting with `VRM_FPU_BD_ERROR` at the first problem: wrong part or board, a missing RTL module, missing inferred interfaces, a clocking wizard added by automation, an unconnected clock or reset, or a DMA that maps more than DDR_LOW. It deletes a stale module-reference cache before creating the FPU cell, so the interfaces always come from the current RTL.

## Steps

1. In Vivado 2025.2, create an RTL project for part `xck26-sfvc784-2LV-c` and select the Kria KR260 board. Add no sources.
2. In the Tcl Console: `source <repository>/bd/vrm_fpu_bd.tcl`
3. Check the Address Editor. The DMA should show only DDR_LOW; the warning about DDR_HIGH being unreachable for a 32-bit master is expected.
4. Run synthesis, implementation and Generate Bitstream.
5. For PYNQ, copy the bitstream from `<project>.runs/impl_1/` and the hardware handoff file from `<project>.gen/sources_1/bd/VrmFpu/hw_handoff/` and give them the same base name, for example `VrmFpu.bit` and `VrmFpu.hwh`.

To run the script again, first remove `VrmFpu.bd` and its wrapper from the project and from disk, or start a new project.

## Simulation in the Vivado GUI

The regression runner does not need a project. To run a testbench in the GUI, add `rtl/*.v` as design sources and the testbench as a simulation source, set it as the simulation top, and set its parameters (for example `VECTOR_FILE` as an absolute path to a file in `tb/mem/` and `MAX_RECORDS` to its record count) in the simulation settings under Generics/Parameters. The expected PASS lines are listed in [verification.md](verification.md).
