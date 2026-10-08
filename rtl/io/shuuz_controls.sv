// SPDX-License-Identifier: GPL-3.0-or-later
// Shuuz cabinet controls from MiSTer inputs: one trackball, two buttons and
// a coin switch.
//
// Copyright (C) 2026 RetroShrimp (the Rampart MiSTer core's
// rampart_controls.sv, from which the motion sources, the sensitivity scaler
// and the pacing are taken; scaler originally from the Blasteroids core).
// Reduced here to one player, with the Shuuz trackball mounting added.
//
// Pad word (hps_io): [0] right, [1] left, [2] down, [3] up, [4] left button,
// [5] right button, [6] coin. The mouse buttons are the two buttons as well.
//
// Trackball. Motion is the sum of every source, in screen directions (right
// and down positive):
//   mouse    both axes;
//   spinner  X only;
//   paddle   X only, the change of the absolute position (a jump of more
//            than 64 in one update is ignored);
//   stick    the left analog stick as a speed, with a small dead zone;
//   d-pad    the speed of a full stick, when the stick is centred.
// The sum is scaled by `sens` in eighths, with the remainder carried.
//
// The cabinet's trackball is mounted with its two rollers at 45 degrees to
// the screen axes. With x to the right and y down, the roller on the LETA's
// channel 0 turns with x - y and the one on channel 1 with x + y. Each
// roller count is two quadrature edges, paced by shuuz_tball_axis.
//
// `pause` stops new motion being taken.
module shuuz_controls #(
    parameter int unsigned SMOOTH_K   = 458182,   // see shuuz_tball_axis
    parameter int unsigned RATE_CAP   = 29,
    parameter int          TRK_STEP   = 2048,
    parameter int unsigned STICK_TICK = 4096,     // clk per stick / d-pad step
    parameter int          STICK_DZ   = 12        // analog dead zone, of 127
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,

    input  logic [31:0] joy,
    input  logic [15:0] ana,            // [7:0] X, [15:8] Y, signed
    input  logic  [8:0] spin,
    input  logic  [7:0] pad,
    input  logic [24:0] ps2_mouse,

    input  logic  [3:0] sens,           // menu index, 0 = 1x
    input  logic        inv_x,
    input  logic        inv_y,

    output logic        lbutton,        // 1 = pressed
    output logic        rbutton,
    output logic        coin,
    output logic        ch0_clk, ch0_dir,   // LETA channel 0 (read at 103000)
    output logic        ch1_clk, ch1_dir    // LETA channel 1 (read at 103002)
);
    assign lbutton = joy[4] | ps2_mouse[0];
    assign rbutton = joy[5] | ps2_mouse[1];
    assign coin    = joy[6];

    // ---- mouse ----
    logic ms_t;
    always_ff @(posedge clk) ms_t <= ps2_mouse[24];
    wire ms_new = ps2_mouse[24] != ms_t;
    wire signed [10:0] ms_x = ms_new ? 11'($signed({ps2_mouse[4], ps2_mouse[15:8]})) : 11'sd0;
    // PS/2 Y is positive upwards
    wire signed [10:0] ms_y = ms_new ? 11'sd0 - 11'($signed({ps2_mouse[5], ps2_mouse[23:16]}))
                                     : 11'sd0;

    // ---- spinner ----
    logic sp_t;
    always_ff @(posedge clk) sp_t <= spin[8];
    wire signed [10:0] sp_x = (spin[8] != sp_t) ? 11'($signed(spin[7:0])) : 11'sd0;

    // ---- paddle ----
    logic [7:0] pd_p;
    always_ff @(posedge clk) pd_p <= pad;
    wire signed [9:0]  pd_d = $signed({2'b00, pad}) - $signed({2'b00, pd_p});
    wire signed [10:0] pd_x = (pd_d > 10'sd64 || pd_d < -10'sd64) ? 11'sd0 : 11'(pd_d);

    // ---- analog stick and d-pad as a speed ----
    localparam int TW = $clog2(STICK_TICK);
    logic [TW-1:0] tdiv;
    logic          tick;
    always_ff @(posedge clk) begin
        if (reset) begin tdiv <= '0; tick <= 1'b0; end
        else begin
            tick <= (tdiv == TW'(STICK_TICK - 1));
            tdiv <= (tdiv == TW'(STICK_TICK - 1)) ? '0 : tdiv + 1'b1;
        end
    end

    localparam logic signed [7:0] DZ = 8'(STICK_DZ);
    function automatic logic signed [7:0] speed(input logic [7:0] a, input logic neg,
                                                input logic pos);
        logic signed [7:0] s;
        s = $signed(a);
        if (s > DZ || s < -DZ) speed = (a == 8'h80) ? -8'sd127 : s;
        else if (pos)          speed = 8'sd127;
        else if (neg)          speed = -8'sd127;
        else                   speed = 8'sd0;
    endfunction

    // One count per 1024 speed units, taken every tick: a full stick gives
    // 127 * 13,983 / 1024 = 1,734 counts a second.
    logic signed [7:0]  vel  [0:1];
    logic signed [10:0] racc [0:1], rate [0:1];
    logic signed [11:0] rsum [0:1];
    always_comb begin
        vel[0] = speed(ana[7:0],  joy[1], joy[0]);
        vel[1] = speed(ana[15:8], joy[3], joy[2]);
        for (int i = 0; i < 2; i++) rsum[i] = 12'(racc[i]) + 12'(vel[i]);
    end
    always_ff @(posedge clk) begin
        for (int i = 0; i < 2; i++) begin
            if (reset) begin
                racc[i] <= '0; rate[i] <= '0;
            end else if (tick) begin
                if (rsum[i] >= 12'sd1024) begin
                    racc[i] <= 11'(rsum[i] - 12'sd1024); rate[i] <= 11'sd1;
                end else if (rsum[i] <= -12'sd1024) begin
                    racc[i] <= 11'(rsum[i] + 12'sd1024); rate[i] <= -11'sd1;
                end else begin
                    racc[i] <= 11'(rsum[i]); rate[i] <= 11'sd0;
                end
            end else begin
                rate[i] <= 11'sd0;
            end
        end
    end

    // ---- sum, sensitivity ----
    // Multiplier in eighths. 1x is first, so a cleared status word is the
    // default; then faster, then slower.
    logic [5:0] mul8;
    always_comb begin
        case (sens)
            4'd0:    mul8 = 6'd8;    // 1x
            4'd1:    mul8 = 6'd9;    // 1.125x
            4'd2:    mul8 = 6'd10;   // 1.25x
            4'd3:    mul8 = 6'd11;   // 1.375x
            4'd4:    mul8 = 6'd12;   // 1.5x
            4'd5:    mul8 = 6'd14;   // 1.75x
            4'd6:    mul8 = 6'd16;   // 2x
            4'd7:    mul8 = 6'd20;   // 2.5x
            4'd8:    mul8 = 6'd24;   // 3x
            4'd9:    mul8 = 6'd32;   // 4x
            4'd10:   mul8 = 6'd2;    // 0.25x
            4'd11:   mul8 = 6'd3;    // 0.375x
            4'd12:   mul8 = 6'd4;    // 0.5x
            4'd13:   mul8 = 6'd5;    // 0.625x
            4'd14:   mul8 = 6'd6;    // 0.75x
            default: mul8 = 6'd7;    // 0.875x
        endcase
    end

    logic signed [10:0] scr  [0:1];     // screen x, y
    logic signed [15:0] frac [0:1], q [0:1], w [0:1];
    logic signed [10:0] c    [0:1];
    always_comb begin
        scr[0] = ms_x + sp_x + pd_x + rate[0];
        scr[1] = ms_y + rate[1];
        for (int i = 0; i < 2; i++) begin
            // |scr| <= 1023 and mul8 <= 32, so the product fits 16 bits.
            q[i] = (16'(pause ? 11'sd0 : scr[i]) * $signed({10'd0, mul8})) + frac[i];
            w[i] = q[i] >>> 3;                      // floor: the residue is 0..7
            c[i] = (w[i] > 16'sd511) ? 11'sd511 : (w[i] < -16'sd511) ? -11'sd511 : 11'(w[i]);
        end
    end

    // ---- the 45 degree mounting ----
    logic signed [10:0] x, y;
    logic signed [10:0] roller [0:1];
    always_comb begin
        x = inv_x ? -c[0] : c[0];
        y = inv_y ? -c[1] : c[1];
    end
    always_ff @(posedge clk) begin
        for (int i = 0; i < 2; i++) begin
            if (reset) frac[i] <= '0;
            else       frac[i] <= q[i] - (w[i] <<< 3);
        end
        if (reset) begin
            roller[0] <= '0; roller[1] <= '0;
        end else begin
            roller[0] <= x - y;
            roller[1] <= x + y;
        end
    end

    shuuz_tball_axis #(.SMOOTH_K(SMOOTH_K), .RATE_CAP(RATE_CAP), .STEP(TRK_STEP)) u_ch0(
        .clk(clk), .reset(reset), .delta(roller[0]), .q_clk(ch0_clk), .q_dir(ch0_dir));
    shuuz_tball_axis #(.SMOOTH_K(SMOOTH_K), .RATE_CAP(RATE_CAP), .STEP(TRK_STEP)) u_ch1(
        .clk(clk), .reset(reset), .delta(roller[1]), .q_clk(ch1_clk), .q_dir(ch1_dir));

    wire unused = &{1'b0, joy[31:7], ps2_mouse[7:6], ps2_mouse[3:2]};
endmodule
