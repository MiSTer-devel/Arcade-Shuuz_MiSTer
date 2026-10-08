// SPDX-License-Identifier: GPL-3.0-or-later
// GAL16V8 136083-1053 at 85N: motion object against playfield. Combinational.
// pin[] carries the levels on the chip's own pins; value[] is what each
// output pin drives.
// Inputs: 1 and 2 the top two bits of the playfield colour, 3 low when its
// two lower bits are both set, 4 high for motion object colours 12-15,
// 5-7 motion object pen bits 1-3 and 8 pen bit 0, all four as raw ROM data,
// which is inverted. Pins 9, 11, 14, 15 and 16 feed two spare gates.
// Outputs: 12 high = show the motion object, 19 high = shade the playfield,
// 13 high = playfield colour 15, 17 and 18 the spare gates.
module shuuz_gal_1053(
    input  wire [19:1]  pin,
    output wire [19:12] value
);
    wire p13 = pin[1] & pin[2] & ~pin[3];
    assign value[13] = p13;
    assign value[12] = (~pin[1] & ~pin[4] & ~pin[7] & ~p13) | (~pin[1] & ~pin[4] & ~pin[6] & ~p13) |
                       (~pin[1] & ~pin[4] & ~pin[5] & ~p13) | ( pin[1] &  pin[4] & ~pin[7] & ~p13) |
                       ( pin[1] &  pin[4] & ~pin[6] & ~p13) | ( pin[1] &  pin[4] & ~pin[5] & ~p13);
    assign value[19] = ( pin[1] &  pin[4] & pin[5] & pin[6] & pin[7] & ~pin[8]) |
                       (~pin[1] & ~pin[4] & pin[5] & pin[6] & pin[7] & ~pin[8]);
    assign value[17] = (~pin[14] & pin[15]) | ~pin[11];
    assign value[18] = (~pin[14] & pin[16]) | ~pin[9];
    assign value[14] = 1'b1;
    assign value[15] = 1'b1;
    assign value[16] = 1'b1;
    wire unused = &{1'b0, pin[19:17], pin[13:12], pin[10]};
endmodule
