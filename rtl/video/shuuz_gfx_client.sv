// SPDX-License-Identifier: GPL-3.0-or-later
// One reader of the graphics ROMs. A fetch names a stamp row (stamp code and
// row, 18 bits); the answer is that row's four ROM bytes as they sit in the
// sockets, inverted: {high ROM byte 1, low ROM byte 1, high ROM byte 0, low
// ROM byte 0}, byte 0 holding the left four pixels. `late` reports a fetch
// made before the previous answer arrived. Taken from the Off the Wall MiSTer
// core's offtwall_gfx_client.sv with the module renamed; that followed the
// Relief Pitcher MiSTer core's relief_gfx_client.sv (Copyright (C) 2026 the
// Skull & Crossbones MiSTer core authors), without its byte picking.
`timescale 1ns/1ps
module shuuz_gfx_client(
    input  wire        clk,
    input  wire        reset,
    input  wire        fetch,
    input  wire [17:0] fetch_addr,
    output reg  [31:0] data,
    output reg         data_valid,
    output reg         late,
    output reg         req,
    output reg  [17:0] addr,
    input  wire        ack,
    input  wire [31:0] row
);
    reg busy;
    always @(posedge clk) begin
        late <= 1'b0;
        if (reset) begin
            req        <= 1'b0;
            addr       <= 18'd0;
            busy       <= 1'b0;
            data       <= 32'd0;
            data_valid <= 1'b0;
        end else begin
            if (fetch) begin
                data_valid <= 1'b0;
                if (busy) late <= 1'b1;
            end
            if (busy) begin
                if (req && ack) begin
                    req        <= 1'b0;
                    busy       <= 1'b0;
                    data_valid <= 1'b1;
                    data       <= row;
                end
            end else if (fetch) begin
                busy <= 1'b1;
                addr <= fetch_addr;
                req  <= 1'b1;
            end
        end
    end
endmodule
