// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_mul_64
// DESCRIPTION:
//   IEEE 754 binary64 multiplication (lane B), correctly rounded in the
//   requested rounding mode with per-transaction exception flags.
//
// Features:
//   - The full 106-bit significand product is kept before rounding.
//   - Subnormal operands are normalized first; subnormal results use
//     gradual underflow in all five rounding modes.
//   - Zero x Inf returns the canonical quiet NaN with NV.
//
// Notes:
//   - Six registered stages, II = 1. An input sampled at clock edge n has a
//     valid result after edge n+5.
//   - NOTE: use_dsp and retiming attributes on the product registers are
//     implementation hints for Vivado; they do not change behavior.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_mul_64 (
    input wire clk,input wire rstn,input wire valid_in,
    input wire [63:0] op_a,input wire [63:0] op_b,
    output reg [63:0] result_out,output reg valid_out,
    input wire [2:0] rm,output reg [4:0] fflags_out
);
    wire sa,sb,za,zb,ia,ib,na,nb;
    wire signed [13:0] ea,eb;
    wire [52:0] ma,mb;
    vrm_fpu_prenorm_64 ua(op_a,sa,ea,ma,za,ia,na);
    vrm_fpu_prenorm_64 ub(op_b,sb,eb,mb,zb,ib,nb);
    wire sp=na || nb || ia || ib || za || zb;
    wire invalid=na || nb || (ia && zb) || (ib && za);
    wire [63:0] special=invalid ? 64'h7ff8000000000000 :
                            (ia || ib) ? {sa^sb,11'h7ff,52'd0} : {sa^sb,63'd0};
    wire special_nv=(na && !op_a[51]) || (nb && !op_b[51]) || (ia && zb) || (ib && za);
    reg [2:0] rm1,rm5;
    reg [2:0] rmp [0:2];
    reg [4:0] flags1,flags5;
    reg [4:0] flagsp [0:2];
    reg v1,s1,sp1;
    reg signed [13:0] e1;
    (* use_dsp="yes" *) reg [52:0] a1,b1;
    reg [63:0] special1;
    reg [2:0] vp,signp,spp;
    reg signed [13:0] ep [0:2];
    reg [63:0] specials [0:2];
    (* use_dsp="yes", retiming_backward=1 *) reg [105:0] product0;
    (* retiming_backward=1 *) reg [105:0] product1,product2;
    reg v5,s5,sp5;
    reg signed [13:0] e5;
    reg [55:0] m5;
    reg [63:0] special5;
    wire [55:0] normalized=product2[105] ?
        {product2[105:51],|product2[50:0]} : {product2[104:50],|product2[49:0]};
    wire [63:0] packed_result;
    wire [4:0] rounded_flags;
    vrm_fpu_round_64 packer(s5,e5,m5,rm5,packed_result,rounded_flags);
    integer k;
    always @(posedge clk) begin
        if(!rstn) begin
            rm1<=0;rm5<=0;flags1<=0;flags5<=0;fflags_out<=0;v1<=0;s1<=0;sp1<=0;e1<=0;a1<=0;b1<=0;special1<=0;
            vp<=0;signp<=0;spp<=0;product0<=0;product1<=0;product2<=0;
            for(k=0;k<3;k=k+1) begin ep[k]<=0;specials[k]<=0;rmp[k]<=0;flagsp[k]<=0;end
            v5<=0;s5<=0;sp5<=0;e5<=0;m5<=0;special5<=0;valid_out<=0;result_out<=0;
        end else begin
            rm1<=rm;flags1<={special_nv,4'd0};v1<=valid_in;s1<=sa^sb;sp1<=sp;e1<=$signed(ea)+$signed(eb);
            a1<=ma;b1<=mb;special1<=special;
            vp<={vp[1:0],v1};signp<={signp[1:0],s1};spp<={spp[1:0],sp1};
            rmp[0]<=rm1;rmp[1]<=rmp[0];rmp[2]<=rmp[1];
            flagsp[0]<=flags1;flagsp[1]<=flagsp[0];flagsp[2]<=flagsp[1];
            ep[0]<=e1;ep[1]<=ep[0];ep[2]<=ep[1];
            specials[0]<=special1;specials[1]<=specials[0];specials[2]<=specials[1];
            product0<=a1*b1;product1<=product0;product2<=product1;
            rm5<=rmp[2];flags5<=flagsp[2];v5<=vp[2];s5<=signp[2];sp5<=spp[2];special5<=specials[2];
            e5<=$signed(ep[2])+(product2[105] ? 14'sd1 : 14'sd0);m5<=normalized;
            valid_out<=v5;result_out<=sp5 ? special5 : packed_result;
            fflags_out<=sp5 ? flags5 : rounded_flags;
        end
    end
endmodule
