// SPDX-License-Identifier: GPL-3.0-or-later
// 68000 at 30C: fx68k with its two clock-phase enables.
// Taken from the Off the Wall MiSTer core's offtwall_cpu.sv (after Batman's)
// with the module renamed.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// CPU_14M picks the processor clock: 1 = 14.318 MHz, 0 = 7.159 MHz. This
// board runs an 8 MHz part at 7.159 MHz.
module shuuz_cpu #(
    parameter bit CPU_14M = 1'b1
)(
    input  wire        clk,
    input  wire        ce_14m,
    input  wire        ce_7m,
    input  wire        reset,
    input  wire  [2:0] ipl_n,
    output wire [23:1] a,
    output wire [15:0] wdata,
    input  wire [15:0] rdata,
    output wire        as_n,
    output wire        uds_n,
    output wire        lds_n,
    output wire        rw,
    input  wire        dtack_n,
    input  wire        vpa_n,
    output wire  [2:0] fc,
    output wire        ce_cpu     // rising edge of the processor clock
);
    assign ce_cpu = CPU_14M ? ce_14m : ce_7m;

    // The falling edge is half a period after the rising one.
    reg [2:0] count;
    always @(posedge clk) begin
        if (ce_cpu) count <= 3'd1;
        else        count <= count + 3'd1;
    end
    wire en_phi2 = CPU_14M ? (count == 3'd2) : (count == 3'd4);

    // Two flops on the interrupt inputs, as any synchronous design needs.
    reg [2:0] ipl_a, ipl_b;
    always @(posedge clk) begin
        if (reset) begin
            ipl_a <= 3'b111;
            ipl_b <= 3'b111;
        end else begin
            ipl_a <= ipl_n;
            ipl_b <= ipl_a;
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    wire e, vma_n, bg_n, reset_out_n, halted_n;   // not connected on the board
    /* verilator lint_on UNUSEDSIGNAL */

    fx68k u_fx68k(
        .clk(clk), .HALTn(1'b1), .extReset(reset), .pwrUp(reset),
        .enPhi1(ce_cpu), .enPhi2(en_phi2),
        .eRWn(rw), .ASn(as_n), .LDSn(lds_n), .UDSn(uds_n), .E(e), .VMAn(vma_n),
        .FC0(fc[0]), .FC1(fc[1]), .FC2(fc[2]), .BGn(bg_n),
        .oRESETn(reset_out_n), .oHALTEDn(halted_n),
        .DTACKn(dtack_n), .VPAn(vpa_n), .BERRn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
        .IPL0n(ipl_b[0]), .IPL1n(ipl_b[1]), .IPL2n(ipl_b[2]),
        .iEdb(rdata), .oEdb(wdata), .eab(a));
endmodule
