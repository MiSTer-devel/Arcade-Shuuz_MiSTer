// SPDX-License-Identifier: GPL-3.0-or-later
// Program ROM, 256 KB (two 27C010 at 23P and 13P), held in block RAM so that
// every read takes the same time, as it does on the board. Adapted from the
// Off the Wall MiSTer core's offtwall_prog_rom.sv.
// Data appears one clk after the address. The download port writes one byte
// at a time: even addresses are the high byte (23P), odd the low byte (13P).
module shuuz_prog_rom(
    input  wire        clk,
    input  wire [17:1] addr,
    output reg  [15:0] q,
    input  wire        dl_we,
    input  wire [17:0] dl_addr,
    input  wire  [7:0] dl_data
);
    (* ramstyle = "no_rw_check, M10K" *) reg [7:0] hi [0:131071];
    (* ramstyle = "no_rw_check, M10K" *) reg [7:0] lo [0:131071];
    always @(posedge clk) begin
        if (dl_we && !dl_addr[0]) hi[dl_addr[17:1]] <= dl_data;
        if (dl_we &&  dl_addr[0]) lo[dl_addr[17:1]] <= dl_data;
        q <= {hi[addr], lo[addr]};
    end
endmodule
