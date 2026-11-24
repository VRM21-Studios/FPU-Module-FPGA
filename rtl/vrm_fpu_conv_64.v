// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_conv_64
// DESCRIPTION:
//   Conversion between 32-bit integers and IEEE 754 binary64 (lane E).
//   conv_op: 0 int32 to binary64, 1 uint32 to binary64, 2 binary64 to
//   int32, 3 binary64 to uint32.
//
// Features:
//   - Integer input is taken from op_a[31:0]; integer results are returned
//     in result_out[31:0] with bits [63:32] zero, for signed and unsigned.
//   - int32/uint32 to binary64 is always exact (flags zero).
//   - binary64 to integer rounds with rm first, then checks the range of
//     the rounded value. NaN, infinity or an out-of-range result raises NV
//     only (NX suppressed) and returns 7fffffff / 80000000 (int32) or
//     ffffffff / 00000000 (uint32).
//
// Notes:
//   - Two registered stages, II = 1. An input sampled at clock edge n has a
//     valid result after edge n+1.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_conv_64 (
    input wire clk,input wire rstn,input wire valid_in,
    input wire [1:0] conv_op,input wire [63:0] op_a,
    output reg [63:0] result_out,output reg valid_out,
    input wire [2:0] rm,output reg [4:0] fflags_out
);
    wire [10:0] raw_exp=op_a[62:52];
    wire [51:0] fraction=op_a[51:0];
    wire fp_sign=op_a[63];
    wire nan_value=(raw_exp==11'h7ff) && (fraction!=52'd0);
    wire int_sign=!conv_op[0] && op_a[31];
    wire [31:0] magnitude=int_sign ? (~op_a[31:0]+32'd1) : op_a[31:0];
    reg [5:0] msb;
    reg [63:0] scaled,mantissa,integer_magnitude;
    reg signed [13:0] exponent,shift_distance;
    reg [6:0] distance;
    reg guard_bit,sticky,inexact,increment,invalid;
    reg [10:0] encoded_exp;
    reg [31:0] integer_result;
    reg [63:0] converted;
    reg [4:0] flags;
    integer j;
    always @* begin
        msb=6'd0;scaled=64'd0;encoded_exp=11'd0;flags=5'd0;
        mantissa={11'd0,(raw_exp!=11'd0),fraction};
        integer_magnitude=64'd0;integer_result=32'd0;
        exponent=(raw_exp==11'd0) ? -14'sd1022 : ($signed({3'b000,raw_exp})-14'sd1023);
        shift_distance=14'sd52-$signed(exponent);
        distance=7'd0;guard_bit=1'b0;sticky=1'b0;converted=64'd0;
        inexact=1'b0;increment=1'b0;invalid=1'b0;
        if(!conv_op[1]) begin
            for(j=0;j<32;j=j+1) if(magnitude[j]) msb=j[5:0];
            scaled={32'd0,magnitude} << (6'd52-msb);
            encoded_exp=11'd1023+{5'd0,msb};
            if(magnitude!=32'd0) converted={int_sign,encoded_exp,scaled[51:0]};
        end else begin
            if($signed(exponent)<=14'sd31) begin
                // Relevant shift range is [21,1074]; don't narrow before clamp.
                if($signed(shift_distance)>14'sd64) begin
                    sticky=|mantissa;
                end else begin
                    distance=shift_distance[6:0];
                    integer_magnitude=mantissa >> distance;
                    guard_bit=mantissa[distance-7'd1];
                    for(j=0;j<64;j=j+1)
                        if({1'b0,j[5:0]}<(distance-7'd1)) sticky=sticky | mantissa[j];
                end
                inexact=guard_bit || sticky;
                case(rm)
                    3'd0: increment=guard_bit && (sticky || integer_magnitude[0]);
                    3'd1: increment=1'b0;
                    3'd2: increment=fp_sign && inexact;
                    3'd3: increment=!fp_sign && inexact;
                    3'd4: increment=guard_bit;
                    default: increment=1'b0;
                endcase
                integer_magnitude=integer_magnitude+{63'd0,increment};
            end
            if(nan_value) begin
                integer_result=conv_op[0] ? 32'hffffffff : 32'h7fffffff;invalid=1'b1;
            end else if(conv_op[0]) begin
                if(fp_sign) begin
                    integer_result=32'd0;
                    invalid=($signed(exponent)>14'sd31) || (integer_magnitude!=64'd0);
                end else if($signed(exponent)>14'sd31 || integer_magnitude>64'hffffffff) begin
                    integer_result=32'hffffffff;invalid=1'b1;
                end else integer_result=integer_magnitude[31:0];
            end else if(fp_sign) begin
                if($signed(exponent)>14'sd31 || integer_magnitude>64'h80000000) begin
                    integer_result=32'h80000000;invalid=1'b1;
                end else integer_result=~integer_magnitude[31:0]+32'd1;
            end else begin
                if($signed(exponent)>14'sd31 || integer_magnitude>64'h7fffffff) begin
                    integer_result=32'h7fffffff;invalid=1'b1;
                end else integer_result=integer_magnitude[31:0];
            end
            converted={32'd0,integer_result};
            flags=invalid ? 5'b10000 : {4'd0,inexact};
        end
    end
    reg v1;
    reg [63:0] result1;
    reg [4:0] flags1;
    always @(posedge clk) begin
        if(!rstn) begin v1<=0;result1<=0;valid_out<=0;result_out<=0;flags1<=0;fflags_out<=0;end
        else begin
            v1<=valid_in;result1<=converted;flags1<=flags;
            valid_out<=v1;result_out<=result1;fflags_out<=flags1;
        end
    end
endmodule
