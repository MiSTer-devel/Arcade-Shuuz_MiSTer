// SPDX-License-Identifier: GPL-3.0-or-later
// VAD DMA channel: the end-of-frame reload's reads and the playfield
// attribute autostore. Taken from the Off the Wall MiSTer core's
// offtwall_vad_dma.sv with the module renamed; adapted there from Relief
// Pitcher's and Batman's. Copyright (C) 2026 the Batman MiSTer core authors.
//
//  * The end-of-frame block is the 64 words just below the SLIP table.
//    shuuz_vad_regs sequences the reload; this module reads the words. It
//    runs in vertical blanking, the only time the schedule has DMA slots.
//  * Autostore: with register 0A bit 7 set, a processor write to the
//    playfield code RAM also writes the high byte of the attribute word at
//    the same tile index, from the high byte of register 1C as it was when
//    the code was written. The game switches the bit on around its text
//    writes.
`timescale 1ns/1ps
module shuuz_vad_dma(
    input  wire        clk,
    input  wire        reset,
    input  wire        line_start,
    input  wire  [8:0] vpos,
    input  wire        vblank,
    input  wire        dma_enable,
    input  wire        oas_en,
    input  wire [14:0] base_pf,
    input  wire [14:0] base_attr,
    input  wire [14:0] base_slip,
    input  wire        eof_req,
    input  wire  [5:0] eof_idx,
    output reg  [15:0] eof_data,
    output reg         eof_ack,
    input  wire  [7:0] pf_attr_latch,
    input  wire        cpu_wr_stb,
    input  wire [14:0] cpu_wr_a,
    output reg         as_req,
    output reg  [14:0] as_a,
    output wire [15:0] as_d,
    output wire  [1:0] as_ds,
    output wire        dma_rq,
    output reg  [14:0] dma_a,
    input  wire        dma_ack,
    input  wire [15:0] dma_q,
    output reg  [10:0] eof_words,
    output reg         eof_late
);
    typedef enum logic [1:0] {IDLE, READ, RELEASE} state_t;
    state_t state;
    assign dma_rq = state == READ;
    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            dma_a     <= 15'd0;
            eof_data  <= 16'd0;
            eof_ack   <= 1'b0;
            eof_words <= 11'd0;
            eof_late  <= 1'b0;
        end else begin
            eof_ack <= 1'b0;
            if (line_start && vpos == 9'd0) eof_words <= 11'd0;
            if (!vblank && (state == READ || (eof_req && dma_enable)))
                eof_late <= 1'b1;
            case (state)
                IDLE: if (eof_req && dma_enable && vblank) begin
                    dma_a <= base_slip - 15'd64 + {9'd0, eof_idx};
                    state <= READ;
                end
                READ: if (dma_ack) begin
                    eof_data  <= dma_q;
                    eof_ack   <= 1'b1;
                    eof_words <= eof_words + 11'd1;
                    state     <= RELEASE;
                end
                RELEASE: if (!eof_req) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    wire in_pf = cpu_wr_a[14:12] == base_pf[14:12];
    reg [7:0] as_byte;
    always @(posedge clk) begin
        if (reset) begin
            as_req  <= 1'b0;
            as_a    <= 15'd0;
            as_byte <= 8'd0;
        end else begin
            as_req <= 1'b0;
            if (cpu_wr_stb && dma_enable && oas_en && in_pf) begin
                as_req  <= 1'b1;
                as_a    <= base_attr + {3'd0, cpu_wr_a[11:0]};
                as_byte <= pf_attr_latch;
            end
        end
    end
    assign as_d  = {as_byte, as_byte};
    assign as_ds = 2'b10;

    wire unused = &{1'b0, base_pf[11:0]};
endmodule
