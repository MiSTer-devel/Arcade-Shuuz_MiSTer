// SPDX-License-Identifier: GPL-3.0-or-later
// Power-on reset and watchdog: the 74LS197 counter at 30B.
// Adapted from the Off the Wall MiSTer core's offtwall_watchdog.sv (after
// Batman's); this board draws the same circuit, with a disable jumper.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// The counter counts the starts of vertical blanking. Its top bit is /SYSRES.
// Power-on clears it to 0, any access to the watchdog address loads 8, and
// the wrap from 15 to 0 resets the board. So the board comes out of reset
// eight frames after power-on, resets if the program is silent for eight
// frames, and then stays in reset for eight frames.
// The WDIS jumper holds the load input active: the count stays at 8.
module shuuz_watchdog #(
    parameter int CLK_HZ = 57272727,
    parameter int POR_US = 10000      // power-on RC delay, about 10 ms
)(
    input  wire       clk,
    input  wire       ext_reset,   // re-run the power-on sequence
    input  wire       vblank,      // high during vertical blanking
    input  wire       wdog_n,      // watchdog address selected
    input  wire       wdis,        // 1 = jumper fitted, watchdog disabled
    output wire       sysres_n,
    output wire [3:0] count
);
    localparam int POR_CYCLES = int'((longint'(POR_US) * CLK_HZ) / 1000000);
    localparam int POR_W = (POR_CYCLES <= 1) ? 1 : $clog2(POR_CYCLES + 1);
    reg [POR_W-1:0] por_count;
    reg             power_on;
    always @(posedge clk) begin
        if (ext_reset) begin
            por_count <= '0;
            power_on  <= 1'b0;
        end else if (!power_on) begin
            if (por_count >= POR_W'(POR_CYCLES - 1)) power_on <= 1'b1;
            else por_count <= por_count + 1'b1;
        end
    end

    reg vblank_q;
    always @(posedge clk) vblank_q <= vblank;

    reg [3:0] q;
    always @(posedge clk) begin
        if (!power_on)                q <= 4'd0;
        else if (!wdog_n || wdis)     q <= 4'd8;
        else if (vblank && !vblank_q) q <= q + 4'd1;
    end
    assign count    = q;
    assign sysres_n = q[3];
endmodule
