//=======================================================================================================
//
// mz2500.sv - Sharp MZ-2500 machine top (BOOTSTRAP PLACEHOLDER).
//
// This is the module both the MiSTer top level (SharpMZ2500.sv) and the Verilator harness (verilator/sim.v)
// instantiate. For now it only proves the plumbing:
//
//   * clock enables from clk_sys = 85.909 MHz (24 x 3.579545 MHz): dot clock 21.477 MHz (400 lines, /4) or
//     14.318 MHz (200 lines, /6), CPU 6 MHz from a fractional accumulator (24 MHz crystal / 4);
//   * MZ-2500 video timing (400 lines: 864 x 448 dots, 24.86 kHz, 55.49 Hz; 200 lines: 896 x 262 dots,
//     15.98 kHz, 60.99 Hz) carrying a test pattern;
//   * a T80 (VHDL, through GHDL in the sim) running a tiny built-in program that OUTs a counter to port 00,
//     whose value colours a block of the test pattern.
//
// Everything here gets replaced: see TODO.md milestone 1 and docs/design.md.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500
(
	input         clk_sys,        // 85.909091 MHz
	input         reset,
	input         lines400,       // front-panel 200/400-line switch: 1 = 400 lines (24 kHz), 0 = 200 lines (15 kHz)
	input  [10:0] ps2_key,        // hps_io ps2_key (not used yet: keyboard is TODO phase 3)

	// Video, one pixel per ce_pix.
	output reg    ce_pix,
	output reg [7:0] R,
	output reg [7:0] G,
	output reg [7:0] B,
	output reg    HSync,
	output reg    VSync,
	output reg    HBlank,
	output reg    VBlank,

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

assign audio_l = 16'd0;
assign audio_r = 16'd0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Clock enables
///////////////////////////////////////////////////////////////////////////////////////////////////

localparam integer CLK_SYS_HZ = 85909091;
localparam integer CPU_HZ     = 6000000;

// Dot clock: clk_sys / 4 (21.477 MHz, 400 lines) or / 6 (14.318 MHz, 200 lines).
reg [2:0] dot_div;
always @(posedge clk_sys) begin
	ce_pix <= 1'b0;
	if (reset) dot_div <= 3'd0;
	else if (dot_div == (lines400 ? 3'd3 : 3'd5)) begin
		dot_div <= 3'd0;
		ce_pix  <= 1'b1;
	end
	else dot_div <= dot_div + 3'd1;
end

// CPU 6 MHz: fractional accumulator (24 MHz crystal and the 21.477 MHz dot crystal are not related).
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

///////////////////////////////////////////////////////////////////////////////////////////////////
// CPU (placeholder program)
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [15:0] cpu_a;
wire  [7:0] cpu_dout;
wire        mreq_n, iorq_n, rd_n, wr_n, m1_n;
reg   [7:0] cpu_din;

// The sim gets T80se as a ghdl synth netlist with these generics already fixed (verilator/Makefile, -g...):
// keep both in step.
`ifdef VERILATOR
T80se cpu
`else
T80se #(.Mode(0), .T2Write(1), .IOWait(1)) cpu
`endif
(
	.RESET_n(~reset),
	.CLK_n(clk_sys),
	.CLKEN(ce_cpu),
	.WAIT_n(1'b1),
	.INT_n(1'b1),
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

//        ld d,0 / loop: ld a,d / out (0),a / inc d / ld bc,0 / dly: dec bc / ld a,b / or c / jr nz,dly / jr loop
always @(*) begin
	case (cpu_a[3:0])
		4'h0: cpu_din = 8'h16; 4'h1: cpu_din = 8'h00;
		4'h2: cpu_din = 8'h7A;
		4'h3: cpu_din = 8'hD3; 4'h4: cpu_din = 8'h00;
		4'h5: cpu_din = 8'h14;
		4'h6: cpu_din = 8'h01; 4'h7: cpu_din = 8'h00; 4'h8: cpu_din = 8'h00;
		4'h9: cpu_din = 8'h0B;
		4'hA: cpu_din = 8'h78;
		4'hB: cpu_din = 8'hB1;
		4'hC: cpu_din = 8'h20; 4'hD: cpu_din = 8'hFB;
		4'hE: cpu_din = 8'h18; 4'hF: cpu_din = 8'hF2;
	endcase
	if (cpu_a[15:4] != 12'd0) cpu_din = 8'h00;   // NOP everywhere else
end

reg [7:0] port00;
always @(posedge clk_sys) begin
	dbg_io_wr <= ~iorq_n & ~wr_n & m1_n;
	if (reset) port00 <= 8'd0;
	else if (~iorq_n & ~wr_n & m1_n) begin
		dbg_io_port <= cpu_a[7:0];
		dbg_io_data <= cpu_dout;
		if (cpu_a[7:0] == 8'h00) port00 <= cpu_dout;
	end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Video timing (positions of sync within blanking are placeholders until the CRTC is modelled)
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [9:0] h_total  = lines400 ? 10'd864 : 10'd896;
wire [8:0] v_total  = lines400 ? 9'd448  : 9'd262;
wire [8:0] v_active = lines400 ? 9'd400  : 9'd200;
localparam [9:0] H_ACTIVE = 10'd640;

reg [9:0] hc;
reg [8:0] vc;
reg [7:0] frame;

always @(posedge clk_sys) begin
	if (reset) begin
		hc <= 10'd0; vc <= 9'd0; frame <= 8'd0;
	end
	else if (ce_pix) begin
		if (hc == h_total - 10'd1) begin
			hc <= 10'd0;
			if (vc == v_total - 9'd1) begin
				vc <= 9'd0;
				frame <= frame + 8'd1;
			end
			else vc <= vc + 9'd1;
		end
		else hc <= hc + 10'd1;
	end
end

// Test pattern: white border, 8 digital colour bars of 80 pixels (MZ order G R B), a 32-pixel grid, a block coloured by
// the CPU's port 00 value and a square that moves one pixel per frame.
wire [8:0] vy  = lines400 ? vc : {vc[7:0], 1'b0};          // 0..399 in both modes
wire       border = (hc == 10'd0) || (hc == H_ACTIVE - 10'd1) || (vc == 9'd0) || (vc == v_active - 9'd1);
wire       grid   = (hc[4:0] == 5'd0) || (vy[4:0] == 5'd0);
wire [2:0] bar_c = (hc < 10'd80) ? 3'd7 : (hc < 10'd160) ? 3'd6 : (hc < 10'd240) ? 3'd5 : (hc < 10'd320) ? 3'd4 :
                    (hc < 10'd400) ? 3'd3 : (hc < 10'd480) ? 3'd2 : (hc < 10'd560) ? 3'd1 : 3'd0;
wire       cpu_blk = (vy >= 9'd280) && (vy < 9'd360) && (hc >= 10'd40) && (hc < 10'd200);
wire [9:0] sq_x    = {1'b0, frame, 1'b0} + 10'd220;
wire       square  = (vy >= 9'd280) && (vy < 9'd312) && (hc >= sq_x) && (hc < sq_x + 10'd32);

always @(posedge clk_sys) begin
	if (ce_pix) begin
		HBlank <= (hc >= H_ACTIVE);
		VBlank <= (vc >= v_active);
		HSync  <= (hc >= H_ACTIVE + 10'd40) && (hc < H_ACTIVE + 10'd104);
		VSync  <= (vc >= v_active + 9'd8) && (vc < v_active + 9'd12);

		if (border) {R, G, B} <= 24'hFFFFFF;
		else if (vy < 9'd240) begin
			// bar_c bits: 2 = G, 1 = R, 0 = B (the MZ digital colour code)
			R <= bar_c[1] ? 8'hFF : 8'h00;
			G <= bar_c[2] ? 8'hFF : 8'h00;
			B <= bar_c[0] ? 8'hFF : 8'h00;
			if (grid) {R, G, B} <= 24'h404040;
		end
		else if (cpu_blk) {R, G, B} <= {port00[1] ? 8'hFF : 8'h40, port00[2] ? 8'hFF : 8'h40, port00[0] ? 8'hFF : 8'h40};
		else if (square)  {R, G, B} <= 24'hFFFF00;
		else if (grid)    {R, G, B} <= 24'h202060;
		else              {R, G, B} <= 24'h000020;
	end
end

endmodule
