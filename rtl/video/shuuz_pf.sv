// SPDX-License-Identifier: GPL-3.0-or-later
// The playfield: 64 x 64 stamps of 8 x 8 pixels, stored a column at a time.
// The code word is bit 15 horizontal flip and a 14-bit stamp; the colour is
// bits 11-8 of the attribute word at the same index. Stamp rows are fetched
// four stamps ahead of the beam. Adapted from the Off the Wall MiSTer core's
// offtwall_pf.sv for a 14-bit stamp code; adapted there from the Relief
// Pitcher, Batman and Skull & Crossbones video models.
// Copyright (C) 2026 the Batman MiSTer core authors.
`timescale 1ns/1ps
module shuuz_pf #(
    parameter int XOFF  = 0,
    parameter int H_PIX = 456
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_7m,
    input  wire  [8:0] px,
    input  wire  [8:0] line,
    input  wire  [8:0] line_next,
    input  wire  [8:0] xscroll,
    input  wire  [8:0] yscroll,
    input  wire [14:0] base_code,
    input  wire [14:0] base_attr,
    output wire [14:0] code_a,
    output wire [14:0] attr_a,
    input  wire [15:0] code_q,
    input  wire [15:0] attr_q,
    output reg         rom_fetch,
    output reg  [16:0] rom_addr,
    input  wire [31:0] rom_row,
    input  wire        rom_valid,
    output reg         rom_late,
    output reg   [3:0] pen,
    output wire  [3:0] colour
);
    localparam int LEAD = 4;
    localparam logic [8:0] XOFFV = XOFF[8:0];
    wire [8:0] mx = px + xscroll + XOFFV;
    wire [2:0] fine_x = mx[2:0];
    wire adv = ce_7m && fine_x == 3'd7;
    localparam logic [9:0] HPIXV = H_PIX[9:0];
    wire [9:0] pxa   = {1'b0, px} + 10'(8 * LEAD);
    wire       wrapf = pxa >= HPIXV;
    wire [8:0] pxf   = wrapf ? 9'(pxa - HPIXV) : pxa[8:0];
    wire [8:0] linef = wrapf ? line_next : line;
    wire [8:0] mxf = pxf   + xscroll + XOFFV;
    wire [8:0] myf = linef + yscroll;
    reg [5:0] col_l, row_l;
    reg [2:0] finey_l;
    always @(posedge clk) begin
        if (reset) begin
            col_l   <= 6'd0;
            row_l   <= 6'd0;
            finey_l <= 3'd0;
        end else if (adv) begin
            col_l   <= mxf[8:3];
            row_l   <= myf[8:3];
            finey_l <= myf[2:0];
        end
    end
    wire [14:0] tile_idx = {3'b000, col_l, row_l};
    assign code_a = base_code + tile_idx;
    assign attr_a = base_attr + tile_idx;

    localparam int DEPTH = LEAD - 1;
    reg [15:0] rcode [0:DEPTH-1];
    reg [15:0] rattr [0:DEPTH-1];
    reg [31:0] gp, g1, g0;
    reg        busy, arm;
    wire rom_done = arm && rom_valid;
    always @(posedge clk) begin
        rom_fetch <= 1'b0;
        rom_late  <= 1'b0;
        if (reset) begin
            for (int i = 0; i < DEPTH; i++) begin
                rcode[i] <= 16'h0000;
                rattr[i] <= 16'h0000;
            end
            gp <= 32'd0; g1 <= 32'd0; g0 <= 32'd0;
            busy     <= 1'b0;
            arm      <= 1'b0;
            rom_addr <= 17'd0;
        end else begin
            if (!adv && !rom_fetch) arm <= 1'b1;
            if (rom_done) begin
                gp   <= rom_row;
                busy <= 1'b0;
            end
            if (adv) begin
                arm <= 1'b0;
                for (int i = 0; i < DEPTH-1; i++) begin
                    rcode[i] <= rcode[i+1];
                    rattr[i] <= rattr[i+1];
                end
                rcode[DEPTH-1] <= code_q;
                rattr[DEPTH-1] <= attr_q;
                g0 <= g1;
                g1 <= rom_done ? rom_row : gp;
                rom_addr  <= {code_q[13:0], finey_l};
                rom_fetch <= 1'b1;
                rom_late  <= busy && !rom_done;
                busy      <= 1'b1;
            end
        end
    end

    wire [3:0] pen_now;
    shuuz_gfx_pixel u_pixel(.row(g0), .hflip(rcode[0][15]), .x(fine_x), .pen(pen_now));
    reg [3:0] colour_r;
    always @(posedge clk) begin
        if (reset) begin
            pen      <= 4'd0;
            colour_r <= 4'd0;
        end else if (ce_7m) begin
            pen      <= pen_now;
            colour_r <= rattr[0][11:8];
        end
    end
    assign colour = colour_r;

    wire unused = &{1'b0, mx[8:3], mxf[2:0], pxa[9], code_q[14]};
endmodule
