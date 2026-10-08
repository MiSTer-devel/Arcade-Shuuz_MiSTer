// SPDX-License-Identifier: GPL-3.0-or-later
// Atari LETA 137304-2002: four quadrature counters, read as four bytes.
// Taken from the Off the Wall MiSTer core's offtwall_leta.sv with the module
// renamed; adapted there from the Rampart MiSTer core (Copyright (C) 2026 RetroShrimp), whose
// behaviour follows leta_rep.vhd by JROK from the Atari System 1 core and
// whose structure follows the Blasteroids core.
//
// Each channel has a CLK and a DIR input. On every chip clock both are
// shifted into 3-sample filters; a level is settled once three samples agree.
// A settled change of one line moves the count by one. With RESOL low only
// every other transition counts. TEST high clears the counters and shows the
// raw inputs, inverted, instead. The part has no reset pin.
module shuuz_leta(
    input  wire       clk,
    input  wire       ck,      // one clk pulse per chip clock
    input  wire       test,
    input  wire       resol,
    input  wire [1:0] ad,      // channel select
    input  wire [3:0] clks,
    input  wire [3:0] dirs,
    output wire [7:0] dout
);
    /* verilator lint_off PROCASSINIT */
    reg [31:0] cnt = 32'd0;
    reg [11:0] ch = 12'd0, dh = 12'd0;
    reg  [3:0] cl = 4'd0, dl = 4'd0;      // last settled CLK / DIR
    /* verilator lint_on PROCASSINIT */

    always @(posedge clk) begin
        if (ck) begin
            for (int i = 0; i < 4; i++) begin
                if (test) begin
                    ch[3*i +: 3] <= 3'd0; dh[3*i +: 3] <= 3'd0; cnt[8*i +: 8] <= 8'd0;
                    cl[i] <= 1'b0; dl[i] <= 1'b0;
                end else begin
                    ch[3*i +: 3] <= {ch[3*i +: 2], clks[i]};
                    dh[3*i +: 3] <= {dh[3*i +: 2], dirs[i]};
                    if (ch[3*i +: 3] == 3'b000) cl[i] <= 1'b0;
                    else if (ch[3*i +: 3] == 3'b111) cl[i] <= 1'b1;
                    if (dh[3*i +: 3] == 3'b000) dl[i] <= 1'b0;
                    else if (dh[3*i +: 3] == 3'b111) dl[i] <= 1'b1;
                    // settled (CLK, DIR) against the previous settled pair
                    case ({ch[3*i +: 3] == 3'b111, ch[3*i +: 3] == 3'b000,
                           dh[3*i +: 3] == 3'b111, dh[3*i +: 3] == 3'b000})
                        4'b1001: begin  // (1,0)
                            if (cl[i] && dl[i])                 cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
                            else if (!cl[i] && !dl[i] && resol) cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
                        end
                        4'b1010: begin  // (1,1)
                            if (cl[i] && !dl[i])                cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
                            else if (!cl[i] && dl[i] && resol)  cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
                        end
                        4'b0110: begin  // (0,1)
                            if (!cl[i] && !dl[i])               cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
                            else if (cl[i] && dl[i] && resol)   cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
                        end
                        4'b0101: begin  // (0,0)
                            if (!cl[i] && dl[i])                cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
                            else if (cl[i] && !dl[i] && resol)  cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

    assign dout = test ? ~{clks[3], dirs[3], clks[2], dirs[2], clks[1], dirs[1], clks[0], dirs[0]}
                       : cnt[8*ad +: 8];
endmodule
