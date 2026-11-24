// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_div_64
// DESCRIPTION:
//   IEEE 754 binary64 division (lane C), correctly rounded in the requested
//   rounding mode with per-transaction exception flags.
//
// Features:
//   - Fully pipelined restoring division: 56 quotient iterations unrolled in
//     space plus an input register. No variable "/" operator is used.
//   - Subnormal operands are normalized before division; the signed
//     exponent is kept through the range checks, so subnormal results are
//     rounded once (no double rounding).
//   - 0/0 and Inf/Inf return the canonical quiet NaN with NV; a finite
//     nonzero divided by zero returns a signed infinity with DZ.
//
// Notes:
//   - II = 1. An input sampled at clock edge n has a valid result after edge
//     n+56.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_div_64 (
    input wire clk,input wire rstn,input wire valid_in,
    input wire [63:0] op_a,input wire [63:0] op_b,
    output wire [63:0] result_out,output wire valid_out,
    input wire [2:0] rm,output wire [4:0] fflags_out
);
    wire sa,sb,za,zb,ia,ib,na,nb;
    wire signed [13:0] ea,eb;
    wire [52:0] ma,mb;
    vrm_fpu_prenorm_64 ua(op_a,sa,ea,ma,za,ia,na);
    vrm_fpu_prenorm_64 ub(op_b,sb,eb,mb,zb,ib,nb);
    wire sp=na || nb || ia || ib || za || zb;
    wire invalid=na || nb || (ia && ib) || (za && zb);
    wire [63:0] special=invalid ? 64'h7ff8000000000000 :
                              (ia || zb) ? {sa^sb,11'h7ff,52'd0} : {sa^sb,63'd0};
    wire special_nv=(na && !op_a[51]) || (nb && !op_b[51]) || (ia && ib) || (za && zb);
    wire special_dz=zb && !za && !ia && !na && !nb;
    localparam STAGES=56;
    reg [2:0] rmp [0:STAGES];
    reg [4:0] flagsp [0:STAGES];
    reg [53:0] remainder [0:STAGES];
    reg [55:0] quotient [0:STAGES];
    reg [52:0] divisor [0:STAGES];
    reg signed [13:0] exponent [0:STAGES];
    reg signp [0:STAGES];
    reg vp [0:STAGES];
    reg spp [0:STAGES];
    reg [63:0] specials [0:STAGES];
    always @(posedge clk) begin
        if(!rstn) begin
            remainder[0]<=0;quotient[0]<=0;divisor[0]<=0;exponent[0]<=0;
            rmp[0]<=0;flagsp[0]<=0;signp[0]<=0;vp[0]<=0;spp[0]<=0;specials[0]<=0;
        end else begin
            remainder[0]<={1'b0,ma};quotient[0]<=0;divisor[0]<=mb;
            exponent[0]<=$signed(ea)-$signed(eb);signp[0]<=sa^sb;
            rmp[0]<=rm;flagsp[0]<={special_nv,special_dz,3'd0};vp[0]<=valid_in;spp[0]<=sp;specials[0]<=special;
        end
    end
    genvar k;
    generate for(k=0;k<STAGES;k=k+1) begin: DIV_STEP
        wire [54:0] trial={1'b0,remainder[k]}-{2'b00,divisor[k]};
        wire take_bit=~trial[54];
        always @(posedge clk) begin
            if(!rstn) begin
                remainder[k+1]<=0;quotient[k+1]<=0;divisor[k+1]<=0;exponent[k+1]<=0;
                signp[k+1]<=0;rmp[k+1]<=0;flagsp[k+1]<=0;vp[k+1]<=0;spp[k+1]<=0;specials[k+1]<=0;
            end else begin
                remainder[k+1]<=take_bit ? {trial[52:0],1'b0} : {remainder[k][52:0],1'b0};
                quotient[k+1]<={quotient[k][54:0],take_bit};divisor[k+1]<=divisor[k];
                exponent[k+1]<=exponent[k];signp[k+1]<=signp[k];rmp[k+1]<=rmp[k];flagsp[k+1]<=flagsp[k];vp[k+1]<=vp[k];
                spp[k+1]<=spp[k];specials[k+1]<=specials[k];
            end
        end
    end endgenerate
    wire high=quotient[STAGES][55];
    wire signed [13:0] final_exp=$signed(exponent[STAGES])-(high ? 14'sd0 : 14'sd1);
    wire sticky=(remainder[STAGES]!=54'd0);
    wire [55:0] normalized=high ?
        {quotient[STAGES][55:1],quotient[STAGES][0] | sticky} :
        {quotient[STAGES][54:0],sticky};
    wire [63:0] packed_result;
    wire [4:0] rounded_flags;
    vrm_fpu_round_64 packer(signp[STAGES],final_exp,normalized,rmp[STAGES],packed_result,rounded_flags);
    assign valid_out=vp[STAGES];
    assign fflags_out=spp[STAGES] ? flagsp[STAGES] : rounded_flags;
    assign result_out=spp[STAGES] ? specials[STAGES] : packed_result;
endmodule
