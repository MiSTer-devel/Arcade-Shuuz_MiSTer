// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer load and save of the 28C16 EEPROM at 38F.
// Taken from the Off the Wall MiSTer core's offtwall_nvram_io.sv with the
// module renamed and the factory-image window removed: Shuuz has none. It
// came there from the Skull & Crossbones core's skullxbo_nvram_io.sv, ported
// from the Bad Lands core (itself from Blasteroids, Xybots and Toobin').
// Copyright (C) 2026 the Skull & Crossbones MiSTer core authors.
//
// The board has no DIP switches: every game and coin option lives in the
// EEPROM. MiSTer file index 2 is the .nvm save file, loaded after the ROMs.
// A blank EEPROM is set up by the game itself. After a write the module waits
// SETTLE_CYCLES of quiet and then asks for one upload, so a burst of option
// writes gives a single save. The dirty flag survives board and watchdog
// resets, as the EEPROM contents do.
`timescale 1ns/1ps

module shuuz_nvram_io #(
	// ~1.17 s at 57.272727 MHz: long enough that a burst of option writes from
	// one self-test page produces a single upload.
	parameter int unsigned SETTLE_CYCLES = 67_108_863
)(
	input  logic        clk,
	input  logic        init_reset,

	input  logic        write_accepted,   // from shuuz_eeprom_28c16

	input  logic        ioctl_download,
	input  logic        ioctl_wr,
	input  logic [26:0] ioctl_addr,
	input  logic  [7:0] ioctl_dout,
	input  logic [15:0] ioctl_index,
	input  logic        ioctl_upload,

	output logic        load_we,
	output logic [10:0] load_addr,
	output logic  [7:0] load_data,
	output logic        seed_we,          // a factory-seed byte: never, Shuuz has none
	output logic        load_end,         // 1-clk: an index-2 download just ended
	output logic [10:0] dump_addr,
	input  logic  [7:0] dump_data,

	output logic        ioctl_upload_req,
	output logic  [7:0] ioctl_upload_index,
	output logic  [7:0] ioctl_din
);

	// Index 2 only; a longer file than 2 KB simply wraps.
	wire index2_nvram = (ioctl_index == 16'd2);

	assign seed_we   = 1'b0;
	assign load_we   = ioctl_download & ioctl_wr & index2_nvram;
	assign load_addr = ioctl_addr[10:0];

	// The end of an index-2 download; the EEPROM erases an all-zero image.
	logic dl2_d;
	wire  dl2 = ioctl_download & index2_nvram;
	always_ff @(posedge clk) begin
		if (init_reset) dl2_d <= 1'b0;
		else            dl2_d <= dl2;
	end
	assign load_end = dl2_d & ~dl2;
	assign load_data = ioctl_dout;
	assign dump_addr = ioctl_addr[10:0];

	localparam int SETTLE_W = (SETTLE_CYCLES <= 1) ? 1 : $clog2(SETTLE_CYCLES + 1);
	logic [SETTLE_W-1:0] settle;
	logic dirty;
	wire  settled      = (settle == SETTLE_W'(SETTLE_CYCLES));
	wire  upload_start = ioctl_upload & index2_nvram;

	always_ff @(posedge clk) begin
		if (init_reset) begin
			dirty  <= 1'b0;
			settle <= '0;
		end else if (write_accepted) begin
			dirty  <= 1'b1;      // a new byte cannot be cleaned by a concurrent upload
			settle <= '0;
		end else if (load_we || upload_start) begin
			dirty  <= 1'b0;
			settle <= '0;
		end else if (dirty && !settled) begin
			settle <= settle + 1'b1;
		end
	end

	assign ioctl_upload_req   = dirty & settled;
	assign ioctl_upload_index = 8'd2;
	assign ioctl_din          = dump_data;


endmodule
