// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_lane_stream
// Description:
//   All six lanes instantiated side by side, each fed by the records of its
//   own opcode from one mixed vector file, issued back to back with a bubble
//   every 7 records. An independent scoreboard per lane allows results of
//   different lanes to complete in the same cycle. Expected values come from
//   Berkeley SoftFloat 3e (tininess after rounding) plus explicit reference
//   rules for RISC-V min/max/class semantics.
//   Checks: result and flags bit-exact, exact latency per lane, no unknown
//   result/flags/valid, no ghost or lost result, full drain.
//   This test covers the lanes; dispatcher ordering is covered by
//   tb_vrm_fpu_native_64.
// Parameters:
//   VECTOR_FILE  default tb/mem/lanes-0.mem (relative to the repository
//                root); MAX_RECORDS >= its record count.
// Result:
//   PASS: "STREAM_SUMMARY,<records>,0" then $finish.
//   FAIL: $fatal with a STREAM_* message.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_lane_stream;
    parameter VECTOR_FILE="tb/mem/lanes-0.mem";
    parameter integer MAX_RECORDS=65536;
    parameter integer GLOBAL_CYCLE_LIMIT=1000000;
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0,vin=0;
    reg [7:0] op=0,subop=0;
    reg [2:0] rm=0;
    reg [63:0] a=0,b=0;
    wire [63:0] res [0:5];
    wire [5:0] valid;
    wire [4:0] flags [0:5];
    vrm_fpu_add_sub_64 la(clk,rstn,vin && op<2,op[0],a,b,res[0],valid[0],rm,flags[0]);
    vrm_fpu_mul_64 lb(clk,rstn,vin && op==2,a,b,res[1],valid[1],rm,flags[1]);
    vrm_fpu_div_64 lc(clk,rstn,vin && op==3,a,b,res[2],valid[2],rm,flags[2]);
    vrm_fpu_sqrt_64 ld(clk,rstn,vin && op==4,a,res[3],valid[3],rm,flags[3]);
    wire [1:0] cm={op==6,subop[0]};
    vrm_fpu_conv_64 le(clk,rstn,vin && (op==5 || op==6),cm,a,res[4],valid[4],rm,flags[4]);
    vrm_fpu_misc_64 lf(clk,rstn,vin && op==7,subop[2:0],a,b,res[5],valid[5],rm,flags[5]);
    reg [255:0] vectors [0:MAX_RECORDS+1];
    reg [63:0] expected [0:5][0:MAX_RECORDS-1];
    reg [4:0] expected_flags [0:5][0:MAX_RECORDS-1];
    integer record_id [0:5][0:MAX_RECORDS-1];
    integer issued_at [0:5][0:MAX_RECORDS-1];
    integer writes [0:5],reads [0:5];
    integer cycles=0,errors=0,received=0,count,fd,idx,lane,j,k;
    integer latency [0:5];
    function integer lane_for(input [7:0] code);
        case(code) 0,1:lane_for=0;2:lane_for=1;3:lane_for=2;4:lane_for=3;
                   5,6:lane_for=4;7:lane_for=5;default:lane_for=-1;endcase
    endfunction
    always @(posedge clk) begin
        #1;cycles=cycles+1;
        if(cycles>GLOBAL_CYCLE_LIMIT) $fatal(1,"STREAM_GLOBAL_TIMEOUT");
        if(rstn) begin
            if((^valid)===1'bx) $fatal(1,"STREAM_UNKNOWN_VALID");
            for(j=0;j<6;j=j+1) if(valid[j]) begin
                if(reads[j]>=writes[j]) $fatal(1,"STREAM_GHOST_OR_DUPLICATE lane=%0d",j);
                if((^flags[j])===1'bx) $fatal(1,"STREAM_UNKNOWN_FLAGS");
                if((^res[j])===1'bx) $fatal(1,"STREAM_UNKNOWN_RESULT");
                if(cycles-issued_at[j][reads[j]]!=latency[j]) $fatal(1,"STREAM_LATENCY lane=%0d",j);
                if(res[j]!==expected[j][reads[j]] || flags[j]!==expected_flags[j][reads[j]]) begin
                    errors=errors+1;
                    $display("STREAM_MISMATCH,%0d,%016h,%016h,%02h,%02h",record_id[j][reads[j]],res[j],expected[j][reads[j]],flags[j],expected_flags[j][reads[j]]);
                end
                reads[j]=reads[j]+1;received=received+1;
            end
        end
    end
    initial begin
        latency[0]=2;latency[1]=5;latency[2]=56;latency[3]=56;latency[4]=1;latency[5]=0;
        for(k=0;k<6;k=k+1) begin writes[k]=0;reads[k]=0;end
        fd=$fopen(VECTOR_FILE,"r");if(!fd) $fatal(1,"STREAM_FILE_OPEN");$fclose(fd);
        vectors[0]=0;vectors[1]=0;$readmemh(VECTOR_FILE,vectors);
        if(vectors[0]!==256'hf7540001 || vectors[1]==0 || vectors[1]>MAX_RECORDS || (^vectors[1])===1'bx)
            $fatal(1,"STREAM_CORPUS_HEADER");
        count=vectors[1];repeat(4) @(negedge clk);rstn=1;
        for(idx=0;idx<count;idx=idx+1) begin
            @(negedge clk);
            // Periodic bubbles; other cycles can issue back to back.
            if(idx%7==0) begin vin=0;@(negedge clk);end
            op=vectors[idx+2][239:232];subop=vectors[idx+2][231:224];
            if((^vectors[idx+2])===1'bx) $fatal(1,"STREAM_CORPUS_UNKNOWN");
            rm=vectors[idx+2][218:216];
            if(rm>4 && op!=7) $fatal(1,"STREAM_UNSUPPORTED_RM");
            a=vectors[idx+2][215:152];b=vectors[idx+2][151:88];lane=lane_for(op);
            if(lane<0) $fatal(1,"STREAM_OPCODE");
            expected[lane][writes[lane]]=vectors[idx+2][87:24];
            expected_flags[lane][writes[lane]]=vectors[idx+2][20:16];
            record_id[lane][writes[lane]]=vectors[idx+2][255:240];
            issued_at[lane][writes[lane]]=cycles+1;
            writes[lane]=writes[lane]+1;vin=1;
        end
        @(negedge clk);vin=0;
        repeat(128) @(negedge clk);
        if(received!=count) $fatal(1,"STREAM_LOSS count=%0d received=%0d",count,received);
        for(k=0;k<6;k=k+1) if(writes[k]!=reads[k]) $fatal(1,"STREAM_DRAIN");
        $display("STREAM_SUMMARY,%0d,%0d",received,errors);
        if(errors) $fatal(1,"STREAM_RESULT_MISMATCH");
        $finish;
    end
endmodule
