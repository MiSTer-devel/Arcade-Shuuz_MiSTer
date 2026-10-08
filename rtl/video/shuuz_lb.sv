// SPDX-License-Identifier: GPL-3.0-or-later
// Motion object line buffers (LB 137536-001 at 85S and its RAM): two banks,
// one written by the MOB for the next line while the other is displayed and
// erased behind the beam. A word is colour (7-4) and pen (3-0); pen 0 is
// never written, so a later object only replaces what its pixels cover.
// Taken from the Off the Wall MiSTer core's offtwall_lb.sv with the module
// renamed; adapted there from the Relief Pitcher, Batman and Skull &
// Crossbones video models.
// Copyright (C) 2026 the Batman MiSTer core authors.
`timescale 1ns/1ps
module shuuz_lb #(
    parameter bit LB_ERASE  = 1'b1,
    parameter bit FIRST_WINS = 1'b0
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        wbank,
    input  logic        we,
    input  logic  [9:0] wa,
    input  logic [7:0] wd,
    input  logic        rd_ce,
    input  logic  [9:0] ra,
    output logic [7:0] q
);
    localparam logic [7:0] EMPTY = 8'd0;
    logic [7:0] mem0 [0:1023];
    logic [7:0] mem1 [0:1023];
    logic        we_d, wbank_d;
    logic  [9:0] wa_d;
    logic [7:0] wd_d;
    logic [7:0] occ;
    logic  [9:0] ra_d;
    logic        ers;
    always_ff @(posedge clk) begin
        if (reset) begin
            we_d <= 1'b0;
            ers  <= 1'b0;
        end else begin
            we_d    <= we;
            wa_d    <= wa;
            wd_d    <= wd;
            wbank_d <= wbank;
            ers     <= rd_ce & (LB_ERASE != 0);
            if (rd_ce) ra_d <= ra;
        end
    end
    wire wr_ok = !reset && we_d && (wd_d[3:0] != 4'h0)
                      && (!FIRST_WINS || (occ[3:0] == 4'h0));
    wire [9:0] a0_rd = (wbank   == 1'b0) ? wa   : ra;
    wire [9:0] a1_rd = (wbank   == 1'b1) ? wa   : ra;
    wire [9:0] a0_wr = (wbank_d == 1'b0) ? wa_d : ra_d;
    wire [9:0] a1_wr = (wbank_d == 1'b1) ? wa_d : ra_d;
    wire       e0_wr = (wbank_d == 1'b0) ? wr_ok : (ers && !reset);
    wire       e1_wr = (wbank_d == 1'b1) ? wr_ok : (ers && !reset);
    wire [7:0] d0_wr = (wbank_d == 1'b0) ? wd_d : EMPTY;
    wire [7:0] d1_wr = (wbank_d == 1'b1) ? wd_d : EMPTY;
    logic [7:0] q0, q1;
    always_ff @(posedge clk) begin
        q0 <= mem0[a0_rd];
        if (e0_wr) mem0[a0_wr] <= d0_wr;
    end
    always_ff @(posedge clk) begin
        q1 <= mem1[a1_rd];
        if (e1_wr) mem1[a1_wr] <= d1_wr;
    end
    assign occ = wbank_d ? q1 : q0;
    assign q   = wbank_d ? q0 : q1;
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, occ[7:4], 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
