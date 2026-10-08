// SPDX-License-Identifier: GPL-3.0-or-later
// Clock enables for the one 57.272727 MHz system clock, four times the
// board's 14.318 MHz crystal. Each enable is high for one clk_sys in its
// period.
//
// The board divides the crystal with a free-running 74LS163 (62D): QB is
// 3.58 MHz, QC 1.79 MHz and QD 894.9 kHz, the clock of the MSM6295 and the
// LETA. The counter here is that divider extended two bits downwards.
module shuuz_clocks(
    input  wire clk_sys,
    input  wire reset,
    output wire ce_14m,   // crystal rate
    output wire ce_14m_n, // the crystal clock's falling edge
    output wire ce_7m,    // 68000 and pixel clock
    output wire ce_3m58,  // 62D QB
    output wire ce_1m79,  // 62D QC
    output wire ce_pcm    // 62D QD, 894.886 kHz
);
    reg [5:0] phase;
    always @(posedge clk_sys) begin
        if (reset) phase <= 6'd0;
        else       phase <= phase + 6'd1;
    end
    assign ce_14m  = !reset && phase[1:0] == 2'd3;
    assign ce_14m_n = !reset && phase[1:0] == 2'd1;
    assign ce_7m   = !reset && phase[2:0] == 3'd7;
    assign ce_3m58 = !reset && phase[3:0] == 4'd15;
    assign ce_1m79 = !reset && phase[4:0] == 5'd31;
    assign ce_pcm  = !reset && phase      == 6'd63;
endmodule
