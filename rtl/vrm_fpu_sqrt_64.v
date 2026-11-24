// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_sqrt_64
// DESCRIPTION:
//   IEEE 754 binary64 square root (lane D), correctly rounded in the
//   requested rounding mode with per-transaction exception flags.
//
// Features:
//   - Fully pipelined restoring square root: 56 steps unrolled in space plus
//     an input register.
//   - Subnormal inputs are normalized before the exponent parity and the
//     radicand scaling are decided.
//   - sqrt(-0) = -0, sqrt(+Inf) = +Inf; a negative nonzero input (including
//     -Inf) returns the canonical quiet NaN with NV.
//
// Notes:
//   - II = 1. An input sampled at clock edge n has a valid result after edge
//     n+56.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_sqrt_64 (
    input wire clk,input wire rstn,input wire valid_in,input wire [63:0] op_a,
    output wire [63:0] result_out,output wire valid_out,
    input wire [2:0] rm,output wire [4:0] fflags_out
);
    wire sign_a,za,ia,na;
    wire signed [13:0] ea;
    wire [52:0] ma;
    vrm_fpu_prenorm_64 ua(op_a,sign_a,ea,ma,za,ia,na);
    wire sp=na || sign_a || ia || za;
    wire [63:0] special=(na || (sign_a && !za)) ? 64'h7ff8000000000000 :
                           ia ? 64'h7ff0000000000000 : {sign_a,63'd0};
    wire special_nv=(na && !op_a[51]) || (sign_a && !za && !na);
    wire special_dz=1'b0;
    localparam STAGES=56;
    reg [2:0] rmp [0:STAGES];
    reg [4:0] flagsp [0:STAGES];
    reg [109:0] radicand [0:STAGES];
    reg [57:0] remainder [0:STAGES];
    reg [56:0] root [0:STAGES];
    reg signed [13:0] exponent [0:STAGES];
    reg vp [0:STAGES];
    reg spp [0:STAGES];
    reg [63:0] specials [0:STAGES];
    always @(posedge clk) begin
        if(!rstn) begin
            radicand[0]<=0;remainder[0]<=0;root[0]<=0;exponent[0]<=0;
            rmp[0]<=0;flagsp[0]<=0;vp[0]<=0;spp[0]<=0;specials[0]<=0;
        end else begin
            radicand[0]<=ea[0] ? {ma,57'd0} : {1'b0,ma,56'd0};
            remainder[0]<=0;root[0]<=0;exponent[0]<=$signed(ea) >>> 1;
            rmp[0]<=rm;flagsp[0]<={special_nv,special_dz,3'd0};vp[0]<=valid_in;spp[0]<=sp;specials[0]<=special;
        end
    end
    genvar k;
    generate for(k=0;k<STAGES;k=k+1) begin: ROOT_STEP
        wire [57:0] extended={remainder[k][55:0],radicand[k][109:108]};
        wire [57:0] trial_divisor={root[k][55:0],2'b01};
        wire [58:0] trial={1'b0,extended}-{1'b0,trial_divisor};
        wire take_bit=~trial[58];
        always @(posedge clk) begin
            if(!rstn) begin
                radicand[k+1]<=0;remainder[k+1]<=0;root[k+1]<=0;exponent[k+1]<=0;
                rmp[k+1]<=0;flagsp[k+1]<=0;vp[k+1]<=0;spp[k+1]<=0;specials[k+1]<=0;
            end else begin
                radicand[k+1]<={radicand[k][107:0],2'b00};
                remainder[k+1]<=take_bit ? trial[57:0] : extended;
                root[k+1]<={root[k][55:0],take_bit};exponent[k+1]<=exponent[k];
                rmp[k+1]<=rmp[k];flagsp[k+1]<=flagsp[k];vp[k+1]<=vp[k];spp[k+1]<=spp[k];specials[k+1]<=specials[k];
            end
        end
    end endgenerate
    wire [55:0] normalized={root[STAGES][55:1],root[STAGES][0] | (remainder[STAGES]!=58'd0)};
    wire [63:0] packed_result;
    wire [4:0] rounded_flags;
    vrm_fpu_round_64 packer(1'b0,exponent[STAGES],normalized,rmp[STAGES],packed_result,rounded_flags);
    assign valid_out=vp[STAGES];
    assign fflags_out=spp[STAGES] ? flagsp[STAGES] : rounded_flags;
    assign result_out=spp[STAGES] ? specials[STAGES] : packed_result;
endmodule
