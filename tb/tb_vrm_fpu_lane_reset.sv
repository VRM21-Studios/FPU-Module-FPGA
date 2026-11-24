// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// Testbench: tb_vrm_fpu_lane_reset
// Description:
//   Reset test of the six lanes. For each of the five rounding modes,
//   signaling-NaN transactions are issued to every lane, reset is asserted
//   while they are in flight, and then one exact operation (1.0 op 1.0) is
//   issued. Expected values are fixed in the testbench.
//   Checks: no completion from before the reset, exactly one completion per
//   lane afterwards, with the exact result and zero flags (no flag leak).
// Parameters:
//   None.
// Result:
//   PASS: "V2_RESET_PASS modes=5 lanes=6" then $finish.
//   FAIL: $fatal with a RESET_* message.
// ============================================================================
`timescale 1ns/1ps
module tb_vrm_fpu_lane_reset;
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0,vin=0;
    reg [2:0] rm=0;
    reg [63:0] a=0,b=0;
    wire [63:0] result [0:5];
    wire [4:0] flags [0:5];
    wire [5:0] valid;
    vrm_fpu_add_sub_64 la(clk,rstn,vin,1'b0,a,b,result[0],valid[0],rm,flags[0]);
    vrm_fpu_mul_64 lb(clk,rstn,vin,a,b,result[1],valid[1],rm,flags[1]);
    vrm_fpu_div_64 lc(clk,rstn,vin,a,b,result[2],valid[2],rm,flags[2]);
    vrm_fpu_sqrt_64 ld(clk,rstn,vin,a,result[3],valid[3],rm,flags[3]);
    vrm_fpu_conv_64 le(clk,rstn,vin,2'b10,a,result[4],valid[4],rm,flags[4]);
    vrm_fpu_misc_64 lf(clk,rstn,vin,3'd0,a,b,result[5],valid[5],rm,flags[5]);
    integer phase=0,j,k,mode;
    integer count [0:5];
    reg [63:0] expected [0:5];
    always @(posedge clk) begin
        #1;
        if(rstn && phase==1 && valid!==6'd0) $fatal(1,"RESET_GHOST_COMPLETION");
        if(rstn && phase==2) begin
            if((^valid)===1'bx) $fatal(1,"RESET_UNKNOWN_VALID");
            for(j=0;j<6;j=j+1) if(valid[j]) begin
                if(result[j]!==expected[j] || flags[j]!==5'd0) $fatal(1,"RESET_RESULT_OR_FLAG_LEAK lane=%0d",j);
                count[j]=count[j]+1;
                if(count[j]>1) $fatal(1,"RESET_DUPLICATE");
            end
        end
    end
    initial begin
        expected[0]=64'h4000000000000000;
        expected[1]=64'h3ff0000000000000;expected[2]=64'h3ff0000000000000;expected[3]=64'h3ff0000000000000;
        expected[4]=64'd1;expected[5]=64'd1;
        for(mode=0;mode<5;mode=mode+1) begin
            phase=0;rstn=0;vin=0;for(k=0;k<6;k=k+1) count[k]=0;
            repeat(4) @(negedge clk);rstn=1;rm=mode[2:0];
            a=64'h7ff0000000000001;b=64'd0;vin=1;
            repeat(3) @(negedge clk);vin=0;rstn=0;
            repeat(4) @(negedge clk);rstn=1;phase=1;
            repeat(64) @(negedge clk);
            phase=2;a=64'h3ff0000000000000;b=64'h3ff0000000000000;vin=1;
            @(negedge clk);vin=0;
            repeat(128) @(negedge clk);
            for(k=0;k<6;k=k+1) if(count[k]!=1) $fatal(1,"RESET_MISSING_COMPLETION lane=%0d",k);
        end
        $display("V2_RESET_PASS modes=5 lanes=6");$finish;
    end
    initial begin #50000;$fatal(1,"RESET_TIMEOUT");end
endmodule
