# ============================================================================
# VRM21 Studios - FPU-Module-FPGA
# ============================================================================
# Script: bd/vrm_fpu_bd.tcl
# Purpose:
#   Creates the block design "VrmFpu" for the Kria KR260 (xck26-sfvc784-2LV-c):
#   Zynq UltraScale+ PS, one AXI DMA in simple mode and the FPU top
#   vrm_fpu_axi_64 as a module reference, then validates the design and makes
#   the HDL wrapper the top. It does not run synthesis, implementation or
#   bitstream generation.
# Usage (Vivado 2025.2 GUI, Tcl Console):
#   1. Create a new RTL project with part xck26-sfvc784-2LV-c and the Kria
#      KR260 board selected. Do not add sources; this script adds rtl/*.v.
#   2. source <repository>/bd/vrm_fpu_bd.tcl
#   3. Check the Address Editor, then run synthesis, implementation and
#      bitstream generation. For PYNQ, export VrmFpu.bit and VrmFpu.hwh with
#      the same base name (the .hwh is under .gen/.../bd/VrmFpu/hw_handoff).
#   To run again after a failure, remove VrmFpu.bd and its wrapper from the
#   project and from disk first (or close and reopen the project).
# Layout expected: this file in <repository>/bd/, RTL in <repository>/rtl/.
#
# STREAM MAP (64-bit AXI4-Stream, one operation = 16 bytes in, 16 bytes out)
#   axi_dma_0/M_AXIS_MM2S    -> vrm_fpu_axi_64_0/s_axis   (A, then B + TLAST)
#   vrm_fpu_axi_64_0/m_axis  -> axi_dma_0/S_AXIS_S2MM     (result, then flags + TLAST)
#   AXI DMA simple mode asserts TLAST only at the end of a transfer, so issue
#   one 16-byte MM2S transfer and one 16-byte S2MM transfer per operation
#   (arm S2MM first).
#
# MEMORY PORTS (same topology as the board-tested build: read side on HP0,
#   write side on HP1, one SmartConnect per port, 128-bit PS ports)
#   axi_dma_0/M_AXI_MM2S -> axi_smc_hp0 -> S_AXI_HP0_FPD
#   axi_dma_0/M_AXI_S2MM -> axi_smc_hp1 -> S_AXI_HP1_FPD
#   The DMA uses 32-bit addresses, so only DDR_LOW is mapped: keep DMA buffers
#   below 2 GB.
#
# CLOCK / RESET
#   One domain: pl_clk0 (nominal 100 MHz; the achieved PS frequency is used),
#   pl_clk1 off, one proc_sys_reset driven by pl_resetn0. Every PL clock pin
#   is connected before connection automation so that no clocking wizard is
#   added.
#
# ADDRESS MAP (assigned by assign_bd_address and printed at the end; a PYNQ
#   overlay reads the actual values from the .hwh)
#   vrm_fpu_axi_64_0/s_axi    AXI4-Lite registers 0x00..0x2C (see
#                             docs/address_map.md)
#   axi_dma_0/S_AXI_LITE      AXI DMA registers (MM2S at 0x00, S2MM at 0x30)
#   PL-to-PS interrupts are off; software polls the DMA status.
# ============================================================================

# ---------------------------------------------------------------- settings
set BD_NAME       "VrmFpu"
set PART          "xck26-sfvc784-2LV-c"
set PL_CLK_MHZ    100
set TOP_MODULE    "vrm_fpu_axi_64"
set FPU_CELL      "vrm_fpu_axi_64_0"
set DMA_CELL      "axi_dma_0"
set FPU_MIN_RANGE 0x100
set DMA_MIN_RANGE 0x100

proc bd_fail {msg} { error "VRM_FPU_BD_ERROR: $msg" }
proc bd_info {msg} { puts "VRM_FPU_BD: $msg" }

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set SRC_DIR    [file normalize [file join $SCRIPT_DIR .. rtl]]

# ---------------------------------------------------------------- project checks
if {[llength [get_projects -quiet]] == 0} {
    bd_fail "no open project: create one first (part $PART, Kria KR260 board)"
}
set proj_name [get_property NAME [current_project]]
set proj_dir  [get_property DIRECTORY [current_project]]
if {[get_property PART [current_project]] ne $PART} {
    bd_fail "project part is [get_property PART [current_project]], expected $PART"
}
set board [get_property BOARD_PART [current_project]]
if {![string match -nocase "*kr260*" $board]} {
    bd_fail "board_part '$board' is not a Kria KR260 board"
}
bd_info "project $proj_name ($proj_dir), board $board, RTL $SRC_DIR"

# ---------------------------------------------------------------- RTL sources
set RTL_FILES [lsort [glob -nocomplain -directory $SRC_DIR *.v]]
if {[llength $RTL_FILES] == 0} { bd_fail "no RTL found in $SRC_DIR" }
# Every vrm_* module instantiated by the RTL must be declared by the RTL.
set declared {}
set used {}
foreach p $RTL_FILES {
    set fd [open $p r]; set text [read $fd]; close $fd
    foreach {all name} [regexp -all -inline -line {^\s*module\s+(\w+)} $text] { lappend declared $name }
    foreach {all name} [regexp -all -inline {\m(vrm_\w+)\M\s*(?:#\s*\(|\w+\s*\()} $text] { lappend used $name }
}
set undeclared {}
foreach name [lsort -unique $used] {
    if {[lsearch -exact $declared $name] < 0} { lappend undeclared $name }
}
if {[llength $undeclared] > 0} { bd_fail "instantiated modules without a source file: $undeclared" }
if {[lsearch -exact $declared $TOP_MODULE] < 0} { bd_fail "top module $TOP_MODULE not found in $SRC_DIR" }
bd_info "RTL: [llength $RTL_FILES] files, [llength [lsort -unique $declared]] modules"

# A module reference needs every RTL file in sources_1.
foreach p $RTL_FILES {
    if {[llength [get_files -quiet -of_objects [get_filesets sources_1] $p]] > 0} { continue }
    set in_sim [get_files -quiet -of_objects [get_filesets sim_1] $p]
    if {[llength $in_sim] > 0} {
        move_files -fileset sources_1 $in_sim
    } else {
        add_files -fileset sources_1 -norecurse $p
    }
}
set_property top $TOP_MODULE [get_filesets sources_1]
update_compile_order -fileset sources_1
set order_rpt [file join $proj_dir "${BD_NAME}_compile_order.txt"]
report_compile_order -of_objects [get_filesets sources_1] -file $order_rpt
set fd [open $order_rpt r]; set rpt [read $fd]; close $fd
set idx [string first "Missing instances" $rpt]
if {$idx < 0 || ![string match "*< empty >*" [string range $rpt $idx end]]} {
    bd_fail "Vivado reports missing instances under $TOP_MODULE; see $order_rpt"
}

# ---------------------------------------------------------------- block design
if {[llength [get_files -quiet ${BD_NAME}.bd]] > 0} {
    bd_fail "block design $BD_NAME already exists: remove it and its wrapper (also from disk), then run again"
}
set bd_dir [file join $proj_dir ${proj_name}.srcs sources_1 bd $BD_NAME]
if {[file exists $bd_dir]} {
    bd_fail "leftover block design folder: $bd_dir (delete it or close and reopen the project)"
}
# No block design exists yet, so a cached module-reference definition can
# only be stale; remove it so the interfaces are inferred from the current RTL.
set mref_dir [file join $proj_dir ${proj_name}.gen sources_1 bd mref $TOP_MODULE]
if {[file exists $mref_dir]} { file delete -force $mref_dir }

create_bd_design $BD_NAME
current_bd_design $BD_NAME

proc need_pin {path} {
    set p [get_bd_pins -quiet $path]
    if {$p eq ""} { bd_fail "pin $path not found" }
    return $p
}
proc need_intf {path} {
    set p [get_bd_intf_pins -quiet $path]
    if {$p eq ""} { bd_fail "interface $path not found" }
    return $p
}
# Connect a pin to a source net only when it is still unconnected.
proc tie {src path} {
    set p [need_pin $path]
    if {[llength [get_bd_nets -quiet -of_objects $p]] == 0} { connect_bd_net $src $p }
}

# ---- 1. Zynq UltraScale+ PS with the KR260 board preset
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps

# ---- 2. PS configuration: pl_clk0, HPM0_FPD for AXI4-Lite, HP0/HP1 for the DMA
set_property -dict [list \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $PL_CLK_MHZ \
    CONFIG.PSU__FPGA_PL1_ENABLE {0} \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__IRQ0 {0} \
    CONFIG.PSU__USE__IRQ1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {1} \
    CONFIG.PSU__SAXIGP3__DATA_WIDTH {128} \
] $ps
foreach i {M_AXI_HPM0_FPD S_AXI_HP0_FPD S_AXI_HP1_FPD} { need_intf zynq_ultra_ps_e_0/$i }
set clk [need_pin zynq_ultra_ps_e_0/pl_clk0]
bd_info "pl_clk0 requested $PL_CLK_MHZ MHz, achieved [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps] MHz"

# ---- 3. AXI DMA: simple mode, 64-bit streams and memory masters, burst 16
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma $DMA_CELL]
set_property -dict [list \
    CONFIG.c_include_sg {0} CONFIG.c_sg_length_width {26} CONFIG.c_addr_width {32} \
    CONFIG.c_include_mm2s {1} CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_include_s2mm {1} CONFIG.c_s_axis_s2mm_tdata_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} CONFIG.c_s2mm_burst_size {16} \
] $dma

# ---- 4. FPU module reference and interface check
create_bd_cell -type module -reference $TOP_MODULE $FPU_CELL
set missing {}
foreach i {s_axi s_axis m_axis} { if {[get_bd_intf_pins -quiet $FPU_CELL/$i] eq ""} { lappend missing $i } }
foreach p {aclk aresetn} { if {[get_bd_pins -quiet $FPU_CELL/$p] eq ""} { lappend missing $p } }
if {[llength $missing] > 0} {
    catch {update_module_reference [get_bd_cells $FPU_CELL]}
    set missing {}
    foreach i {s_axi s_axis m_axis} { if {[get_bd_intf_pins -quiet $FPU_CELL/$i] eq ""} { lappend missing $i } }
    if {[llength $missing] > 0} {
        bd_fail "$FPU_CELL lacks $missing; visible: [get_bd_intf_pins -quiet $FPU_CELL/*]"
    }
}

# ---- 5. AXI4-Stream connections
connect_bd_intf_net [need_intf $DMA_CELL/M_AXIS_MM2S] [need_intf $FPU_CELL/s_axis]
connect_bd_intf_net [need_intf $FPU_CELL/m_axis]      [need_intf $DMA_CELL/S_AXIS_S2MM]

# ---- 6. Clock and reset, explicit before connection automation
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_pl0
connect_bd_net $clk [need_pin rst_pl0/slowest_sync_clk]
connect_bd_net [need_pin zynq_ultra_ps_e_0/pl_resetn0] [need_pin rst_pl0/ext_reset_in]
set rstn [need_pin rst_pl0/peripheral_aresetn]
foreach p [list $FPU_CELL/aclk $DMA_CELL/s_axi_lite_aclk $DMA_CELL/m_axi_mm2s_aclk \
                $DMA_CELL/m_axi_s2mm_aclk zynq_ultra_ps_e_0/maxihpm0_fpd_aclk \
                zynq_ultra_ps_e_0/saxihp0_fpd_aclk zynq_ultra_ps_e_0/saxihp1_fpd_aclk] {
    tie $clk $p
}
foreach p [list $FPU_CELL/aresetn $DMA_CELL/axi_resetn] { tie $rstn $p }

# ---- 7. AXI4-Lite slaves on M_AXI_HPM0_FPD by connection automation
foreach s [list $FPU_CELL/s_axi $DMA_CELL/S_AXI_LITE] {
    set pin [need_intf $s]
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
        Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
        Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave /$s \
        ddr_seg {Auto} intc_ip {Auto} master_apm {0}] $pin
}
if {[get_bd_cells -quiet -hierarchical -filter {VLNV =~ "*clk_wiz*"}] ne ""} {
    bd_fail "connection automation inserted a clocking wizard; check the clock connections"
}

# ---- 8. DDR side: one SmartConnect per HP port, created explicitly
#          (DMA read side on HP0, write side on HP1)
foreach {smc src hp} [list \
        axi_smc_hp0 $DMA_CELL/M_AXI_MM2S zynq_ultra_ps_e_0/S_AXI_HP0_FPD \
        axi_smc_hp1 $DMA_CELL/M_AXI_S2MM zynq_ultra_ps_e_0/S_AXI_HP1_FPD] {
    set cell [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect $smc]
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $cell
    tie $clk  $smc/aclk
    tie $rstn $smc/aresetn
    connect_bd_intf_net [need_intf $src] [need_intf $smc/S00_AXI]
    connect_bd_intf_net [need_intf $smc/M00_AXI] [need_intf $hp]
}

# ---- 9. Any clock or reset input still open (interconnect added by automation)
foreach cell [get_bd_cells -quiet] {
    set vlnv [get_property VLNV $cell]
    if {[string match "*zynq_ultra_ps_e*" $vlnv] || [string match "*proc_sys_reset*" $vlnv]} { continue }
    foreach p [get_bd_pins -quiet -of_objects $cell -filter {TYPE == clk && DIR == I}] {
        if {[llength [get_bd_nets -quiet -of_objects $p]] == 0} { connect_bd_net $clk $p }
    }
    foreach p [get_bd_pins -quiet -of_objects $cell -filter {TYPE == rst && DIR == I}] {
        if {[llength [get_bd_nets -quiet -of_objects $p]] == 0} { connect_bd_net $rstn $p }
    }
}
foreach p [get_bd_pins -quiet -hierarchical -filter {(TYPE == clk || TYPE == rst) && DIR == I}] {
    if {[llength [get_bd_nets -quiet -of_objects $p]] == 0 && ![string match "/rst_pl0/*" $p]} {
        bd_fail "clock/reset pin left unconnected: $p"
    }
}

# ---- 10. Address map
assign_bd_address
# 32-bit DMA masters: keep DDR_LOW only (a warning for DDR_HIGH is expected).
foreach sp [list $DMA_CELL/Data_MM2S $DMA_CELL/Data_S2MM] {
    set space [get_bd_addr_spaces -quiet $sp]
    if {$space eq ""} { bd_fail "address space $sp not found" }
    foreach seg [get_bd_addr_segs -quiet -of_objects $space] {
        if {![string match "*DDR_LOW*" [get_property NAME $seg]]} { catch {exclude_bd_addr_seg $seg} }
    }
    set excl {}
    catch {set excl [get_bd_addr_segs -quiet -excluded -of_objects $space]}
    set kept {}
    foreach seg [get_bd_addr_segs -quiet -of_objects $space] {
        if {[lsearch -exact $excl $seg] < 0} { lappend kept [get_property NAME $seg] }
    }
    if {[llength $kept] != 1 || ![string match "*DDR_LOW*" [lindex $kept 0]]} {
        bd_fail "$sp must map exactly DDR_LOW, has: $kept"
    }
}
set ps_space [get_bd_addr_spaces -quiet zynq_ultra_ps_e_0/Data]
set ps_excl {}
catch {set ps_excl [get_bd_addr_segs -quiet -excluded -of_objects $ps_space]}
foreach {cell minimum} [list $FPU_CELL $FPU_MIN_RANGE $DMA_CELL $DMA_MIN_RANGE] {
    set segs {}
    foreach seg [get_bd_addr_segs -quiet -of_objects $ps_space] {
        if {[string match "*SEG_${cell}_*" [get_property NAME $seg]] && [lsearch -exact $ps_excl $seg] < 0} {
            lappend segs $seg
        }
    }
    if {[llength $segs] != 1} { bd_fail "$cell must have exactly one PS address segment, found [llength $segs]" }
    set seg [lindex $segs 0]
    if {[get_property RANGE $seg] < $minimum} { bd_fail "$cell address range is smaller than its register map" }
    bd_info [format "ADDRESS %-18s offset %s range %s" $cell [get_property OFFSET $seg] [get_property RANGE $seg]]
}

# ---- 11. Validate, save and make the wrapper the top
regenerate_bd_layout
validate_bd_design
save_bd_design
set wrap [make_wrapper -files [get_files ${BD_NAME}.bd] -top]
if {$wrap eq "" || ![file exists $wrap]} { bd_fail "wrapper not generated; use Sources > Create HDL Wrapper" }
add_files -norecurse $wrap
set_property top ${BD_NAME}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
bd_info "done: top = ${BD_NAME}_wrapper. Check the Address Editor, then build the bitstream."
