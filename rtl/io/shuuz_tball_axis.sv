`timescale 1ns/1ps
//============================================================================
//  One trackball axis: MiSTer motion in, LETA CLK/DIR quadrature out.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  From the Rampart MiSTer core (rampart_tball_axis.sv); here one count is
//  two quadrature transitions, because the Shuuz LETA has RESOL low.
//  Pacing scheme from blstroid_whirly.sv of the Blasteroids MiSTer core
//  (GPL-3.0).
//
//  `delta` is signed motion in LETA counts, one value per clk_sys (0 when
//  nothing moved), already scaled and in the direction the LETA should count.
//  It is added to a backlog, clamped to +/-127 counts, and the backlog is
//  played out one count (two edges) at a time through shuuz_trackball,
//  which makes the CLK/DIR edges.
//
//  Why a pacer.  A mouse or spinner reports in bursts, and a fast one can
//  report more counts in a frame than a real trackball could make.  The game
//  reads each 8-bit LETA counter once per pass of its main loop and takes the
//  difference as a signed byte, so 128 counts or more between two reads wrap
//  and read as motion the other way.  The backlog is therefore drained at a
//  rate proportional to its size, with a speed limit:
//
//      acc += min(|backlog|, RATE_CAP)   every clk_sys
//      one count each time acc reaches SMOOTH_K
//
//      counts/s = min(|backlog|, RATE_CAP) * f_clk / SMOOTH_K
//
//  With the defaults (f_clk = 57.272727 MHz):
//    * a burst decays with tau = SMOOTH_K / f_clk = 8.0 ms, so it leaves as
//      evenly spaced edges instead of one clump;
//    * the top speed is 29 * f_clk / SMOOTH_K = 3625 counts/s, 60.5 counts
//      per 59.92 Hz frame, so even a main-loop pass that spans two frames
//      sees at most 121 counts, short of the wrap at 128;
//    * counts are at least SMOOTH_K / RATE_CAP = 15 799 clk_sys (276 us)
//      apart and the two edges of a count 2048 clk_sys (32 LETA clocks)
//      apart, far above the three samples its input filter needs, so no
//      edge is ever lost.
//  The accumulator parks one short of SMOOTH_K while the backlog is empty,
//  so the first count of a movement leaves on the next clock.
//
//  The speed limit comes from the game's 8-bit difference, with margin; it is
//  not a measured property of the cabinet's trackball.
//============================================================================

module shuuz_tball_axis #(
	parameter int unsigned SMOOTH_K = 458182,
	parameter int unsigned RATE_CAP = 29,
	parameter int          STEP     = 2048     // shuuz_trackball edge spacing
) (
	input  logic               clk,
	input  logic               reset,
	input  logic signed [10:0] delta,
	output logic               q_clk,
	output logic               q_dir
);

	logic signed [7:0] err;                 // backlog, +/-127 counts

	localparam int        ACCW = $clog2(SMOOTH_K + RATE_CAP + 1);
	localparam [ACCW-1:0] K    = ACCW'(SMOOTH_K);
	localparam [ACCW-1:0] CAP  = ACCW'(RATE_CAP);

	logic      [ACCW-1:0] acc;
	wire                  moving  = (err != 8'sd0);
	wire       [6:0]      mag     = err[7] ? 7'(-err) : 7'(err);
	wire       [ACCW-1:0] inc     = (ACCW'(mag) > CAP) ? CAP : ACCW'(mag);
	wire       [ACCW:0]   acc_sum = {1'b0, acc} + {1'b0, inc};
	wire                  step    = moving && (acc_sum >= {1'b0, K});

	wire signed [12:0] err_next = 13'(err) + 13'(delta)
	                            - (step ? (err[7] ? -13'sd1 : 13'sd1) : 13'sd0);

	logic       out_stb;
	logic [7:0] out_d;

	always_ff @(posedge clk) begin
		if (reset) begin
			acc     <= K - 1'b1;
			err     <= '0;
			out_stb <= 1'b0;
			out_d   <= 8'd0;
		end else begin
			if      (!moving) acc <= K - 1'b1;
			else if (step)    acc <= ACCW'(acc_sum - {1'b0, K});
			else              acc <= ACCW'(acc_sum);

			if      (err_next >  13'sd127) err <=  8'sd127;
			else if (err_next < -13'sd127) err <= -8'sd127;
			else                           err <= 8'(err_next);

			out_stb <= step;
			out_d   <= err[7] ? 8'hFE : 8'h02;
		end
	end

	shuuz_trackball #(.STEP(STEP)) u_enc (
		.clk(clk), .reset(reset), .strobe(out_stb), .delta(out_d),
		.q_clk(q_clk), .q_dir(q_dir)
	);

endmodule
