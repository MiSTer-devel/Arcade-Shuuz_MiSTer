// SPDX-License-Identifier: GPL-3.0-or-later
// Graphics and sample ROMs in SDRAM (MiSTer only). Adapted from the Off the
// Wall MiSTer core's offtwall_gfx_mem.sv.
//
// SDRAM word addresses:
//   000000-03FFFF  playfield graphics
//   040000-0BFFFF  motion object graphics
//   0C0000-0DFFFF  sound samples, two bytes per word, first byte low
// A graphics word holds one byte from each ROM bank: pen bits 3 and 2 in
// bits 15-8, pen bits 1 and 0 in bits 7-0. A stamp row is two consecutive
// words, read as one burst and handed to the playfield or the motion object
// reader as {word 1, word 0}. The playfield is served first; it has a
// deadline every eight pixels. A sample byte is one word read.
//
// Download words are written one at a time; the loader waits for dl_ack.
module shuuz_rom_mem(
    input  wire        clk,
    input  wire        reset,
    // download
    input  wire        dl_wr,       // held until dl_ack
    input  wire [19:0] dl_addr,     // word address
    input  wire [15:0] dl_data,
    output reg         dl_ack,
    // readers
    input  wire        pf_req,
    input  wire [16:0] pf_addr,     // stamp (16-3), row (2-0)
    output reg         pf_ack,
    output reg  [31:0] pf_row,
    input  wire        mo_req,
    input  wire [17:0] mo_addr,     // stamp (17-3), row (2-0)
    output reg         mo_ack,
    output reg  [31:0] mo_row,
    input  wire        snd_req,
    input  wire [17:0] snd_addr,    // byte address
    output reg         snd_ack,
    output reg   [7:0] snd_data,
    // SDRAM controller
    output reg         sd_req,
    output reg         sd_we,
    output reg  [23:0] sd_addr,
    output reg  [15:0] sd_wdata,
    output reg   [2:0] sd_blen,
    input  wire        sd_ready,
    input  wire        sd_valid,
    input  wire [15:0] sd_rdata,
    output wire        rfsh_ok,
    output wire        idle
);
    localparam logic [23:0] MO_BASE = 24'h040000, SND_BASE = 24'h0C0000;
    typedef enum logic [2:0] {IDLE, WRITE, WAIT_WRITE, READ0, READ1, DONE} state_t;
    state_t state;
    reg [1:0]  who;                 // 0 playfield, 1 motion objects, 2 samples
    reg        odd;
    reg [15:0] first;
    assign rfsh_ok = 1'b1;
    assign idle    = state == IDLE && !dl_wr;

    // A request is taken once: the reader drops it the clk after the answer.
    wire pf_new  = pf_req && !pf_ack;
    wire mo_new  = mo_req && !mo_ack;
    wire snd_new = snd_req && !snd_ack;
    always @(posedge clk) begin
        sd_req  <= 1'b0;
        dl_ack  <= 1'b0;
        pf_ack  <= 1'b0;
        mo_ack  <= 1'b0;
        snd_ack <= 1'b0;
        if (reset) begin
            state <= IDLE;
        end else case (state)
            IDLE: if (sd_ready && !sd_req) begin
                if (dl_wr && !dl_ack) begin
                    sd_req   <= 1'b1;
                    sd_we    <= 1'b1;
                    sd_blen  <= 3'd0;
                    sd_addr  <= {4'd0, dl_addr};
                    sd_wdata <= dl_data;
                    state    <= WRITE;
                end else if (pf_new || mo_new) begin
                    who     <= pf_new ? 2'd0 : 2'd1;
                    sd_req  <= 1'b1;
                    sd_we   <= 1'b0;
                    sd_blen <= 3'd1;
                    sd_addr <= pf_new ? {6'd0, pf_addr, 1'b0} : MO_BASE + {5'd0, mo_addr, 1'b0};
                    state   <= READ0;
                end else if (snd_new) begin
                    who     <= 2'd2;
                    odd     <= snd_addr[0];
                    sd_req  <= 1'b1;
                    sd_we   <= 1'b0;
                    sd_blen <= 3'd0;
                    sd_addr <= SND_BASE + {7'd0, snd_addr[17:1]};
                    state   <= READ1;
                end
            end
            // The controller drops ready while it works on the request.
            WRITE:      if (!sd_ready) state <= WAIT_WRITE;
            WAIT_WRITE: if (sd_ready) begin dl_ack <= 1'b1; state <= DONE; end
            READ0: if (sd_valid) begin first <= sd_rdata; state <= READ1; end
            READ1: if (sd_valid) begin
                case (who)
                    2'd0:    begin pf_row <= {sd_rdata, first}; pf_ack <= 1'b1; end
                    2'd1:    begin mo_row <= {sd_rdata, first}; mo_ack <= 1'b1; end
                    default: begin
                        snd_data <= odd ? sd_rdata[15:8] : sd_rdata[7:0];
                        snd_ack  <= 1'b1;
                    end
                endcase
                state <= DONE;
            end
            DONE: state <= IDLE;
            default: state <= IDLE;
        endcase
    end
endmodule
