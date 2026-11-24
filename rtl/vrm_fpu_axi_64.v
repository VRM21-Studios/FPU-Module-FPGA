// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_axi_64
// DESCRIPTION:
//   AXI wrapper around the binary64 dispatcher vrm_fpu_native_64. The
//   operation is configured through AXI4-Lite; operands and results move
//   through AXI4-Stream. One operation is one input packet (operand A, then
//   operand B with TLAST) and one output packet (result, then the exception
//   flags in bits [4:0] with TLAST). OP, FUNCT3 and RM are captured together
//   with operand A, so a register write between A and B does not affect an
//   operation that has already started.
//
// Features:
//   - Up to 64 operations in flight. An operation is admitted only when an
//     output slot is reserved for it, so results are never dropped while the
//     output stream is stalled.
//   - Sticky and last exception flags, an error register, and a watchdog
//     for an input packet left incomplete after operand A.
//   - Abort (CTRL bit 1) flushes every operation in flight; AXI4-Lite stays
//     usable during the abort.
//
// Registers (byte offset, 32-bit):
//   0x00 CTRL        RW   bit 0 enable, bit 1 abort (action; clears enable)
//   0x04 STATUS      RO   bit 0 partial packet (A received), bit 1 operations
//                         in flight, bit 2 output valid, bit 3 halted
//   0x08 OP          RW   0 ADD, 1 SUB, 2 MUL, 3 DIV, 4 SQRT,
//                         5 int32/uint32 to binary64, 6 binary64 to
//                         int32/uint32, 7 compare / min / max / class
//   0x0C FUNCT3      RW   OP 5/6: 0 signed int32, 1 unsigned int32
//                         OP 7: 0 FEQ, 1 FLT, 2 FLE, 3 FMIN, 4 FMAX, 5 FCLASS
//   0x10 RM          RW   0 RNE, 1 RTZ, 2 RDN, 3 RUP, 4 RMM
//   0x14 FFLAGS      W1C  sticky {NV, DZ, OF, UF, NX}, accumulated when a
//                         result packet is delivered
//   0x18 LAST_FLAGS  RO   flags of the last delivered result
//   0x1C ABI         RO   2 (packet format revision)
//   0x20 ERR         W1C  bit 0 rejected register access or invalid
//                         OP/FUNCT3/RM tuple, bit 1 framing error, bit 2
//                         watchdog timeout
//   0x24 WATCHDOG    RW   cycles allowed between A and B (reset 65536,
//                         zero rejected)
//   0x28 SLOTS       RO   64
//   0x2C LATENCY     RO   56 (core latency in clock edges)
//   Unmapped addresses and out-of-range writes return SLVERR.
//
// Notes:
//   - A framing error (TLAST on A or missing on B) or a watchdog timeout
//     halts the data plane until an abort or reset. An invalid OP/FUNCT3/RM
//     tuple only blocks operand A and sets ERR bit 0; it does not halt.
//   - Abort keeps OP, FUNCT3, RM, the watchdog limit and the sticky flags.
//   - Single clock domain. The ports are plain and conventionally named, so
//     Vivado infers s_axi (AXI4-Lite), s_axis and m_axis (AXI4-Stream), aclk
//     and aresetn; the interface frequency comes from the clock connected in
//     the block design.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_axi_64 (
    input  wire         aclk,
    input  wire         aresetn,

    // AXI4-Lite slave (PS), 8-bit address
    input  wire [7:0]   s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output reg  [1:0]   s_axi_bresp,
    output reg          s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [7:0]   s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output reg  [31:0]  s_axi_rdata,
    output reg  [1:0]   s_axi_rresp,
    output reg          s_axi_rvalid,
    input  wire         s_axi_rready,

    // AXI4-Stream in: operand A, then operand B with tlast
    input  wire [63:0]  s_axis_tdata,
    input  wire         s_axis_tlast,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    // AXI4-Stream out: result, then flags with tlast
    output wire [63:0]  m_axis_tdata,
    output wire         m_axis_tlast,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);
    localparam integer RESULT_SLOTS=64;
    localparam integer CORE_LATENCY=56;
    reg enabled,halted;
    reg [3:0] config_op;
    reg [2:0] config_funct3,config_rm;
    reg [31:0] watchdog_limit;
    reg [4:0] sticky_flags,last_flags;
    reg [2:0] errors;
    reg aw_held,w_held;
    reg [7:0] aw_address;
    reg [31:0] w_data;
    reg [3:0] w_strobe;
    wire write_commit=aw_held && w_held && !s_axi_bvalid;
    assign s_axi_awready=aresetn && !aw_held && !s_axi_bvalid;
    assign s_axi_wready=aresetn && !w_held && !s_axi_bvalid;
    assign s_axi_arready=aresetn && !s_axi_rvalid;
    function [31:0] merge_bytes;
        input [31:0] old_value,new_value;
        input [3:0] strobes;
        integer j;
        begin
            merge_bytes=old_value;
            for(j=0;j<4;j=j+1) if(strobes[j]) merge_bytes[j*8 +: 8]=new_value[j*8 +: 8];
        end
    endfunction
    reg [31:0] candidate;
    reg write_ok;
    always @* begin
        candidate=32'd0;write_ok=1'b1;
        case(aw_address)
            8'h00: begin candidate=merge_bytes({31'd0,enabled},w_data,w_strobe);if(candidate[31:2]!=0) write_ok=0;end
            8'h08: begin candidate=merge_bytes({28'd0,config_op},w_data,w_strobe);if(candidate>7) write_ok=0;end
            8'h0c: begin candidate=merge_bytes({29'd0,config_funct3},w_data,w_strobe);if(candidate>5) write_ok=0;end
            8'h10: begin candidate=merge_bytes({29'd0,config_rm},w_data,w_strobe);if(candidate>4) write_ok=0;end
            8'h14: begin candidate=merge_bytes(32'd0,w_data,w_strobe);if(candidate[31:5]!=0) write_ok=0;end
            8'h20: begin candidate=merge_bytes(32'd0,w_data,w_strobe);if(candidate[31:3]!=0) write_ok=0;end
            8'h24: begin candidate=merge_bytes(watchdog_limit,w_data,w_strobe);if(candidate==0) write_ok=0;end
            default: write_ok=0;
        endcase
    end
    wire write_effect=write_commit && write_ok && (|w_strobe);
    wire abort_now=write_effect && aw_address==8'h00 && candidate[1];
    wire [4:0] flags_clear=(write_effect && aw_address==8'h14) ? candidate[4:0] : 5'd0;
    wire [2:0] errors_clear=(write_effect && aw_address==8'h20) ? candidate[2:0] : 3'd0;
    reg partial,flags_phase;
    reg [6:0] reserved;
    reg [31:0] watchdog_count;
    reg [63:0] saved_a;
    reg [3:0] snapshot_op;
    reg [2:0] snapshot_funct3,snapshot_rm;
    wire tuple_legal=config_op<=7 &&
        (config_op==7 ? config_funct3<=5 :
         (config_rm<=4 && ((config_op==5 || config_op==6) ? config_funct3<=1 : 1'b1)));
    wire request_ready,request_valid;
    wire [137:0] request_data;
    wire result_ready,result_valid;
    wire [68:0] result_data;
    // Disable blocks new A, while B uses its existing reservation.
    assign s_axis_tready=aresetn && !halted && request_ready &&
        (partial || (enabled && reserved<RESULT_SLOTS && tuple_legal));
    wire input_fire=s_axis_tvalid && s_axis_tready;
    wire framing_now=input_fire && (partial ? !s_axis_tlast : s_axis_tlast);
    wire timeout_now=partial && !input_fire && watchdog_count>=watchdog_limit-32'd1;
    wire data_rstn=aresetn && !abort_now && !framing_now && !timeout_now;
    wire core_valid;
    wire [63:0] core_result;
    wire [4:0] core_flags;
    vrm_fpu_record_fifo #(138,RESULT_SLOTS) requests(aclk,data_rstn,
        {snapshot_op,snapshot_funct3,snapshot_rm,saved_a,s_axis_tdata},
        input_fire && partial && s_axis_tlast,request_ready,request_data,request_valid,1'b1);
    vrm_fpu_native_64 core(aclk,data_rstn,request_valid && data_rstn,
        request_data[137:134],request_data[133:131],request_data[130:128],request_data[127:64],request_data[63:0],core_valid,core_result,core_flags);
    vrm_fpu_record_fifo #(69,RESULT_SLOTS) results(aclk,data_rstn,{core_flags,core_result},
        core_valid,result_ready,result_data,result_valid,m_axis_tready && m_axis_tvalid && flags_phase);
    assign m_axis_tvalid=aresetn && !halted && result_valid;
    assign m_axis_tdata=m_axis_tvalid ? (flags_phase ? {59'd0,result_data[68:64]} : result_data[63:0]) : 64'd0;
    assign m_axis_tlast=m_axis_tvalid && flags_phase;
    wire output_fire=m_axis_tvalid && m_axis_tready;
    wire delivered=output_fire && flags_phase && data_rstn;
    wire config_bad=enabled && !partial && s_axis_tvalid && !tuple_legal;
    reg [31:0] read_value;
    reg read_ok;
    always @* begin
        read_value=32'd0;read_ok=1'b1;
        case(s_axi_araddr)
            8'h00: read_value={31'd0,enabled};
            8'h04: read_value={28'd0,halted,m_axis_tvalid,(reserved!=0),partial};
            8'h08: read_value={28'd0,config_op};
            8'h0c: read_value={29'd0,config_funct3};
            8'h10: read_value={29'd0,config_rm};
            8'h14: read_value={27'd0,sticky_flags};
            8'h18: read_value={27'd0,last_flags};
            8'h1c: read_value=32'd2;
            8'h20: read_value={29'd0,errors};
            8'h24: read_value=watchdog_limit;
            8'h28: read_value=RESULT_SLOTS;
            8'h2c: read_value=CORE_LATENCY;
            default: read_ok=1'b0;
        endcase
    end
    always @(posedge aclk) begin
        if(!aresetn) begin
            enabled<=0;halted<=0;config_op<=0;config_funct3<=0;config_rm<=0;
            watchdog_limit<=32'd65536;sticky_flags<=0;last_flags<=0;errors<=0;
            aw_held<=0;w_held<=0;aw_address<=0;w_data<=0;w_strobe<=0;
            s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rresp<=0;s_axi_rdata<=0;
        end else begin
            if(s_axi_awvalid && s_axi_awready) begin aw_held<=1;aw_address<=s_axi_awaddr;end
            if(s_axi_wvalid && s_axi_wready) begin w_held<=1;w_data<=s_axi_wdata;w_strobe<=s_axi_wstrb;end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(write_commit) begin
                aw_held<=0;w_held<=0;s_axi_bvalid<=1;s_axi_bresp<=write_ok ? 2'b00 : 2'b10;
            end
            if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1;s_axi_rdata<=read_value;s_axi_rresp<=read_ok ? 2'b00 : 2'b10;
            end
            sticky_flags<=(sticky_flags & ~flags_clear) | (delivered ? result_data[68:64] : 5'd0);
            if(delivered) last_flags<=result_data[68:64];
            errors<=(errors & ~errors_clear) |
                {timeout_now,framing_now,((write_commit && !write_ok) || (s_axi_arvalid && s_axi_arready && !read_ok) || config_bad)};
            if(write_effect) case(aw_address)
                8'h00: enabled<=candidate[0];
                8'h08: config_op<=candidate[3:0];
                8'h0c: config_funct3<=candidate[2:0];
                8'h10: config_rm<=candidate[2:0];
                8'h24: watchdog_limit<=candidate;
                default: begin end
            endcase
            if(framing_now || timeout_now) begin enabled<=0;halted<=1;end
            if(abort_now) begin enabled<=0;halted<=0;end
        end
    end
    always @(posedge aclk) begin
        if(!data_rstn) begin
            partial<=0;flags_phase<=0;reserved<=0;watchdog_count<=0;
            saved_a<=0;snapshot_op<=0;snapshot_funct3<=0;snapshot_rm<=0;
        end else begin
            case({(input_fire && !partial),delivered})
                2'b10: reserved<=reserved+7'd1;
                2'b01: reserved<=reserved-7'd1;
                default: reserved<=reserved;
            endcase
            if(input_fire) begin
                partial<=!partial;
                if(!partial) begin
                    saved_a<=s_axis_tdata;snapshot_op<=config_op;snapshot_funct3<=config_funct3;snapshot_rm<=config_rm;
                end
            end
            if(!partial || input_fire) watchdog_count<=0;
            else watchdog_count<=watchdog_count+32'd1;
            if(output_fire) flags_phase<=!flags_phase;
        end
    end
    // synthesis translate_off
    always @(posedge aclk) if(data_rstn) begin
        if(core_valid && !result_ready) begin $display("FPU_ASSERT_RESULT_OVERFLOW");$finish;end
        if(reserved>RESULT_SLOTS || (delivered && reserved==0)) begin $display("FPU_ASSERT_CREDIT");$finish;end
    end
    // synthesis translate_on
endmodule
