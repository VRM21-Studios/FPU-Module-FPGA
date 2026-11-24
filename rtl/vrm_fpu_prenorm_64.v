// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_prenorm_64
// DESCRIPTION:
//   Combinational operand normalization for the arithmetic lanes. For a
//   nonzero finite input x, |x| = mantissa * 2^(exponent - 52) with
//   mantissa[52] = 1, so subnormal inputs are left-aligned like normal ones.
//
// Features:
//   - Signed 14-bit exponent in [-1074, 1023]; the same width also covers
//     the sums and differences formed by the multiplier and divider.
//   - Zero, infinity and NaN flags for the special-case paths.
//
// Notes:
//   - A zero input returns fixed mantissa/exponent fields; callers handle
//     zero through their special-case path.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_prenorm_64 (
    input wire [63:0] fp_in,
    output wire sign,
    output reg signed [13:0] exponent,
    output reg [52:0] mantissa,
    output wire is_zero,
    output wire is_inf,
    output wire is_nan
);
    wire [10:0] raw_exp = fp_in[62:52];
    wire [51:0] fraction = fp_in[51:0];
    assign sign = fp_in[63];
    assign is_zero = (raw_exp==11'd0) && (fraction==52'd0);
    assign is_inf = (raw_exp==11'h7ff) && (fraction==52'd0);
    assign is_nan = (raw_exp==11'h7ff) && (fraction!=52'd0);
    reg [5:0] shift_count;
    integer j;
    always @* begin
        shift_count=6'd0;
        exponent=$signed({3'b000,raw_exp})-14'sd1023;
        mantissa={1'b1,fraction};
        if (raw_exp==11'd0) begin
            // A zero receives deterministic fields; special-case bypass owns it.
            exponent=-14'sd1022;
            mantissa={1'b0,fraction};
            for(j=0;j<52;j=j+1)
                if(fraction[j]) shift_count=6'd52-j[5:0];
            if(fraction!=52'd0) begin
                mantissa={1'b0,fraction} << shift_count;
                exponent=-14'sd1022-$signed({8'd0,shift_count});
            end
        end
    end
endmodule
