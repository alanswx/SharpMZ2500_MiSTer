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
//   * Memory: 256 KB main RAM and the 32 KB IPL ROM in SDRAM, kanji ROM 256 KB in block RAM, ROMs loaded
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
	input  [10:0] ps2_key,

	// ROM download (hps_io ioctl): boot.rom = IPL at 000000, kanji ROM at 010000
	input         ioctl_download,
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
wire sys_reset = reset | ioctl_download | ipl_reset;
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
localparam integer PIT_HZ     = 31250;
localparam integer OPN_HZ     = 2000000;

// CPU 6 MHz: fractional accumulator (the 24 MHz and 21.477 MHz crystals are not related).
reg [27:0] cpu_acc;
reg        ce_cpu;
always @(posedge clk_sys) begin
	ce_cpu <= 1'b0;
	if (reset) cpu_acc <= 28'd0;
	else if (cpu_acc >= CLK_SYS_HZ - CPU_HZ) begin
		cpu_acc <= cpu_acc - (CLK_SYS_HZ - CPU_HZ);
		ce_cpu  <= 1'b1;
	end
	else cpu_acc <= cpu_acc + CPU_HZ;
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
	.INT_n(int_n),
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
reg  [7:0] kanji_bank;   // CF
reg  [4:0] dic_bank;     // CE

wire [5:0]  cur_page = page[cpu_a[15:13]];
wire [12:0] cur_off  = cpu_a[12:0];

///////////////////////////////////////////////////////////////////////////////////////////////////
// Memories
///////////////////////////////////////////////////////////////////////////////////////////////////

wire ld_ipl   = ioctl_download && ioctl_addr[24:15] == 10'd0;
wire ld_kanji = ioctl_download && ioctl_addr[24:16] >= 9'd1 && ioctl_addr[24:16] <= 9'd4;

// Main RAM 256 KB (pages 00-1F) and the IPL ROM (pages 34-37) are in SDRAM: byte address 000000-03FFFF for the
// RAM, 040000-047FFF for the IPL. The controller (rtl/sdram.sv) takes a request on a rising edge of rd or we and
// drops 'ready' until it is done. CPU reads are issued at the start of the memory cycle and the CPU waits only if
// the data isn't back by T2 (at 6 MHz it normally is: T1 to T2 is 14 clk_sys); writes are posted at the end of
// the cycle. The IPL is written here during the ROM download (ioctl_wait holds hps_io).
wire        ram_page     = !cur_page[5] || cur_page[5:2] == 4'b1101;
wire [24:0] cpu_ram_addr = cur_page[5] ? {6'd0, 1'b1, 3'b000, cur_page[1:0], cur_off} : {7'd0, cur_page[4:0], cur_off};

localparam RAM_IDLE = 2'd0, RAM_RD = 2'd1, RAM_WR = 2'd2;
reg  [1:0] ram_st;
reg  [1:0] ram_cnt;
reg        ram_wpend;
reg [24:0] ram_waddr;
reg  [7:0] ram_wdata;
reg        ram_rdone;
reg  [7:0] ram_q;

always @(posedge clk_sys) begin
	if (cyc_start) ram_rdone <= 1'b0;
	case (ram_st)
		RAM_IDLE:
			if (ram_wpend) begin
				ram_we <= 1'b1; ram_addr <= ram_waddr; ram_din <= ram_wdata;
				ram_wpend <= 1'b0; ram_cnt <= 2'd3; ram_st <= RAM_WR;
			end
			else if (mem_rd && ram_page && !ram_rdone && !cpu_reset) begin
				ram_rd <= 1'b1; ram_addr <= cpu_ram_addr; ram_cnt <= 2'd3; ram_st <= RAM_RD;
			end
		RAM_RD:
			if (ram_cnt != 2'd0) ram_cnt <= ram_cnt - 2'd1;
			else if (ram_ready) begin ram_q <= ram_dout; ram_rdone <= 1'b1; ram_rd <= 1'b0; ram_st <= RAM_IDLE; end
		RAM_WR:
			if (ram_cnt != 2'd0) ram_cnt <= ram_cnt - 2'd1;
			else if (ram_ready) begin ram_we <= 1'b0; ram_st <= RAM_IDLE; end
		default: ram_st <= RAM_IDLE;
	endcase
	// new writes (after the state machine so they win over the clear above)
	if (mem_wr_end && !cur_page[5]) begin
		ram_wpend <= 1'b1; ram_waddr <= cpu_ram_addr; ram_wdata <= cpu_dout;
	end
	if (ld_ipl && ioctl_wr) begin
		ram_wpend <= 1'b1; ram_waddr <= 25'h40000 | {10'd0, ioctl_addr[14:0]}; ram_wdata <= ioctl_dout;
	end
	if (reset) begin
		ram_st <= RAM_IDLE; ram_rd <= 1'b0; ram_we <= 1'b0; ram_wpend <= 1'b0; ram_rdone <= 1'b0;
	end
end

assign ioctl_wait = ram_wpend || ram_st != RAM_IDLE;
wire   ram_wait    = mem_rd && ram_page && !ram_rdone;

// Kanji ROM 256 KB: CPU window (page 39 with CF bit 7) on port A, text raster on port B
wire [17:0] kanji_raddr;
wire  [7:0] kanji_rdata, kanji_cdata;
wire [17:0] kanji_ld_addr = ioctl_addr[17:0] - 18'h10000;
dpram #(.AW(18), .DW(8)) kanji_rom
(
	.clk(clk_sys),
	.a_addr(ioctl_download ? kanji_ld_addr : {kanji_bank[6:0], cur_off[10:0]}),
	.a_we(ld_kanji & ioctl_wr),
	.a_din(ioctl_dout),
	.a_dout(kanji_cdata),
	.b_addr(kanji_raddr),
	.b_dout(kanji_rdata)
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Video
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [7:0] vid_io_dout, vid_mem_dout;
wire       gv_busy;
wire       hblank_t, vblank_t, hblank_g, vblank_g;
reg  [7:0] ppi_pa, ppi_pc;
reg  [7:0] pio_pa;

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

	.kanji_addr(kanji_raddr),
	.kanji_data(kanji_rdata),

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
				if (!m1_n)                     wait_cnt <= 3'd1;
				else if (cur_page[5:4] == 2'b10) wait_cnt <= 3'd1;   // GVRAM
				else if (cur_page[5:2] == 4'b1100) wait_cnt <= 3'd2; // RMW
				else if (cur_page == 6'h38)    wait_cnt <= 3'd1;
				else if (cur_page == 6'h39)    wait_cnt <= 3'd2;
				else                           wait_cnt <= 3'd0;
				if (pg_tv && !hblank_t && !vblank_t) wait_t <= 1'b1;
				if (pg_gv && !hblank_g && !vblank_g) wait_g <= 1'b1;
			end
			else begin
				if (port[7:3] == 5'b11011 || port[7:2] == 6'b111010 || port[7:1] == 7'b1100100) wait_cnt <= 3'd1;
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

mz2500_int intc
(
	.clk(clk_sys),
	.reset(sys_reset),
	.wr_stb(io_wr_end && port[7:1] == 7'b1100011),   // C6, C7
	.a0(port[0]),
	.din(cpu_dout),
	.src({1'b0, 1'b0, pit_out[0], vblank_g}),
	.iei(1'b1),
	.ack_stb(inta_end),
	.reti_stb(reti_stb),
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
wire [7:0] ppi_pb = {kbd_data[7], 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, ~vblank_g};
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
	if (reset | ioctl_download | ipl_reset) begin
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

wire [7:0] opn_port_b = {1'b0, ~lines400, 1'b1, 1'b1, 1'b0, 3'b111};   // CSP 37h (+40h for 200 lines)

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
		6'h39: mem_dout = (kanji_bank[7] && cur_off[12:11] == 2'd0) ? kanji_cdata : vid_mem_dout;
		default: mem_dout = 8'hFF;
	endcase
end

always @(*) begin
	io_dout = 8'hFF;
	case (port)
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
		8'hEF: io_dout = 8'h3F;                                  // joysticks: nothing pressed
		8'hCA: io_dout = 8'h30;                                  // MZ-1E26 phone unit idle (FFh = 'powered from the phone')
		default: io_dout = 8'hFF;
	endcase
end

always @(*) begin
	if (inta)        cpu_din = int_ack_mine ? int_vector : 8'hFF;
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
