// SPDX-License-Identifier: GPL-3.0-or-later
// The I/O block at 105000 and the trackball counters at 103000.
//
// Reads go through one 74LS257 (28A), selected by address line 1:
//   105000: bit 11 /VIDBL, bit 0 left coin, bit 1 right coin
//   105002: bit 11 self-test switch, bit 0 left button, bit 1 right button
// Its fourth section carries two JAMMA pins the Shuuz harness leaves open.
// The other two multiplexers on the drawing are not fitted, so the remaining
// data lines are not driven on a read. rdrive marks the driven bits.
//
// Writes clock a 74LS174 (15A) from data lines 13-8 at the end of the write:
//   13 motor enable, 12 VCR power, 11 and 10 coin counters, 9 /AUDRES,
//   8 /PCMRES (0 holds the sound chip in reset). Reset clears it.
//
// The LETA (47F) counts the two trackball axes: channel 0 is the Y coupler,
// channel 1 the X coupler. Its clock is the 895 kHz sound clock, and its TEST
// and RESOL pins are grounded. All switches are 0 = closed.
module shuuz_inputs #(
    parameter int SPARE_BIT = 2        // data line of the fourth mux section
)(
    input  wire        clk,
    input  wire        sysres_n,
    input  wire        ce_pcm,
    input  wire        ma1,
    input  wire        latch_n,        // write to 105000
    input  wire [15:0] wdata,
    input  wire        leta_n,

    input  wire        vidbl_n,
    input  wire        self_test_n,
    input  wire        coin1_n, coin2_n,
    input  wire        lbutton_n, rbutton_n,
    input  wire        fire1_n, acta2_n,          // not wired in the Shuuz harness
    input  wire        xclk, xdir, yclk, ydir,    // trackball coupler outputs

    output wire [15:0] sw_rdata,       // valid while /SWITCH is low
    output wire [15:0] sw_rdrive,
    output wire  [7:0] leta_rdata,

    output reg         motor_ena,
    output reg         vcr_power,
    output reg   [1:0] coin_counter,
    output reg         audres_n,
    output reg         pcmres_n
);
    // ---- 28A ----
    wire y1 = ma1 ? self_test_n : vidbl_n;
    wire y2 = ma1 ? lbutton_n   : coin1_n;
    wire y3 = ma1 ? rbutton_n   : coin2_n;
    wire y4 = ma1 ? acta2_n     : fire1_n;
    assign sw_rdrive = 16'h0803 | (16'd1 << SPARE_BIT);
    assign sw_rdata  = {4'd0, y1, 9'd0, y3, y2} | ({15'd0, y4} << SPARE_BIT);

    // ---- 15A: clocked by the rising edge of /LATCH ----
    reg        latch_q;
    reg [13:8] held;
    always @(posedge clk) begin
        latch_q <= latch_n;
        if (!latch_n) held <= wdata[13:8];
        if (!sysres_n) begin
            {motor_ena, vcr_power, coin_counter, audres_n, pcmres_n} <= 6'd0;
        end else if (latch_n && !latch_q) begin
            {motor_ena, vcr_power, coin_counter, audres_n, pcmres_n} <= held;
        end
    end

    // ---- 47F ----
    wire unused_leta = leta_n;
    shuuz_leta u_leta(.clk(clk), .ck(ce_pcm), .test(1'b0), .resol(1'b0),
        .ad({1'b0, ma1}), .clks({2'b00, xclk, yclk}), .dirs({2'b00, xdir, ydir}),
        .dout(leta_rdata));

    wire unused = &{1'b0, wdata[15:14], wdata[7:0], unused_leta};
endmodule
