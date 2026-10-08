// SPDX-License-Identifier: GPL-3.0-or-later
// GAL16V8 136083-1050 at 55C: main address decoder. Combinational.
// pin[] carries the levels on the chip's own pins; value[] is what each
// output pin drives. Pin 1 is BAS and pins 2-9 are address lines 21 down to
// 14. Outputs, all active low: 19 /ROM0, 18 /ROM1, 17 /ROM2, 16 /VRAM,
// 15 /AUX, 14 the enable of the I/O decoder. Pins 13 and 12 have no terms.
module shuuz_gal_1050(
    input  wire [19:1]  pin,
    output wire [19:12] value
);
    assign value[19] = ~(pin[1] & ~pin[2] & ~pin[3] & ~pin[4] & ~pin[5]);
    assign value[18] = ~(pin[1] & ~pin[2] & ~pin[3] & ~pin[4] & pin[5]);
    assign value[17] = ~((pin[1] & ~pin[2] & ~pin[3] & pin[4] & ~pin[6] & ~pin[7]) |
                         (pin[1] & ~pin[2] & ~pin[3] & pin[4] & ~pin[5]));
    assign value[16] = ~(pin[1] & pin[2] & pin[3] & pin[4] & pin[5] & pin[6]);
    assign value[15] = ~(pin[1] & pin[2] & ~pin[3] & pin[4] & ~pin[5] & ~pin[6] & ~pin[7] &
                         ~pin[8] & ~pin[9]);
    assign value[14] = ~(~pin[2] & pin[3] & ~pin[4] & ~pin[5] & ~pin[6] & ~pin[7]);
    assign value[13] = 1'b1;
    assign value[12] = 1'b1;
    wire unused = &{1'b0, pin[19:10]};
endmodule
