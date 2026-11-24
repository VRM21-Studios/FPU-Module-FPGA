// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_axi_64
// Description:
//   System test of the AXI wrapper vrm_fpu_axi_64 (and through it the full
//   dispatcher). Expected results and flags come from the vector file; they
//   were generated with Berkeley SoftFloat 3e (tininess after rounding) plus
//   explicit reference rules for RISC-V min/max/class semantics.
//   Phases:
//     1. Register checks: ABI/SLOTS/LATENCY values, AW-first, W-first and
//        simultaneous writes, held B/R responses, SLVERR on illegal writes
//        and unmapped reads, byte strobes, W1C of ERR.
//     2. Invalid OP/FUNCT3/RM tuple blocks operand A without halting.
//     3. Tuple snapshot at operand A; configuration writes racing A.
//     4. All 64 result slots reserved with the output stalled; full-rate
//        burst of 256 operations with no avoidable bubble.
//     5. Every vector-file record through AXI with random output stalls.
//     6. Sticky/last flags and W1C timing, framing errors, watchdog limit,
//        abort and reset at every packet boundary.
//   Continuous checks: stream payload held under backpressure, idle output
//   masked to zero, no ghost or duplicate result, TLAST position, result
//   slot accounting.
// Parameters:
//   VECTOR_FILE  vector file (default tb/mem/integration_smoke.mem,
//                relative to the repository root); MAX_RECORDS >= its count.
// Result:
//   PASS: prints "AXI_SUMMARY,<delivered>,<checks>,0" and calls $finish
//         (1527 delivered results and 4323 checks with the default file).
//   FAIL: $fatal with an AXI_* message, or an FPU_ASSERT_* line from the RTL.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_axi_64;
    parameter VECTOR_FILE="tb/mem/integration_smoke.mem";
    parameter integer MAX_RECORDS=4096;
    reg clk=0;always #5 clk=~clk;
    reg rstn=0;
    reg [7:0] awaddr=0,araddr=0;
    reg awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0;
    reg [31:0] wdata=0;reg [3:0] wstrb=0;
    wire awready,wready,arready,bvalid,rvalid;
    wire [1:0] bresp,rresp;wire [31:0] rdata;
    reg [63:0] sdata=0;reg slast=0,svalid=0;wire sready;
    wire [63:0] mdata;wire mlast,mvalid;reg mready=0;
    integer ready_mode=0;reg [31:0] rng=32'h21f0754;
    vrm_fpu_axi_64 dut(
        .aclk(clk),.aresetn(rstn),.s_axi_awaddr(awaddr),.s_axi_awprot(3'd0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(3'd0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .s_axis_tdata(sdata),.s_axis_tlast(slast),.s_axis_tvalid(svalid),.s_axis_tready(sready),.m_axis_tdata(mdata),.m_axis_tlast(mlast),.m_axis_tvalid(mvalid),.m_axis_tready(mready));
    reg [255:0] vectors [0:MAX_RECORDS+1];
    reg [63:0] expected [0:8191];reg [4:0] expflags [0:8191];
    integer wr=0,rd=0,out_phase=0,cycles=0,delivered_total=0,epoch_a=0,epoch_flags=0,native_pending=0;
    integer checks=0;
    reg hold_m=0,hold_b=0,hold_r=0;reg [64:0] prev_m;reg [1:0] prev_b;reg [33:0] prev_r;
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        mready=(ready_mode==1) || (ready_mode==2 && (rng[2:0]!=0));
    end
    always @(posedge clk) begin
        cycles=cycles+1;if(cycles>500000) $fatal(1,"AXI_TIMEOUT");
        if(!rstn || !dut.data_rstn) begin
            wr=0;rd=0;out_phase=0;epoch_a=0;epoch_flags=0;native_pending=0;hold_m=0;
        end else begin
            if(hold_m && (!mvalid || {mlast,mdata}!==prev_m)) $fatal(1,"AXI_STREAM_STALL");
            if(!mvalid && (mdata!==0 || mlast!==0)) $fatal(1,"AXI_IDLE_MASK");
            hold_m=mvalid && !mready;prev_m={mlast,mdata};
            if(svalid && sready && !dut.partial) epoch_a=epoch_a+1;
            if(dut.request_valid) native_pending=native_pending+1;
            if(dut.core_valid) native_pending=native_pending-1;
            if(mvalid && mready) begin
                if(rd>=wr) $fatal(1,"AXI_GHOST");
                if(mlast!==out_phase[0]) $fatal(1,"AXI_TLAST");
                if(!out_phase && mdata!==expected[rd]) $fatal(1,"AXI_RESULT idx=%0d actual=%h expected=%h",rd,mdata,expected[rd]);
                if(out_phase && mdata!=={59'd0,expflags[rd]}) $fatal(1,"AXI_FLAGS");
                if(out_phase) begin rd=rd+1;delivered_total=delivered_total+1;epoch_flags=epoch_flags+1;end
                out_phase=1-out_phase;
            end
        end
        if(rstn) begin
            if(hold_b && (!bvalid || bresp!==prev_b)) $fatal(1,"AXI_B_STALL");
            if(hold_r && (!rvalid || {rresp,rdata}!==prev_r)) $fatal(1,"AXI_R_STALL");
            hold_b=bvalid && !bready;prev_b=bresp;hold_r=rvalid && !rready;prev_r={rresp,rdata};
        end else begin hold_b=0;hold_r=0;end
        #1;
        if(rstn && dut.data_rstn) begin
            if(dut.reserved!==epoch_a-epoch_flags) $fatal(1,"AXI_RESERVATION actual=%0d model=%0d",dut.reserved,epoch_a-epoch_flags);
            if(dut.requests.count+dut.results.count+native_pending+int'(dut.partial)!=dut.reserved)
                $fatal(1,"AXI_STAGE_CONSERVATION req=%0d result=%0d native=%0d partial=%0d reserved=%0d",dut.requests.count,dut.results.count,native_pending,dut.partial,dut.reserved);
        end
    end
    task automatic require(input bit ok,input string message);
        begin if(!ok) $fatal(1,"AXI_CHECK %s",message);checks=checks+1;end
    endtask
    task automatic drive_aw(input [7:0] addr,input integer delay_cycles);
        begin
            repeat(delay_cycles) @(negedge clk);
            @(negedge clk);awaddr=addr;awvalid=1;
            do @(posedge clk);while(!awready);
            @(negedge clk);awvalid=0;
        end
    endtask
    task automatic drive_w(input [31:0] data,input [3:0] strobe,input integer delay_cycles);
        begin
            repeat(delay_cycles) @(negedge clk);
            @(negedge clk);wdata=data;wstrb=strobe;wvalid=1;
            do @(posedge clk);while(!wready);
            @(negedge clk);wvalid=0;
        end
    endtask
    task automatic write_reg(input [7:0] addr,input [31:0] data,input [3:0] strobe,input integer skew,input integer stall,input [1:0] response);
        begin
            fork drive_aw(addr,skew<0 ? -skew:0);drive_w(data,strobe,skew>0 ? skew:0);join
            while(bvalid!==1) @(negedge clk);
            require(bresp===response,"write response");repeat(stall) @(negedge clk);
            bready=1;@(posedge clk);@(negedge clk);bready=0;
        end
    endtask
    task automatic read_reg(input [7:0] addr,input [31:0] value,input [1:0] response,input integer stall);
        begin
            @(negedge clk);araddr=addr;arvalid=1;
            do @(posedge clk);while(!arready);
            @(negedge clk);arvalid=0;
            while(rvalid!==1) @(negedge clk);
            require(rresp===response && rdata===value,"read value/response");
            repeat(stall) @(negedge clk);rready=1;@(posedge clk);@(negedge clk);rready=0;
        end
    endtask
    task automatic beat(input [63:0] data,input bit last);
        begin
            @(negedge clk);sdata=data;slast=last;svalid=1;
            do @(posedge clk);while(!sready);
            @(negedge clk);svalid=0;slast=0;sdata=0;
        end
    endtask
    task automatic full_rate_burst(input integer transactions);
        integer k;time previous;
        begin
            previous=0;@(negedge clk);
            for(k=0;k<2*transactions;k=k+1) begin
                svalid=1;sdata=64'h3ff0000000000000;slast=k%2;
                if(k%2==0) queue_result(64'h4000000000000000,0);
                do @(posedge clk);while(!sready);
                if(k>0) require($time-previous==10,"one stream beat per cycle");
                previous=$time;@(negedge clk);
            end
            svalid=0;slast=0;sdata=0;
        end
    endtask
    task automatic queue_result(input [63:0] result,input [4:0] flags);
        begin expected[wr]=result;expflags[wr]=flags;wr=wr+1;end
    endtask
    task automatic drain;
        integer k;
        begin
            ready_mode=1;k=0;
            while(rd!=wr || dut.reserved!=0) begin @(negedge clk);k=k+1;if(k>5000) $fatal(1,"AXI_DRAIN");end
            repeat(70) @(negedge clk);require(!mvalid && dut.reserved==0,"drain and ghost guard");
        end
    endtask
    task automatic consume_result_only;
        begin
            while(!mvalid) @(negedge clk);
            require(!mlast,"expected result phase");
            @(posedge clk);#2;ready_mode=1;
            @(posedge clk);#2;ready_mode=0;
            repeat(2) @(negedge clk);require(mvalid && mlast,"held flags");
        end
    endtask
    task automatic reset_epoch;
        begin
            @(negedge clk);rstn=0;ready_mode=0;
            repeat(4) @(negedge clk);rstn=1;
            repeat(70) @(negedge clk);
            require(!mvalid && dut.reserved==0 && !dut.enabled,"reset flush");
            read_reg(8'h14,0,0,0);read_reg(8'h20,0,0,0);read_reg(8'h08,0,0,0);read_reg(8'h24,65536,0,0);
        end
    endtask
    task automatic enable_add;
        begin write_reg(8'h08,0,15,0,0,0);write_reg(8'h0c,0,15,0,0,0);write_reg(8'h10,0,15,0,0,0);write_reg(0,1,15,0,0,0);end
    endtask
    task automatic abort_epoch;
        begin write_reg(0,2,15,0,5,0);repeat(70) @(negedge clk);require(!mvalid && dut.reserved==0 && !dut.enabled,"abort flush");end
    endtask
    integer i,count,fd;reg [255:0] row;
    initial begin
        fd=$fopen(VECTOR_FILE,"r");if(!fd) $fatal(1,"AXI_VECTOR_OPEN");$fclose(fd);$readmemh(VECTOR_FILE,vectors);
        if(vectors[0]!==256'hf7540001 || (^vectors[1])===1'bx || vectors[1]==0 || vectors[1]>MAX_RECORDS) $fatal(1,"AXI_VECTOR_HEADER");
        count=vectors[1];repeat(5) @(negedge clk);rstn=1;repeat(3) @(negedge clk);
        read_reg(8'h1c,2,0,7);read_reg(8'h28,64,0,0);read_reg(8'h2c,56,0,0);read_reg(8'h24,65536,0,0);
        // AW-first, W-first, simultaneous; held responses and independent AR.
        write_reg(8'h08,2,15,4,8,0);write_reg(8'h08,1,15,-4,0,0);write_reg(8'h08,0,15,0,0,0);
        fork write_reg(8'h10,3,15,0,12,0);read_reg(8'h1c,2,0,10);join
        write_reg(8'h08,32'h100,2,0,0,2);read_reg(8'h08,0,0,0);
        write_reg(8'h08,32'hffffffff,0,0,0,0);read_reg(8'h08,0,0,0);
        write_reg(8'h10,5,15,0,0,2);read_reg(8'h10,3,0,0);
        write_reg(8'h24,0,15,0,0,2);write_reg(8'h1c,0,0,0,0,2);
        write_reg(8'h01,1,15,0,0,2);read_reg(8'h80,0,2,4);
        read_reg(8'h20,1,0,0);write_reg(8'h20,1,1,0,0,0);read_reg(8'h20,0,0,0);
        // Invalid tuple blocks A but can be repaired without abort.
        write_reg(8'h08,5,15,0,0,0);write_reg(8'h0c,5,15,0,0,0);write_reg(0,1,15,0,0,0);
        @(negedge clk);svalid=1;sdata=0;repeat(4) @(negedge clk);require(!sready,"invalid tuple admission");svalid=0;
        read_reg(8'h20,1,0,0);enable_add();write_reg(8'h20,1,15,0,0,0);
        // Snapshot at external A, B can complete after disable/reconfigure.
        queue_result(64'h4008000000000000,0);beat(64'h3ff0000000000000,0);
        write_reg(0,0,15,0,0,0);write_reg(8'h08,1,15,0,0,0);write_reg(8'h10,2,15,0,0,0);
        beat(64'h4000000000000000,1);drain();require(!sready,"disabled A");
        enable_add();ready_mode=0;
        // A concurrent config commit observes the old tuple at A acceptance.
        enable_add();queue_result(64'h4008000000000000,0);
        fork
            write_reg(8'h08,1,15,0,3,0);
            begin wait(dut.write_commit && dut.aw_address==8'h08);beat(64'h3ff0000000000000,0);end
        join
        beat(64'h4000000000000000,1);drain();enable_add();ready_mode=0;
        // Fill63 complete reservations, then reserve the last slot with A.
        for(i=0;i<63;i=i+1) begin queue_result(64'h4000000000000000,0);beat(64'h3ff0000000000000,0);beat(64'h3ff0000000000000,1);end
        queue_result(64'h4000000000000000,0);beat(64'h3ff0000000000000,0);
        require(dut.reserved==64 && sready,"pending B with last credit");beat(64'h3ff0000000000000,1);
        repeat(180) @(negedge clk);require(!sready && dut.reserved==64 && dut.results.count==64,"full stall safe");drain();
        // Full-rate static configuration: no avoidable gap between stream beats.
        enable_add();ready_mode=1;full_rate_burst(256);drain();
        // Real oracle vectors through all six lanes and all legal modes.
        ready_mode=2;
        for(i=0;i<count;i=i+1) begin
            row=vectors[i+2];
            write_reg(8'h08,{24'd0,row[239:232]},15,(i%3)-1,0,0);
            write_reg(8'h0c,{24'd0,row[231:224]},15,0,0,0);
            write_reg(8'h10,{24'd0,row[223:216]},15,0,0,0);
            queue_result(row[87:24],row[20:16]);beat(row[215:152],0);
            repeat(i%7) @(negedge clk);beat(row[151:88],1);
        end
        drain();
        // Sticky flags become visible only after the flags beat is delivered.
        write_reg(8'h14,31,15,0,0,0);read_reg(8'h14,0,0,0);
        write_reg(8'h08,4,15,0,0,0);write_reg(8'h10,0,15,0,0,0);ready_mode=0;
        queue_result(64'h7ff8000000000000,16);beat(64'hbff0000000000000,0);beat(0,1);
        consume_result_only();read_reg(8'h14,0,0,0);drain();read_reg(8'h14,16,0,0);read_reg(8'h18,16,0,0);
        write_reg(8'h14,16,0,0,0,0);read_reg(8'h14,16,0,0);write_reg(8'h14,16,1,0,0,0);read_reg(8'h14,0,0,0);read_reg(8'h18,16,0,0);
        ready_mode=0;queue_result(64'h7ff8000000000000,16);beat(64'hbff0000000000000,0);beat(0,1);consume_result_only();
        fork
            write_reg(8'h14,16,1,0,5,0);
            begin wait(dut.write_commit && dut.aw_address==8'h14);#2;ready_mode=1;@(posedge clk);#2;ready_mode=0;end
        join
        read_reg(8'h14,16,0,0);drain();
        // Framing failures cancel the entire epoch, never fabricate completion.
        enable_add();ready_mode=0;beat(0,1);repeat(3) @(negedge clk);
        require(dut.halted && !sready && dut.reserved==0,"early TLAST halt");read_reg(8'h20,2,0,0);abort_epoch();
        write_reg(8'h20,7,15,0,0,0);enable_add();beat(0,0);beat(0,0);
        require(dut.halted && dut.reserved==0,"missing TLAST halt");abort_epoch();write_reg(8'h20,7,15,0,0,0);
        // Abort preserves configuration, sticky flags and error diagnostics.
        read_reg(8'h14,16,0,0);read_reg(8'h08,0,0,0);
        // Watchdog at limit, B handshake at boundary wins over timeout.
        enable_add();write_reg(8'h24,4,15,0,0,0);beat(0,0);
        repeat(5) @(negedge clk);require(dut.halted && dut.errors[2],"watchdog halt");abort_epoch();write_reg(8'h20,7,15,0,0,0);
        enable_add();queue_result(0,0);beat(0,0);
        while(dut.watchdog_count<3) @(negedge clk);
        sdata=0;slast=1;svalid=1;@(posedge clk);@(negedge clk);svalid=0;slast=0;
        require(!dut.halted && dut.errors==0,"boundary B wins");drain();write_reg(8'h24,65536,15,0,0,0);
        // Complete packets are never timed out solely by downstream stall.
        write_reg(8'h24,4,15,0,0,0);ready_mode=0;queue_result(0,0);beat(0,0);beat(0,1);
        repeat(150) @(negedge clk);require(!dut.halted && dut.reserved==1,"no output-stall watchdog");drain();write_reg(8'h24,65536,15,0,0,0);
        // Abort partial, native in-flight, result held, and flags held.
        enable_add();beat(0,0);abort_epoch();enable_add();
        queue_result(0,0);beat(0,0);beat(0,1);abort_epoch();enable_add();ready_mode=0;
        queue_result(0,0);beat(0,0);beat(0,1);repeat(80) @(negedge clk);require(mvalid && !mlast,"held result");abort_epoch();
        enable_add();queue_result(0,0);beat(0,0);beat(0,1);while(!mvalid) @(negedge clk);
        consume_result_only();abort_epoch();
        // Reset at partial, in-flight, result and flags boundaries cancels epochs.
        enable_add();beat(0,0);reset_epoch();
        enable_add();queue_result(0,0);beat(0,0);beat(0,1);reset_epoch();
        enable_add();ready_mode=0;queue_result(0,0);beat(0,0);beat(0,1);while(!mvalid) @(negedge clk);reset_epoch();
        enable_add();queue_result(0,0);beat(0,0);beat(0,1);consume_result_only();reset_epoch();
        // Outstanding address or responses also reset cleanly.
        drive_aw(8'h08,0);require(dut.aw_held,"AW buffered independently");reset_epoch();
        drive_w(1,15,0);require(dut.w_held,"W buffered independently");reset_epoch();
        fork drive_aw(8'h08,0);drive_w(1,15,0);join
        while(!bvalid) @(negedge clk);reset_epoch();
        @(negedge clk);araddr=8'h1c;arvalid=1;@(posedge clk);@(negedge clk);arvalid=0;
        require(rvalid,"R response pending");reset_epoch();
        enable_add();queue_result(64'h4000000000000000,0);beat(64'h3ff0000000000000,0);beat(64'h3ff0000000000000,1);drain();
        $display("AXI_SUMMARY,%0d,%0d,0",delivered_total,checks);$finish;
    end
endmodule
