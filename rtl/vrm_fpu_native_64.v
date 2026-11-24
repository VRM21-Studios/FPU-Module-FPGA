// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_native_64
// DESCRIPTION:
//   Dispatcher for the six binary64 lanes: A add/sub, B mul, C div, D sqrt,
//   E conversion, F compare/min/max/class. Delay lines give every lane the
//   same latency, so results leave in issue order and never collide.
//
// Features:
//   - fpu_op: 0 ADD, 1 SUB, 2 MUL, 3 DIV, 4 SQRT, 5 int32/uint32 to
//     binary64, 6 binary64 to int32/uint32, 7 compare/min/max/class.
//   - funct3 selects the conversion signedness (op 5/6: 0 signed,
//     1 unsigned) or the op 7 function (0 FEQ ... 5 FCLASS).
//   - rm: 0 RNE, 1 RTZ, 2 RDN, 3 RUP, 4 RMM (ignored by op 7).
//
// Notes:
//   - II = 1 for any mix of operations. A request sampled at clock edge n
//     has a valid result after edge n+56.
//   - WARNING: there is no output backpressure. The caller must be able to
//     accept every result 56 edges after issuing it; vrm_fpu_axi_64 does so
//     by reserving an output slot before admitting a request.
//   - WARNING: illegal op/funct3/rm tuples must not be issued. Simulation
//     stops with FPU_ASSERT_NATIVE_CONFIG if one is.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_native_64(
    input wire clk,input wire rstn,input wire valid_in,
    input wire [3:0] fpu_op,input wire [2:0] funct3,input wire [2:0] rm,
    input wire [63:0] op_a,input wire [63:0] op_b,
    output wire valid_out,output wire [63:0] result_out,output wire [4:0] fflags_out
);
    wire legal=(fpu_op<=4'd7) &&
        ((fpu_op==4'd7) ? (funct3<=3'd5) :
         ((rm<=3'd4) && ((fpu_op==4'd5 || fpu_op==4'd6) ? (funct3<=3'd1) : 1'b1)));
    wire [5:0] raw_valid,balanced_valid;
    wire [63:0] raw_result [0:5];
    wire [4:0] raw_flags [0:5];
    wire [63:0] balanced_result [0:5];
    wire [4:0] balanced_flags [0:5];
    vrm_fpu_add_sub_64 add_sub(clk,rstn,valid_in && legal && fpu_op<=1,fpu_op==1,op_a,op_b,raw_result[0],raw_valid[0],rm,raw_flags[0]);
    vrm_fpu_mul_64 mul(clk,rstn,valid_in && legal && fpu_op==2,op_a,op_b,raw_result[1],raw_valid[1],rm,raw_flags[1]);
    vrm_fpu_div_64 div(clk,rstn,valid_in && legal && fpu_op==3,op_a,op_b,raw_result[2],raw_valid[2],rm,raw_flags[2]);
    vrm_fpu_sqrt_64 sqrt(clk,rstn,valid_in && legal && fpu_op==4,op_a,raw_result[3],raw_valid[3],rm,raw_flags[3]);
    vrm_fpu_conv_64 conv(clk,rstn,valid_in && legal && (fpu_op==5 || fpu_op==6),{fpu_op==6,funct3[0]},op_a,raw_result[4],raw_valid[4],rm,raw_flags[4]);
    vrm_fpu_misc_64 misc(clk,rstn,valid_in && legal && fpu_op==7,funct3,op_a,op_b,raw_result[5],raw_valid[5],rm,raw_flags[5]);
    vrm_fpu_delay #(54) balance_a(clk,rstn,raw_valid[0],raw_result[0],raw_flags[0],balanced_valid[0],balanced_result[0],balanced_flags[0]);
    vrm_fpu_delay #(51) balance_b(clk,rstn,raw_valid[1],raw_result[1],raw_flags[1],balanced_valid[1],balanced_result[1],balanced_flags[1]);
    vrm_fpu_delay #(0) balance_c(clk,rstn,raw_valid[2],raw_result[2],raw_flags[2],balanced_valid[2],balanced_result[2],balanced_flags[2]);
    vrm_fpu_delay #(0) balance_d(clk,rstn,raw_valid[3],raw_result[3],raw_flags[3],balanced_valid[3],balanced_result[3],balanced_flags[3]);
    vrm_fpu_delay #(55) balance_e(clk,rstn,raw_valid[4],raw_result[4],raw_flags[4],balanced_valid[4],balanced_result[4],balanced_flags[4]);
    vrm_fpu_delay #(56) balance_f(clk,rstn,raw_valid[5],raw_result[5],raw_flags[5],balanced_valid[5],balanced_result[5],balanced_flags[5]);
    assign valid_out=|balanced_valid;
    assign result_out=({64{balanced_valid[0]}} & balanced_result[0]) |
        ({64{balanced_valid[1]}} & balanced_result[1]) | ({64{balanced_valid[2]}} & balanced_result[2]) |
        ({64{balanced_valid[3]}} & balanced_result[3]) | ({64{balanced_valid[4]}} & balanced_result[4]) | ({64{balanced_valid[5]}} & balanced_result[5]);
    assign fflags_out=({5{balanced_valid[0]}} & balanced_flags[0]) |
        ({5{balanced_valid[1]}} & balanced_flags[1]) | ({5{balanced_valid[2]}} & balanced_flags[2]) |
        ({5{balanced_valid[3]}} & balanced_flags[3]) | ({5{balanced_valid[4]}} & balanced_flags[4]) | ({5{balanced_valid[5]}} & balanced_flags[5]);
    // synthesis translate_off
    always @(posedge clk) if(rstn) begin
        if(valid_in && legal!==1'b1) begin $display("FPU_ASSERT_NATIVE_CONFIG");$finish;end
        if((balanced_valid & (balanced_valid-6'd1))!=0) begin $display("FPU_ASSERT_COLLISION");$finish;end
    end
    // synthesis translate_on
endmodule
