// SPDX-License-Identifier: GPL-3.0-or-later
// Analog output alignment: the OSD decode, the read-rate generator and the
// blanking glue around rmonic79's `crt_adjust` (crt_adjust.sv, from
// MiSTer-CRT-Adjust), written from that project's core-side example.
//
// Copyright (C) 2026 RetroShrimp (the Blasteroids MiSTer core's
// blstroid_analog_adjust.sv, from which this is taken). Re-derived here for
// an 8-clock pixel and the Shuuz raster.
//
// Sits between shuuz_core and arcade_video. It never touches the core's own
// timing, so the game cannot observe it. The OSD has an On/Off and three
// amounts, all two's complement:
//   H-Size      resamples the line so every pixel is wider or narrower by the
//               same amount
//   H-Position  moves the picture inside an unchanged HSync
//   V-Shift     moves VSync by whole lines
// Off is a bit-exact bypass. On, the line buffer is live even with every
// amount at 0.
//
// The raster (pixels of ce_pix, clk_sys / 8): 456 a line, active 0..335,
// HSync 375..406, 262 lines, 240 visible. The line counter and VBlank change
// at the line wrap, after HSync, so the buffer bank that closes at the HSync
// rise of line L already holds line L. The engine is built with VB_LATE = 0
// for that, and the vertical blank handed on below is sampled the same way.
//
// H-Position: content shift. The buffer's write pointer restarts at the
// HSync rise, so in buffer coordinates the picture is 81..416 of 456: an
// 81-pixel lead-in and a 39-pixel run-out. H-Position beyond +39, or
// enlarging with H-Size at H-Position 0, runs the right edge out of the
// buffer, as with the stage this replaced; a negative H-Position buys the
// room back. If a CRT shows a black block on the right that this cannot
// cure, HPOS_MODE = 0 moves the sync instead and nothing else changes.
//
// H-Size: the read period is 64 + hsize units, 64 units being one pixel
// (CLK_PER_PIX clocks), and the accumulator adds 64/CLK_PER_PIX a clock, so
// each OSD step is 1/64 (1.56%) of a pixel. CLK_PER_PIX must be a power of
// two for that to stay exact.

module shuuz_analog_adjust #(
	parameter int H_TOTAL     = 456,   // ce_pix ticks per line
	parameter int V_TOTAL     = 262,   // lines per frame
	parameter int CLK_PER_PIX = 8,     // clk_sys cycles per ce_pix
	parameter int HPOS_MODE   = 1,     // 1 = content shift, 0 = sync shift
	parameter int AW          = 11     // line buffer address bits
) (
	input  logic       clk,
	input  logic       ce_pix,

	// OSD
	input  logic       osd_on,         // CRT Adjust Off/On
	input  logic [4:0] osd_hsize,      // CRT H-Size        +15 / -16
	input  logic [6:0] osd_hpos,       // CRT H-Position    +63 / -64
	input  logic [5:0] osd_vshift,     // CRT V-Shift       +31 / -32

	input  logic [7:0] r_in, g_in, b_in,
	input  logic       hs_in, vs_in, hb_in, vb_in,

	output logic [7:0] r_out, g_out, b_out,
	output logic       hs_out, vs_out, hb_out, vb_out,
	output logic       ce_out
);

	localparam [7:0] ACC_STEP = 8'(64 / CLK_PER_PIX);

	// ---------------- OSD decode ----------------
	// Sampled at ce_pix so a menu change lands on a pixel boundary.
	logic              active;
	logic signed [4:0] hsize_s;
	logic signed [8:0] hpos_s;
	logic signed [5:0] vshift_s;

	always_ff @(posedge clk) if (ce_pix) begin
		active   <= osd_on;
		hsize_s  <= $signed(osd_hsize);
		hpos_s   <= 9'($signed(osd_hpos));
		vshift_s <= $signed(osd_vshift);
	end

	// ---------------- read-rate generator ----------------
	// Reset on the rise of the engine's line reference, never on the raw
	// HSync, so the write side, the engine's read counter and this rate all
	// restart on the same edge.
	wire  hs_ref;
	logic hs_ref_d;
	always_ff @(posedge clk) hs_ref_d <= hs_ref;
	wire  hs_ref_rise = hs_ref & ~hs_ref_d;

	wire  [7:0] rd_period = 8'd64 + {{3{hsize_s[4]}}, hsize_s};   // 48..79
	logic [7:0] rd_acc;
	wire        rd_tick = (rd_acc + ACC_STEP) >= rd_period;

	always_ff @(posedge clk) begin
		if      (hs_ref_rise) rd_acc <= 8'd0;
		else if (rd_tick)     rd_acc <= rd_acc + ACC_STEP - rd_period;
		else                  rd_acc <= rd_acc + ACC_STEP;
	end

	wire rd_ce = active ? rd_tick : ce_pix;

	// ---------------- the engine ----------------
	wire [7:0] str_r, str_g, str_b;
	wire       str_hs, str_vs, str_hb, str_vb;

	crt_adjust #(
		.VTOTAL    (V_TOTAL),
		.HTOTAL    (H_TOTAL),
		.HPOS_MODE (HPOS_MODE),
		.AW        (AW),
		.VB_LATE   (0)
	) u_crt_adjust (
		.clk        (clk),
		.pxl_cen    (ce_pix),
		.pxl2_cen   (rd_ce),
		.active     (active),
		.hsize      (hsize_s),      // unused by the engine; the rate above is H-Size
		.hoffset    (hpos_s),
		.voffset    (vshift_s),
		.r_in       (r_in), .g_in (g_in), .b_in (b_in),
		.hs_in      (hs_in),
		.vs_in      (vs_in),
		.hb_in      (hb_in | vb_in),
		.vb_in      (vb_in),
		.r_out      (str_r), .g_out (str_g), .b_out (str_b),
		.hs_out     (str_hs), .vs_out (str_vs),
		.hb_out     (str_hb), .vb_out (str_vb),
		.hs_ref_out (hs_ref)
	);

	// ---------------- the vertical blank handed to arcade_video ----------
	// While On the engine emits each line one line late, but its own vb_out is
	// the native blank. arcade_video takes VBlank where HBlank falls, so the
	// native blank would hide the last visible line. This one is sampled once
	// a line on the same edge, and the same way, as the engine's own gate, so
	// DE closes over exactly the lines the engine already blanks.
	logic hs_ref_q;
	always_ff @(posedge clk) if (ce_pix) hs_ref_q <= hs_ref;
	wire  ref_line_tick = ce_pix & hs_ref & ~hs_ref_q;

	logic vb_read;
	always_ff @(posedge clk) if (ref_line_tick) vb_read <= vb_in;

	// DE follows the picture. Upstream's example pins the start of DE to the
	// native active region so the OSD does not move with H-Position; that
	// assumes the picture never starts earlier than the native one, which a
	// negative H-Position does here, and the left of the picture would be cut.

	// ---------------- outputs ----------------
	assign r_out  = str_r;
	assign g_out  = str_g;
	assign b_out  = str_b;
	assign hs_out = str_hs;
	assign vs_out = str_vs;
	assign hb_out = str_hb;
	assign vb_out = active ? vb_read : str_vb;
	assign ce_out = rd_ce;

endmodule
