// SPDX-License-Identifier: GPL-3.0-or-later
// Colour RAM address from the playfield pixel and the line-buffer pixel,
// decided by the priority GAL at 85N (136083-1053).
//
// The GAL shows a motion object pixel only where its colour group agrees
// with the playfield's (object colours 12-15 over playfield colours 8-15,
// the rest over playfield colours 0-7), its pen is 2 or more and the
// playfield colour is not 15. Pen 1 under the same agreement shades the
// playfield instead. Pen 0 is nothing.
//
// Colour RAM address: motion object 000 + colour * 16 + pen; playfield
// 100 + colour * 16 + pen; shaded playfield 300 + colour * 16 + pen.
//
// How the GAL's pins reach the pixel buses is not on any published sheet.
// The wiring here follows the signal names MAME's source gives the equations.
// The result is registered once, on the pixel clock.
module shuuz_mixer(
    input  wire       clk,
    input  wire       reset,
    input  wire       ce,
    input  wire [7:0] mo,          // line buffer: colour, pen; pen 0 is empty
    input  wire [3:0] pf_pen,
    input  wire [3:0] pf_colour,
    output reg  [9:0] index
);
    wire [19:12] g;
    // Pins 19 down to 1. The motion object pen reaches the GAL as ROM data,
    // which is inverted.
    wire [19:1] pin = {10'd0, 1'b0,
                       ~mo[0], ~mo[3], ~mo[2], ~mo[1],
                       mo[7] & mo[6],
                       ~(pf_colour[1] & pf_colour[0]), pf_colour[2], pf_colour[3]};
    shuuz_gal_1053 u_85n(.pin(pin), .value(g));
    wire show_mo = g[12];
    wire shade   = g[19];

    always @(posedge clk) begin
        if (reset)   index <= 10'd0;
        else if (ce) index <= show_mo ? {2'b00, mo} : {shade, 1'b1, pf_colour, pf_pen};
    end
    wire unused = &{1'b0, g[18:13]};
endmodule
