// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_round_64
// DESCRIPTION:
//   Combinational rounding and packing of a finite binary64 result. Input
//   is the sign, an unbiased signed exponent and a 56-bit significand
//   normalized at bit 55 whose three low bits are guard, round and sticky.
//
// Features:
//   - rm: 0 RNE, 1 RTZ, 2 RDN, 3 RUP, 4 RMM.
//   - fflags = {NV, DZ, OF, UF, NX}; this module produces OF, UF and NX. NV
//     and DZ come from the special-case logic of each operator.
//   - Overflow follows the rounding direction: to infinity or to the
//     largest finite value of the same sign.
//   - Tininess is detected after rounding: the significand is first rounded
//     to 53 bits with an unbounded exponent, and the result is tiny if it is
//     still below the smallest normal value. UF is raised only when the
//     result is both tiny and inexact.
//
// Notes:
//   - rm values 5..7 are outside the interface contract.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_round_64 (
    input wire sign,input wire signed [13:0] exponent,
    input wire [55:0] significand,input wire [2:0] rm,
    output reg [63:0] fp_out,output reg [4:0] fflags
);
    reg [55:0] shifted;
    reg [53:0] rounded;
    reg signed [13:0] exp_work,distance;
    reg [10:0] encoded_exp;
    reg discarded,increment,inexact,tiny,to_infinity;
    reg [2:0] precision_increment;
    reg [56:0] precision_sum;
    integer k;
    always @* begin
        shifted=significand;exp_work=$signed(exponent);distance=14'sd0;
        discarded=1'b0;encoded_exp=11'd0;fflags=5'd0;fp_out=64'd0;
        increment=1'b0;inexact=1'b0;tiny=1'b0;to_infinity=1'b0;
        precision_increment=3'd0;
        case(rm)
            3'd0,3'd4: precision_increment=3'd4;
            3'd2: precision_increment=sign ? 3'd7 : 3'd0;
            3'd3: precision_increment=sign ? 3'd0 : 3'd7;
            default: precision_increment=3'd0;
        endcase
        precision_sum={1'b0,significand}+{54'd0,precision_increment};
        if($signed(exponent)<-14'sd1022) begin
            tiny=($signed(exponent)<-14'sd1023) || !precision_sum[56];
            distance=-14'sd1022-$signed(exponent);
            for(k=0;k<56;k=k+1)
                if($signed({1'b0,k[12:0]})<$signed(distance)) discarded=discarded | significand[k];
            shifted=($signed(distance)>=14'sd56) ? 56'd0 : (significand >> distance);
            shifted[0]=shifted[0] | discarded;
            exp_work=-14'sd1022;
        end
        inexact=|shifted[2:0];
        case(rm)
            3'd0: increment=shifted[2] && (shifted[1] || shifted[0] || shifted[3]);
            3'd1: increment=1'b0;
            3'd2: increment=sign && inexact;
            3'd3: increment=!sign && inexact;
            3'd4: increment=shifted[2];
            default: increment=1'b0;
        endcase
        rounded={1'b0,shifted[55:3]}+{53'd0,increment};
        if(rounded[53]) begin rounded=rounded >> 1;exp_work=$signed(exp_work)+14'sd1;end
        if($signed(exp_work)>14'sd1023) begin
            fflags=5'b00101;
            to_infinity=(rm==3'd0 || rm==3'd4 || (rm==3'd2 && sign) || (rm==3'd3 && !sign));
            fp_out=to_infinity ? {sign,11'h7ff,52'd0} : {sign,11'h7fe,52'hfffffffffffff};
        end else begin
            fflags={3'b000,(tiny && inexact),inexact};
            if(rounded==54'd0) fp_out={sign,63'd0};
            else begin
                if(rounded[52]) encoded_exp=exp_work[10:0]+11'd1023;
                fp_out={sign,encoded_exp,rounded[51:0]};
            end
        end
    end
endmodule
