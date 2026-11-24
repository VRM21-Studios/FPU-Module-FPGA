// ============================================================================
// VRM21 Studios - FPU-Module-FPGA
// ============================================================================
// MODULE: vrm_fpu_record_fifo
// DESCRIPTION:
//   First-word-fall-through FIFO for fixed-width records (WIDTH bits,
//   DEPTH entries) with a ready/valid interface on both sides. The AXI
//   wrapper uses it for admitted requests and for results.
//
// Features:
//   - out_data is zero while the FIFO is empty.
//   - Pointers and occupancy are cleared by a synchronous reset; the
//     storage itself is not reset and is never read while empty.
//
// Notes:
//   - DEPTH must be a power of two and at least 2; simulation stops with
//     FPU_ASSERT_FIFO_DEPTH otherwise.
//   - Adapted from the FWFT FIFO of VRM21-RTL-Utilities, commit
//     39c61d8635d358a34c33f4f06b8e0aaa5c886f47: a Verilog-2001 constant
//     function replaces $clog2, there is no initial-state dependency, and
//     the record interface carries no TLAST field.
//
// MIT License
//
// Copyright (c) 2026 Ryadh Al Ariz Bangsawan Putra Rambe
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// ============================================================================
`timescale 1ns/1ps
module vrm_fpu_record_fifo #(
    parameter integer WIDTH=69,parameter integer DEPTH=64
)(input wire clk,input wire rstn,
  input wire [WIDTH-1:0] in_data,input wire in_valid,output wire in_ready,
  output wire [WIDTH-1:0] out_data,output wire out_valid,input wire out_ready);
    function integer log2;
        input integer value;
        integer n;
        begin n=value-1;log2=0;while(n>0) begin log2=log2+1;n=n/2;end end
    endfunction
    localparam integer P=log2(DEPTH);
    (* ram_style="distributed" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [P-1:0] rd_ptr,wr_ptr;
    reg [P:0] count;
    wire push=in_valid && in_ready;
    wire pop=out_valid && out_ready;
    assign in_ready=count<DEPTH;
    assign out_valid=count!=0;
    assign out_data=out_valid ? mem[rd_ptr] : {WIDTH{1'b0}};
    always @(posedge clk) begin
        if(!rstn) begin rd_ptr<=0;wr_ptr<=0;count<=0;end
        else begin
            if(push) begin mem[wr_ptr]<=in_data;wr_ptr<=wr_ptr+1'b1;end
            if(pop) rd_ptr<=rd_ptr+1'b1;
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(rstn && (DEPTH<2 || (DEPTH & (DEPTH-1))!=0)) begin
        $display("FPU_ASSERT_FIFO_DEPTH");$finish;
    end
    // synthesis translate_on
endmodule
