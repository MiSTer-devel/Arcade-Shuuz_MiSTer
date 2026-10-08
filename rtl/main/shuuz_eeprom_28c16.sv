// SPDX-License-Identifier: GPL-3.0-or-later
// 28C16 EEPROM at 38F (2K x 8) and the flop at 10B that locks it.
// Taken from the Off the Wall MiSTer core's offtwall_eeprom_28c16.sv (after
// Batman, Skull & Crossbones and Bad Lands) with the module renamed. This
// board's schematic draws the same circuit.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// The chip is on the low data byte. A flop gates its output enable: reset
// locks it (reads work, writes are ignored), an access to the unlock address
// unlocks it (reads float, the next write programs), and the end of any
// low-byte write locks it again. WRITE_CYCLES is the byte programming time.
//
// MiSTer additions: the array is block RAM. Block RAM powers up as zeros, so
// an erase pass writes FF when no image was loaded. A factory seed, if given,
// is kept and replayed over an all-zero save file; Shuuz has none.
`timescale 1ns/1ps

module shuuz_eeprom_28c16 #(
	parameter int CLK_HZ       = 57272727,
	parameter int WRITE_CYCLES = CLK_HZ / 100      // 10 ms, the 2816A data-sheet bound
)(
	input  logic        clk,
	input  logic        init_reset,   // FPGA / PLL init and NVRAM restore
	input  logic        reset,        // the board's /SYSRES, active high

	// /UNLOCK drives the flop's /PRE, which is level sensitive, so this port is
	// the level "an access to 101000 is in progress".  Reads unlock too.
	input  logic        unlock,       // a level, not a pulse
	input  logic        any_write,    // 1-clk pulse: /WL rising, any low-byte write
	input  logic        cpu_we,       // 1-clk pulse: that write had /EEPROM asserted
	input  logic [10:0] cpu_addr,     // MA11:1
	input  logic  [7:0] cpu_wdata,    // D7:0
	output logic  [7:0] cpu_rdata,    // D7:0
	output logic        busy,
	output logic        oe_n,         // the flop's Q, wired straight to the chip's /OE
	output logic        unlocked,     // the flop's Q
	output logic        write_accepted,

	// MiSTer NVRAM restore / save-back (shuuz_nvram_io)
	input  logic        load_we,
	input  logic [10:0] load_addr,
	input  logic  [7:0] load_data,
	// seed_we: this load_we byte is a factory seed, not part of the save file
	// (unused here).  load_end: 1-clk pulse as an index-2 download ends.
	input  logic        seed_we,
	input  logic        load_end,
	input  logic [10:0] dump_addr,
	output logic  [7:0] dump_data
);

	localparam int BUSY_W = (WRITE_CYCLES <= 1) ? 1 : $clog2(WRITE_CYCLES + 1);
	logic [BUSY_W-1:0] busy_ctr;
	logic [7:0] mem [0:2047];

	// ---- power-up erase --------------------------------------------------
	/* verilator lint_off MULTIDRIVEN */
	/* verilator lint_off PROCASSINIT */
	// preserve: the data input is constant 1, so without it synthesis deletes
	// the register and the power-up erase never runs.
	(* preserve *) logic programmed = 1'b0;
	logic        ld_seen    = 1'b0;
	logic        ld_nonzero = 1'b0;
	logic        por_run    = 1'b0;
	/* verilator lint_on PROCASSINIT */
	/* verilator lint_on MULTIDRIVEN */
	logic [10:0] por_addr;

	// ---- factory seed ----------------------------------------------------
	// The seed is written to the array and kept here; an all-zero index-2 image
	// (no save file yet) replays it.  `seeded` needs `preserve` like `programmed`.
	/* verilator lint_off MULTIDRIVEN */
	/* verilator lint_off PROCASSINIT */
	(* preserve *) logic seeded = 1'b0;
	logic        l2_seen    = 1'b0;
	logic        l2_nonzero = 1'b0;
	/* verilator lint_on PROCASSINIT */
	/* verilator lint_on MULTIDRIVEN */
	logic [7:0]  seed_mem [0:2047];
	logic [7:0]  seed_q;
	logic        por_run_d;
	logic [10:0] por_addr_d;
	wire         replay = load_end & l2_seen & ~l2_nonzero;

`ifndef ALTERA_RESERVED_QIS
	// Simulation only: model the FPGA RAM powering up at 0x00 (not the 28C16
	// erased state); the erase pass below then writes 0xFF.
	initial for (int i = 0; i < 2048; i++) mem[i] = 8'h00;
`endif

	wire ld_data_nz = load_we & (|load_data);
	wire nx_seen    = ld_seen    | load_we;
	wire nx_nonzero = ld_nonzero | ld_data_nz;

	always_ff @(posedge clk) begin
		if (ld_data_nz || write_accepted) programmed <= 1'b1;
		if (load_we & seed_we)            seeded     <= 1'b1;

		// index-2 image census; restarts when init_reset falls
		if (load_end || init_reset) begin
			l2_seen    <= 1'b0;
			l2_nonzero <= 1'b0;
		end else if (load_we & ~seed_we) begin
			l2_seen <= 1'b1;
			if (|load_data) l2_nonzero <= 1'b1;
		end

		if (init_reset) begin
			ld_seen    <= nx_seen;
			ld_nonzero <= nx_nonzero;
			por_run    <= nx_seen ? ~nx_nonzero : ~programmed;
			por_addr   <= 11'd0;
		end else begin
			ld_seen    <= 1'b0;
			ld_nonzero <= 1'b0;
			if (replay) begin
				// all-zero index-2 image: rewrite the seed (or 0xFF) over it
				por_run  <= 1'b1;
				por_addr <= 11'd0;
			end else if (load_we || write_accepted) por_run <= 1'b0;
			else if (por_run) begin
				por_addr <= por_addr + 1'b1;
				if (&por_addr) por_run <= 1'b0;
			end
		end
	end

	assign busy = |busy_ctr;

	// No gate on the board: Q drives /OE directly.  Locked (Q = 0) -> /OE low,
	// outputs on, /WE ignored.
	assign oe_n = unlocked;

	// A write programs only while unlocked and not busy.  `unlocked` is sampled
	// before the same /WL edge re-locks the flop, so the intended byte is stored.
	assign write_accepted = cpu_we & unlocked & ~busy;

	// ---- the unlock flop at 10B --------------------------------------------
	// /CLR = /SYSRES; /PRE (unlock) is a level and wins over its own /WL edge.
	always_ff @(posedge clk) begin
		if (init_reset || reset) unlocked <= 1'b0;
		else if (unlock)         unlocked <= 1'b1;
		else if (any_write)      unlocked <= 1'b0;
	end

	// ---- the write decode ------------------------------------------------
	// Priority: load_we > init_reset (no write) > erase/seed pass > CPU write.
	// The pass is one stage deep so it can write the registered seed read.
	always_ff @(posedge clk) begin
		seed_q     <= seed_mem[por_addr];
		por_run_d  <= por_run & ~init_reset;
		por_addr_d <= por_addr;
		if (load_we & seed_we) seed_mem[load_addr] <= load_data;
	end
	wire we_load = load_we;
	wire we_por  = ~load_we & ~init_reset & por_run_d;
	wire we_cpu  = ~load_we & ~init_reset & ~we_por & ~por_run & write_accepted;

	always_ff @(posedge clk) begin
		if (load_we || init_reset) busy_ctr <= '0;
		else begin
			if (busy)   busy_ctr <= busy_ctr - 1'b1;
			if (we_cpu) busy_ctr <= BUSY_W'(WRITE_CYCLES);
		end
	end

	// ---- the cell array: one write port, two registered read ports -------
	// The loader write is outside the init_reset guard because restored bytes
	// arrive while init_reset is high.
	wire        mem_we = we_load | we_por | we_cpu;
	wire [10:0] mem_wa = we_load ? load_addr : we_por ? por_addr_d : cpu_addr;
	wire  [7:0] mem_wd = we_load ? load_data
	                   : we_por  ? (seeded ? seed_q : 8'hFF)
	                   :           cpu_wdata;

	logic [7:0] cpu_q;

	always_ff @(posedge clk) begin
		if (mem_we) mem[mem_wa] <= mem_wd;
		cpu_q     <= mem[cpu_addr];    // read port 1 -- the 68000 (BD7:0)
		dump_data <= mem[dump_addr];   // read port 2 -- the NVRAM upload
	end

	// While programming or unlocked (/OE high) the outputs float; the board
	// has no pull-ups, so the core uses 0xFF for every undriven lane.
	// Registered alongside the RAM output to keep the same one-cycle latency.
	logic float_d;
	always_ff @(posedge clk) float_d <= busy | oe_n;
	assign cpu_rdata = float_d ? 8'hFF : cpu_q;

endmodule
