// SPDX-License-Identifier: GPL-3.0-or-later
// The processor side of the game board: 68000, program ROM, address decode,
// wait states, interrupts, watchdog, EEPROM and the I/O block. The video
// section and the sound chip connect through ports.
//
// Address map (address lines 23 and 22 are not connected):
//   000000-03FFFF  program ROM
//   100000  EEPROM (low byte)        101000  EEPROM unlock
//   102000  watchdog                 103000  trackball counters (low byte)
//   105000  switches / output latch  106000  sound chip (low byte)
//   107000  the YM2149 site, not fitted: the cycle runs, nothing answers
//   3E0000-3FFFFF  the video section
// The eight I/O strobes ignore address line 15. A data line nothing drives
// reads as 1.
module shuuz_main #(
    parameter int CLK_HZ  = 57272727,
    parameter int EEPROM_WRITE_CYCLES = CLK_HZ / 100
)(
    input  wire        clk,
    input  wire        init_reset,         // FPGA start-up and ROM download
    input  wire        ce_7m,              // the 68000 clock
    input  wire        ce_14m_n,           // falling edge of the 14.318 MHz clock
    input  wire        ce_pcm,

    // program ROM download
    input  wire        dl_we,
    input  wire [17:0] dl_addr,
    input  wire  [7:0] dl_data,

    // video section
    input  wire        vblank,
    input  wire        vidbl_n,
    input  wire        vint_n,
    input  wire        vdtack_n,
    input  wire [15:0] video_rdata,
    output wire        vvram_n,            // the bus strobes as the video section sees them
    output wire        vuds_n,
    output wire        vlds_n,

    // sound chip
    input  wire  [7:0] pcm_rdata,
    output wire        pcmrd_n,
    output wire        pcmwr_n,
    output wire        pcmres_n,

    // cabinet
    input  wire        self_test_n,
    input  wire        coin1_n, coin2_n,
    input  wire        lbutton_n, rbutton_n,
    input  wire        xclk, xdir, yclk, ydir,
    input  wire        wdis,
    output wire  [1:0] coin_counter,
    output wire        motor_ena,

    // EEPROM image load and save
    input  wire        nv_load_we,
    input  wire [10:0] nv_load_addr,
    input  wire  [7:0] nv_load_data,
    input  wire        nv_load_end,
    input  wire [10:0] nv_dump_addr,
    output wire  [7:0] nv_dump_data,
    output wire        nv_write_accepted,

    // the bus, for the video section and for observation
    output wire [23:1] a,
    output wire [15:0] wdata,              // as driven on the board's data lines
    output wire [15:0] rdata,
    output wire        as_n,
    output wire        uds_n,
    output wire        lds_n,
    output wire        rw,
    output wire        dtack_n,
    output wire  [2:0] fc,
    output wire  [2:0] ipl_n,
    output wire        sysres_n,
    output wire        ce_cpu
);
    // ---- reset and watchdog ----
    wire wdog_n;
    wire [3:0] wdog_count;
    shuuz_watchdog #(.CLK_HZ(CLK_HZ)) u_watchdog(.clk(clk), .ext_reset(init_reset),
        .vblank(vblank), .wdog_n(wdog_n), .wdis(wdis), .sysres_n(sysres_n),
        .count(wdog_count));

    // ---- interrupts: level 4 from the video section, autovectored ----
    wire sint_n = 1'b1;                    // only the unfitted sound header drives it
    assign ipl_n = {vint_n & sint_n, sint_n, 1'b1};
    wire bas   = !as_n;
    wire vpa_n = !(bas && fc == 3'b111);

    // ---- processor ----
    wire [15:0] cpu_wdata;
    shuuz_cpu #(.CPU_14M(1'b0)) u_cpu(.clk(clk), .ce_14m(1'b0), .ce_7m(ce_7m),
        .reset(!sysres_n), .ipl_n(ipl_n), .a(a), .wdata(cpu_wdata), .rdata(rdata),
        .as_n(as_n), .uds_n(uds_n), .lds_n(lds_n), .rw(rw), .dtack_n(dtack_n),
        .vpa_n(vpa_n), .fc(fc), .ce_cpu(ce_cpu));
    // A 68000 writing one byte puts it on both halves of the data bus.
    assign wdata = (!uds_n &&  lds_n) ? {2{cpu_wdata[15:8]}} :
                   ( uds_n && !lds_n) ? {2{cpu_wdata[7:0]}}  : cpu_wdata;

    // ---- address decode: the GAL at 55C and the 74LS138 at 55B ----
    wire [19:12] dec;
    shuuz_gal_1050 u_decode(.pin({10'd0, a[14], a[15], a[16], a[17], a[18], a[19], a[20],
                                  a[21], bas}), .value(dec));
    wire rom0_n = dec[19];
    wire vram_n = dec[16];
    wire io_en  = bas && !dec[14];
    wire eeprom_n = !(io_en && a[14:12] == 3'd0);
    wire unlock_n = !(io_en && a[14:12] == 3'd1);
    assign wdog_n = !(io_en && a[14:12] == 3'd2);
    wire leta_n   = !(io_en && a[14:12] == 3'd3);
    wire par_n    = !(io_en && a[14:12] == 3'd5);
    wire pcm_n    = !(io_en && a[14:12] == 3'd6);
    wire y_n      = !(io_en && a[14:12] == 3'd7);

    // ---- strobes ----
    wire wl_n     = rw || lds_n;
    wire latch_n  = rw || par_n;
    wire switch_n = par_n || !rw;

    // ---- wait states ----
    wire ctr_dtack_n;
    wire [3:0] wait_count;
    shuuz_dtack u_dtack(.clk(clk), .ce_cpu(ce_cpu), .as_n(as_n), .eeprom_n(eeprom_n),
        .slow_n(leta_n && pcm_n && y_n), .vram_n(vram_n), .vpa_n(vpa_n),
        .dtack_n(ctr_dtack_n), .count(wait_count));
    assign dtack_n = vdtack_n && ctr_dtack_n;

    // ---- the GAL at 45E: strobes for the video section, one clock late ----
    wire [19:12] g45;
    shuuz_gal_1051 u_45e(.clk(clk), .ce(ce_14m_n), .reset(init_reset),
        .pin({10'd0, vram_n, uds_n, lds_n, rw, ctr_dtack_n, a[1], a[2], y_n, 1'b0}),
        .value(g45));
    // The video section does not answer an interrupt acknowledge.
    assign vvram_n = g45[19] || fc == 3'b111;
    assign vuds_n  = g45[18];
    assign vlds_n  = g45[17];

    // ---- sound chip strobes ----
    assign pcmrd_n = pcm_n || !rw;
    assign pcmwr_n = ctr_dtack_n || pcm_n || rw || lds_n;

    // ---- program ROM: output enable is W//R, so it drives on reads only ----
    wire rom_sel = !rom0_n && rw && fc != 3'b111;
    wire [15:0] rom_q;
    shuuz_prog_rom u_rom(.clk(clk), .addr(a[17:1]), .q(rom_q),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data));

    // ---- write data and address held past the end of the cycle ----
    reg [15:0] wdata_q;
    reg        wl_q, ee_in_window;
    reg [10:0] ee_addr;
    always @(posedge clk) begin
        wl_q <= wl_n;
        if (!as_n) wdata_q <= rw ? 16'hFFFF : wdata;
        if (!wl_n) ee_in_window <= !eeprom_n;
        if (!eeprom_n) ee_addr <= a[11:1];
    end
    wire wl_rise = wl_n && !wl_q;

    // ---- I/O block ----
    wire [15:0] sw_rdata, sw_rdrive;
    wire  [7:0] leta_rdata;
    wire        vcr_power, audres_n;
    shuuz_inputs u_inputs(.clk(clk), .sysres_n(sysres_n), .ce_pcm(ce_pcm), .ma1(a[1]),
        .latch_n(latch_n), .wdata(wdata), .leta_n(leta_n),
        .vidbl_n(vidbl_n), .self_test_n(self_test_n), .coin1_n(coin1_n), .coin2_n(coin2_n),
        .lbutton_n(lbutton_n), .rbutton_n(rbutton_n), .fire1_n(1'b1), .acta2_n(1'b1),
        .xclk(xclk), .xdir(xdir), .yclk(yclk), .ydir(ydir),
        .sw_rdata(sw_rdata), .sw_rdrive(sw_rdrive), .leta_rdata(leta_rdata),
        .motor_ena(motor_ena), .vcr_power(vcr_power), .coin_counter(coin_counter),
        .audres_n(audres_n), .pcmres_n(pcmres_n));

    // ---- EEPROM: the unlock flop drives its output enable ----
    wire [7:0] ee_q;
    wire ee_busy, ee_oe_n, ee_unlocked;
    shuuz_eeprom_28c16 #(.CLK_HZ(CLK_HZ), .WRITE_CYCLES(EEPROM_WRITE_CYCLES)) u_eeprom(
        .clk(clk), .init_reset(init_reset), .reset(!sysres_n), .unlock(!unlock_n),
        .any_write(wl_rise), .cpu_we(wl_rise && ee_in_window), .cpu_addr(ee_addr),
        .cpu_wdata(wdata_q[7:0]), .cpu_rdata(ee_q), .busy(ee_busy), .oe_n(ee_oe_n),
        .unlocked(ee_unlocked), .write_accepted(nv_write_accepted),
        .load_we(nv_load_we), .load_addr(nv_load_addr), .load_data(nv_load_data),
        .seed_we(1'b0), .load_end(nv_load_end),
        .dump_addr(nv_dump_addr), .dump_data(nv_dump_data));

    // ---- read data: anything not driven reads as ones ----
    assign rdata = rom_sel             ? rom_q :
                   !vvram_n            ? video_rdata :
                   (!eeprom_n && rw)   ? {8'hFF, ee_q} :
                   !leta_n             ? {8'hFF, leta_rdata} :
                   !switch_n           ? (sw_rdata | ~sw_rdrive) :
                   !pcmrd_n            ? {8'hFF, pcm_rdata} : 16'hFFFF;

    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = &{1'b0, dec, g45, wdog_count, wait_count, ee_busy, ee_oe_n, ee_unlocked,
                    vcr_power, audres_n, a[23:22]};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
