// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_round_64
// Description:
//   Unit test of the combinational round/pack block vrm_fpu_round_64. Each
//   record gives sign, unbiased exponent, 56-bit significand and rm, and the
//   expected packed binary64 result and flags from Berkeley SoftFloat 3e
//   (softfloat_roundPackToF64, tininess after rounding). The set holds
//   directed exponents around overflow, the normal/subnormal boundary and
//   total underflow with significands at the rounding boundaries, in all
//   five rounding modes, plus 8192 random records.
//   Checks: packed result and flags bit-exact for every record.
// Parameters:
//   VECTOR_FILE  default tb/mem/round.mem (relative to the repository root);
//                MAX_RECORDS >= its record count.
// Result:
//   PASS: "ROUND_SUMMARY,<records>,0" then $finish
//         ("ROUND_SUMMARY,15872,0" with the default file).
//   FAIL: $fatal with a ROUND_* message.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_round_64;
    parameter VECTOR_FILE="tb/mem/round.mem";
    parameter integer MAX_RECORDS=65536;
    reg [255:0] vectors [0:MAX_RECORDS+1];
    reg sign=0;
    reg signed [13:0] exponent=0;
    reg [55:0] significand=0;
    reg [2:0] rm=0;
    wire [63:0] result;
    wire [4:0] flags;
    integer fd,count,j,errors=0;
    vrm_fpu_round_64 dut(sign,exponent,significand,rm,result,flags);
    initial begin
        fd=$fopen(VECTOR_FILE,"r");if(!fd) $fatal(1,"ROUND_VECTOR_OPEN");$fclose(fd);
        vectors[0]=0;vectors[1]=0;$readmemh(VECTOR_FILE,vectors);
        if(vectors[0]!==256'hf7540001 || vectors[1]==0 || vectors[1]>MAX_RECORDS || (^vectors[1])===1'bx)
            $fatal(1,"ROUND_HEADER");
        count=vectors[1];
        for(j=0;j<count;j=j+1) begin
            if((^vectors[j+2])===1'bx) $fatal(1,"ROUND_VECTOR_UNKNOWN");
            sign=vectors[j+2][215];exponent=vectors[j+2][165:152];
            significand=vectors[j+2][143:88];rm=vectors[j+2][218:216];
            #1;
            if(result!==vectors[j+2][87:24] || flags!==vectors[j+2][20:16]) begin
                errors=errors+1;
                $display("ROUND_MISMATCH,%0d,%016h,%016h,%02h,%02h",j,result,vectors[j+2][87:24],flags,vectors[j+2][20:16]);
            end
        end
        $display("ROUND_SUMMARY,%0d,%0d",count,errors);
        if(errors) $fatal(1,"ROUND_CHECK_FAIL");
        $finish;
    end
    initial begin #1000000;$fatal(1,"ROUND_TIMEOUT");end
endmodule
