//=======================================================================================================
//
// SharpMZ2500.sv - MiSTer top level for the Sharp MZ-2500 / MZ-2520 core (BOOTSTRAP).
//
// OSD, clocks, hps_io and video output. The machine itself is rtl/mz2500.sv (for now a test pattern and a
// T80 running a stub program). sys/ is the stock Template_MiSTer sys drop-in.
//
// Copyright (C) 2026 Alan Steremberg. Based on Template_MiSTer (C) Sorgelig.
//
// This source file is free software: you can redistribute it and/or modify it under the terms of the GNU
// General Public License as published by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
// License for more details. You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.
//=======================================================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// SDRAM: main RAM, kanji and dictionary ROMs will live here (docs/design.md). Unused for now.
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

`ifdef MISTER_DUAL_SDRAM
assign {SDRAM2_DQ, SDRAM2_A, SDRAM2_BA, SDRAM2_CLK, SDRAM2_nWE, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nCS} = 'Z;
`endif

`ifdef MISTER_FB
assign FB_EN = 0;
assign FB_FORMAT = 0;
assign FB_WIDTH = 0;
assign FB_HEIGHT = 0;
assign FB_BASE = 0;
assign FB_STRIDE = 0;
assign FB_FORCE_BLANK = 0;
`ifdef MISTER_FB_PALETTE
assign FB_PAL_CLK = 0;
assign FB_PAL_ADDR = 0;
assign FB_PAL_DOUT = 0;
assign FB_PAL_WR = 0;
`endif
`endif

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v"

// Placeholder menu. Planned entries (docs/design.md): boot.rom / IPL, CG, kanji and dictionary ROM loading,
// S0-S3 floppy drives (D88/2D), tape image, boot mode switch, model (2500/2520), mouse, joystick.
localparam CONF_STR =
{
	"SharpMZ2500;;",
	"-;",
	"-,Bootstrap: test pattern only;",
	"-;",
	"O[1],Lines (front switch),400 (24 kHz),200 (15 kHz);",
	"O[3:2],Boot Mode,MZ-2500,MZ-2000,MZ-80B;",
	"O[4],Model,MZ-2500,MZ-2520;",
	"O[6:5],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

// 85.909091 MHz = 24 x 3.579545 MHz (4 x the 21.477 MHz 400-line dot clock, 6 x the 14.318 MHz 200-line one).
// The CPU (6 MHz), OPN (2 MHz) and 8253 clocks come from accumulators in rtl/mz2500.sv.
wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

/////////////////  HPS  ///////////////////////////

wire forced_scandoubler;
wire [21:0] gamma_bus;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [31:0] joystick_0, joystick_1;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),
	.forced_scandoubler(forced_scandoubler),

	.ps2_key(ps2_key),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(1'b0)
);

/////////////////  RESET  /////////////////////////

wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

/////////////////  MACHINE  ///////////////////////

wire        lines400 = ~status[1];
wire        ce_pix;
wire  [7:0] R, G, B;
wire        HSync, VSync, HBlank, VBlank;
wire [15:0] audio_l, audio_r;

mz2500 mz2500
(
	.clk_sys(clk_sys),
	.reset(reset),
	.lines400(lines400),
	.ps2_key(ps2_key),

	.ce_pix(ce_pix),
	.R(R), .G(G), .B(B),
	.HSync(HSync), .VSync(VSync),
	.HBlank(HBlank), .VBlank(VBlank),

	.audio_l(audio_l),
	.audio_r(audio_r),

	.cpu_pc(),
	.cpu_ce(),
	.cpu_m1_n(),
	.dbg_io_wr(),
	.dbg_io_port(),
	.dbg_io_data()
);

/////////////////  AUDIO  /////////////////////////

assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;
assign AUDIO_S = 1'b1;
assign AUDIO_MIX = 2'd0;

/////////////////  VIDEO  /////////////////////////

assign LED_USER  = ioctl_download;
assign CLK_VIDEO = clk_sys;

// 400-line mode is already 24.86 kHz: no scandoubler there (HDMI goes through the scaler; analogue output
// needs vga_scaler=1 or a 24 kHz monitor). 200-line mode is 15.98 kHz and may be doubled.
wire [1:0] scale = status[6:5];
wire [2:0] sl    = scale ? scale - 1'd1 : 3'd0;
wire       sd_on = ~lines400 & (scale != 2'd0 || forced_scandoubler);
assign VGA_SL = sd_on ? sl[1:0] : 2'd0;

video_mixer #(.LINE_LENGTH(1024), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix),
	.scandoubler(sd_on),
	.hq2x(scale == 2'd1),
	.gamma_bus(gamma_bus),
	.R(R), .G(G), .B(B),
	.HSync(HSync), .VSync(VSync),
	.HBlank(HBlank), .VBlank(VBlank),
	.HDMI_FREEZE(1'b0),
	.freeze_sync(),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_VS(VGA_VS), .VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

endmodule
