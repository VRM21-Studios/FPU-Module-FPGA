// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_delay
// DESCRIPTION:
//   Registered delay line for a lane result (valid, 64-bit result and
//   5-bit flags). The dispatcher uses it to give every lane the same total
//   latency.
//
// Notes:
//   - DELAY registers; DELAY = 0 is a direct connection.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_delay #(parameter integer DELAY=0)(
    input wire clk,input wire rstn,input wire valid_in,
    input wire [63:0] result_in,input wire [4:0] flags_in,
    output wire valid_out,output wire [63:0] result_out,output wire [4:0] flags_out
);
    generate if(DELAY==0) begin: DIRECT
        assign valid_out=valid_in;
        assign result_out=result_in;
        assign flags_out=flags_in;
    end else begin: PIPE
        reg [68:0] payload [0:DELAY-1];
        reg [DELAY-1:0] vp;
        integer k;
        always @(posedge clk) begin
            if(!rstn) begin
                vp<=0;
                for(k=0;k<DELAY;k=k+1) payload[k]<=0;
            end else begin
                vp[0]<=valid_in;payload[0]<={flags_in,result_in};
                for(k=1;k<DELAY;k=k+1) begin
                    vp[k]<=vp[k-1];payload[k]<=payload[k-1];
                end
            end
        end
        assign valid_out=vp[DELAY-1];
        assign result_out=payload[DELAY-1][63:0];
        assign flags_out=payload[DELAY-1][68:64];
    end endgenerate
endmodule
