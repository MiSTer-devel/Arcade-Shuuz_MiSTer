// SPDX-License-Identifier: GPL-3.0-or-later
// /DTACK: the 74LS163A wait counter at 50B.
// Structure taken from the Off the Wall MiSTer core's offtwall_dtack.sv
// (after Batman's); the load inputs are this board's.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// The counter runs on the processor clock. It is cleared between bus cycles
// (/CLR = BAS), loads {1, /VRAM, slow, /EEPROM} while its QC output is low,
// then counts up; DTACK is its carry out at 15. ENT is the /VPA net, so the
// counter neither counts nor carries during an interrupt acknowledge.
//   nothing low      loads 15: no wait states
//   /EEPROM low      loads 14: one wait state
//   slow low         loads 13: two wait states (LETA, MSM6295, YM2149 site)
//   /VRAM low        loads 11: QC stays low, so it reloads every clock and
//                    never carries; the video section ends those cycles
module shuuz_dtack(
    input  wire       clk,
    input  wire       ce_cpu,
    input  wire       as_n,
    input  wire       eeprom_n,
    input  wire       slow_n,      // /LETA and /PCM and /Y
    input  wire       vram_n,
    input  wire       vpa_n,
    output wire       dtack_n,
    output wire [3:0] count
);
    reg [3:0] q;
    wire rco = (q == 4'hF) && vpa_n;                                  // ENT gates the carry
    always @(posedge clk) begin
        if (ce_cpu) begin
            if (as_n)              q <= 4'd0;                         // /CLR
            else if (!q[2])        q <= {1'b1, vram_n, slow_n, eeprom_n};  // /LOAD = QC
            else if (vpa_n && !rco) q <= q + 4'd1;                    // ENT = /VPA, ENP = /DTACK
        end
    end
    assign dtack_n = !rco;
    assign count   = q;
endmodule
