// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer top level for Shuuz: the menu, clocks, controls, ROM download, save
// file, video and audio around the game board in shuuz_core. Adapted from
// the Off the Wall MiSTer core's shell, itself from the Relief Pitcher,
// Rampart and Batman shells.
// Copyright (C) 2026 the Batman MiSTer core authors.
`timescale 1ns/1ps

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1        = 0;
assign VGA_SCALER    = 0;
assign VGA_DISABLE   = 0;
assign HDMI_FREEZE   = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT= 0;
assign FB_FORCE_BLANK= 0;

assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

wire  [1:0] ar  = status[122:121];
wire [11:0] arx = (ar == 2'd0) ? 12'd4 : 12'(ar - 1'd1);
wire [11:0] ary = (ar == 2'd0) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Shuuz;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[4],Orientation,Original,Flip;",
	"O[22:20],Scale,Normal,V-Integer,HV-Integer,Narrower HV-Integer;",
	"-;",
	"P1,Analog alignment;",
	"P1-;",
	"P1O[27:23],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[34:28],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,+49,+50,+51,+52,+53,+54,+55,+56,+57,+58,+59,+60,+61,+62,+63,-64,-63,-62,-61,-60,-59,-58,-57,-56,-55,-54,-53,-52,-51,-50,-49,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[40:35],Analog VGA H-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[46:41],Analog VGA V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	// The trackball: mouse, spinner, paddle, analog stick or d-pad.
	"O[13:10],Trackball speed,1x,1.125x,1.25x,1.375x,1.5x,1.75x,2x,2.5x,3x,4x,0.25x,0.375x,0.5x,0.625x,0.75x,0.875x;",
	"O[14],Trackball X,Normal,Inverted;",
	"O[15],Trackball Y,Normal,Inverted;",
	"-;",
	// The self-test switch on the game board.
	"O[6],Service,Off,On;",
	"-;",
	"T[0],Reset;",
	"J1,Left Button,Right Button,Coin;",
	"jn,A,B,Select;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [24:0] ps2_mouse;
wire        direct_video;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] ioctl_index;
wire        ioctl_wait;
wire        ioctl_upload, ioctl_upload_req;
wire  [7:0] ioctl_upload_index, ioctl_din;

wire [31:0] joystick_0;
wire [15:0] joystick_l_analog_0;
wire  [8:0] spinner_0;
wire  [7:0] paddle_0;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),

	// The EEPROM image: index 2, 2048 bytes.
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(ioctl_upload_index),
	.ioctl_din(ioctl_din),

	.joystick_0(joystick_0),
	.joystick_l_analog_0(joystick_l_analog_0),
	.spinner_0(spinner_0),
	.paddle_0(paddle_0),

	.ps2_mouse(ps2_mouse)
);

wire clk_sys;               // 57.272727 MHz
wire clk_sdram;             // the same rate, phase-shifted for the SDRAM_CLK pin
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.locked(pll_locked)
);

assign SDRAM_CLK = clk_sdram;

// `reset` (the menu, the MiSTer button or the framework) restarts the game
// only. The SDRAM, the ROMs loaded into it and the save file are reset by
// ~pll_locked alone.
wire reset = RESET | status[0] | buttons[1];

wire        ce_pix;
wire  [7:0] core_r, core_g, core_b;
wire        core_hs, core_vs, core_hb, core_vb;
wire        core_rom_loaded;
wire signed [15:0] audio;

// Cabinet controls: one trackball, two buttons, one coin switch on the pad.
wire ctl_lbutton, ctl_rbutton, ctl_coin;
wire ch0_clk, ch0_dir, ch1_clk, ch1_dir;

shuuz_controls u_controls
(
	.clk(clk_sys), .reset(~pll_locked), .pause(1'b0),
	.joy(joystick_0), .ana(joystick_l_analog_0), .spin(spinner_0), .pad(paddle_0),
	.ps2_mouse(ps2_mouse),
	.sens(status[13:10]), .inv_x(status[14]), .inv_y(status[15]),
	.lbutton(ctl_lbutton), .rbutton(ctl_rbutton), .coin(ctl_coin),
	.ch0_clk(ch0_clk), .ch0_dir(ch0_dir), .ch1_clk(ch1_clk), .ch1_dir(ch1_dir)
);

shuuz_core u_core
(
	.clk_sys(clk_sys), .init_reset(~pll_locked), .reset(reset),

	.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index), .ioctl_wait(ioctl_wait),
	.ioctl_upload(ioctl_upload), .ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(ioctl_upload_index), .ioctl_din(ioctl_din),
	.rom_loaded(core_rom_loaded),

	// The board reads the Y coupler on LETA channel 0 and the X coupler on
	// channel 1.
	.self_test_n(~status[6]),
	.coin1_n(~ctl_coin), .coin2_n(1'b1),
	.lbutton_n(~ctl_lbutton), .rbutton_n(~ctl_rbutton),
	.xclk(ch1_clk), .xdir(ch1_dir), .yclk(ch0_clk), .ydir(ch0_dir),
	.wdis(1'b0),
	.coin_counter(), .motor_ena(),

	.ce_pix(ce_pix), .vga_r(core_r), .vga_g(core_g), .vga_b(core_b),
	.hsync(core_hs), .vsync(core_vs), .hblank(core_hb), .vblank(core_vb),
	.pix_index(), .pix_colour(),
	.audio(audio),
	.pcm_code(), .pcm_stb(), .snd_late(), .gfx_late(), .eof_late(), .beam_h(), .beam_v(),
	.cpu_a(), .cpu_wdata(), .cpu_rdata(), .cpu_as_n(), .cpu_uds_n(), .cpu_lds_n(),
	.cpu_rw(), .cpu_dtack_n(), .cpu_fc(), .sysres_n(),

	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH), .SDRAM_CKE(SDRAM_CKE), .SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nWE(SDRAM_nWE)
);

// The board's output is mono.
assign AUDIO_S = 1'b1;
assign AUDIO_L = audio;
assign AUDIO_R = audio;

wire [7:0] adj_r, adj_g, adj_b;
wire       adj_hs, adj_vs, adj_hb, adj_vb, adj_ce;

shuuz_analog_adjust #(.H_TOTAL(456), .V_TOTAL(262), .CLK_PER_PIX(8)) u_analog_adjust
(
	.clk        (clk_sys),
	.ce_pix     (ce_pix),
	.osd_hsize  (status[27:23]),
	.osd_hpos   (status[34:28]),
	.osd_hshift (status[40:35]),
	.osd_vshift (status[46:41]),
	.r_in(core_r), .g_in(core_g), .b_in(core_b),
	.hs_in(core_hs), .vs_in(core_vs), .hb_in(core_hb), .vb_in(core_vb),
	.r_out(adj_r), .g_out(adj_g), .b_out(adj_b),
	.hs_out(adj_hs), .vs_out(adj_vs), .hb_out(adj_hb), .vb_out(adj_vb),
	.ce_out(adj_ce)
);

wire [2:0] fx = 3'b000;

wire       rotate_ccw = 1'b0;
wire       no_rotate  = 1'b1;
wire       flip       = status[4] & ~direct_video;
wire       video_rotated;

wire vga_de_raw;

arcade_video #(.WIDTH(336), .DW(24)) arcade_video
(
	.clk_video (clk_sys),
	.ce_pix    (adj_ce),
	.RGB_in    ({adj_r, adj_g, adj_b}),
	.HBlank    (adj_hb),
	.VBlank    (adj_vb),
	.HSync     (adj_hs),
	.VSync     (adj_vs),

	.CLK_VIDEO (CLK_VIDEO),
	.CE_PIXEL  (CE_PIXEL),
	.VGA_R     (VGA_R),
	.VGA_G     (VGA_G),
	.VGA_B     (VGA_B),
	.VGA_HS    (VGA_HS),
	.VGA_VS    (VGA_VS),
	.VGA_DE    (vga_de_raw),
	.VGA_SL    (VGA_SL),

	.fx                 (fx),
	.forced_scandoubler (forced_scandoubler),
	.gamma_bus          (gamma_bus)
);

wire [2:0] scale_sel = (status[22:20] == 3'd0) ? 3'd0 :
                       (status[22:20] == 3'd1) ? 3'd1 :
                       (status[22:20] == 3'd2) ? 3'd4 :
                                                 3'd2;

video_freak video_freak
(
	.CLK_VIDEO  (CLK_VIDEO),
	.CE_PIXEL   (CE_PIXEL),
	.VGA_VS     (VGA_VS),
	.HDMI_WIDTH (HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE     (VGA_DE),
	.VIDEO_ARX  (VIDEO_ARX),
	.VIDEO_ARY  (VIDEO_ARY),
	.VGA_DE_IN  (vga_de_raw),
	.ARX        (arx),
	.ARY        (ary),
	.CROP_SIZE  (12'd0),
	.CROP_OFF   (5'd0),
	.SCALE      (scale_sel)
);

screen_rotate screen_rotate (.*);

assign LED_USER = ioctl_download;

/* verilator lint_off UNUSEDSIGNAL */
wire _unused_emu = &{1'b0, core_rom_loaded, joystick_0, ps2_mouse, 1'b0};
/* verilator lint_on UNUSEDSIGNAL */

endmodule
