// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_add_sub_64
// DESCRIPTION:
//   IEEE 754 binary64 addition and subtraction (lane A). The exact sum is
//   rounded once to binary64 in the requested rounding mode, and the
//   exception flags of the transaction are returned with the result.
//
// Features:
//   - is_sub selects A - B; subtraction is addition with the sign of B
//     inverted, so NaN classification is unchanged.
//   - Rounding modes (rm): 0 RNE, 1 RTZ, 2 RDN, 3 RUP, 4 RMM.
//   - fflags_out = {NV, DZ, OF, UF, NX}; an invalid operation returns the
//     canonical quiet NaN 7ff8000000000000.
//   - Subnormal inputs and results are supported (no flush to zero).
//   - An exact zero from operands of opposite effective sign is -0 in RDN
//     and +0 in every other mode.
//
// Notes:
//   - Three registered stages, one new input per clock (II = 1). An input
//     sampled at clock edge n has a valid result after edge n+2, including
//     the special-case paths.
//   - rm values 5..7 are outside the interface contract; the dispatcher
//     never forwards them.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_add_sub_64 (
    input wire clk, input wire rstn, input wire valid_in, input wire is_sub,
    input wire [63:0] op_a, input wire [63:0] op_b,
    output reg [63:0] result_out, output reg valid_out,
    input wire [2:0] rm,output reg [4:0] fflags_out
);
    wire sa,sb,za,zb,ia,ib,na,nb;
    wire signed [13:0] ea,eb;
    wire [52:0] ma,mb;
    vrm_fpu_prenorm_64 ua(op_a,sa,ea,ma,za,ia,na);
    vrm_fpu_prenorm_64 ub(op_b,sb,eb,mb,zb,ib,nb);
    wire bs=sb ^ is_sub;
    wire special_nv=(na && !op_a[51]) || (nb && !op_b[51]) || (ia && ib && sa!=bs);
    wire large_a=($signed(ea)>$signed(eb)) || ((ea==eb) && ma>=mb);
    wire [55:0] large_m={large_a ? ma : mb,3'b000};
    wire [55:0] small_m={large_a ? mb : ma,3'b000};
    wire signed [13:0] common_e=large_a ? ea : eb;
    wire signed [13:0] difference=large_a ? ($signed(ea)-$signed(eb)) : ($signed(eb)-$signed(ea));
    reg [55:0] aligned;
    reg jam;
    integer k;
    always @* begin
        jam=1'b0;
        for(k=0;k<56;k=k+1)
            if($signed({1'b0,k[12:0]})<$signed(difference)) jam=jam | small_m[k];
        aligned=($signed(difference)>=14'sd56) ? 56'd0 : (small_m >> difference);
        aligned[0]=aligned[0] | jam;
    end
    reg sp;
    reg [63:0] special;
    always @* begin
        sp=1'b1; special=64'd0;
        if(na || nb || (ia && ib && sa!=bs)) special=64'h7ff8000000000000;
        else if(ia || ib) special={ia ? sa : bs,11'h7ff,52'd0};
        else if(za && zb) special={(sa==bs) ? sa : (rm==3'd2),63'd0};
        else if(za) special={bs,op_b[62:0]};
        else if(zb) special=op_a;
        else sp=1'b0;
    end
    reg v1,s1,subtract1,sp1;
    reg [2:0] rm1,rm2;
    reg [4:0] flags1,flags2;
    reg signed [13:0] e1;
    reg [55:0] l1,r1;
    reg [63:0] special1;
    reg [56:0] arithmetic;
    reg [55:0] normalized;
    reg signed [13:0] norm_exp;
    reg [5:0] leading;
    integer j;
    always @* begin
        arithmetic=subtract1 ? ({1'b0,l1}-{1'b0,r1}) : ({1'b0,l1}+{1'b0,r1});
        normalized=arithmetic[55:0]; norm_exp=$signed(e1); leading=6'd0;
        if(arithmetic[56]) begin
            normalized={arithmetic[56:2],arithmetic[1] | arithmetic[0]};
            norm_exp=$signed(e1)+14'sd1;
        end else if(arithmetic!=57'd0) begin
            for(j=0;j<56;j=j+1) if(arithmetic[j]) leading=6'd55-j[5:0];
            normalized=arithmetic[55:0] << leading;
            norm_exp=$signed(e1)-$signed({8'd0,leading});
        end
    end
    reg v2,s2,sp2;
    reg signed [13:0] e2;
    reg [55:0] m2;
    reg [63:0] special2;
    wire [63:0] packed_result;
    wire [4:0] rounded_flags;
    vrm_fpu_round_64 packer(s2,e2,m2,rm2,packed_result,rounded_flags);
    always @(posedge clk) begin
        if(!rstn) begin
            v1<=0;s1<=0;subtract1<=0;sp1<=0;e1<=0;l1<=0;r1<=0;special1<=0;
            v2<=0;s2<=0;sp2<=0;e2<=0;m2<=0;special2<=0;
            valid_out<=0;result_out<=0;fflags_out<=0;rm1<=0;rm2<=0;flags1<=0;flags2<=0;
        end else begin
            v1<=valid_in;rm1<=rm;flags1<={special_nv,4'd0}; s1<=large_a ? sa : bs; subtract1<=sa ^ bs;
            e1<=common_e;l1<=large_m;r1<=aligned;sp1<=sp;special1<=special;
            v2<=v1;rm2<=rm1;flags2<=flags1;s2<=(arithmetic==57'd0) ? (rm1==3'd2) : s1;
            e2<=norm_exp;m2<=normalized;sp2<=sp1;special2<=special1;
            valid_out<=v2;result_out<=sp2 ? special2 : packed_result;
            fflags_out<=sp2 ? flags2 : rounded_flags;
        end
    end
endmodule
