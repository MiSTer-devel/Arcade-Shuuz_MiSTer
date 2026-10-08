// SPDX-License-Identifier: GPL-3.0-or-later
// VAD 137656-001 at 50S (modelled as the -002 of the sister boards):
// the 32-word register file, the end-of-frame reload and the parameter-word
// decoder. Taken from the Off the Wall MiSTer core's offtwall_vad_regs.sv with
// the module renamed; adapted there from Relief Pitcher's and Batman's.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// The VAD sheet was never published; this follows MAME's atarivad and what
// the game program does.
//  * Once a frame, at the start of vertical blanking, words 00-1B of the
//    end-of-frame block in video RAM are copied into the register file. A
//    zero word leaves its register alone.
//  * Registers 10-1B hold parameter words: a destination in bits 3-0 and a
//    9-bit value in bits 15-7. Tags: 5 motion object configuration, 9 motion
//    object X, A playfield fine X, B playfield X, D motion object Y,
//    F playfield Y. The board has one playfield; it takes B plus the low
//    three bits of A.
//  * The parameter registers are state: the reload pass decodes every
//    non-zero one in index order, whether or not the end-of-frame block
//    replaced it this frame. The game depends on this when it writes a
//    register directly (see alias_we) and expects the value to last.
//  * alias_we: the game also reaches registers 10-1B through 3FCF40-3FCF7F
//    and 3FCFC0-3FCFFF. It clears 3FCFC0-3FCFFF before every screen load and
//    sets 3FCF74 or 3FCF76 on two screens; nothing ever reads that RAM back.
//  * The value of the tag 5 word moves every motion object horizontally by
//    (value - 183) pixels; 183 is the value in the default table.
//  * Reading register 00 returns the beam: line clamped to 255, bit 14 in
//    vertical blanking.
`timescale 1ns/1ps
module shuuz_vad_regs #(
    parameter int EOF_LAST      = 'h1B,
    parameter bit EOF_SKIP_ZERO = 1'b1,
    parameter bit REPLAY        = 1'b1,    // decode kept parameter registers every frame
    parameter int MO_X_CENTRE   = 183      // tag 5 value that leaves objects where they are
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_cs,
    input  wire        cpu_we,          // one pulse per bus cycle, 3EFFC0-3EFFFF
    input  wire        alias_we,        // one pulse per bus cycle, the 3FCFxx windows
    input  wire  [4:0] cpu_a,
    input  wire [15:0] cpu_din,
    input  wire  [1:0] cpu_ds,
    output reg  [15:0] cpu_dout,
    input  wire  [8:0] vpos,
    input  wire        vblank,
    input  wire        vblank_start,
    output reg         eof_req,
    output wire  [5:0] eof_idx,
    input  wire [15:0] eof_data,
    input  wire        eof_ack,
    output wire [15:0] reg_vsy,
    output wire [15:0] reg_vbl,
    output wire [15:0] reg_vint,
    output wire [15:0] reg_hsy,
    output wire [15:0] reg_hbl,
    output wire [15:0] reg_pmbase,
    output wire [15:0] reg_albase,
    output wire [15:0] reg_opt,
    output reg   [8:0] mo_xscroll,
    output reg   [8:0] mo_yscroll,
    output wire  [8:0] mo_xoffset,
    output wire  [8:0] pf_xscroll,
    output reg   [8:0] pf_yscroll,
    output wire  [7:0] pf_attr_latch,
    output wire        vad_enable,
    output wire        dma_enable,
    output wire        irq_arm,
    output wire        irq_ack
);
    reg [15:0] regs [0:31];
    assign reg_vsy    = regs[5'h01];
    assign reg_vbl    = regs[5'h02];
    assign reg_vint   = regs[5'h03];
    assign reg_hsy    = regs[5'h04];
    assign reg_hbl    = regs[5'h05];
    assign reg_pmbase = regs[5'h08];
    assign reg_albase = regs[5'h09];
    assign reg_opt    = regs[5'h0A];
    assign vad_enable = regs[5'h00][15];
    assign dma_enable = regs[5'h00][15];
    assign pf_attr_latch = regs[5'h1C][15:8];

    function automatic bit is_param(input logic [4:0] index);
        is_param = index >= 5'h10 && index <= 5'h1B;
    endfunction

    typedef enum logic [1:0] { EOF_IDLE, EOF_READ, EOF_WAIT } eof_state_t;
    eof_state_t eof_st;
    reg  [5:0] eof_i;
    reg        eof_received;
    reg [15:0] eof_hold;
    wire        eof_available = eof_received || eof_ack;
    wire [15:0] eof_word = eof_received ? eof_hold : eof_data;
    wire  [4:0] eof_i_lo = eof_i[4:0];

    wire cpu_wr   = (cpu_cs && cpu_we && |cpu_ds) ||
                    (alias_we && |cpu_ds && is_param(cpu_a));
    wire eof_step = eof_st == EOF_WAIT && eof_available && !cpu_wr;
    wire eof_load = eof_step && (!EOF_SKIP_ZERO || eof_word != 16'h0000);

    wire        wr   = cpu_wr || eof_load;
    wire  [4:0] wr_a = cpu_wr ? cpu_a : eof_i_lo;
    wire [15:0] wr_d = cpu_wr ? {cpu_ds[1] ? cpu_din[15:8] : regs[cpu_a][15:8],
                                 cpu_ds[0] ? cpu_din[7:0]  : regs[cpu_a][7:0]}
                              : eof_word;

    wire        replay   = REPLAY && eof_step && !eof_load && is_param(eof_i_lo);
    wire        par_word = (wr && is_param(wr_a)) || replay;
    wire [15:0] par_src  = wr ? wr_d : regs[eof_i_lo];
    wire  [3:0] par_tag  = par_src[3:0];
    wire  [8:0] par_val  = par_src[15:7];

    localparam logic [8:0] CENTRE = MO_X_CENTRE[8:0];
    reg [8:0] mo_config, pf_xcoarse;
    reg [2:0] pf_xfine;
    always @(posedge clk) begin
        if (reset) begin
            mo_xscroll <= 9'd0;
            mo_yscroll <= 9'd0;
            mo_config  <= CENTRE;
            pf_xcoarse <= 9'd0;
            pf_xfine   <= 3'd0;
            pf_yscroll <= 9'd0;
        end else if (par_word) begin
            case (par_tag)
                4'h5: mo_config  <= par_val;
                4'h9: mo_xscroll <= par_val;
                4'hA: pf_xfine   <= par_val[2:0];
                4'hB: pf_xcoarse <= par_val;
                4'hD: mo_yscroll <= par_val;
                4'hF: pf_yscroll <= par_val;
                default: ;      // 6 and 7 go to the MOB too; E is the absent playfield
            endcase
        end
    end
    assign pf_xscroll = pf_xcoarse + {6'd0, pf_xfine};
    assign mo_xoffset = mo_config - CENTRE;

    always @(posedge clk) begin
        if (reset) begin
            for (int k = 0; k < 32; k++) regs[k] <= 16'h0000;
        end else if (wr) begin
            regs[wr_a] <= wr_d;
        end
    end
    assign irq_arm = wr && wr_a == 5'h03;
    assign irq_ack = wr && wr_a == 5'h1E;

    localparam logic [5:0] EOFLAST = EOF_LAST[5:0];
    always @(posedge clk) begin
        if (reset) begin
            eof_st       <= EOF_IDLE;
            eof_received <= 1'b0;
            eof_hold     <= 16'd0;
            eof_i        <= 6'd0;
            eof_req      <= 1'b0;
        end else begin
            case (eof_st)
                EOF_IDLE: begin
                    eof_req <= 1'b0;
                    if (vblank_start && dma_enable) begin
                        eof_i  <= 6'd0;
                        eof_st <= EOF_READ;
                    end
                end
                EOF_READ: begin
                    eof_received <= 1'b0;
                    if (!cpu_wr) begin
                        eof_req <= 1'b1;
                        eof_st  <= EOF_WAIT;
                    end
                end
                EOF_WAIT: begin
                    if (eof_ack) begin
                        eof_hold     <= eof_data;
                        eof_received <= 1'b1;
                        eof_req      <= 1'b0;
                    end
                    if (eof_step) begin
                        eof_received <= 1'b0;
                        eof_req      <= 1'b0;
                        if (eof_i == EOFLAST) eof_st <= EOF_IDLE;
                        else begin
                            eof_i  <= eof_i + 6'd1;
                            eof_st <= EOF_READ;
                        end
                    end
                end
                default: eof_st <= EOF_IDLE;
            endcase
        end
    end
    assign eof_idx = eof_i;

    wire  [7:0] vclamp = vpos[8] ? 8'hFF : vpos[7:0];
    always @* cpu_dout = cpu_a == 5'h00 ? {1'b0, vblank, 6'b0, vclamp} : regs[cpu_a];

    wire unused = &{1'b0, regs[5'h1C][7:0], regs[5'h00][14:0], par_src[6:4]};
endmodule
