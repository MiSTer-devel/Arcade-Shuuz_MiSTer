// SPDX-License-Identifier: GPL-3.0-or-later
// GAL16V8 136083-1051 at 45E. Pins 13-15 and 17-19 are registers clocked by
// pin 1; pins 12 and 16 are combinational. clk/ce stand for the rising edge
// of pin 1; reset is power-up only.
// Inputs: 2 /Y, 3 MA2, 4 MA1, 5 /DTACK, 6 R//W, 7 /LDS, 8 /UDS, 9 /VRAM.
// Outputs: 19 /VVRAM, 18 /VUDS, 17 /VLDS (the bus strobes for the video
// section, one clock late), 16 W//R, 15 BDIR and 14 BC1 for the YM2149 site
// (not fitted), 12 that site's reset. Pin 13 is a register with no terms.
module shuuz_gal_1051(
    input  wire         clk, ce, reset,
    input  wire [19:1]  pin,
    output wire [19:12] value
);
    reg [19:13] q;
    wire p12 = ~(~pin[2] & ~pin[3] & ~pin[4] & ~pin[6]);
    always @(posedge clk) begin
        if (reset) q <= 7'b1110001;
        else if (ce) begin
            q[19] <= pin[9];
            q[18] <= pin[8];
            q[17] <= pin[7];
            q[15] <= ~((~pin[3] & ~q[15]) | ~p12 | (pin[6] & ~q[15]) | (pin[2] & ~q[15]) |
                       (q[14] & ~q[15]) | (~pin[5] & q[15]));
            q[14] <= ~((~pin[4] & ~q[14]) | ~p12 | (pin[3] & pin[6] & ~q[14]) |
                       (pin[2] & ~q[15]) | (~pin[3] & ~pin[6] & ~q[14]) | (~q[14] & q[15]) |
                       (~pin[5] & q[15]));
            q[13] <= 1'b1;
        end
    end
    assign value = {q[19:17], ~pin[6], q[15:13], p12};
    wire unused = &{1'b0, pin[19:10], pin[1], q[16]};
endmodule
