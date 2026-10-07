//=======================================================================================================
//
// mz2500.sv - Sharp MZ-2500 machine.
//
// Shared by the MiSTer top level (SharpMZ2500.sv) and the Verilator harness (verilator/sim.v).
// Hardware reference: docs/hardware.md (CSP EmuZ-2500 is the behavioural reference, MAME the second one).
//
//   * Z80 (T80) at 6 MHz with CSP's wait states: one per M1, page waits for GVRAM/RMW/text VRAM/PCG,
//     I/O waits (FDC, PIO, OPN, RTC) and the display-period WAIT for text VRAM / PCG and GVRAM.
//   * MMU: eight 8 KB windows, page registers B4/B5, IPL reset map (34-37, 04-07) and the "special" reset
//     (8255 PC1 rising: map 00-07 and CPU reset), IPL reset when 8255 PC3 stays low for 100 us.
//   * Memory: 256 KB main RAM, the 32 KB IPL ROM and the 256 KB kanji ROM in SDRAM, ROMs loaded
//     through ioctl (boot.rom layout of docs/roms.md: IPL at 000000, kanji at 010000).
//   * Devices: video (mz2500_video: text CRTC, graphics controller, VRAMs), interrupt block (C6/C7), 8253
//     (E4-E7, gate pulses F0-F3), 8255 (E0-E3), Z80 PIO port A/B for the keyboard (E8-EB), keyboard matrix,
//     YM2203 register stub (C8/C9: SSG registers and port B switches; no sound yet), floppy (mz2500_fdc:
//     MB8876 + two D88 drives on image slots), joystick port (EF, nothing pressed).
//
// Unmapped ports and pages read FFh.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500
(
	input         clk_sys,        // 85.909091 MHz
	input         reset,
	input         lines400,       // front-panel 200/400-line switch: 1 = 400 lines (24 kHz), 0 = 200 lines (15 kHz)
	input   [1:0] boot_mode,      // front-panel boot switch: 0 = MZ-2500, 1 = MZ-2000, 2 = MZ-80B (applies at reset)
	input  [10:0] ps2_key,
	input  [64:0] rtc,            // hps_io RTC: BCD time and date, bit 64 toggles on an update
	input   [5:0] joy0,           // MiSTer joysticks 1 and 2: right, left, down, up, trigger A, trigger B (active high)
	input   [5:0] joy1,
	input  [24:0] ps2_mouse,      // hps_io ps2_mouse

	// ROM download (hps_io ioctl): boot.rom = IPL at 000000, kanji ROM at 010000
	input         ioctl_download,
	input   [7:0] ioctl_index,        // 0 = boot.rom (IPL + kanji), 1 = MZT tape image
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	output        ioctl_wait,

	// SDRAM client (rtl/sdram.sv in 8-bit mode): main RAM and IPL ROM
	output reg        ram_rd,
	output reg        ram_we,
	output reg [24:0] ram_addr,
	output reg  [7:0] ram_din,
	input       [7:0] ram_dout,
	input             ram_ready,

	// Floppy image slots (hps_io sd_* bus), drives 1 and 2
	input       [1:0] img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	output     [31:0] sd_lba[2],
	output      [1:0] sd_rd,
	output      [1:0] sd_wr,
	input       [1:0] sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	output      [7:0] sd_buff_din[2],
	input             sd_buff_wr,
	output            fdd_busy,

	// Video, one pixel per ce_pix.
	output        ce_pix,
	output  [7:0] R,
	output  [7:0] G,
	output  [7:0] B,
	output        HSync,
	output        VSync,
	output        HBlank,
	output        VBlank,

	// Audio (silent for now).
	output [15:0] audio_l,
	output [15:0] audio_r,

	// Debug / sim visibility.
	output [15:0] cpu_pc,
	output        cpu_ce,
	output        cpu_m1_n,
	output reg    dbg_io_wr,
	output reg [7:0] dbg_io_port,
	output reg [7:0] dbg_io_data
);


///////////////////////////////////////////////////////////////////////////////////////////////////
// Resets
///////////////////////////////////////////////////////////////////////////////////////////////////

reg  ipl_reset;               // IPL reset from 8255 PC3 (BST) held low
wire rom_dl    = ioctl_download && ioctl_index == 8'd0;    // boot.rom: holds the machine in reset
wire tape_dl   = ioctl_download && ioctl_index == 8'd1;    // MZT tape image into SDRAM
wire sys_reset = reset | rom_dl | ipl_reset;
reg  [3:0] cpu_rst_cnt;       // special reset: CPU reset pulse
wire cpu_reset = sys_reset | (cpu_rst_cnt != 4'd0);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Clock enables
///////////////////////////////////////////////////////////////////////////////////////////////////

// MZ_FAST_SIM (verilator 'make fast'): clk_sys at half rate, 42.95 MHz, for faster simulation. Every rate below
// is derived from CLK_SYS_HZ; the video module halves its dot divider.
`ifdef MZ_FAST_SIM
localparam integer CLK_SYS_HZ = 42954545;
`else
localparam integer CLK_SYS_HZ = 85909091;
`endif
localparam integer CPU_HZ     = 6000000;
localparam integer CPU_HZ_LOW = 4000000;    // MZ-80B / MZ-2000 boot modes
localparam integer PIT_HZ     = 31250;
localparam integer OPN_HZ     = 2000000;

// CPU 6 MHz: fractional accumulator (the 24 MHz and 21.477 MHz crystals are not related).
// boot mode, latched at reset (CSP reads config.boot_mode at power on)
reg  [1:0] boot_m;
always @(posedge clk_sys) if (reset) boot_m <= boot_mode;
wire       mode_2500 = boot_m == 2'd0;
wire [27:0] cpu_hz = mode_2500 ? CPU_HZ : CPU_HZ_LOW;

reg [27:0] cpu_acc;
reg        ce_cpu;
always @(posedge clk_sys) begin
	ce_cpu <= 1'b0;
	if (reset) cpu_acc <= 28'd0;
	else if (cpu_acc >= CLK_SYS_HZ - cpu_hz) begin
		cpu_acc <= cpu_acc - (CLK_SYS_HZ - cpu_hz);
		ce_cpu  <= 1'b1;
	end
	else cpu_acc <= cpu_acc + cpu_hz;
end
assign cpu_ce = ce_cpu;

// 8253 CLK0: 31.25 kHz (24 MHz / 768)
reg [27:0] pit_acc;
reg        ce_pit;
always @(posedge clk_sys) begin
	ce_pit <= 1'b0;
	if (reset) pit_acc <= 28'd0;
	else if (pit_acc >= CLK_SYS_HZ - PIT_HZ) begin
		pit_acc <= pit_acc - (CLK_SYS_HZ - PIT_HZ);
		ce_pit  <= 1'b1;
	end
	else pit_acc <= pit_acc + PIT_HZ;
end

// YM2203 master clock: 2 MHz (24 MHz / 12)
reg [27:0] opn_acc;
reg        ce_opn;
always @(posedge clk_sys) begin
	ce_opn <= 1'b0;
	if (reset) opn_acc <= 28'd0;
	else if (opn_acc >= CLK_SYS_HZ - OPN_HZ) begin
		opn_acc <= opn_acc - (CLK_SYS_HZ - OPN_HZ);
		ce_opn  <= 1'b1;
	end
	else opn_acc <= opn_acc + OPN_HZ;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// CPU
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [15:0] cpu_a;
wire  [7:0] cpu_dout;
wire        mreq_n, iorq_n, rd_n, wr_n, m1_n;
reg   [7:0] cpu_din;
wire        int_n;
wire        sio_int_n, sio_ack_mine, sio_ieo, sio_sel;   // Z80 SIO (below)
wire  [7:0] sio_vector, sio_dout;
wire        wait_n;

// T80 v350 (rtl/T80_v350, Sorgelig's MiSTer version). The sim gets T80s as a ghdl synth netlist with these
// generics already fixed (verilator/Makefile, -g...): keep both in step.
`ifdef VERILATOR
T80s cpu
`else
T80s #(.Mode(0), .T2Write(1), .IOWait(1)) cpu
`endif
(
	.RESET_n(~cpu_reset),
	.CLK(clk_sys),
	.CEN(ce_cpu),
	.OUT0(1'b0),
	.WAIT_n(wait_n),
	.INT_n(int_n & sio_int_n),
	.NMI_n(1'b1),
	.BUSRQ_n(1'b1),
	.M1_n(m1_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.RFSH_n(),
	.HALT_n(),
	.BUSAK_n(),
	.A(cpu_a),
	.DI(cpu_din),
	.DO(cpu_dout)
);

assign cpu_pc   = cpu_a;
assign cpu_m1_n = m1_n;

// Bus cycles. T80se drives the strobes from CLKEN edges; each lasts at least one CPU clock (14 clk_sys), so
// edges are seen here as level changes. Side effects are committed at the end of a cycle (the address and
// data are still valid on that clock).
wire mem_rd = ~mreq_n & ~rd_n;
wire mem_wr = ~mreq_n & ~wr_n;
wire io_rd  = ~iorq_n & ~rd_n & m1_n;
wire io_wr  = ~iorq_n & ~wr_n & m1_n;
wire inta   = ~iorq_n & ~m1_n;
wire any_cyc = mem_rd | mem_wr | io_rd | io_wr;

reg mem_rd_d, mem_wr_d, io_rd_d, io_wr_d, inta_d, any_d, m1_d;
always @(posedge clk_sys) begin
	mem_rd_d <= mem_rd; mem_wr_d <= mem_wr; io_rd_d <= io_rd; io_wr_d <= io_wr; inta_d <= inta;
	any_d <= any_cyc; m1_d <= m1_n;
end
wire cyc_start  = any_cyc & ~any_d;
wire mem_rd_end = mem_rd_d & ~mem_rd;
wire mem_wr_end = mem_wr_d & ~mem_wr;
wire io_rd_end  = io_rd_d & ~io_rd;
wire io_wr_end  = io_wr_d & ~io_wr;
wire inta_end   = inta_d & ~inta;

wire [7:0] port = cpu_a[7:0];

wire [7:0] opn_dout, opn_pa;   // YM2203 (below): data out, port A output
wire       opn_pa_oe;

///////////////////////////////////////////////////////////////////////////////////////////////////
// MMU (B4, B5, B7)
///////////////////////////////////////////////////////////////////////////////////////////////////

reg  [5:0] page[0:7];
reg  [2:0] bank;
reg  [1:0] mmu_mode;
reg  [7:0] pio_pa;
reg  [7:0] kanji_bank;   // CF
reg  [4:0] dic_bank;     // CE

// MZ-2000 / MZ-80B compatibility windows (CSP memory.cpp update_vram_map), on top of the eight pages:
//   B7 mode 3 (MZ-2000): PIO port A bits 7-6 = 10: GVRAM plane vram_page at C000-FFFF; 11: text VRAM at D000-DFFF.
//   B7 mode 2 (MZ-80B):  10: text VRAM at D000-DFFF, GVRAM plane (vram_page bit 0) at E000-FFFF;
//                        11: the same at 5000-5FFF / 6000-7FFF.
// A GVRAM window is presented as the direct GVRAM page of that plane, the text VRAM as page 38, so the decode,
// the wait states and the display-period WAIT below apply unchanged.
reg  [2:0] vram_page;            // F7 (MZ-2000 display mode) or F4-F7 (MZ-80B display mode)
wire [1:0] disp_mod;             // text R0F MOD (video module)
always @(posedge clk_sys) begin
	if (sys_reset) vram_page <= 3'd0;
	else if (io_wr_end && ((disp_mod == 2'd1 && port == 8'hF7) || (disp_mod == 2'd2 && port[7:2] == 6'b111101)))
		vram_page <= cpu_dout[2:0];
end
wire [1:0] vram_sel = pio_pa[7:6];
wire [5:0] page_raw = page[cpu_a[15:13]];
reg  [5:0] cur_page;
reg [12:0] cur_off;
reg        compat_win;           // the access is in a compatibility window (1 wait in those modes, CSP)
always @(*) begin
	cur_page = page_raw; cur_off = cpu_a[12:0]; compat_win = 1'b0;
	if (mmu_mode == 2'd3) begin
		if (vram_sel == 2'b10 && cpu_a[15:14] == 2'b11) begin
			cur_page = {3'b100, vram_page[1:0], cpu_a[13]}; compat_win = 1'b1;          // plane, offset 0-3FFF
		end
		else if (vram_sel == 2'b11 && cpu_a[15:12] == 4'hD) begin
			cur_page = 6'h38; cur_off = {1'b0, cpu_a[11:0]}; compat_win = 1'b1;
		end
	end
	else if (mmu_mode == 2'd2 && vram_sel[1]) begin
		if (cpu_a[15:12] == (vram_sel[0] ? 4'h5 : 4'hD)) begin
			cur_page = 6'h38; cur_off = {1'b0, cpu_a[11:0]}; compat_win = 1'b1;
		end
		else if (cpu_a[15:13] == (vram_sel[0] ? 3'd3 : 3'd7)) begin
			cur_page = {4'b1000, vram_page[0], 1'b0}; compat_win = 1'b1;                 // plane B/R, 8 KB
		end
	end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Memories
///////////////////////////////////////////////////////////////////////////////////////////////////

wire ld_ipl   = rom_dl && ioctl_addr[24:15] == 10'd0;
wire ld_kanji = rom_dl && ioctl_addr[24:16] >= 9'd1 && ioctl_addr[24:16] <= 9'd4;
wire ld_tape  = tape_dl && ioctl_addr[24:20] == 5'd0;      // up to 1 MB at SDRAM 100000

// SDRAM holds main RAM 256 KB (pages 00-1F) at 000000-03FFFF, the IPL ROM (pages 34-37) at 040000-047FFF and the
// kanji ROM at 080000-0BFFFF (CPU window: page 39 with CF bit 7; text raster glyph fetches). The controller
// (rtl/sdram.sv) takes a request on a rising edge of rd or we and drops 'ready' until it is done. Clients, in
// priority order: the text raster (a glyph byte per text cell, requested two cells ahead of display), posted CPU
// writes and ROM-download writes, CPU reads (issued at the start of the memory cycle; the CPU waits only if the data
// isn't back by T2, at 6 MHz it normally is: T1 to T2 is 14 clk_sys).
wire        kwin         = cur_page == 6'h39 && kanji_bank[7] && cur_off[12:11] == 2'd0;
wire        ram_page     = !cur_page[5] || cur_page[5:2] == 4'b1101 || kwin;
wire [24:0] cpu_ram_addr = kwin        ? {5'd0, 2'b10, kanji_bank[6:0], cur_off[10:0]} :
                           cur_page[5] ? {6'd0, 1'b1, 3'b000, cur_page[1:0], cur_off} : {7'd0, cur_page[4:0], cur_off};

wire [17:0] kanji_ld_addr = ioctl_addr[17:0] - 18'h10000;

// Data recorder (rtl/mz2500_cmt.sv): the tape image is downloaded to SDRAM 100000 (ioctl index 1); the player
// reads it a byte at a time through the SDRAM arbiter (lowest priority).
reg        tape_loaded;
reg [19:0] tape_len;
reg        tape_dl_d;
always @(posedge clk_sys) begin
	tape_dl_d <= tape_dl;
	if (reset) begin tape_loaded <= 1'b0; tape_len <= 20'd0; end
	else if (tape_dl && !tape_dl_d) begin tape_loaded <= 1'b0; tape_len <= 20'd0; end
	else if (ld_tape && ioctl_wr) tape_len <= ioctl_addr[19:0] + 20'd1;
	else if (!tape_dl && tape_dl_d) tape_loaded <= tape_len != 20'd0;
end
wire        cmt_rd_req;
wire [19:0] cmt_rd_addr;
reg         cmt_rd_ack, cmt_rd_busy;
reg   [7:0] cmt_rd_q;
wire        cmt_read, cmt_tready_n, cmt_wready_n, cmt_tend, cmt_motor;
wire [17:0] kanji_raddr;
wire        kanji_req;
wire  [6:0] kanji_tag;
reg         kanji_ack;
reg   [6:0] kanji_ack_tag;
reg   [7:0] kanji_q;

localparam RAM_IDLE = 3'd0, RAM_RD = 3'd1, RAM_WR = 3'd2, RAM_KR = 3'd3, RAM_TR = 3'd4;
reg  [2:0] ram_st;
reg  [1:0] ram_cnt;
reg        ram_wpend;
reg        ld_pend;              // ROM / tape download write (own slot: the CPU may be writing at the same time)
reg [24:0] ld_addr;
reg  [7:0] ld_data;
reg [24:0] ram_waddr;
reg  [7:0] ram_wdata;
reg        ram_rdone;
reg  [7:0] ram_q;

always @(posedge clk_sys) begin
	kanji_ack <= 1'b0;
	cmt_rd_ack <= 1'b0;
	if (cmt_rd_ack) cmt_rd_busy <= 1'b0;   // the player has dropped or replaced its request by the next clock
	if (cyc_start) ram_rdone <= 1'b0;
	case (ram_st)
		RAM_IDLE:
			if (kanji_req && !ioctl_download) begin
				ram_rd <= 1'b1; ram_addr <= {5'd0, 2'b10, kanji_raddr}; kanji_ack_tag <= kanji_tag;
				ram_cnt <= 2'd3; ram_st <= RAM_KR;
			end
			else if (ram_wpend) begin
				ram_we <= 1'b1; ram_addr <= ram_waddr; ram_din <= ram_wdata;
				ram_wpend <= 1'b0; ram_cnt <= 2'd3; ram_st <= RAM_WR;
			end
			else if (ld_pend) begin
				ram_we <= 1'b1; ram_addr <= ld_addr; ram_din <= ld_data;
				ld_pend <= 1'b0; ram_cnt <= 2'd3; ram_st <= RAM_WR;
			end
			else if (mem_rd && ram_page && !ram_rdone && !cpu_reset) begin
				ram_rd <= 1'b1; ram_addr <= cpu_ram_addr; ram_cnt <= 2'd3; ram_st <= RAM_RD;
			end
			else if (cmt_rd_req && !cmt_rd_busy) begin
				ram_rd <= 1'b1; ram_addr <= {4'd0, 1'b1, cmt_rd_addr}; ram_cnt <= 2'd3; ram_st <= RAM_TR; cmt_rd_busy <= 1'b1;
			end
		RAM_RD:
			if (ram_cnt != 2'd0) ram_cnt <= ram_cnt - 2'd1;
			else if (ram_ready) begin ram_q <= ram_dout; ram_rdone <= 1'b1; ram_rd <= 1'b0; ram_st <= RAM_IDLE; end
		RAM_KR:
			if (ram_cnt != 2'd0) ram_cnt <= ram_cnt - 2'd1;
			else if (ram_ready) begin kanji_q <= ram_dout; kanji_ack <= 1'b1; ram_rd <= 1'b0; ram_st <= RAM_IDLE; end
		RAM_TR:
			if (ram_cnt != 2'd0) ram_cnt <= ram_cnt - 2'd1;
			else if (ram_ready) begin cmt_rd_q <= ram_dout; cmt_rd_ack <= 1'b1; ram_rd <= 1'b0; ram_st <= RAM_IDLE; end
		RAM_WR:
			if (ram_cnt != 2'd0) ram_cnt <= ram_cnt - 2'd1;
			else if (ram_ready) begin ram_we <= 1'b0; ram_st <= RAM_IDLE; end
	endcase
	// new writes (after the state machine so they win over the clear above)
	if (mem_wr_end && !cur_page[5]) begin
		ram_wpend <= 1'b1; ram_waddr <= cpu_ram_addr; ram_wdata <= cpu_dout;
	end
	if (ld_ipl && ioctl_wr) begin
		ld_pend <= 1'b1; ld_addr <= 25'h40000 | {10'd0, ioctl_addr[14:0]}; ld_data <= ioctl_dout;
	end
	if (ld_tape && ioctl_wr) begin
		ld_pend <= 1'b1; ld_addr <= {4'd0, 1'b1, ioctl_addr[19:0]}; ld_data <= ioctl_dout;
	end
	if (ld_kanji && ioctl_wr) begin
		ld_pend <= 1'b1; ld_addr <= {5'd0, 2'b10, kanji_ld_addr}; ld_data <= ioctl_dout;
	end
	if (reset) begin
		ram_st <= RAM_IDLE; ram_rd <= 1'b0; ram_we <= 1'b0; ram_wpend <= 1'b0; ld_pend <= 1'b0; ram_rdone <= 1'b0; cmt_rd_busy <= 1'b0;
	end
end

assign ioctl_wait = ld_pend || (ioctl_download && ram_st != RAM_IDLE);
// The CPU waits for its SDRAM read, and on a write while the previous posted write hasn't been issued yet
// (one-entry write buffer: a PUSH right behind a raster glyph fetch would otherwise overwrite the first byte).
wire   ram_wait    = (mem_rd && ram_page && !ram_rdone) || (mem_wr && !cur_page[5] && ram_wpend);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Video
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [7:0] vid_io_dout, vid_mem_dout;
wire       gv_busy;
wire       hblank_t, vblank_t, hblank_g, vblank_g;
reg  [7:0] ppi_pa, ppi_pc;

mz2500_video video
(
	.clk(clk_sys),
	.reset(sys_reset),
	.lines400(lines400),

	.io_addr(port),
	.io_hi(cpu_a[15:8]),
	.io_din(cpu_dout),
	.io_wr_stb(io_wr_end),
	.io_dout(vid_io_dout),

	.mem_page(cur_page),
	.mem_off(cur_off),
	.mem_din(cpu_dout),
	.mem_wr_stb(mem_wr_end),
	.mem_rd_stb(mem_rd_end),
	.mem_dout(vid_mem_dout),
	.gv_busy(gv_busy),

	.hblank_t(hblank_t),
	.vblank_t(vblank_t),
	.hblank_g(hblank_g),
	.vblank_g(vblank_g),

	.column80(pio_pa[5]),
	.screen_mask(ppi_pc[0]),
	.pal4096(~opn_pa[2]),
	.boot_mode(boot_m),
	.vid_n(ppi_pa[4]),
	.vram_page(vram_page),
	.disp_mod(disp_mod),

	.kanji_addr(kanji_raddr),
	.kanji_req(kanji_req),
	.kanji_tag(kanji_tag),
	.kanji_ack(kanji_ack),
	.kanji_ack_tag(kanji_ack_tag),
	.kanji_data(kanji_q),

	.ce_pix(ce_pix),
	.R(R), .G(G), .B(B),
	.HSync(HSync), .VSync(VSync),
	.HBlank(HBlank), .VBlank(VBlank)
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Wait states (CSP memory.cpp / mz2500.cpp, 6 MHz values)
///////////////////////////////////////////////////////////////////////////////////////////////////

wire pg_gv  = cur_page[5:4] == 2'b10 || cur_page[5:2] == 4'b1100;   // GVRAM 20-2F, RMW 30-33
wire pg_tv  = cur_page == 6'h38 || cur_page == 6'h39;               // text VRAM, PCG / kanji

reg [2:0] wait_cnt;
reg       wait_t, wait_g;

always @(posedge clk_sys) begin
	if (cpu_reset) begin
		wait_cnt <= 3'd0; wait_t <= 1'b0; wait_g <= 1'b0;
	end
	else begin
		if (cyc_start) begin
			if (mem_rd | mem_wr) begin
				if (!mode_2500)                wait_cnt <= (cur_page[5:2] == 4'b1100 || compat_win) ? 3'd1 : 3'd0;  // 80B/2000
				else if (!m1_n)                wait_cnt <= 3'd1;
				else if (cur_page[5:4] == 2'b10) wait_cnt <= 3'd1;   // GVRAM
				else if (cur_page[5:2] == 4'b1100) wait_cnt <= 3'd2; // RMW
				else if (cur_page == 6'h38)    wait_cnt <= 3'd1;
				else if (cur_page == 6'h39)    wait_cnt <= 3'd2;
				else                           wait_cnt <= 3'd0;
				if (pg_tv && !hblank_t && !vblank_t) wait_t <= 1'b1;
				if (pg_gv && !hblank_g && !vblank_g) wait_g <= 1'b1;
			end
			else begin
				if (mode_2500 && (port[7:3] == 5'b11011 || port[7:2] == 6'b111010)) wait_cnt <= 3'd1;   // FDC, PIO
				else if (port[7:1] == 7'b1100100) wait_cnt <= 3'd1;                                       // OPN
				else if (port == 8'hCC) wait_cnt <= 3'd3;
				else wait_cnt <= 3'd0;
			end
		end
		else if (ce_cpu && wait_cnt != 3'd0 && !wait_t && !wait_g) wait_cnt <= wait_cnt - 3'd1;
		if (hblank_t || vblank_t) wait_t <= 1'b0;
		if (hblank_g || vblank_g) wait_g <= 1'b0;
	end
end

assign wait_n = (wait_cnt == 3'd0) && !wait_t && !wait_g && !(gv_busy && pg_gv && (mem_rd | mem_wr)) && !ram_wait;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Interrupts: interrupt block (C6/C7), RETI detection
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [2:0] pit_out;
wire       int_ack_mine;
wire [7:0] int_vector;

// RETI = ED 4D in two consecutive opcode fetches
reg  [7:0] op_cur, op_prev;
reg        reti_stb;
always @(posedge clk_sys) begin
	reti_stb <= 1'b0;
	if (mem_rd & ~m1_n) op_cur <= cpu_din;
	if (mem_rd_end && !m1_d) begin
		op_prev <= op_cur;
		if (op_prev == 8'hED && op_cur == 8'h4D) reti_stb <= 1'b1;
	end
end

// Daisy chain: PIO (no interrupts used) -> SIO -> interrupt block. RETI goes to the SIO first if it has a
// channel in service.

mz2500_sio sio
(
	.clk(clk_sys),
	.reset(sys_reset),
	.io_addr(port),
	.din(cpu_dout),
	.wr_stb(io_wr_end),
	.rd_stb(io_rd_end),
	.dout(sio_dout),
	.sel(sio_sel),
	.mouse_sel(opn_pa[3]),
	.ps2_mouse(ps2_mouse),
	.int_n(sio_int_n),
	.ack_mine(sio_ack_mine),
	.vector(sio_vector),
	.ack_stb(inta_end),
	.reti_stb(reti_stb),
	.ieo(sio_ieo)
);

mz2500_int intc
(
	.clk(clk_sys),
	.reset(sys_reset),
	.wr_stb(io_wr_end && port[7:1] == 7'b1100011),   // C6, C7
	.a0(port[0]),
	.din(cpu_dout),
	.src({1'b0, 1'b0, pit_out[0], vblank_g}),
	.iei(sio_ieo),
	.ack_stb(inta_end && !sio_ack_mine),
	.reti_stb(reti_stb && sio_ieo),
	.int_n(int_n),
	.ack_mine(int_ack_mine),
	.vector(int_vector)
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// 8253 (E4-E7), gate pulses (F0-F3)
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [7:0] pit_dout;
reg  [2:0] pit_out_d;
always @(posedge clk_sys) pit_out_d <= pit_out;
wire gate_pulse = io_wr_end && port[7:2] == 6'b111100;

mz_pit8253 pit
(
	.clk(clk_sys),
	.reset(sys_reset),
	.addr(port[1:0]),
	.din(cpu_dout),
	.dout(pit_dout),
	.wr_stb(io_wr_end && port[7:2] == 6'b111001),
	.rd_stb(io_rd_end && port[7:2] == 6'b111001),
	.clk_ce({pit_out_d[1] & ~pit_out[1], pit_out_d[0] & ~pit_out[0], ce_pit}),
	.gate(3'b111),
	.gate_trig({1'b0, gate_pulse, gate_pulse}),
	.out(pit_out)
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// 8255 (E0-E3): mode 0, port A out, port B in, port C out
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [7:0] kbd_data;
wire [7:0] ppi_pb = {kbd_data[7], cmt_read, cmt_tready_n, cmt_wready_n, cmt_tend, 1'b1, 1'b1, ~vblank_g};
reg  [7:0] ppi_pc_new;
reg [13:0] bst_cnt;   // 100 us at clk_sys

always @(*) begin
	ppi_pc_new = ppi_pc;
	if (io_wr_end && port == 8'hE2) ppi_pc_new = cpu_dout;
	if (io_wr_end && port == 8'hE3) begin
		if (cpu_dout[7]) ppi_pc_new = 8'h00;
		else ppi_pc_new[cpu_dout[3:1]] = cpu_dout[0];
	end
end

always @(posedge clk_sys) begin
	ipl_reset <= 1'b0;
	if (reset | rom_dl | ipl_reset) begin
		ppi_pa <= 8'h00; ppi_pc <= 8'h00;
		cpu_rst_cnt <= 4'd0;
		bst_cnt <= 14'd0;
	end
	else begin
		if (cpu_rst_cnt != 4'd0) cpu_rst_cnt <= cpu_rst_cnt - 4'd1;
		if (io_wr_end && port == 8'hE0) ppi_pa <= cpu_dout;
		if (io_wr_end && port == 8'hE3 && cpu_dout[7]) ppi_pa <= 8'h00;
		ppi_pc <= ppi_pc_new;
		// NST (PC1) 0 -> 1: special reset
		if (!ppi_pc[1] && ppi_pc_new[1]) cpu_rst_cnt <= 4'd15;
		// BST (PC3) 1 -> 0 starts the IPL reset timer, 0 -> 1 cancels it (CSP cmt.cpp, 100 us)
		if (ppi_pc[3] && !ppi_pc_new[3]) bst_cnt <= CLK_SYS_HZ / 10000;   // 100 us
		else if (ppi_pc_new[3]) bst_cnt <= 14'd0;
		else if (bst_cnt == 14'd1) begin bst_cnt <= 14'd0; ipl_reset <= 1'b1; end
		else if (bst_cnt != 14'd0) bst_cnt <= bst_cnt - 14'd1;
	end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// MMU registers and small devices
///////////////////////////////////////////////////////////////////////////////////////////////////

reg  [7:0] pio_ctl_a, pio_ctl_b;

wire       rtc_pulse_n;
wire [3:0] rtc_dout;
// OPN port B: CSP 37h (+40h for 200 lines); bit 3 is the RTC pulse output
wire [7:0] opn_port_b = {1'b0, ~lines400, boot_m != 2'd2, boot_m != 2'd1, rtc_pulse_n, 3'b111};

rp5c15 #(.CLK_HZ(CLK_SYS_HZ)) rtc_chip
(
	.clk(clk_sys),
	.reset(sys_reset),
	.addr(cpu_a[11:8]),
	.din(cpu_dout[3:0]),
	.wr_stb(io_wr_end && port == 8'hCC),
	.dout(rtc_dout),
	.rtc(rtc),
	.pulse_n(rtc_pulse_n)
);

always @(posedge clk_sys) begin
	if (sys_reset) begin
		page[0] <= 6'h34; page[1] <= 6'h35; page[2] <= 6'h36; page[3] <= 6'h37;
		page[4] <= 6'h04; page[5] <= 6'h05; page[6] <= 6'h06; page[7] <= 6'h07;
		bank <= 3'd0; mmu_mode <= 2'd0;
		kanji_bank <= 8'd0; dic_bank <= 5'd0;
		pio_pa <= 8'h00; pio_ctl_a <= 8'd0; pio_ctl_b <= 8'd0;
	end
	else begin
		// special reset: map 00-07
		if (!ppi_pc[1] && ppi_pc_new[1]) begin
			page[0] <= 6'h00; page[1] <= 6'h01; page[2] <= 6'h02; page[3] <= 6'h03;
			page[4] <= 6'h04; page[5] <= 6'h05; page[6] <= 6'h06; page[7] <= 6'h07;
			bank <= 3'd0;
		end
		if (io_rd_end && port == 8'hB5) bank <= bank + 3'd1;
		if (io_wr_end) begin
			case (port)
				8'hB4: bank <= cpu_dout[2:0];
				8'hB5: begin page[bank] <= cpu_dout[5:0]; bank <= bank + 3'd1; end
				8'hB7: begin
					if (!mmu_mode[1] && cpu_dout[1]) begin
						page[0] <= 6'h00; page[1] <= 6'h01; page[2] <= 6'h02; page[3] <= 6'h03;
						page[4] <= 6'h04; page[5] <= 6'h05; page[6] <= 6'h06; page[7] <= 6'h07;
					end
					mmu_mode <= cpu_dout[1:0];
				end
				8'hCE: dic_bank <= cpu_dout[4:0];
				8'hCF: kanji_bank <= cpu_dout;
				8'hE8: pio_pa <= cpu_dout;
				8'hE9: pio_ctl_a <= cpu_dout;
				8'hEB: pio_ctl_b <= cpu_dout;
				default: ;
			endcase
		end
	end
end

wire [7:0] fdc_din;
mz2500_fdc fdc
(
	.clk_sys(clk_sys),
	.reset(sys_reset),
	.ce_cpu(ce_cpu),
	.io_addr(port),
	.io_rd(io_rd),
	.io_wr(io_wr),
	.io_dout(cpu_dout),
	.io_din(fdc_din),
	.drsel(opn_pa[1]),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.busy(fdd_busy)
);

// YM2203 (jotego jt03) at C8 (address / status) and C9 (data). Port A (output): bit 1 DRSEL swaps the floppy
// units, bit 2 PLT selects the 4096-colour board, bit 3 the mouse. Port B (input): the front-panel switches.
// The OPN's IRQ is not connected on the MZ-2500 (software polls the timer flags in the status register).
// jt12 needs a reset of at least 6 cen cycles and must not be written during it: stretch the machine reset.
reg  [9:0] opn_rst_cnt;
always @(posedge clk_sys) begin
	if (sys_reset) opn_rst_cnt <= 10'd1023;
	else if (opn_rst_cnt != 10'd0) opn_rst_cnt <= opn_rst_cnt - 10'd1;
end
wire        opn_rst = sys_reset || opn_rst_cnt != 10'd0;
wire signed [15:0] opn_snd;

jt03 opn
(
	.rst(opn_rst),
	.clk(clk_sys),
	.cen(ce_opn),
	.din(cpu_dout),
	.addr(port[0]),
	.cs_n(~(io_wr_end && port[7:1] == 7'b1100100 && !opn_rst)),
	.wr_n(1'b0),
	.dout(opn_dout),
	.irq_n(),
	.IOA_in(opn_pa_oe ? opn_pa : 8'hFF),   // an output port reads back its own pins (IPL does read-modify-write)
	.IOB_in(opn_port_b),
	.IOA_out(opn_pa),
	.IOB_out(),
	.IOA_oe(opn_pa_oe),
	.IOB_oe(),
	.psg_A(), .psg_B(), .psg_C(),
	.fm_snd(),
	.psg_snd(),
	.snd(opn_snd),
	.snd_sample(),
	.debug_view()
);

// Mix: OPN plus the 1-bit beeper (8255 PC2).
wire signed [15:0] beep = ppi_pc[2] ? 16'sd4096 : 16'sd0;
assign audio_l = opn_snd + beep;
assign audio_r = opn_snd + beep;

// Joystick port EF (CSP joystick.cpp). Write: bits 1-0 / 3-2 trigger outputs of port 1 / 2 (0 pulls the trigger
// input low), bits 4 / 5 common pins (0 = read the directions), bit 6 selects port 2. Read: bits 3-0 right, left,
// down, up and bit 5 / 4 trigger A / B of the selected port, active low; bits 7-6 = 0.
reg  [7:0] joy_mode;
always @(posedge clk_sys) begin
	if (sys_reset) joy_mode <= 8'h0F;
	else if (io_wr_end && port == 8'hEF) joy_mode <= cpu_dout;
end
wire [5:0] joy_sel = joy_mode[6] ? joy1 : joy0;
wire       joy_dir = joy_mode[6] ? !joy_mode[5] : !joy_mode[4];
wire       trg_a   = joy_mode[6] ? joy_mode[2] : joy_mode[0];
wire       trg_b   = joy_mode[6] ? joy_mode[3] : joy_mode[1];
wire [7:0] joy_rd  = {2'b00, ~(joy_sel[4] | ~trg_a), ~(joy_sel[5] | ~trg_b),
                      ~(joy_dir & joy_sel[0]), ~(joy_dir & joy_sel[1]), ~(joy_dir & joy_sel[2]), ~(joy_dir & joy_sel[3])};

mz2500_cmt #(.CLK_HZ(CLK_SYS_HZ)) cmt
(
	.clk(clk_sys),
	.reset(sys_reset),
	.mz80b(boot_m == 2'd2),
	.fmt80b(boot_m != 2'd0),
	.pa(ppi_pa),
	.loaded(tape_loaded),
	.tape_len(tape_len),
	.rd_req(cmt_rd_req),
	.rd_addr(cmt_rd_addr),
	.rd_ack(cmt_rd_ack),
	.rd_data(cmt_rd_q),
	.read(cmt_read),
	.tready_n(cmt_tready_n),
	.wready_n(cmt_wready_n),
	.tend(cmt_tend),
	.motor(cmt_motor)
);

mz2500_kbd kbd
(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key(ps2_key),
	.column(pio_pa[4:0]),
	.data(kbd_data)
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// CPU data input
///////////////////////////////////////////////////////////////////////////////////////////////////

reg [7:0] mem_dout, io_dout;

always @(*) begin
	mem_dout = 8'hFF;
	casez (cur_page)
		6'b0?????, 6'b1101??: mem_dout = ram_q;
		6'b10????, 6'b1100??, 6'h38: mem_dout = vid_mem_dout;
		6'h39: mem_dout = kwin ? ram_q : vid_mem_dout;
		default: mem_dout = 8'hFF;
	endcase
end

always @(*) begin
	io_dout = 8'hFF;
	if (sio_sel) io_dout = sio_dout;
	else case (port)
		8'hB4: io_dout = {5'd0, bank};
		8'hB5: io_dout = {2'd0, page[bank]};
		8'hBC, 8'hBD, 8'hBE, 8'hBF, 8'hF4, 8'hF5, 8'hF6, 8'hF7: io_dout = vid_io_dout;
		8'hC8, 8'hC9: io_dout = opn_dout;
		8'hD8, 8'hD9, 8'hDA, 8'hDB: io_dout = fdc_din;
		8'hE0: io_dout = ppi_pa;
		8'hE1: io_dout = ppi_pb;
		8'hE2: io_dout = ppi_pc;
		8'hE4, 8'hE5, 8'hE6, 8'hE7: io_dout = pit_dout;
		8'hE8: io_dout = pio_pa;
		8'hEA: io_dout = kbd_data;
		8'hEF: io_dout = joy_rd;
		8'hCC: io_dout = {4'h0, rtc_dout};                       // RP5C15, register on A11-A8
		8'hCA: io_dout = 8'h30;                                  // MZ-1E26 phone unit idle (FFh = 'powered from the phone')
		default: io_dout = 8'hFF;
	endcase
end

always @(*) begin
	if (inta)        cpu_din = sio_ack_mine ? sio_vector : int_ack_mine ? int_vector : 8'hFF;
	else if (~iorq_n) cpu_din = io_dout;
	else             cpu_din = mem_dout;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Debug
///////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk_sys) begin
	dbg_io_wr <= io_wr;
	if (io_wr) begin
		dbg_io_port <= port;
		dbg_io_data <= cpu_dout;
	end
end

endmodule
