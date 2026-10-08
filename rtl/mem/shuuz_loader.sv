// SPDX-License-Identifier: GPL-3.0-or-later
// Routes the ROM download stream (MiSTer only). Adapted from the Off the Wall
// MiSTer core's offtwall_loader.sv. Stream layout, in bytes:
//   000000-03FFFF  program ROMs, high byte (23P) first
//   040000-0BFFFF  playfield graphics, 512 KB
//   0C0000-1BFFFF  motion object graphics, 1 MB
//   1C0000-1FFFFF  sound samples, 256 KB (75B then 65B)
// Program bytes go straight to the program ROM. Everything after them is
// paired into 16-bit words, first byte low, and written to SDRAM at word
// (offset - 040000) / 2. For graphics the low byte is the ROM that holds pen
// bits 1 and 0 and the high byte the ROM that holds pen bits 3 and 2.
// busy holds the stream while a word is being written.
module shuuz_loader(
    input  wire        clk,
    input  wire        reset,
    input  wire        wr,          // one clk per byte
    input  wire [20:0] addr,
    input  wire  [7:0] data,
    output wire        busy,
    output wire        prog_we,
    output reg         rom_wr,      // held until rom_ack
    output reg  [19:0] rom_addr,    // SDRAM word address
    output reg  [15:0] rom_data,
    input  wire        rom_ack
);
    localparam logic [20:0] ROM = 21'h040000;
    assign prog_we = wr && addr < ROM;
    wire        is_rom = wr && addr >= ROM;
    wire [20:0] offset = addr - ROM;

    reg [7:0] low;
    always @(posedge clk) begin
        if (reset) begin
            rom_wr <= 1'b0;
        end else begin
            if (rom_ack) rom_wr <= 1'b0;
            if (is_rom && !offset[0]) low <= data;
            if (is_rom && offset[0]) begin
                rom_wr   <= 1'b1;
                rom_addr <= offset[20:1];
                rom_data <= {data, low};
            end
        end
    end
    assign busy = rom_wr || (is_rom && offset[0]);
endmodule
