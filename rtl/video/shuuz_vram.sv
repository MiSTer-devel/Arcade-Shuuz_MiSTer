// SPDX-License-Identifier: GPL-3.0-or-later
// The 64 KB video RAM block at 3F0000 (RAMs at 41N and 70N) and the VAD's
// access schedule. Each pixel has eight clk phases: 0 and 1 read the
// playfield code and attribute, 5 is the motion object slot, 6 the
// processor's, 7 the end-of-frame reload's (vertical blanking only).
// The board's real schedule is not known. The work RAM and the stack are in
// this RAM, and the game draws about thirty motion objects on one line (its
// volume display), so both get a slot every pixel here.
// Taken from the Off the Wall MiSTer core's offtwall_vram.sv with the module
// renamed; adapted there from the Relief Pitcher, Batman and Skull &
// Crossbones video RAM models.
// Copyright (C) 2026 the Batman MiSTer core authors.
`timescale 1ns/1ps
module shuuz_vram #(
    parameter int MO_SLOTS_ACT   = 8,
    parameter int MO_SLOTS_BLANK = 8,
    parameter int CPU_SLOTS_ACT   = 8,
    parameter int CPU_SLOTS_BLANK = 8,
    parameter bit IACK_STEALS    = 1'b0
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        ce_14m,
    input  logic  [9:0] hd,
    input  logic        blank,
    input  logic [14:0] pf_code_a,
    input  logic [14:0] pf_attr_a,
    output logic [15:0] pf_code_q,
    output logic [15:0] pf_attr_q,
    input  logic        mo_req,
    input  logic [14:0] mo_a,
    output logic        mo_ack,
    output logic [15:0] mo_q,
    input  logic        dma_req,
    input  logic        dma_we,
    input  logic [14:0] dma_a,
    input  logic [15:0] dma_d,
    output logic        dma_ack,
    output logic [15:0] dma_q,
    input  logic        cpu_cs,
    input  logic        cpu_we,
    input  logic  [1:0] cpu_ds,
    input  logic [14:0] cpu_a,
    input  logic [15:0] cpu_din,
    output logic [15:0] cpu_dout,
    output logic        cpu_grant,
    input  logic        ovrdtack,
    input  logic        iack,
    output logic        cpu_wr_stb,
    output logic [14:0] cpu_wr_a,
    input  logic        as_req,
    input  logic [14:0] as_a,
    input  logic [15:0] as_d,
    input  logic  [1:0] as_ds,
    input  logic        init_wr,
    input  logic [14:0] init_a,
    input  logic [15:0] init_d,
    output logic [10:0] mo_words_line,
    output logic [10:0] cpu_words_line,
    output logic [10:0] dma_words_line,
    output logic [15:0] cpu_wait_worst,
    output logic        layer_late
);
    logic [1:0] sub;
    always_ff @(posedge clk) begin
        if (reset)       sub <= 2'd0;
        else if (ce_14m) sub <= 2'd0;
        else             sub <= sub + 2'd1;
    end
    // ph is the clk phase within the pixel, g the pixel within a group of
    // eight. spread(g, n) is true on n of the eight pixels, evenly spaced.
    wire [2:0] ph = {hd[0], sub};
    wire [2:0] g  = hd[3:1];
    localparam int MOA = (MO_SLOTS_ACT   > 8) ? 8 : MO_SLOTS_ACT;
    localparam int MOB = (MO_SLOTS_BLANK > 8) ? 8 : MO_SLOTS_BLANK;
    localparam int CPA = (CPU_SLOTS_ACT   > 8) ? 8 : CPU_SLOTS_ACT;
    localparam int CPB = (CPU_SLOTS_BLANK > 8) ? 8 : CPU_SLOTS_BLANK;
    function automatic bit spread(input logic [2:0] gg, input int n);
        int lo, hi;
        begin
            if (n <= 0)      spread = 1'b0;
            else if (n >= 8) spread = 1'b1;
            else begin
                lo = (int'(gg)       * n) / 8;
                hi = ((int'(gg) + 1) * n) / 8;
                spread = (lo != hi);
            end
        end
    endfunction
    wire mo_slot  = (ph == 3'd5) && spread(g, blank ? MOB : MOA);
    wire cpu_slot = (ph == 3'd6) && spread(g, blank ? CPB : CPA);
    wire dma_slot = blank && (ph == 3'd7);
    logic [14:0] sa;
    logic        swe;
    logic  [1:0] sds;
    logic [15:0] sd;
    logic        post_v,  post2_v;
    logic [14:0] post_a,  post2_a;
    logic [15:0] post_d,  post2_d;
    logic  [1:0] post_ds, post2_ds;
    logic        cpu_pend;
    logic        cpu_hit;
    logic        cpu_done;
    wire cpu_active = cpu_cs & ~(iack & ~IACK_STEALS);
    wire cpu_wr     = cpu_active &  cpu_we;
    wire cpu_rd     = cpu_active & ~cpu_we;
    // A processor write is posted when it can be: the bus cycle ends at once
    // and the word is stored in the next processor slot. post2 holds the
    // attribute write made by the autostore (shuuz_vad_dma). Reads wait for
    // the slot. With ovrdtack set, writes wait too.
    // Reserve the attribute slot until the write strobe has reached DMA.
    wire as_pending = cpu_wr_stb | as_req;
    wire post_take = cpu_wr & ~ovrdtack & ~cpu_done & ~cpu_pend
                     & ~post_v & ~post2_v & ~as_pending;
    logic mo_claimed, dma_claimed;
    wire mo_take = mo_slot && mo_req && !mo_claimed;
    wire dma_take = dma_slot && dma_req && !dma_claimed;
    always_ff @(posedge clk) begin
        if (reset) begin
            mo_claimed <= 1'b0;
            dma_claimed <= 1'b0;
        end else begin
            if (!mo_req) mo_claimed <= 1'b0;
            else if (mo_take) mo_claimed <= 1'b1;
            if (!dma_req) dma_claimed <= 1'b0;
            else if (dma_take) dma_claimed <= 1'b1;
        end
    end
    always_comb begin
        sa  = 15'd0;
        swe = 1'b0;
        sds = 2'b11;
        sd  = 16'd0;
        cpu_hit = 1'b0;
        case (ph)
            3'd0: sa = pf_code_a;
            3'd1: sa = pf_attr_a;
            default: ;
        endcase
        if (dma_take) begin
            sa  = dma_a;
            swe = dma_we;
            sd  = dma_d;
        end
        if (mo_take) begin
            sa  = mo_a;
            swe = 1'b0;
        end
        if (cpu_slot) begin
            if (post_v) begin
                sa  = post_a;
                swe = 1'b1;
                sds = post_ds;
                sd  = post_d;
            end else if (post2_v) begin
                sa  = post2_a;
                swe = 1'b1;
                sds = post2_ds;
                sd  = post2_d;
            end else if (cpu_pend && cpu_active && !cpu_done && !as_pending) begin
                sa      = cpu_a;
                swe     = cpu_we;
                sds     = cpu_ds;
                sd      = cpu_din;
                cpu_hit = 1'b1;
            end
        end
    end
    // The RAM, as two byte lanes. init_* preloads it in simulation.
    logic [7:0] vr_hi [0:32767];
    logic [7:0] vr_lo [0:32767];
    logic [15:0] sq;
    wire [14:0] aa  = init_wr ? init_a : sa;
    wire        awh = init_wr | (!reset & swe & sds[1]);
    wire        awl = init_wr | (!reset & swe & sds[0]);
    wire [15:0] ad  = init_wr ? init_d : sd;
    always_ff @(posedge clk) begin
        if (awh) vr_hi[aa] <= ad[15:8];
        if (awl) vr_lo[aa] <= ad[7:0];
        sq <= {vr_hi[aa], vr_lo[aa]};
    end
`ifndef ALTERA_RESERVED_QIS
    initial begin
        for (int i = 0; i < 32768; i++) begin
            vr_hi[i] = 8'h00;
            vr_lo[i] = 8'h00;
        end
    end
`endif
    logic [2:0] ph_d;
    logic       mo_slot_d, cpu_hit_d, dma_slot_d, dma_rd_d;
    always_ff @(posedge clk) begin
        ph_d       <= ph;
        mo_slot_d  <= !reset & mo_take;
        cpu_hit_d  <= !reset & cpu_hit;
        dma_slot_d <= !reset & dma_take;
        dma_rd_d   <= !reset & dma_take & ~dma_we;
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            pf_code_q <= 16'h0000;
            pf_attr_q <= 16'h0000;
        end else begin
            case (ph_d)
                3'd0: pf_code_q <= sq;
                3'd1: pf_attr_q <= sq;
                default: ;
            endcase
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            mo_ack  <= 1'b0;
            mo_q    <= 16'h0000;
            dma_ack <= 1'b0;
            dma_q   <= 16'h0000;
        end else begin
            mo_ack <= mo_slot_d;
            if (mo_slot_d) mo_q <= sq;
            dma_ack <= dma_slot_d;
            if (dma_rd_d)  dma_q <= sq;
        end
    end
    always_ff @(posedge clk) begin
        cpu_wr_stb <= 1'b0;
        if (reset) begin
            cpu_pend <= 1'b0;
            cpu_done <= 1'b0;
            post_v   <= 1'b0;
            post_a   <= 15'd0;
            post_d   <= 16'd0;
            post_ds  <= 2'b00;
            post2_v  <= 1'b0;
            post2_a  <= 15'd0;
            post2_d  <= 16'd0;
            post2_ds <= 2'b00;
            cpu_wr_a <= 15'd0;
            cpu_dout <= 16'h0000;
        end else begin

            if (!cpu_active) begin
                cpu_pend <= 1'b0;
                cpu_done <= 1'b0;
            end else if (!cpu_done) begin
                if (post_take) begin
                    post_v   <= 1'b1;
                    post_a   <= cpu_a;
                    post_d   <= cpu_din;
                    post_ds  <= cpu_ds;
                    cpu_done <= 1'b1;
                    cpu_wr_stb <= |cpu_ds;
                    cpu_wr_a   <= cpu_a;
                end else begin
                    cpu_pend <= 1'b1;
                end
            end
            if (cpu_hit) begin
                cpu_pend <= 1'b0;
                cpu_done <= 1'b1;
                if (cpu_we) begin
                    cpu_wr_stb <= |cpu_ds;
                    cpu_wr_a   <= cpu_a;
                end
            end
            if (cpu_hit_d) cpu_dout <= sq;
            if (cpu_slot) begin
                if      (post_v)  post_v  <= 1'b0;
                else if (post2_v) post2_v <= 1'b0;
            end
            if (as_req) begin
                post2_v  <= 1'b1;
                post2_a  <= as_a;
                post2_d  <= as_d;
                post2_ds <= as_ds;
            end
        end
    end
    logic cpu_rd_served;
    always_ff @(posedge clk) begin
        if (reset)                 cpu_rd_served <= 1'b0;
        else if (!cpu_active)      cpu_rd_served <= 1'b0;
        else if (cpu_hit_d)        cpu_rd_served <= 1'b1;
    end
    assign cpu_grant = cpu_active & (cpu_we ? cpu_done : cpu_rd_served);
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_rd = &{1'b0, cpu_rd, 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */
    // Diagnostics: words served per line, the longest processor wait, and
    // layer_late if another client's slot ever falls on a playfield phase.
    wire line_wrap = ce_14m & (hd == 10'd0);
    logic [15:0] cpu_wait;
    always_ff @(posedge clk) begin
        if (reset) begin
            mo_words_line  <= 11'd0;
            cpu_words_line <= 11'd0;
            dma_words_line <= 11'd0;
            cpu_wait       <= 16'd0;
            cpu_wait_worst <= 16'd0;
            layer_late     <= 1'b0;
        end else begin
            if (line_wrap) begin
                mo_words_line  <= 11'd0;
                cpu_words_line <= 11'd0;
                dma_words_line <= 11'd0;
            end else begin
                if (mo_take)  mo_words_line  <= mo_words_line  + 11'd1;
                if (cpu_slot && (cpu_pend || post_v || post2_v))
                                         cpu_words_line <= cpu_words_line + 11'd1;
                if (dma_take) dma_words_line <= dma_words_line + 11'd1;
            end
            if (!cpu_active)      cpu_wait <= 16'd0;
            else if (!cpu_grant)  cpu_wait <= cpu_wait + 16'd1;
            if (cpu_active && !cpu_grant && (cpu_wait > cpu_wait_worst))
                cpu_wait_worst <= cpu_wait;
            if ((ph <= 3'd1) && (mo_slot || cpu_slot || dma_slot))
                layer_late <= 1'b1;
        end
    end
endmodule
