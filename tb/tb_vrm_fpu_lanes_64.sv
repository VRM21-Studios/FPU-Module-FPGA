// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_lanes_64
// Description:
//   Lane test for vrm_fpu_conv_64, vrm_fpu_misc_64 or vrm_fpu_mul_64,
//   selected by KIND. Streams every record of the matching vector file, one
//   per clock with a bubble every 17 records. Expected values come from
//   Berkeley SoftFloat 3e (tininess after rounding) plus explicit reference
//   rules for RISC-V min/max/class semantics.
//   Checks: result and flags bit-exact, exact lane latency (CONV 1, MISC 0,
//   MUL 5 clock edges), opcode/rm matching the selected lane, no unknown
//   valid, no ghost or lost result.
// Parameters:
//   KIND                  0 CONV (tb/mem/conv.mem), 1 MISC (tb/mem/misc.mem),
//                         2 MUL (tb/mem/mul.mem)
//   VECTOR_FILE           vector file for the selected KIND
//   MAX_RECORDS           must be >= the record count of VECTOR_FILE
//   CORRUPT_ACTUAL_FLAGS  1 flips a flag bit (negative control); keep 0
// Result:
//   PASS: "QUAL_SUMMARY,<records>,0" then $finish.
//   FAIL: $fatal with a QUAL_* message.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_lanes_64;
    parameter integer KIND=0;
    parameter VECTOR_FILE="tb/mem/conv.mem";
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
    generate
        if(KIND==0) begin: CONV
            wire [1:0] mode={op==6,subop[0]};
            vrm_fpu_conv_64 dut(clk,rstn,vin,mode,a,result,valid,rm,flags);
        end else if(KIND==1) begin: MISC
            vrm_fpu_misc_64 dut(clk,rstn,vin,subop[2:0],a,b,result,valid,rm,flags);
        end else begin: MULTIPLY
            vrm_fpu_mul_64 dut(clk,rstn,vin,a,b,result,valid,rm,flags);
        end
    endgenerate
    localparam integer LATENCY=(KIND==0) ? 1 : (KIND==1) ? 0 : 5;
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
            if((KIND==0 && (op!=5 && op!=6 || subop>1)) || (KIND==1 && (op!=7 || subop>5)) || (KIND==2 && op!=2))
                $fatal(1,"QUAL_SELECTOR");
            if(KIND!=1 && rm>4) $fatal(1,"QUAL_RM");
            a=vectors[i+2][215:152];b=vectors[i+2][151:88];
            expected[write_count]=vectors[i+2][87:24];expected_flags[write_count]=vectors[i+2][20:16];
            issued[write_count]=cycles+1;write_count=write_count+1;vin=1;
        end
        @(negedge clk);vin=0;
        repeat(16) @(negedge clk);
        if(read_count!=count) $fatal(1,"QUAL_LOSS");
        $display("QUAL_SUMMARY,%0d,%0d",read_count,errors);
        if(errors) $fatal(1,"QUAL_RESULT_OR_FLAGS");
        $finish;
    end
endmodule
