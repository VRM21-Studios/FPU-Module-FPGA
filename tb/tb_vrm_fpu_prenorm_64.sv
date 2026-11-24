// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_prenorm_64
// Description:
//   Exhaustive check of vrm_fpu_prenorm_64 over every subnormal with a
//   single set fraction bit (52 per sign) and every normal exponent with an
//   all-ones fraction (2046 per sign), plus zero, infinity and NaN. Expected
//   values are computed in the testbench.
//   Checks: normalized mantissa, signed exponent, sign and class flags.
// Parameters:
//   None.
// Result:
//   PASS: "PRENORM_PASS finite=4196 specials=3" then $finish.
//   FAIL: $fatal with a PRENORM_* message.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_prenorm_64;
    reg [63:0] data=0;
    wire sign,z,inf,nan;
    wire signed [13:0] exponent;
    wire [52:0] mantissa;
    integer j,s,count=0;
    vrm_fpu_prenorm_64 dut(data,sign,exponent,mantissa,z,inf,nan);
    initial begin
        for(s=0;s<2;s=s+1) begin
            for(j=0;j<52;j=j+1) begin
                data=(64'd1<<j) | (s ? 64'h8000000000000000 : 64'd0);#1;
                if(mantissa!==53'h10000000000000 || $signed(exponent)!==(-1074+j) || sign!==s[0] || z || inf || nan)
                    $fatal(1,"PRENORM_SUBNORMAL bit=%0d",j);
                count=count+1;
            end
            for(j=1;j<2047;j=j+1) begin
                data={s[0],j[10:0],52'hfffffffffffff};#1;
                if(mantissa!==53'h1fffffffffffff || $signed(exponent)!==(j-1023) || sign!==s[0] || z || inf || nan)
                    $fatal(1,"PRENORM_NORMAL exp=%0d",j);
                count=count+1;
            end
        end
        data=64'd0;#1;if(!z || inf || nan || mantissa!==53'd0) $fatal(1,"PRENORM_ZERO");
        data=64'h7ff0000000000000;#1;if(z || !inf || nan) $fatal(1,"PRENORM_INFINITY");
        data=64'h7ff0000000000001;#1;if(z || inf || !nan) $fatal(1,"PRENORM_NAN");
        $display("PRENORM_PASS finite=%0d specials=3",count);$finish;
    end
    initial begin #100000;$fatal(1,"PRENORM_TIMEOUT");end
endmodule
