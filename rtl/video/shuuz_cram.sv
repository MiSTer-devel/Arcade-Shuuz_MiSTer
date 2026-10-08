// SPDX-License-Identifier: GPL-3.0-or-later
// Colour RAM at 3E0000 (the RAM at 54K; 1024 words are used): one copy read
// by the pixel scan and one by the processor, both written together. Taken
// from the Off the Wall MiSTer core's offtwall_cram.sv with the module
// renamed; adapted there from the Relief Pitcher, Batman and Skull &
// Crossbones colour RAM models.
// Copyright (C) 2026 the Batman MiSTer core authors.
//
// The scan reads in the first half of each pixel. With o_dcdma (register 0A
// bit 10) set, the processor uses the second half; with it clear, the
// processor takes the first half and that pixel repeats the colour read
// before it (`steal` counts these). A write is posted: the bus cycle ends
// at once unless ocrdtack is set, and the word is stored in the next slot.
`timescale 1ns/1ps
module shuuz_cram (
    input logic clk, reset, ce, pix_half,
    input logic [10:0] pix_index,
    input logic blank,
    input logic cpu_cs, cpu_we,
    input logic [1:0] cpu_ds,
    input logic [10:0] cpu_a,
    input logic [15:0] cpu_din,
    output logic [15:0] cpu_dout,
    output logic cpu_grant,
    input logic o_dcdma, ocrdtack,
    input logic init_wr,
    input logic [10:0] init_a,
    input logic [15:0] init_d,
    output logic [15:0] colour,
    output logic [10:0] pix_index_out,
    output logic [15:0] steal
);
    logic [7:0] crs_hi[0:2047],crs_lo[0:2047];
    logic [7:0] crc_hi[0:2047],crc_lo[0:2047];
    logic cpu_done,post_valid;
    logic [10:0] post_a;
    logic [15:0] post_d;
    logic [1:0] post_ds;
    wire post_take = cpu_cs && cpu_we && !cpu_done && !ocrdtack && !post_valid;
    wire slot = o_dcdma ? pix_half : !pix_half;
    wire post_drain = slot && post_valid && !reset;
    wire direct = slot && cpu_cs && !cpu_done && !post_valid && !post_take && !reset;
    wire ram_slot = post_drain || direct;
    wire write_ram = post_drain || (direct && cpu_we);
    wire [10:0] a = init_wr ? init_a : (post_valid ? post_a : cpu_a);
    wire [15:0] d = init_wr ? init_d : (post_valid ? post_d : cpu_din);
    wire [1:0] ds = post_valid ? post_ds : cpu_ds;
    wire wh = init_wr || (write_ram && ds[1]);
    wire wl = init_wr || (write_ram && ds[0]);
    wire scan_slot = !pix_half && (o_dcdma || !ram_slot);
    logic [15:0] scan_q;
    logic [10:0] scan_index;
    always_ff @(posedge clk) begin
        if(wh) crs_hi[a] <= d[15:8];
        if(wl) crs_lo[a] <= d[7:0];
        if(scan_slot) begin
            scan_q <= {crs_hi[pix_index],crs_lo[pix_index]};
            scan_index <= pix_index;
        end
    end
    always_ff @(posedge clk) begin
        if(wh) crc_hi[a] <= d[15:8];
        if(wl) crc_lo[a] <= d[7:0];
        if(direct && !cpu_we) cpu_dout <= {crc_hi[cpu_a],crc_lo[cpu_a]};
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            cpu_done <= 1'b0;
            post_valid <= 1'b0;
            post_a <= 11'd0;
            post_d <= 16'd0;
            post_ds <= 2'd0;
            steal <= 16'd0;
        end else begin
            if(!cpu_cs) cpu_done <= 1'b0;
            if(post_drain) post_valid <= 1'b0;
            if(post_take) begin
                post_valid <= 1'b1;
                post_a <= cpu_a;
                post_d <= cpu_din;
                post_ds <= cpu_ds;
                cpu_done <= 1'b1;
            end
            if(direct) cpu_done <= 1'b1;
            if(ram_slot && !o_dcdma) steal <= steal+16'd1;
        end
    end
    assign cpu_grant = cpu_cs && cpu_done;
    always_ff @(posedge clk) begin
        if(reset) begin
            colour <= 16'd0;
            pix_index_out <= 11'd0;
        end else if(ce) begin
            colour <= blank ? 16'd0 : scan_q;
            pix_index_out <= blank ? 11'd0 : scan_index;
        end
    end
endmodule
