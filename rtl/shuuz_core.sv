// SPDX-License-Identifier: GPL-3.0-or-later
// Shuuz: the game board and the memories that stand in for its ROMs.
// Everything runs on clk_sys = 57.272727 MHz with clock enables. Switch
// inputs are as the board sees them: 0 = closed.
//
module shuuz_core #(
    parameter int EEPROM_WRITE_CYCLES = 57272727 / 100
)(
    input  wire        clk_sys,
    input  wire        init_reset,     // PLL not locked: also restarts the SDRAM
    input  wire        reset,          // user reset

    // MiSTer file channels: index 0 is the ROM stream (layout in
    // shuuz_loader.sv), index 2 the EEPROM save file
    input  wire        ioctl_download,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire  [7:0] ioctl_dout,
    input  wire [15:0] ioctl_index,
    output wire        ioctl_wait,
    input  wire        ioctl_upload,
    output wire        ioctl_upload_req,
    output wire  [7:0] ioctl_upload_index,
    output wire  [7:0] ioctl_din,
    output reg         rom_loaded,

    // cabinet
    input  wire        self_test_n,
    input  wire        coin1_n, coin2_n,
    input  wire        lbutton_n, rbutton_n,
    input  wire        xclk, xdir, yclk, ydir,     // trackball coupler outputs
    input  wire        wdis,                       // watchdog disable jumper
    output wire  [1:0] coin_counter,
    output wire        motor_ena,

    // picture
    output wire        ce_pix,
    output wire  [7:0] vga_r, vga_g, vga_b,
    output wire        hsync, vsync, hblank, vblank,
    output wire  [9:0] pix_index,      // colour RAM address of the pixel shown
    output wire [15:0] pix_colour,     // and the colour RAM word read there

    // sound: the output of the board's summing stage
    output wire signed [15:0] audio,

    // diagnostics for the simulations; left open in the MiSTer build
    output wire signed [15:0] pcm_code,   // MSM6295 output, 12 bits times 16
    output wire        pcm_stb,           // one clock for each new pcm_code
    output wire        snd_late,          // a sample or a filter step came late
    output wire        gfx_late, eof_late,
    output wire  [8:0] beam_h, beam_v,
    output wire [23:1] cpu_a,
    output wire [15:0] cpu_wdata, cpu_rdata,
    output wire        cpu_as_n, cpu_uds_n, cpu_lds_n, cpu_rw, cpu_dtack_n,
    output wire  [2:0] cpu_fc,
    output wire        sysres_n,

    inout  wire [15:0] SDRAM_DQ,
    output wire [12:0] SDRAM_A,
    output wire  [1:0] SDRAM_BA,
    output wire        SDRAM_DQML, SDRAM_DQMH, SDRAM_CKE, SDRAM_nCS,
    output wire        SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE
);
    localparam logic [26:0] STREAM_BYTES = 27'h200000;

    // ---- download ----
    wire downloading = ioctl_download && ioctl_index == 16'd0;
    wire ld_wr = downloading && ioctl_wr && ioctl_addr < STREAM_BYTES;
    wire ld_busy, prog_we, rom_wr, rom_ack;
    wire [19:0] rom_addr;
    wire [15:0] rom_data;
    shuuz_loader u_loader(.clk(clk_sys), .reset(init_reset), .wr(ld_wr), .addr(ioctl_addr[20:0]),
        .data(ioctl_dout), .busy(ld_busy), .prog_we(prog_we),
        .rom_wr(rom_wr), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ack(rom_ack));

    wire        pf_req, pf_ack, mo_req, mo_ack, snd_req, snd_ack;
    wire [17:0] snd_addr;
    wire [16:0] pf_addr;
    wire [17:0] mo_addr;
    wire [31:0] pf_row, mo_row;
    wire  [7:0] snd_data;
    wire        sd_req, sd_we, sd_ready, sd_valid, rfsh_ok, mem_idle;
    wire [23:0] sd_addr;
    wire [15:0] sd_wdata, sd_rdata;
    wire  [2:0] sd_blen;
    shuuz_rom_mem u_rom(.clk(clk_sys), .reset(init_reset),
        .dl_wr(rom_wr), .dl_addr(rom_addr), .dl_data(rom_data), .dl_ack(rom_ack),
        .pf_req(pf_req), .pf_addr(pf_addr), .pf_ack(pf_ack), .pf_row(pf_row),
        .mo_req(mo_req), .mo_addr(mo_addr), .mo_ack(mo_ack), .mo_row(mo_row),
        .snd_req(snd_req), .snd_addr(snd_addr), .snd_ack(snd_ack), .snd_data(snd_data),
        .sd_req(sd_req), .sd_we(sd_we), .sd_addr(sd_addr), .sd_wdata(sd_wdata),
        .sd_blen(sd_blen), .sd_ready(sd_ready), .sd_valid(sd_valid), .sd_rdata(sd_rdata),
        .rfsh_ok(rfsh_ok), .idle(mem_idle));
    shuuz_sdram u_sdram(.clk(clk_sys), .reset(init_reset), .addr(sd_addr),
        .wdata(sd_wdata), .we(sd_we), .blen(sd_blen), .req(sd_req), .rdata(sd_rdata),
        .valid(sd_valid), .ready(sd_ready), .rfsh_ok(rfsh_ok),
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_nWE(SDRAM_nWE));
    assign ioctl_wait = ld_busy || !sd_ready;

    // The game starts only after one complete, in-order download.
    reg [26:0] received;
    reg        was_download, bad_download;
    always @(posedge clk_sys) begin
        if (init_reset) begin
            received <= 27'd0; was_download <= 1'b0; bad_download <= 1'b0; rom_loaded <= 1'b0;
        end else begin
            was_download <= downloading;
            if (downloading && !was_download) begin
                received <= 27'd0; bad_download <= 1'b0; rom_loaded <= 1'b0;
            end
            if (downloading && ioctl_wr) begin
                if (ioctl_addr != (was_download ? received : 27'd0) || ioctl_addr >= STREAM_BYTES)
                    bad_download <= 1'b1;
                received <= ioctl_addr + 27'd1;
            end
            if (!downloading && received == STREAM_BYTES && !bad_download && !ld_busy
                && mem_idle) rom_loaded <= 1'b1;
        end
    end
    wire hold = init_reset || reset || downloading || !rom_loaded;

    // ---- EEPROM save file ----
    wire        nv_load_we, nv_seed_we, nv_load_end, nv_write_accepted;
    wire [10:0] nv_load_addr, nv_dump_addr;
    wire  [7:0] nv_load_data, nv_dump_data;
    shuuz_nvram_io u_nvram(.clk(clk_sys), .init_reset(init_reset),
        .write_accepted(nv_write_accepted),
        .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index), .ioctl_upload(ioctl_upload),
        .load_we(nv_load_we), .load_addr(nv_load_addr), .load_data(nv_load_data),
        .seed_we(nv_seed_we), .load_end(nv_load_end),
        .dump_addr(nv_dump_addr), .dump_data(nv_dump_data),
        .ioctl_upload_req(ioctl_upload_req), .ioctl_upload_index(ioctl_upload_index),
        .ioctl_din(ioctl_din));

    // ---- clocks ----
    wire ce_14m, ce_14m_n, ce_7m, ce_3m58, ce_1m79, ce_pcm;
    shuuz_clocks u_clocks(.clk_sys(clk_sys), .reset(init_reset), .ce_14m(ce_14m),
        .ce_14m_n(ce_14m_n), .ce_7m(ce_7m), .ce_3m58(ce_3m58), .ce_1m79(ce_1m79),
        .ce_pcm(ce_pcm));

    // ---- game board ----
    wire        vblank_board, hblank_board, vidbl_n, vint_n, vdtack_n;
    wire        vvram_n, vuds_n, vlds_n;
    wire [15:0] video_rdata;
    wire        pcmrd_n, pcmwr_n, pcmres_n, ce_cpu;
    wire  [7:0] pcm_rdata;
    wire  [2:0] ipl_n;
    shuuz_main #(.EEPROM_WRITE_CYCLES(EEPROM_WRITE_CYCLES)) u_main(
        .clk(clk_sys), .init_reset(hold), .ce_7m(ce_7m), .ce_14m_n(ce_14m_n), .ce_pcm(ce_pcm),
        .dl_we(prog_we), .dl_addr(ioctl_addr[17:0]), .dl_data(ioctl_dout),
        .vblank(vblank_board), .vidbl_n(vidbl_n), .vint_n(vint_n), .vdtack_n(vdtack_n),
        .video_rdata(video_rdata), .vvram_n(vvram_n), .vuds_n(vuds_n), .vlds_n(vlds_n),
        .pcm_rdata(pcm_rdata), .pcmrd_n(pcmrd_n), .pcmwr_n(pcmwr_n), .pcmres_n(pcmres_n),
        .self_test_n(self_test_n), .coin1_n(coin1_n), .coin2_n(coin2_n),
        .lbutton_n(lbutton_n), .rbutton_n(rbutton_n),
        .xclk(xclk), .xdir(xdir), .yclk(yclk), .ydir(ydir), .wdis(wdis),
        .coin_counter(coin_counter), .motor_ena(motor_ena),
        .nv_load_we(nv_load_we), .nv_load_addr(nv_load_addr), .nv_load_data(nv_load_data),
        .nv_load_end(nv_load_end), .nv_dump_addr(nv_dump_addr), .nv_dump_data(nv_dump_data),
        .nv_write_accepted(nv_write_accepted),
        .a(cpu_a), .wdata(cpu_wdata), .rdata(cpu_rdata), .as_n(cpu_as_n),
        .uds_n(cpu_uds_n), .lds_n(cpu_lds_n), .rw(cpu_rw), .dtack_n(cpu_dtack_n),
        .fc(cpu_fc), .ipl_n(ipl_n), .sysres_n(sysres_n), .ce_cpu(ce_cpu));

    shuuz_video u_video(.clk(clk_sys), .reset(hold), .ce_14m(ce_14m),
        .select_n(vvram_n), .rw(cpu_rw), .uds_n(vuds_n), .lds_n(vlds_n), .a(cpu_a[16:1]),
        .wdata(cpu_wdata), .rdata(video_rdata), .vdtack_n(vdtack_n), .vint_n(vint_n),
        .snap_wr(1'b0), .snap_cr(1'b0), .snap_a(15'd0), .snap_d(16'd0),
        .pf_req(pf_req), .pf_addr(pf_addr), .pf_ack(pf_ack), .pf_row(pf_row),
        .mo_req(mo_req), .mo_addr(mo_addr), .mo_ack(mo_ack), .mo_row(mo_row),
        .ce_pix(ce_pix), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
        .pix_index(pix_index), .pix_colour(pix_colour),
        .hblank_board(hblank_board), .vblank_board(vblank_board), .vidbl_n(vidbl_n),
        .beam_h(beam_h), .beam_v(beam_v), .gfx_late(gfx_late), .eof_late(eof_late));

    // ---- sound ----
    // MSM6295 75D: chip select tied active, so the two strobes time each
    // access. Its sample ROMs 75B and 65B are one 256 KB block, 75B first.
    wire oki_late, filter_late, filter_valid, filter_clipped;
    shuuz_oki u_oki(.clk(clk_sys), .ce_pcm(ce_pcm), .okires_n(pcmres_n && !hold),
        .wr_stb(!pcmwr_n), .wr_data(cpu_wdata[7:0]), .rd_data(pcm_rdata),
        .oki_req(snd_req), .oki_addr(snd_addr), .oki_ack(snd_ack), .oki_data(snd_data),
        .audio_stb(pcm_stb), .late(oki_late), .audio(pcm_code));
    shuuz_audio u_audio(.clk(clk_sys), .reset(hold), .ce_pcm(ce_pcm), .dac(pcm_code[15:4]),
        .sample(audio), .valid(filter_valid), .late(filter_late), .clipped(filter_clipped));
    assign snd_late = oki_late || filter_late;

    wire unused = &{1'b0, ce_3m58, ce_1m79, nv_seed_we, hblank_board, pcmrd_n, ce_cpu, ipl_n,
                    filter_valid, filter_clipped};
endmodule
