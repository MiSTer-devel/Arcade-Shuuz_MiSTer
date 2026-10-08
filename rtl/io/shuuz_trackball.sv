`timescale 1ns/1ps
//============================================================================
//  Trackball axis to quadrature: drives one LETA CLK/DIR pair.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  From the Rampart MiSTer core (rampart_trackball.sv), module renamed.
//
//  Each delta is added to a pending count, and the pending count is played
//  out as quadrature transitions, one every STEP clk_sys, so the LETA's
//  3-sample input filter (CK = 895 kHz here: 64 clk_sys) sees every edge.
//  Forward motion is the sequence (CLK,DIR) = 00, 10, 11, 01.  The Shuuz
//  board grounds the LETA's RESOL pin, so it counts once for every two
//  transitions; shuuz_tball_axis therefore feeds two transitions per count.
//============================================================================

module shuuz_trackball #(
	parameter int STEP = 2048          // clk_sys per transition (about 28 kHz)
) (
	input  logic       clk,
	input  logic       reset,
	input  logic       strobe,          // 1-clk: a new delta
	input  logic [7:0] delta,           // signed
	output logic       q_clk,
	output logic       q_dir
);

	localparam int SW = $clog2(STEP);

	logic signed [9:0] pend;
	logic [1:0]        ph;      // position in the 4-step cycle
	logic [SW-1:0]     tmr;

	wire signed [9:0] d10  = {{2{delta[7]}}, delta};
	wire signed [10:0] sum = 11'(pend) + 11'(d10);

	always_ff @(posedge clk) begin
		if (reset) begin
			pend <= '0; ph <= 2'd0; tmr <= '0;
		end else begin
			tmr <= tmr + 1'b1;
			if (strobe) begin
				if (sum > 11'sd500)       pend <= 10'sd500;
				else if (sum < -11'sd500) pend <= -10'sd500;
				else                      pend <= sum[9:0];
			end else if (tmr == '0 && pend != 10'sd0) begin
				if (pend > 10'sd0) begin ph <= ph + 2'd1; pend <= pend - 10'sd1; end
				else               begin ph <= ph - 2'd1; pend <= pend + 10'sd1; end
			end
		end
	end

	// ph 0..3 -> (CLK,DIR) 00, 10, 11, 01
	assign q_clk = (ph == 2'd1) || (ph == 2'd2);
	assign q_dir = (ph == 2'd2) || (ph == 2'd3);

endmodule
