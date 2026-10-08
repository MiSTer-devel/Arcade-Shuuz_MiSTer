// SPDX-License-Identifier: GPL-3.0-or-later
// MOB 137593-001 at 70S: for every line, read the first link from the SLIP
// table, walk the linked list of motion objects in video RAM and draw the
// stamp rows that cross the line into the line buffer. An entry is four
// words: link (7-0); horizontal flip (15) and stamp (14-0); X (15-7) and
// colour (3-0); Y (15-7), width (6-4) and height (2-0) in stamps less one.
// The list ends at an entry that links to itself or was already visited.
// xoffset is the horizontal shift set by the configuration word.
// Taken from the Off the Wall MiSTer core's offtwall_mob.sv with the module
// renamed; adapted there from the Relief Pitcher, Batman and Skull &
// Crossbones video models.
// Copyright (C) 2026 the Batman MiSTer core authors.
`timescale 1ns/1ps
module shuuz_mob #(
    parameter int MO_WORD_BUDGET = 456,
    parameter int BITMAP_W       = 336,
    parameter int BITMAP_H       = 240,
    parameter int SLIP_SHIFT     = 3
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        line_start,
    input  logic  [8:0] vline,
    input  logic  [8:0] xscroll,
    input  logic  [8:0] yscroll,
    input  logic  [8:0] xoffset,
    input  logic [14:0] base_mo,
    input  logic [14:0] base_slip,
    output logic [14:0] vram_a,
    output logic        vram_rd,
    input  logic        vram_ack,
    input  logic [15:0] vram_q,
    output logic        rom_fetch,
    output logic [17:0] rom_addr,
    input  logic [31:0] rom_row,
    input  logic        rom_valid,
    output logic        lb_we,
    output logic  [9:0] lb_a,
    output logic [7:0] lb_d,
    output logic        busy,
    output logic [10:0] words,
    output logic        budget_hit,
    output logic        line_over
);
    typedef enum logic [3:0] {
        S_IDLE, S_SLIP, S_E3, S_E1, S_E2,
        S_TILE, S_ROMREQ, S_ROMHOLD, S_ROMWAIT, S_PIX, S_E0, S_DONE
    } state_t;
    state_t st;
    logic  [5:0] band;
    logic  [7:0] link;
    logic [14:0] code;
    logic        hflip;
    logic  [3:0] width;
    logic  [2:0] ty, row;
    logic  [3:0] j;
    logic  [2:0] px;
    logic  [9:0] sx0;

    logic  [3:0] mcol;
    logic [31:0] rq;
    wire  [8:0] yfield   = vram_q[15:7];
    wire  [3:0] h_next   = {1'b0, vram_q[2:0]} + 4'd1;
    wire  [3:0] w_next   = {1'b0, vram_q[6:4]} + 4'd1;
    wire  [8:0] ypos_mod = 9'd0 - yfield - yscroll - {2'd0, h_next, 3'd0};
    wire signed [10:0] ypos_true =
        (ypos_mod >= BITMAP_H[8:0]) ? ($signed({2'b00, ypos_mod}) - 11'sd512)
                                    :  $signed({2'b00, ypos_mod});
    wire signed [10:0] dv = $signed({2'b00, vline}) - ypos_true;
    wire signed [10:0] vext = $signed({4'd0, h_next, 3'd0});
    wire        vmatch = (dv >= 0) && (dv < vext);
    wire  [8:0] xfield   = vram_q[15:7];
    wire  [8:0] xpos_mod = xfield + xoffset - xscroll;
    wire  [9:0] xpos_lb  = (xpos_mod >= BITMAP_W[8:0]) ? ({1'b0, xpos_mod} + 10'd512)
                                                       :  {1'b0, xpos_mod};
    wire  [3:0] kcode = hflip ? (width - 4'd1 - j) : j;
    wire  [6:0] tyw   = {4'd0, ty} * {3'd0, width};
    wire [14:0] stamp = code + {8'd0, tyw} + {11'd0, kcode};
    wire [3:0] pen;
    shuuz_gfx_pixel u_pixel(.row(rq), .hflip(hflip), .x(px), .pen(pen));
    logic vram_release;
    wire word_done = vram_ack && !vram_release;
    always_ff @(posedge clk) begin
        if (reset) vram_release <= 1'b0;
        else vram_release <= vram_ack || line_start;
    end
    logic [255:0] visited;
    wire over_budget = (words >= MO_WORD_BUDGET[10:0]);
    wire  [8:0] bsum = vline + yscroll;
    assign rom_addr = {stamp, row};
    always_comb begin
        vram_a  = 15'd0;
        vram_rd = 1'b0;
        case (st)
            S_SLIP: begin vram_a = base_slip + {9'd0, band};      vram_rd = !vram_release; end
            S_E3:   begin vram_a = base_mo + {5'd0, link, 2'b11}; vram_rd = !vram_release; end
            S_E1:   begin vram_a = base_mo + {5'd0, link, 2'b01}; vram_rd = !vram_release; end
            S_E2:   begin vram_a = base_mo + {5'd0, link, 2'b10}; vram_rd = !vram_release; end
            S_E0:   begin vram_a = base_mo + {5'd0, link, 2'b00}; vram_rd = !vram_release; end
            default:  ;
        endcase
    end
    assign busy  = (st != S_IDLE) && (st != S_DONE);
    always_ff @(posedge clk) begin
        if (reset) begin
            st         <= S_IDLE;
            lb_we      <= 1'b0;
            words      <= 11'd0;
            budget_hit <= 1'b0;
            line_over  <= 1'b0;
            rom_fetch  <= 1'b0;
            visited <= '0;
        end else begin
            lb_we     <= 1'b0;
            rom_fetch <= 1'b0;
            if (line_start) begin
                band       <= bsum[8:SLIP_SHIFT];
                visited <= '0;
                words      <= 11'd0;
                budget_hit <= 1'b0;
                if (busy) line_over <= 1'b1;
                st         <= S_SLIP;
            end else begin
                case (st)
                    S_SLIP: if (word_done) begin
                        words <= words + 11'd1;
                        link  <= vram_q[7:0];
                        st    <= S_E3;
                    end
                    S_E3: begin
                        if (over_budget) begin
                            budget_hit <= 1'b1;
                            st         <= S_DONE;
                        end else if (word_done) begin
                            words  <= words + 11'd1;
                            visited[link] <= 1'b1;
                            width  <= w_next;
                            ty     <= dv[5:3];
                            row    <= dv[2:0];
                            st     <= visited[link] ? S_DONE : (vmatch ? S_E1 : S_E0);
                        end
                    end
                    S_E1: if (word_done) begin
                        words <= words + 11'd1;
                        code  <= vram_q[14:0];
                        hflip <= vram_q[15];
                        st    <= S_E2;
                    end
                    S_E2: if (word_done) begin
                        words <= words + 11'd1;
                        sx0   <= xpos_lb;

                        mcol  <= vram_q[3:0];
                        j     <= 4'd0;
                        st    <= S_TILE;
                    end
                    S_TILE: st <= (j < width) ? S_ROMREQ : S_E0;
                    S_ROMREQ: begin
                        rom_fetch <= 1'b1;
                        st        <= S_ROMHOLD;
                    end
                    S_ROMHOLD: st <= S_ROMWAIT;
                    S_ROMWAIT: if (rom_valid) begin
                        rq <= rom_row;
                        px <= 3'd0;
                        st <= S_PIX;
                    end
                    S_PIX:  begin
                        lb_we <= 1'b1;
                        lb_a  <= sx0 + {3'd0, j, 3'd0} + {7'd0, px};
                        lb_d  <= {mcol, pen};
                        px    <= px + 3'd1;
                        if (px == 3'd7) begin j <= j + 4'd1; st <= S_TILE; end
                    end
                    S_E0: begin
                        if (over_budget) begin
                            budget_hit <= 1'b1;
                            st         <= S_DONE;
                        end else if (word_done) begin
                            words <= words + 11'd1;
                            if (vram_q[7:0] == link) st <= S_DONE;
                            else begin link <= vram_q[7:0]; st <= S_E3; end
                        end
                    end
                    S_IDLE, S_DONE: ;
                    default: st <= S_DONE;
                endcase
            end
        end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, ypos_true[10], dv[10:6], bsum[2:0], 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
