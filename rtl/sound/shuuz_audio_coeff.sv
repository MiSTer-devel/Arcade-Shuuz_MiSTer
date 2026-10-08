// SPDX-License-Identifier: GPL-3.0-or-later
// Filter coefficients for shuuz_audio, computed from the component values
// by a script kept with the development sources. Do not edit by hand.
// Sections in signal order; terms are b0, b1, b2, a1, a2 with 30
// fraction bits, for one step every 256 clocks of 57.272727 MHz.
module shuuz_audio_coeff(
    input  wire [2:0] section, term,
    output reg signed [31:0] coefficient
);
    always @* begin
        coefficient = 32'sd0;
        case ({section, term})
            {3'd0, 3'd0}: coefficient = 32'sh3fff3890;
            {3'd0, 3'd1}: coefficient = 32'shc000c770;
            {3'd0, 3'd3}: coefficient = 32'sh3ffe7121;
            {3'd1, 3'd0}: coefficient = 32'shfe547bda;
            {3'd1, 3'd1}: coefficient = 32'shfe547bda;
            {3'd1, 3'd3}: coefficient = 32'sh3e6e2280;
            {3'd2, 3'd0}: coefficient = 32'sh013aca7e;
            {3'd2, 3'd1}: coefficient = 32'sh013aca7e;
            {3'd2, 3'd3}: coefficient = 32'sh3d8a6b03;
            {3'd3, 3'd0}: coefficient = 32'sh0012dc97;
            {3'd3, 3'd1}: coefficient = 32'sh0025b92f;
            {3'd3, 3'd2}: coefficient = 32'sh0012dc97;
            {3'd3, 3'd3}: coefficient = 32'sh7d313bbb;
            {3'd3, 3'd4}: coefficient = 32'shc28351e7;
            {3'd4, 3'd0}: coefficient = 32'shf2b3328e;
            {3'd4, 3'd1}: coefficient = 32'shf2b3328e;
            {3'd4, 3'd3}: coefficient = 32'sh2fe0f776;
            default: ;
        endcase
    end
endmodule
