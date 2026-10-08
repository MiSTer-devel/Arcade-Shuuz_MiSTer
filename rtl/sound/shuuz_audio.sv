// SPDX-License-Identifier: GPL-3.0-or-later
// The analogue path from the MSM6295 output pin to the output of the summing
// stage (LM324 95C), before the cabinet's volume control and amplifier.
//
//   stage 1: C65 into R76, feedback R75 and C64: inverting, gain 2.13,
//            blocks DC, low-pass at 884 Hz
//   stage 2: R85/C60, R73, R74/C67/C61 around a follower: third-order
//            low-pass
//   stage 3: R88 into the summing node, feedback R89 and C59: inverting,
//            gain 1.65, low-pass at 10.3 kHz. The other three inputs of this
//            stage are the unfitted YM2149's amplifier and two unused pins.
//
// The stages run as five first- and second-order sections, one step every
// 256 clocks, which is 33 steps for each MSM6295 output sample. Voltages are
// relative to the mid-point supply and carry 30 fraction bits. The chip's
// output is taken as 2.5 V either side of its mid-point at full scale, and
// 8 V either side at the stage 3 output is full scale of `sample`.
//
// One multiplier is shared, after the Relief Pitcher core's audio filter.
module shuuz_audio (
    input  wire               clk,
    input  wire               reset,
    input  wire               ce_pcm,
    input  wire signed [11:0] dac,        // the MSM6295's output code
    output reg  signed [15:0] sample,
    output reg                valid,      // one clock: sample has changed
    output reg                late,       // a step was not finished in time
    output reg                clipped     // the output has reached full scale
);
    localparam int SECTIONS = 5;
    localparam signed [21:0] VOLTS_PER_CODE = 22'sd1310720;     // 2.5 V / 2048

    reg [1:0] divider;
    wire tick = ce_pcm && divider == 2'd3;

    reg signed [39:0] x1 [0:SECTIONS-1], x2 [0:SECTIONS-1];
    reg signed [39:0] y1 [0:SECTIONS-1], y2 [0:SECTIONS-1];
    reg signed [39:0] in, current;
    reg  [2:0] section, term;
    reg  [1:0] phase;
    reg        busy;

    wire signed [31:0] coefficient;
    shuuz_audio_coeff u_coeff(.section(section), .term(term), .coefficient(coefficient));

    wire signed [39:0] section_in = section == 3'd0 ? in : current;
    reg  signed [39:0] operand;
    always @* begin
        case (term)
            3'd0:    operand = section_in;
            3'd1:    operand = x1[section];
            3'd2:    operand = x2[section];
            3'd3:    operand = y1[section];
            default: operand = y2[section];
        endcase
    end

    reg signed [31:0] coefficient_r;
    reg signed [39:0] operand_r;
    reg signed [71:0] product;
    reg signed [75:0] accumulator;
    wire signed [75:0] rounded = (accumulator + 76'sd536870912) >>> 30;
    wire over  = !rounded[75] && |rounded[74:39];
    wire under =  rounded[75] && !(&rounded[74:39]);
    wire signed [39:0] result = over ? 40'sh7FFFFFFFFF : under ? 40'sh8000000000 : rounded[39:0];

    // 8 V is 2^33 here and 2^15 at the output.
    wire signed [40:0] nearest = 41'(result) + 41'sd131072;
    wire signed [22:0] scaled = nearest[40:18];
    wire out_over  = scaled >  23'sd32767;
    wire out_under = scaled < -23'sd32768;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (reset) begin
            divider <= 2'd0; busy <= 1'b0; late <= 1'b0; clipped <= 1'b0; sample <= 16'sd0;
            in <= 40'sd0; current <= 40'sd0; section <= 3'd0; term <= 3'd0; phase <= 2'd0;
            coefficient_r <= 32'sd0; operand_r <= 40'sd0; product <= 72'sd0; accumulator <= 76'sd0;
            for (int i = 0; i < SECTIONS; i++) begin
                x1[i] <= 40'sd0; x2[i] <= 40'sd0; y1[i] <= 40'sd0; y2[i] <= 40'sd0;
            end
        end else begin
            if (ce_pcm) divider <= divider + 2'd1;
            if (tick && busy) late <= 1'b1;
            if (!busy) begin
                if (tick) begin
                    in <= dac * VOLTS_PER_CODE;
                    section <= 3'd0; term <= 3'd0; phase <= 2'd0; accumulator <= 76'sd0;
                    busy <= 1'b1;
                end
            end else case (phase)
                2'd0: begin coefficient_r <= coefficient; operand_r <= operand; phase <= 2'd1; end
                2'd1: begin product <= coefficient_r * operand_r; phase <= 2'd2; end
                2'd2: begin
                    accumulator <= accumulator + 76'(product);
                    if (term == 3'd4) phase <= 2'd3;
                    else begin term <= term + 3'd1; phase <= 2'd0; end
                end
                2'd3: begin
                    current <= result;
                    x2[section] <= x1[section]; x1[section] <= section_in;
                    y2[section] <= y1[section]; y1[section] <= result;
                    if (section == 3'(SECTIONS - 1)) begin
                        sample <= out_over ? 16'sh7FFF : out_under ? 16'sh8000 : scaled[15:0];
                        if (out_over || out_under) clipped <= 1'b1;
                        valid <= 1'b1;
                        busy <= 1'b0;
                    end else begin
                        section <= section + 3'd1; term <= 3'd0; phase <= 2'd0;
                        accumulator <= 76'sd0;
                    end
                end
            endcase
        end
    end
endmodule
