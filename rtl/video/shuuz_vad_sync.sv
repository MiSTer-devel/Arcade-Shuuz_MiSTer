// SPDX-License-Identifier: GPL-3.0-or-later
// VAD 137656-001 at 50S (modelled as the -002 of the sister boards):
// beam counters, sync, blanking and the scanline interrupt, programmed by
// registers 01-05. Taken from the Off the Wall MiSTer core's
// offtwall_vad_sync.sv with the module renamed; adapted there from Relief
// Pitcher's and Batman's.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// Register fields (the layout MAME uses; the VAD sheet was never published):
//   01  vsync start (11-3), vsync end (2-0)
//   02  last line (15-9), vblank start (8-0)
//   03  scanline interrupt line (8-0)
//   04  hsync end / 2 (15-10), hsync start (9-0)
//   05  hblank end (11, 10), hblank start (9-0)
// An end field is a terminator on the low bits: the event ends at the next
// count whose low bits match. The last-line field applies only past line 255.
// h counts at 14.318 MHz, two counts per pixel, 912 a line.
//
// With HB_MODE = 0, hblank is a fixed window of HB_ACTIVE counts starting
// HB_PHASE counts into the line, because register 05 does not decode
// cleanly for a 336-pixel picture; HB_MODE = 1 is the literal reading.
//
// The counters run from power-up whatever register 00 says: the watchdog
// holds the 68000 in reset until it has counted eight vertical blanks, so
// the beam must run before the program can set the VAD up. Register 00 bit
// 15 gates only the scanline interrupt (and the DMA elsewhere).
`timescale 1ns/1ps
module shuuz_vad_sync #(
	parameter int H_TOTAL   = 912,     // 14.318 MHz counts per line
	parameter int H_VISIBLE = 336,     // pixels
	parameter int HB_MODE   = 0,       // 0 = fixed window, 1 = register literal
	parameter int HB_PHASE  = 0,       // counts from line start to the picture
	parameter int HB_ACTIVE = 2 * H_VISIBLE,   // counts of picture
	// 0 = a comparator on the line counter, every frame; 1 = a one-shot
	// re-armed by each register 03 write.
	parameter bit IRQ_ONESHOT = 1'b0
)(
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_14m,
	input  logic        vad_enable,    // register 00 bit 15
	input  logic [15:0] reg_vsy,       // register 01
	input  logic [15:0] reg_vbl,       // register 02
	input  logic [15:0] reg_vint,      // register 03
	input  logic [15:0] reg_hsy,       // register 04
	input  logic [15:0] reg_hbl,       // register 05
	input  logic        irq_arm,       // a write to register 03
	input  logic        irq_ack,       // a write to register 1E
	output logic [9:0]  h,             // 0 .. H_TOTAL-1
	output logic [8:0]  v,             // 0 .. last line
	output logic [9:0]  hd,            // h restarted HB_PHASE counts into the line
	output logic        hsync_n,       // active low
	output logic        vsync_n,       // active low
	output logic        hblank,
	output logic        vblank,
	output logic        hde, vde,      // display enables
	output logic [9:0]  hpos,          // pixel, 0 .. H_VISIBLE-1 while hde
	output logic [8:0]  vpos,          // = v
	// The line after v, wrapped at the last line. The playfield fetch reaches
	// into the next line near the end of each line.
	output logic [8:0]  v_next,
	output logic        line_start,    // one clk at h == 0
	output logic        frame_start,   // one clk at h == 0, v == 0
	output logic        vblank_start,  // one clk on the line vblank starts
	output logic        eof_window,    // vertical blanking: the reload may run
	output logic        vint_n         // scanline interrupt, level 4
);
	wire [8:0] v_sy_s = reg_vsy[11:3];
	wire [2:0] v_sy_e = reg_vsy[2:0];
	wire [6:0] v_last = reg_vbl[15:9];
	wire [8:0] v_bl_s = reg_vbl[8:0];
	wire [8:0] v_int  = reg_vint[8:0];
	wire [5:0] h_sy_e2= reg_hsy[15:10];     // the hsync end, halved
	wire [9:0] h_sy_s = reg_hsy[9:0];
	wire [9:0] h_bl_s = reg_hbl[9:0];
	wire [4:0] h_bl_e = {reg_hbl[11], 3'b000, reg_hbl[10]};  // bit 11 = /16, bit 10 = /1
	// Register 05 bits 15-12 clear the line buffer on the board; the model
	// erases behind the beam instead (shuuz_lb), so they are unused.
	wire [6:0] hs_e_lo = {h_sy_e2, 1'b0};  // the hsync terminator
	localparam logic [9:0] HTOT = H_TOTAL[9:0];

	// ---- counters ----
	wire        last_h  = (h == HTOT - 10'd1);
	wire        last_v  = v[8] & (v[6:0] == v_last);
	wire [9:0]  h_next  = last_h ? 10'd0 : (h + 10'd1);
	wire [8:0]  v_step  = last_h ? (last_v ? 9'd0 : (v + 9'd1)) : v;
	always_ff @(posedge clk) begin
		if (reset) begin
			h <= 10'd0;
			v <= 9'd0;
		end else if (ce_14m) begin                // free-running, see the header
			h <= h_next;
			v <= v_step;
		end
	end
	localparam logic [9:0] HPHASE = HB_PHASE[9:0];
	always_ff @(posedge clk) begin
		if (reset)                        hd <= 10'd0;
		else if (ce_14m)                  hd <= (h_next == HPHASE) ? 10'd0
		                                        : ((hd == HTOT - 10'd1) ? 10'd0 : hd + 10'd1);
	end

	// ---- sync: set on the start count, cleared on the terminator ----
	logic hs, vs;
	always_ff @(posedge clk) begin
		if (reset) begin
			hs <= 1'b0;
			vs <= 1'b0;
		end else if (ce_14m) begin
			if      (h_next == h_sy_s)                 hs <= 1'b1;
			else if (hs && (h_next[6:0] == hs_e_lo))   hs <= 1'b0;
			if (last_h) begin
				if      (v_step == v_sy_s)                 vs <= 1'b1;
				else if (vs && (v_step[2:0] == v_sy_e))    vs <= 1'b0;
			end
		end
	end
	assign hsync_n = ~hs;
	assign vsync_n = ~vs;

	// ---- blanking ----
	// vblank starts at the end of line V_BL_S and ends at the frame wrap.
	logic vb;
	always_ff @(posedge clk) begin
		if (reset)                                vb <= 1'b1;
		else if (ce_14m && last_h) begin
			if      (last_v)          vb <= 1'b0;      // entering line 0
			else if (v == v_bl_s)     vb <= 1'b1;      // entering line V_BL_S + 1
		end
	end
	assign vblank = vb;
	localparam logic [9:0] HBACT = HB_ACTIVE[9:0];
	logic hb_lit;                                  // the HB_MODE = 1 reading
	always_ff @(posedge clk) begin
		if (reset)                        hb_lit <= 1'b1;
		else if (ce_14m) begin
			if      (h_next == h_bl_s)                            hb_lit <= 1'b1;
			else if (hb_lit && ((h_next[4:0] & h_bl_e) == h_bl_e)
			         && (h_bl_e != 5'd0))                         hb_lit <= 1'b0;
		end
	end
	assign hblank = (HB_MODE == 0) ? (hd >= HBACT) : hb_lit;
	assign hde  = ~hblank;
	assign vde  = ~vblank;
	assign hpos = {1'b0, hd[9:1]};                          // two counts per pixel
	assign vpos = v;
	assign v_next = last_v ? 9'd0 : (v + 9'd1);

	// ---- markers ----
	assign line_start   = ce_14m & (h == 10'd0);
	assign frame_start  = line_start & (v == 9'd0);
	assign vblank_start = ce_14m & last_h & (v == v_bl_s);
	assign eof_window   = vb;

	// ---- scanline interrupt: set on line v_int, cleared by register 1E ----
	logic irq, armed;
	wire  hit = ce_14m & vad_enable & last_h & (v_step == v_int);
	always_ff @(posedge clk) begin
		if (reset) begin
			irq   <= 1'b0;
			armed <= 1'b0;
		end else begin
			if (irq_arm) armed <= 1'b1;
			if (irq_ack) irq   <= 1'b0;
			else if (hit && (armed | ~IRQ_ONESHOT)) begin
				irq <= 1'b1;
				if (IRQ_ONESHOT) armed <= 1'b0;
			end
		end
	end
	assign vint_n = ~irq;
	/* verilator lint_off UNUSEDSIGNAL */
	wire _unused = &{1'b0, reg_vsy[15:12], reg_vint[15:9], reg_hbl[15:12], 1'b0};
	/* verilator lint_on UNUSEDSIGNAL */
endmodule
