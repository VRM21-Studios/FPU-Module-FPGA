// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_native_64
// Description:
//   Streams every vector-file record into the dispatcher vrm_fpu_native_64,
//   one per clock with a bubble every 17 records, and compares the 64-bit
//   result and the 5 exception flags bit-exactly. Expected values come from
//   Berkeley SoftFloat 3e (tininess after rounding) plus explicit reference
//   rules for RISC-V min/max/class semantics.
//   Checks: result and flags, latency of exactly 56 clock edges for every
//   record, in-order delivery, no unknown valid, no ghost or lost result.
// Parameters:
//   VECTOR_FILE           default tb/mem/integration_smoke.mem (relative to
//                         the repository root)
//   MAX_RECORDS           must be >= the record count of VECTOR_FILE
//   CORRUPT_ACTUAL_FLAGS  1 flips a flag bit to prove the checker fails
//                         (negative control); keep 0 for a normal run
// Result:
//   PASS: "QUAL_SUMMARY,<records>,0" then $finish
//         ("QUAL_SUMMARY,1200,0" with the default file).
//   FAIL: $fatal with a QUAL_* message, or an FPU_ASSERT_* line from the RTL.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_native_64;

    parameter VECTOR_FILE="tb/mem/integration_smoke.mem";
    parameter integer MAX_RECORDS=60000;
    parameter integer MAX_CYCLES=200000;
    parameter integer CORRUPT_ACTUAL_FLAGS=0;
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0,vin=0;
    reg [7:0] op=0,subop=0;
    reg [2:0] rm=0;
    reg [63:0] a=0,b=0;
    wire [63:0] result;
    wire [4:0] flags;
    wire valid;
    vrm_fpu_native_64 dut(clk,rstn,vin,op[3:0],subop[2:0],rm,a,b,valid,result,flags);
    localparam integer LATENCY=56;
    reg [255:0] vectors [0:MAX_RECORDS+1];
    reg [63:0] expected [0:MAX_RECORDS-1];
    reg [4:0] expected_flags [0:MAX_RECORDS-1];
    integer issued [0:MAX_RECORDS-1];
    integer read_count=0,write_count=0,cycles=0,errors=0,count,fd,i;
    wire [4:0] observed_flags=flags ^ (CORRUPT_ACTUAL_FLAGS ? 5'd1 : 5'd0);
    always @(posedge clk) begin
        #1;cycles=cycles+1;
        if(cycles>MAX_CYCLES) $fatal(1,"QUAL_TIMEOUT");
        if(rstn) begin
            if(valid===1'bx) $fatal(1,"QUAL_UNKNOWN_VALID");
            if(valid) begin
                if(read_count>=write_count) $fatal(1,"QUAL_DUPLICATE_OR_GHOST");
                if(cycles-issued[read_count]!=LATENCY) $fatal(1,"QUAL_LATENCY");
                if(result!==expected[read_count] || observed_flags!==expected_flags[read_count]) begin
                    errors=errors+1;
                    if(errors<=8) $display("QUAL_MISMATCH,%0d,%016h,%016h,%02h,%02h",read_count,result,expected[read_count],observed_flags,expected_flags[read_count]);
                end
                read_count=read_count+1;
            end
        end
    end
    initial begin
        fd=$fopen(VECTOR_FILE,"r");if(!fd) $fatal(1,"QUAL_FILE_OPEN");$fclose(fd);
        vectors[0]=0;vectors[1]=0;$readmemh(VECTOR_FILE,vectors);
        if(vectors[0]!==256'hf7540001 || vectors[1]==0 || vectors[1]>MAX_RECORDS || (^vectors[1])===1'bx)
            $fatal(1,"QUAL_HEADER");
        count=vectors[1];repeat(4) @(negedge clk);rstn=1;
        for(i=0;i<count;i=i+1) begin
            @(negedge clk);
            if(i%17==0) begin vin=0;@(negedge clk);end
            if((^vectors[i+2])===1'bx) $fatal(1,"QUAL_VECTOR_UNKNOWN");
            op=vectors[i+2][239:232];subop=vectors[i+2][231:224];rm=vectors[i+2][218:216];
            a=vectors[i+2][215:152];b=vectors[i+2][151:88];
            expected[write_count]=vectors[i+2][87:24];expected_flags[write_count]=vectors[i+2][20:16];
            issued[write_count]=cycles+1;write_count=write_count+1;vin=1;
        end
        @(negedge clk);vin=0;
        repeat(80) @(negedge clk);
        if(read_count!=count) $fatal(1,"QUAL_LOSS");
        $display("QUAL_SUMMARY,%0d,%0d",read_count,errors);
        if(errors) $fatal(1,"QUAL_RESULT_OR_FLAGS");
        $finish;
    end
endmodule
