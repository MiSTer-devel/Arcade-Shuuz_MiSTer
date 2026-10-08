// SPDX-License-Identifier: GPL-3.0-or-later
// One pen from a stamp row as shuuz_gfx_client delivers it. Each ROM byte
// holds four pixels of two planes, a nibble per plane; the high ROMs carry
// pen bits 3 and 2, the low ROMs bits 1 and 0. The ROM data is inverted.
// Taken from the Off the Wall MiSTer core's offtwall_gfx_pixel.sv with the
// module renamed; the download packs this board's ROMs the same way.
module shuuz_gfx_pixel(
    input  wire [31:0] row,
    input  wire        hflip,
    input  wire  [2:0] x,       // 0 is the left pixel as displayed
    output wire  [3:0] pen
);
    wire [2:0] p = hflip ? ~x : x;
    wire [7:0] lo = p[2] ? row[23:16] : row[7:0];
    wire [7:0] hi = p[2] ? row[31:24] : row[15:8];
    wire [1:0] n = ~p[1:0];
    assign pen = ~{hi[{1'b1, n}], hi[{1'b0, n}], lo[{1'b1, n}], lo[{1'b0, n}]};
endmodule
