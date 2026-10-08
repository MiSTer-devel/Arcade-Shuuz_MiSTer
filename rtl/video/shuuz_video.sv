// SPDX-License-Identifier: GPL-3.0-or-later
// The video section at 3E0000-3FFFFF: colour RAM, the VAD's registers and
// video RAM schedule, one playfield, the motion objects and their line
// buffer, the priority GAL and the DAC. Adapted from the Off the Wall MiSTer
// core's offtwall_video.sv: this board's mixer, colour RAM size, playfield
// stamp width and blanking output. Adapted there from the Relief Pitcher
// and Batman video models.
// Copyright (C) 2026 the Batman MiSTer core authors.
`timescale 1ns/1ps
module shuuz_video #(
    parameter int PF_XOFF    = 0,
    parameter int PIPE       = 2,       // pixel stages between the layers and the DAC
    parameter int MO_BUDGET  = 456,     // video RAM words the MOB may read per line
    parameter bit MO_ENABLE  = 1'b1,
    parameter bit REPLAY     = 1'b1,    // see shuuz_vad_regs
    parameter int H_TOTAL    = 912,     // 14.318 MHz periods per line
    parameter int H_VISIBLE  = 336
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_14m,
    // processor bus
    input  wire        select_n,    // 3E0000-3FFFFF, not during interrupt acknowledge
    input  wire        rw,
    input  wire        uds_n,
    input  wire        lds_n,
    input  wire [16:1] a,
    input  wire [15:0] wdata,
    output wire [15:0] rdata,
    output wire        vdtack_n,
    output wire        vint_n,
    // simulation preload of video RAM (cr = 0) and colour RAM (cr = 1)
    input  wire        snap_wr,
    input  wire        snap_cr,
    input  wire [14:0] snap_a,
    input  wire [15:0] snap_d,
    // graphics ROM readers: stamp row address, four bytes back
    output wire        pf_req,
    output wire [16:0] pf_addr,
    input  wire        pf_ack,
    input  wire [31:0] pf_row,
    output wire        mo_req,
    output wire [17:0] mo_addr,
    input  wire        mo_ack,
    input  wire [31:0] mo_row,
    // picture
    output wire        ce_pix,
    output wire  [7:0] vga_r, vga_g, vga_b,
    output wire        hsync, vsync, hblank, vblank,
    output wire  [9:0] pix_index,   // colour RAM address of the pixel on vga_*
    output wire [15:0] pix_colour,  // and the colour RAM word read there
    // board timing and diagnostics
    output wire        hblank_board,
    output wire        vblank_board,
    output wire        vidbl_n,     // low during horizontal or vertical blanking
    output wire  [8:0] beam_h, beam_v,
    output reg         gfx_late,    // sticky: a layer missed its fetch
    output wire        eof_late     // sticky: the reload ran into the picture
);
    wire        acc     = !select_n;
    wire        is_vr   = a[16];
    wire        is_reg  = !a[16] && a[15:6] == 10'h3FF;
    wire        is_cr   = !a[16] && a[15:11] == 5'd0;      // 3E0000-3E07FF
    wire        is_alias = a[16] && a[15:8] == 8'hCF && a[6];
    wire  [1:0] cpu_ds  = {!uds_n, !lds_n};
    wire        cpu_wr  = acc && !rw && (!uds_n || !lds_n);
    wire        acc_arr = acc && (rw || cpu_wr);
    reg reg_written;
    always @(posedge clk) begin
        if (reset || !acc) reg_written <= 1'b0;
        else if (cpu_wr && (is_reg || is_alias)) reg_written <= 1'b1;
    end

    wire [15:0] reg_vsy, reg_vbl, reg_vint, reg_hsy, reg_hbl;
    wire [15:0] reg_pmbase, reg_albase, reg_opt, reg_dout;
    wire  [8:0] mo_xscroll, mo_yscroll, mo_xoffset, pf_xscroll, pf_yscroll;
    wire  [7:0] pf_attr_latch;
    wire        vad_enable, dma_enable, irq_arm, irq_ack;
    wire        eof_req, eof_ack;
    wire  [5:0] eof_idx;
    wire [15:0] eof_data;
    wire  [9:0] h, hd, hpos;
    wire  [8:0] v, vpos, v_next;
    wire        hsync_n, vsync_n, hblank_i, vblank_i, hde, vde;
    wire        line_start, frame_start, vblank_start, eof_window;

    shuuz_vad_regs #(.REPLAY(REPLAY)) u_regs(
        .clk(clk), .reset(reset),
        .cpu_cs(acc && is_reg), .cpu_we(cpu_wr && is_reg && !reg_written),
        .alias_we(cpu_wr && is_alias && !reg_written),
        .cpu_a(a[5:1]), .cpu_din(wdata), .cpu_ds(cpu_ds), .cpu_dout(reg_dout),
        .vpos(v), .vblank(vblank_i), .vblank_start(vblank_start),
        .eof_req(eof_req), .eof_idx(eof_idx), .eof_data(eof_data), .eof_ack(eof_ack),
        .reg_vsy(reg_vsy), .reg_vbl(reg_vbl), .reg_vint(reg_vint),
        .reg_hsy(reg_hsy), .reg_hbl(reg_hbl),
        .reg_pmbase(reg_pmbase), .reg_albase(reg_albase), .reg_opt(reg_opt),
        .mo_xscroll(mo_xscroll), .mo_yscroll(mo_yscroll), .mo_xoffset(mo_xoffset),
        .pf_xscroll(pf_xscroll), .pf_yscroll(pf_yscroll),
        .pf_attr_latch(pf_attr_latch),
        .vad_enable(vad_enable), .dma_enable(dma_enable),
        .irq_arm(irq_arm), .irq_ack(irq_ack));

    shuuz_vad_sync #(.H_TOTAL(H_TOTAL), .H_VISIBLE(H_VISIBLE)) u_sync(
        .clk(clk), .reset(reset), .ce_14m(ce_14m), .vad_enable(vad_enable),
        .reg_vsy(reg_vsy), .reg_vbl(reg_vbl), .reg_vint(reg_vint),
        .reg_hsy(reg_hsy), .reg_hbl(reg_hbl),
        .irq_arm(irq_arm), .irq_ack(irq_ack),
        .h(h), .v(v), .hd(hd),
        .hsync_n(hsync_n), .vsync_n(vsync_n), .hblank(hblank_i), .vblank(vblank_i),
        .hde(hde), .vde(vde), .hpos(hpos), .vpos(vpos), .v_next(v_next),
        .line_start(line_start), .frame_start(frame_start),
        .vblank_start(vblank_start), .eof_window(eof_window), .vint_n(vint_n));

    wire       pix_half = hd[0];
    wire       ce_7m    = ce_14m && hd[0];
    wire [8:0] px       = hd[9:1];
    wire       blank    = hblank_i || vblank_i;
    assign ce_pix = ce_7m;

    // Register fields: bases are word indices into video RAM.
    wire [14:0] base_pf   = {reg_pmbase[15:13], 12'b0};
    wire [14:0] base_attr = {reg_pmbase[9:7],   12'b0};
    wire [14:0] base_mo   = {reg_pmbase[5:1],   10'b0};
    wire [14:0] base_slip = {reg_albase[9:6],   11'b0} | {3'b000, reg_albase[5:0], 6'b0};
    wire        oas_en    = reg_opt[7];
    wire        ovrdtack  = reg_opt[5];
    wire        ocrdtack  = reg_opt[4];
    wire        o_dcdma   = reg_opt[10];

    wire [14:0] a_pfc, a_pfa, mo_vram_a, dma_a, as_a, cpu_wr_a;
    wire [15:0] q_pfc, q_pfa, mo_vram_q, dma_q, as_d, vr_dout;
    wire        mo_vram_rd, mo_vram_ack, dma_rq, dma_ack, as_req;
    wire  [1:0] as_ds;
    wire        vr_grant, cpu_wr_stb, layer_late;
    wire [10:0] mo_words_line, cpu_words_line, dma_words_line, eof_words;
    wire [15:0] cpu_wait_worst;
    shuuz_vram u_vram(
        .clk(clk), .reset(reset), .ce_14m(ce_14m), .hd(hd), .blank(blank),
        .pf_code_a(a_pfc), .pf_attr_a(a_pfa), .pf_code_q(q_pfc), .pf_attr_q(q_pfa),
        .mo_req(mo_vram_rd), .mo_a(mo_vram_a), .mo_ack(mo_vram_ack), .mo_q(mo_vram_q),
        .dma_req(dma_rq), .dma_we(1'b0), .dma_a(dma_a), .dma_d(16'd0),
        .dma_ack(dma_ack), .dma_q(dma_q),
        .cpu_cs(acc_arr && is_vr), .cpu_we(cpu_wr && is_vr), .cpu_ds(cpu_ds),
        .cpu_a(a[15:1]), .cpu_din(wdata), .cpu_dout(vr_dout),
        .cpu_grant(vr_grant), .ovrdtack(ovrdtack), .iack(1'b0),
        .cpu_wr_stb(cpu_wr_stb), .cpu_wr_a(cpu_wr_a),
        .as_req(as_req), .as_a(as_a), .as_d(as_d), .as_ds(as_ds),
        .init_wr(snap_wr && !snap_cr), .init_a(snap_a), .init_d(snap_d),
        .mo_words_line(mo_words_line), .cpu_words_line(cpu_words_line),
        .dma_words_line(dma_words_line), .cpu_wait_worst(cpu_wait_worst),
        .layer_late(layer_late));

    shuuz_vad_dma u_dma(
        .clk(clk), .reset(reset),
        .line_start(line_start), .vpos(v), .vblank(vblank_i),
        .dma_enable(dma_enable), .oas_en(oas_en),
        .base_pf(base_pf), .base_attr(base_attr), .base_slip(base_slip),
        .eof_req(eof_req), .eof_idx(eof_idx), .eof_data(eof_data), .eof_ack(eof_ack),
        .pf_attr_latch(pf_attr_latch),
        .cpu_wr_stb(cpu_wr_stb), .cpu_wr_a(cpu_wr_a),
        .as_req(as_req), .as_a(as_a), .as_d(as_d), .as_ds(as_ds),
        .dma_rq(dma_rq), .dma_a(dma_a), .dma_ack(dma_ack), .dma_q(dma_q),
        .eof_words(eof_words), .eof_late(eof_late));

    wire        pf_fetch, pf_valid, pf_late, pf_cl_late;
    wire [16:0] pf_raddr;
    wire [31:0] pf_data;
    wire  [3:0] pf_pen, pf_colour;
    shuuz_pf #(.XOFF(PF_XOFF), .H_PIX(H_TOTAL / 2)) u_pf(
        .clk(clk), .reset(reset), .ce_7m(ce_7m), .px(px), .line(v), .line_next(v_next),
        .xscroll(pf_xscroll), .yscroll(pf_yscroll),
        .base_code(base_pf), .base_attr(base_attr),
        .code_a(a_pfc), .attr_a(a_pfa), .code_q(q_pfc), .attr_q(q_pfa),
        .rom_fetch(pf_fetch), .rom_addr(pf_raddr), .rom_row(pf_data),
        .rom_valid(pf_valid), .rom_late(pf_late),
        .pen(pf_pen), .colour(pf_colour));
    wire [17:0] pf_addr18;
    shuuz_gfx_client u_pf_rom(
        .clk(clk), .reset(reset), .fetch(pf_fetch), .fetch_addr({1'b0, pf_raddr}),
        .data(pf_data), .data_valid(pf_valid), .late(pf_cl_late),
        .req(pf_req), .addr(pf_addr18), .ack(pf_ack), .row(pf_row));
    assign pf_addr = pf_addr18[16:0];

    // The MOB draws the next line into the bank that is not on display.
    wire        mob_fetch, mob_valid, mo_cl_late;
    wire [17:0] mob_raddr;
    wire [31:0] mob_data;
    wire        mob_lb_we, mo_busy, mo_budget_hit, mo_line_over;
    wire  [9:0] mob_lb_a;
    wire  [7:0] mob_lb_d, lb_q;
    wire [10:0] mo_words;
    reg         wbank;
    always @(posedge clk) begin
        if (reset)           wbank <= 1'b0;
        else if (line_start) wbank <= !wbank;
    end
    shuuz_mob #(.MO_WORD_BUDGET(MO_BUDGET)) u_mob(
        .clk(clk), .reset(reset),
        .line_start(line_start && MO_ENABLE), .vline(v_next),
        .xscroll(mo_xscroll), .yscroll(mo_yscroll), .xoffset(mo_xoffset),
        .base_mo(base_mo), .base_slip(base_slip),
        .vram_a(mo_vram_a), .vram_rd(mo_vram_rd),
        .vram_ack(mo_vram_ack), .vram_q(mo_vram_q),
        .rom_fetch(mob_fetch), .rom_addr(mob_raddr),
        .rom_row(mob_data), .rom_valid(mob_valid),
        .lb_we(mob_lb_we), .lb_a(mob_lb_a), .lb_d(mob_lb_d),
        .busy(mo_busy), .words(mo_words), .budget_hit(mo_budget_hit),
        .line_over(mo_line_over));
    shuuz_gfx_client u_mo_rom(
        .clk(clk), .reset(reset), .fetch(mob_fetch), .fetch_addr(mob_raddr),
        .data(mob_data), .data_valid(mob_valid), .late(mo_cl_late),
        .req(mo_req), .addr(mo_addr), .ack(mo_ack), .row(mo_row));
    shuuz_lb u_lb(
        .clk(clk), .reset(reset), .wbank(wbank),
        .we(mob_lb_we), .wa(mob_lb_a), .wd(mob_lb_d),
        .rd_ce(ce_7m), .ra({1'b0, px}), .q(lb_q));

    always @(posedge clk) begin
        if (reset) gfx_late <= 1'b0;
        else if (pf_late || pf_cl_late || mo_cl_late || layer_late
                 || mo_budget_hit || mo_line_over) gfx_late <= 1'b1;
    end

    reg [7:0] mix_mo;
    always @(posedge clk) begin
        if (reset)      mix_mo <= 8'd0;
        else if (ce_7m) mix_mo <= lb_q;
    end
    wire [9:0] mix_index;
    shuuz_mixer u_mixer(.clk(clk), .reset(reset), .ce(ce_7m), .mo(mix_mo),
        .pf_pen(pf_pen), .pf_colour(pf_colour), .index(mix_index));

    // Blanking and sync follow the picture through the same pixel stages.
    reg [3:0] d_bl, d_hs, d_vs, d_hb, d_vb;
    always @(posedge clk) begin
        if (reset) begin
            d_bl <= 4'hF; d_hs <= 4'hF; d_vs <= 4'hF; d_hb <= 4'hF; d_vb <= 4'hF;
        end else if (ce_7m) begin
            d_bl <= {d_bl[2:0], blank};
            d_hs <= {d_hs[2:0], !hsync_n};
            d_vs <= {d_vs[2:0], !vsync_n};
            d_hb <= {d_hb[2:0], hblank_i};
            d_vb <= {d_vb[2:0], vblank_i};
        end
    end
    wire [15:0] colour, cr_dout, cram_steal;
    wire [10:0] pix_index11;
    assign pix_colour = colour;
    wire        cr_grant;
    shuuz_cram u_cram(
        .clk(clk), .reset(reset), .ce(ce_7m), .pix_half(pix_half),
        .pix_index({1'b0, mix_index}), .blank(d_bl[PIPE-1]),
        .cpu_cs(acc_arr && is_cr), .cpu_we(cpu_wr && is_cr), .cpu_ds(cpu_ds),
        .cpu_a({1'b0, a[10:1]}), .cpu_din(wdata), .cpu_dout(cr_dout), .cpu_grant(cr_grant),
        .o_dcdma(o_dcdma), .ocrdtack(ocrdtack),
        .init_wr(snap_wr && snap_cr), .init_a(snap_a[10:0]), .init_d(snap_d),
        .colour(colour), .pix_index_out(pix_index11), .steal(cram_steal));
    assign pix_index = pix_index11[9:0];
    shuuz_dac u_dac(.colour(colour), .red(vga_r), .green(vga_g), .blue(vga_b));
    assign hsync  = d_hs[PIPE];
    assign vsync  = d_vs[PIPE];
    assign hblank = d_hb[PIPE];
    assign vblank = d_vb[PIPE];

    assign rdata = is_reg ? reg_dout : is_vr ? vr_dout : is_cr ? cr_dout : 16'hFFFF;
    wire grant = acc && (is_reg ? 1'b1 : is_vr ? vr_grant : is_cr ? cr_grant : 1'b1);
    assign vdtack_n = !grant;
    assign vblank_board = vblank_i;
    assign hblank_board = hblank_i;
    assign vidbl_n = !blank;
    assign beam_h = hd[9:1];
    assign beam_v = v;

    wire unused = &{1'b0, h, hpos, vpos, hde, vde, frame_start, eof_window,
                    reg_pmbase[12:10], reg_pmbase[6], reg_pmbase[0], reg_albase[15:10],
                    reg_opt[15:11], reg_opt[9:8], reg_opt[6], reg_opt[3:0],
                    mo_busy, mo_words, mo_words_line, cpu_words_line, dma_words_line,
                    cpu_wait_worst, eof_words, cram_steal, d_bl[3], d_hs[3], d_vs[3],
                    d_hb[3], d_vb[3], pf_addr18[17], pix_index11[10]};
endmodule
