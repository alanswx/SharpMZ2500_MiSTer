//=======================================================================================================
//
// mz2500_video.sv - MZ-2500 video: raster timing, text CRTC (F4-F7), graphics controller (BC-BF), text VRAM,
// PCG RAM, graphics VRAM and the text/graphics mixer.
//
// Behaviour follows CSP (EmuZ-2500 crtc.cpp, memory.cpp); register-level reference in docs/hardware.md
// section 5. The picture is generated per dot like the real raster, while the register semantics, the text
// window formulas and the colour/priority rules are CSP's (which draws a whole 640x400 frame at a time):
//
//   * raster: 400 lines = 864 x 448 dots, 200 lines = 896 x 262 dots. Line numbers 'v' are CSP's event_vline
//     numbers, so the blanking signals the CPU sees (F4 status, 8255 PB0, the CRTC interrupt, display WAIT)
//     switch at the same lines as in CSP: text V display from R03*k to R05*k (k = 2 at 400 lines), graphics
//     V display from GDEVS to GDEVE. The visible 640 x 400 (200) picture starts at line 34 (38) and dot 72
//     (88), which is where CSP's default text window (R03 = 17/38, R07 = 9/11) puts its first pixel.
//   * every 8 dots a fetch slot reads one text cell (two cells in 40 columns: screen 1 and screen 2) and one
//     graphics byte per plane (two in the 320-dot modes), two slots ahead of the dot being shown.
//   * 200-line output shows CSP's even buffer lines (y400 = 2 * y).
//
// Not done yet: 256-colour graphics (1D/9D/19/99), 64-colour text, the MZ-2000
// and MZ-80B display modes (text R0F MOD), scan-line options.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500_video
(
	input            clk,             // clk_sys 85.909 MHz
	input            reset,
	input            lines400,

	// CPU I/O (ports AE, BC-BF, F4-F7)
	input      [7:0] io_addr,
	input      [7:0] io_hi,
	input      [7:0] io_din,
	input            io_wr_stb,
	output reg [7:0] io_dout,

	// CPU memory: physical page (6 bits) and offset inside the 8 KB page
	input      [5:0] mem_page,
	input     [12:0] mem_off,
	input      [7:0] mem_din,
	input            mem_wr_stb,
	input            mem_rd_stb,
	output reg [7:0] mem_dout,
	output           gv_busy,         // graphics clear in progress (CPU GVRAM accesses wait)

	// blanking as the CPU sees it (1 = blank)
	output reg       hblank_t,
	output reg       vblank_t,
	output reg       hblank_g,
	output reg       vblank_g,

	input            column80,        // Z80 PIO port A bit 5
	input            screen_mask,     // 8255 port C bit 0 (VGATE): black screen
	input            pal4096,         // OPN port A bit 2 = 0: output through the 4096-colour board (AE)

	// Kanji ROM raster port (one clock latency)
	output reg [17:0] kanji_addr,
	input      [7:0] kanji_data,

	output reg       ce_pix,
	output reg [7:0] R,
	output reg [7:0] G,
	output reg [7:0] B,
	output reg       HSync,
	output reg       VSync,
	output reg       HBlank,
	output reg       VBlank
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Registers
///////////////////////////////////////////////////////////////////////////////////////////////////

reg  [7:0] textreg[0:15];
reg  [4:0] palreg[0:15];
reg  [7:0] textreg_num;
reg  [7:0] cgreg[0:31];
reg  [7:0] cgreg_num;
reg  [3:0] cg_mask;
reg        font8;              // F7 bit 0: 8-line font
reg        clear_flag;
reg  [3:0] p4r[0:15], p4g[0:15], p4b[0:15];   // 4096-colour palette (port AE), 4 bits per component

wire [8:0] GDEVS = {cgreg[9][0],  cgreg[8]};
wire [8:0] GDEVE = {cgreg[11][0], cgreg[10]};
wire [6:0] GDEHS = cgreg[12][6:0];
wire [6:0] GDEHE = cgreg[13][6:0];
wire [7:0] gmode = cgreg[14];
wire [2:0] HDSC  = cgreg[15][2:0];
wire [14:0] SAD0 = {cgreg[17][6:0], cgreg[16]};
wire [14:0] SAD1 = {cgreg[19][6:0], cgreg[18]};
wire [14:0] SAD2 = {cgreg[21][6:0], cgreg[20]};
wire [8:0] SLN1  = {cgreg[23][0], cgreg[22]};

wire four_c = (gmode & 8'h13) == 8'h03;

// graphics mode classes (CSP draw_cg)
wire m640_200 = gmode == 8'h17 || gmode == 8'h97;
wire m320_16  = gmode == 8'h14 || gmode == 8'h15 || gmode == 8'h94 || gmode == 8'h95;
wire m640_4   = gmode == 8'h03;
wire m640_16  = gmode == 8'h93;
wire m_on     = m640_200 | m320_16 | m640_4 | m640_16;
wire m320     = m320_16;
wire gfx400   = m640_4 | m640_16 | gmode == 8'h19 | gmode == 8'h99;
wire [14:0] gex = gmode[7] ? 15'h4000 : 15'h0000;
wire pl1_front = gmode[0] == 1'b0;   // 14/94: screen 1 in front; 15/95: screen 0 in front

///////////////////////////////////////////////////////////////////////////////////////////////////
// Memories
///////////////////////////////////////////////////////////////////////////////////////////////////

// CPU port decode
wire is_gv  = mem_page[5:4] == 2'b10;
wire is_rmw = mem_page[5:2] == 4'b1100;
wire is_tv  = mem_page == 6'h38;
wire is_pcg = mem_page == 6'h39;

// direct GVRAM pages 20-2F: plane and plane address (4-colour mode remaps, CSP ofs_table_4c)
reg  [1:0] d_plane;
reg        d_valid;
reg [14:0] d_addr;
always @(*) begin
	d_valid = 1'b1;
	d_plane = mem_page[2:1];
	d_addr  = {mem_page[3], mem_page[0], mem_off};
	if (four_c) begin
		d_addr = {1'b0, mem_page[0], mem_off};
		case (mem_page[3:1])
			3'd0: d_plane = 2'd0;
			3'd1: d_plane = 2'd1;
			3'd4: d_plane = 2'd2;
			3'd5: d_plane = 2'd3;
			default: d_valid = 1'b0;
		endcase
	end
end

// RMW pages 30-33
wire [14:0] rmw_addr  = {mem_page[1:0], mem_off};
wire        rmw_hi    = rmw_addr[14];
wire [14:0] rmw_paddr = four_c ? {1'b0, rmw_addr[13:0]} : rmw_addr;

// clear engine
reg        clr_active;
reg [14:0] clr_addr, clr_last;
reg  [3:0] clr_planes;
assign gv_busy = clr_active;

// graphics VRAM: four planes of 32 KB (B, R, G, I)
reg  [14:0] gv_b_addr;
wire [14:0] gv_a_addr = clr_active ? clr_addr : is_rmw ? rmw_paddr : d_addr;
wire  [7:0] gv_a_dout[0:3];
wire  [7:0] gv_b_dout[0:3];
reg   [3:0] gv_we;
reg   [7:0] gv_din[0:3];

genvar gi;
generate
	for (gi = 0; gi < 4; gi = gi + 1) begin : gvram
		dpram #(.AW(15), .DW(8)) plane
		(
			.clk(clk),
			.a_addr(gv_a_addr), .a_we(gv_we[gi]), .a_din(gv_din[gi]), .a_dout(gv_a_dout[gi]),
			.b_addr(gv_b_addr), .b_dout(gv_b_dout[gi])
		);
	end
endgenerate

// text VRAM: character, attribute, character high (page 38: 0000, 0800, 1000)
reg  [10:0] tv_b_addr;
wire  [7:0] tv_a_dout[0:2];
wire  [7:0] tv_b_dout[0:2];
// PCG RAM: four banks of 2 KB (page 39)
reg  [10:0] pcg_b_addr;
wire  [7:0] pcg_a_dout[0:3];
wire  [7:0] pcg_b_dout[0:3];

generate
	for (gi = 0; gi < 3; gi = gi + 1) begin : tvram
		dpram #(.AW(11), .DW(8)) ram
		(
			.clk(clk),
			.a_addr(mem_off[10:0]), .a_we(mem_wr_stb && is_tv && mem_off[12:11] == gi), .a_din(mem_din),
			.a_dout(tv_a_dout[gi]),
			.b_addr(tv_b_addr), .b_dout(tv_b_dout[gi])
		);
	end
	for (gi = 0; gi < 4; gi = gi + 1) begin : pcgram
		dpram #(.AW(11), .DW(8)) ram
		(
			.clk(clk),
			.a_addr(mem_off[10:0]), .a_we(mem_wr_stb && is_pcg && mem_off[12:11] == gi), .a_din(mem_din),
			.a_dout(pcg_a_dout[gi]),
			.b_addr(pcg_b_addr), .b_dout(pcg_b_dout[gi])
		);
	end
endgenerate

// RMW view of the four planes at the CPU address
wire [7:0] rb = four_c ? (rmw_hi ? gv_a_dout[2] : gv_a_dout[0]) : gv_a_dout[0];
wire [7:0] rr = four_c ? (rmw_hi ? gv_a_dout[3] : gv_a_dout[1]) : gv_a_dout[1];
wire [7:0] rg = four_c ? 8'h00 : gv_a_dout[2];
wire [7:0] ri = four_c ? 8'h00 : gv_a_dout[3];

reg [7:0] latch[0:3];

function [7:0] compare(input [3:0] c, input [7:0] b, input [7:0] r, input [7:0] g, input [7:0] i);
	for (int n = 0; n < 8; n++) compare[n] = (c == {i[n], g[n], r[n], b[n]});
endfunction

wire [1:0] rmw_pl = four_c ? {1'b0, cgreg[7][0]} : cgreg[7][1:0];
wire [7:0] rmw_rd = cgreg[7][4] ? compare(cgreg[7][3:0], rb, rr, rg, ri) :
                    (rmw_pl == 2'd0) ? rb : (rmw_pl == 2'd1) ? rr : (rmw_pl == 2'd2) ? rg : ri;

always @(*) begin
	mem_dout = 8'hFF;
	if (is_gv)       mem_dout = d_valid ? gv_a_dout[d_plane] : 8'hFF;
	else if (is_rmw) mem_dout = rmw_rd;
	else if (is_tv)  mem_dout = (mem_off[12:11] == 2'd3) ? 8'hFF : tv_a_dout[mem_off[12:11]];
	else if (is_pcg) mem_dout = pcg_a_dout[mem_off[12:11]];
end

// GVRAM writes: direct, read-modify-write (CSP CRTC::write_data8) or clear
function [7:0] rmw_new(input [7:0] old, input [7:0] d, input [7:0] pat, input en_data);
	if (cgreg[5][7:6] == 2'b00) rmw_new = (old & ~cgreg[6]) | (en_data ? (d & pat & cgreg[6]) : 8'h00);
	else                        rmw_new = (old & ~d) | (en_data ? (d & pat) : 8'h00);
endfunction

always @(*) begin
	gv_we = 4'd0;
	for (int p = 0; p < 4; p++) gv_din[p] = mem_din;
	if (clr_active) begin
		gv_we = clr_planes;
		for (int p = 0; p < 4; p++) gv_din[p] = 8'h00;
	end
	else if (mem_wr_stb && is_gv && d_valid) gv_we[d_plane] = 1'b1;
	else if (mem_wr_stb && is_rmw && !cgreg[5][7]) begin
		if (four_c) begin
			// plane roles: "B" = B or G (offsets 4000-7FFF), "R" = R or I
			if (cgreg[5][0]) begin
				gv_we[rmw_hi ? 2 : 0] = 1'b1;
				gv_din[rmw_hi ? 2 : 0] = rmw_new(rb, mem_din, cgreg[0], cgreg[4][0]);
			end
			if (cgreg[5][1]) begin
				gv_we[rmw_hi ? 3 : 1] = 1'b1;
				gv_din[rmw_hi ? 3 : 1] = rmw_new(rr, mem_din, cgreg[1], cgreg[4][1]);
			end
		end
		else begin
			for (int p = 0; p < 4; p++) begin
				gv_we[p]  = cgreg[5][p];
				gv_din[p] = rmw_new(gv_a_dout[p], mem_din, cgreg[p], cgreg[4][p]);
			end
		end
	end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Register writes, I/O reads, clear engine
///////////////////////////////////////////////////////////////////////////////////////////////////

always @(*) begin
	io_dout = 8'hFF;
	case (io_addr)
		8'hBC: io_dout = cgreg[7][4] ? compare(cgreg[7][3:0], latch[0], latch[1], latch[2], latch[3]) : latch[0];
		8'hBD: io_dout = cgreg[7][4] ? {~vblank_g, 6'd0, clear_flag} : latch[1];
		8'hBE: io_dout = latch[2];
		8'hBF: io_dout = latch[3];
		8'hF4, 8'hF5, 8'hF6, 8'hF7: io_dout = {6'd0, ~hblank_t, ~vblank_t};
		default: ;
	endcase
end

reg vblank_g_d;

always @(posedge clk) begin
	if (reset) begin
		for (int n = 0; n < 16; n++) begin textreg[n] <= 8'd0; palreg[n] <= n[4:0]; end
		for (int n = 0; n < 32; n++) cgreg[n] <= 8'd0;
		textreg[3] <= lines400 ? 8'd17 : 8'd38;
		textreg[5] <= lines400 ? 8'd217 : 8'd238;
		textreg[7] <= lines400 ? 8'd9 : 8'd11;
		textreg[8] <= lines400 ? 8'd89 : 8'd91;
		cgreg[0] <= 8'hFF; cgreg[1] <= 8'hFF; cgreg[2] <= 8'hFF; cgreg[3] <= 8'hFF; cgreg[6] <= 8'hFF;
		cgreg[10] <= lines400 ? 8'h90 : 8'hC8; cgreg[11] <= lines400 ? 8'h01 : 8'h00;
		cgreg[13] <= 8'd80;
		cgreg_num <= 8'h80;
		textreg_num <= 8'd0;
		cg_mask <= 4'hF;
		for (int n = 0; n < 16; n++) begin
			p4r[n] <= (n == 8) ? 4'h9 : ((n & 4'hA) == 4'hA) ? 4'hF : ((n & 4'hA) == 4'h2) ? 4'h7 : 4'h0;
			p4g[n] <= (n == 8) ? 4'h9 : ((n & 4'hC) == 4'hC) ? 4'hF : ((n & 4'hC) == 4'h4) ? 4'h7 : 4'h0;
			p4b[n] <= (n == 8) ? 4'h9 : ((n & 4'h9) == 4'h9) ? 4'hF : ((n & 4'h9) == 4'h1) ? 4'h7 : 4'h0;
		end
		font8 <= 1'b1;
		clear_flag <= 1'b0;
		clr_active <= 1'b0;
		latch[0] <= 8'd0; latch[1] <= 8'd0; latch[2] <= 8'd0; latch[3] <= 8'd0;
	end
	else begin
		if (clr_active) begin
			clr_addr <= clr_addr + 15'd1;
			if (clr_addr == clr_last) clr_active <= 1'b0;
		end

		vblank_g_d <= vblank_g;
		if (vblank_g && !vblank_g_d) clear_flag <= 1'b0;

		if (mem_rd_stb && is_rmw) begin
			latch[0] <= rb; latch[1] <= rr; latch[2] <= rg; latch[3] <= ri;
		end

		if (io_wr_stb) begin
			case (io_addr)
				8'hBC: cgreg_num <= io_din;
				8'hBD: begin
					cgreg[cgreg_num[4:0]] <= io_din;
					case (cgreg_num[4:0])
						5'h05: if (io_din[7:6] == 2'b10) begin
							clr_active <= 1'b1;
							clr_planes <= io_din[3:0];
							clear_flag <= 1'b1;
							case (gmode)
								8'h03, 8'h14, 8'h15, 8'h17, 8'h1D: begin clr_addr <= 15'h0000; clr_last <= 15'h3FFF; end
								8'h94, 8'h95, 8'h97, 8'h9D:        begin clr_addr <= 15'h4000; clr_last <= 15'h7FFF; end
								default:                           begin clr_addr <= 15'h0000; clr_last <= 15'h7FFF; end
							endcase
						end
						5'h08: cgreg[9]  <= 8'd0;
						5'h0A: cgreg[11] <= 8'd0;
						default: ;
					endcase
					if (cgreg_num[7]) cgreg_num <= {cgreg_num[7:2], cgreg_num[1:0] + 2'd1};
				end
				8'hF4: textreg_num <= io_din;
				8'hF5: begin
					if (textreg_num < 8'h10) begin
						if (textreg_num == 8'h0F && textreg[15][1:0] != 2'd0)
							textreg[15] <= {io_din[7:2], textreg[15][1:0]};
						else
							textreg[textreg_num[3:0]] <= io_din;
					end
					else if (textreg_num[7:4] == 4'h8) palreg[textreg_num[3:0]] <= io_din[4:0];
				end
				8'hF6: cg_mask <= {io_din[0], io_din[2:0]};
				8'hF7: font8 <= io_din[0];
				// 16-bit port: A12-A9 = palette number, A8 = 1 for G (D3-0), 0 for R (D7-4) and B (D3-0)
				8'hAE: if (io_hi[0]) p4g[io_hi[4:1]] <= io_din[3:0];
				       else begin p4r[io_hi[4:1]] <= io_din[7:4]; p4b[io_hi[4:1]] <= io_din[3:0]; end
				default: ;
			endcase
		end
	end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Raster timing
///////////////////////////////////////////////////////////////////////////////////////////////////

wire [9:0] htotal = lines400 ? 10'd864 : 10'd896;
wire [8:0] vtotal = lines400 ? 9'd448  : 9'd262;
wire [9:0] hstart = lines400 ? 10'd72  : 10'd88;
wire [8:0] vstart = lines400 ? 9'd34   : 9'd38;
wire [8:0] vact   = lines400 ? 9'd400  : 9'd200;

reg  [2:0] dot_div;
reg  [9:0] hc;
reg  [8:0] v;

always @(posedge clk) begin
	ce_pix <= 1'b0;
	if (reset) dot_div <= 3'd0;
`ifdef MZ_FAST_SIM
	else if (dot_div == (lines400 ? 3'd1 : 3'd2)) begin
`else
	else if (dot_div == (lines400 ? 3'd3 : 3'd5)) begin
`endif
		dot_div <= 3'd0;
		ce_pix  <= 1'b1;
	end
	else dot_div <= dot_div + 3'd1;
end

wire signed [10:0] x  = $signed({1'b0, hc}) - $signed({1'b0, hstart});
wire signed [9:0]  yo = $signed({1'b0, v}) - $signed({1'b0, vstart});
wire        y_act = (yo >= 0) && (yo < $signed({1'b0, vact}));
wire  [8:0] yb    = lines400 ? yo[8:0] : {yo[7:0], 1'b0};    // CSP buffer line 0..399

// CPU-visible blanking (CSP event_vline / event_callback). Horizontal edges in dots: CSP times them in CPU
// clocks (start - 2, end + 6 for text; start - 2, end + 4 for graphics), here converted at 2.23 (400 lines)
// or 3.35 (200 lines) CPU clocks per 8 dots.
wire  [9:0] ts = {textreg[7][6:0], 3'b000} - (lines400 ? 10'd7 : 10'd5);
wire  [9:0] te = {textreg[8][6:0], 3'b000} + (lines400 ? 10'd21 : 10'd14);
wire  [9:0] gs = {GDEHS + 7'd10, 3'b000} - (lines400 ? 10'd7 : 10'd5);
wire  [9:0] ge = {GDEHE + 7'd10, 3'b000} + (lines400 ? 10'd14 : 10'd10);

always @(posedge clk) begin
	if (reset) begin
		hc <= 10'd0; v <= 9'd0;
		hblank_t <= 1'b1; vblank_t <= 1'b1; hblank_g <= 1'b1; vblank_g <= 1'b1;
	end
	else if (ce_pix) begin
		if (hc == htotal - 10'd1) begin
			hc <= 10'd0;
			v  <= (v == vtotal - 9'd1) ? 9'd0 : v + 9'd1;
		end
		else hc <= hc + 10'd1;

		if (hc == 10'd0) begin
			if (v == (lines400 ? {textreg[5], 1'b0} : {1'b0, textreg[5]}))      vblank_t <= 1'b1;
			else if (v == (lines400 ? {textreg[3], 1'b0} : {1'b0, textreg[3]})) vblank_t <= 1'b0;
			if (v == GDEVE)      vblank_g <= 1'b1;
			else if (v == GDEVS) vblank_g <= 1'b0;
		end
		hblank_t <= !(textreg[7][6:0] < textreg[8][6:0] && hc >= ts && hc < te);
		hblank_g <= !(GDEHS < GDEHE && hc >= gs && hc < ge);
	end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Per-line setup (at hc == 1): text row and glyph line, graphics address chain
///////////////////////////////////////////////////////////////////////////////////////////////////

wire        rows20 = textreg[0][4];
wire  [4:0] vd     = {textreg[9][3:0], 1'b0};
wire [10:0] tsa    = {textreg[2][2:0], textreg[1]};

reg         t_rowok;           // this line belongs to a drawn glyph line
reg   [3:0] t_gl;              // glyph line 0-15 (16-line font) / 0-7 (8-line font)
reg  [10:0] t_base;            // address of the row's first cell

wire signed [10:0] ys  = $signed({2'b00, yb}) + $signed({6'd0, vd}) - (rows20 ? 11'sd2 : 11'sd0);
wire        [18:0] ys205 = ys[9:0] * 9'd205;
wire         [5:0] row = rows20 ? ys205[17:12] : ys[9:4];
// row * 80 / row * 40
wire        [10:0] rowoff = column80 ? ({row, 6'd0} + {row, 4'd0}) : ({row, 5'd0} + {row, 3'd0});

reg  [14:0] g_chain, g_line_start;
reg         g_adv;               // advance the chain (one graphics byte fetched)
reg  [14:0] g_chain_prev;        // chain value of the current fetch slot
reg         g_hi_prev;
wire  [6:0] slot_next = x[9:3] + 7'd1;   // slot whose first dot is x + 1 (x = 8s - 1)
reg   [8:0] g_gy_prev;
reg         g_hsc;              // this line uses the horizontal scroll (y < SLN1)
wire  [8:0] gy = gfx400 ? yb : {1'b0, yb[8:1]};

// li for 20-row mode: ys - row*20 (row*20 = row*16 + row*4)
wire  [8:0] li20 = ys[8:0] - ({3'd0, row} << 4) - ({3'd0, row} << 2);

always @(posedge clk) begin
	if (ce_pix && hc == 10'd1 && y_act) begin
		t_rowok <= (ys >= 0) && (rows20 ? (li20 < 9'd16) : 1'b1);
		t_gl    <= font8 ? {1'b0, (rows20 ? li20[3:1] : ys[3:1])} : (rows20 ? li20[3:0] : ys[3:0]);
		t_base  <= tsa + rowoff;

		if (yo == 0) begin
			g_chain      <= (SLN1 == 9'd0) ? SAD2 : SAD0;
			g_line_start <= (SLN1 == 9'd0) ? SAD2 : SAD0;
		end
		else if (gy != g_gy_prev) begin
			if (gy == SLN1) begin g_chain <= SAD2; g_line_start <= SAD2; end
			else g_line_start <= g_chain;
		end
		else g_chain <= g_line_start;
		g_gy_prev <= gy;
		g_hsc     <= gy < SLN1;
	end
	else if (g_adv) g_chain <= (g_chain == SAD1) ? 15'd0 : g_chain + 15'd1;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Fetch slots: during the 8 dots starting at x = 8 * (s - 2), fetch text slot s and graphics byte s
///////////////////////////////////////////////////////////////////////////////////////////////////

wire        slot_start = ce_pix && y_act && x[2:0] == 3'd0 && x >= -16 && x < 624;
wire  [6:0] slot = x[9:3] + 7'd2;

reg   [6:0] f_slot;
reg   [3:0] f_step;
reg         f_run;

// text fetch registers
reg   [7:0] f_t1, f_attr, f_t2;
reg  [31:0] tres[0:1];            // 8 text values (4 bits each, pixel 0 = bits 3-0)
// graphics fetch registers
reg   [7:0] f_b0, f_r0, f_g0, f_i0;
reg  [31:0] gres[0:1];            // 640-dot modes: 8 pixels per slot
reg  [31:0] g320[0:1];            // 320-dot modes: 8 pixels per 16 dots

reg         blink;
reg  [25:0] blink_cnt;
always @(posedge clk) begin
	if (reset) begin blink <= 1'b0; blink_cnt <= 26'd0; end
`ifdef MZ_FAST_SIM
	else if (blink_cnt == 26'd21477272) begin blink_cnt <= 26'd0; blink <= ~blink; end   // 500 ms
`else
	else if (blink_cnt == 26'd42954544) begin blink_cnt <= 26'd0; blink <= ~blink; end   // 500 ms
`endif
	else blink_cnt <= blink_cnt + 26'd1;
end

wire [3:0] trans = textreg[0][1] ? 4'd8 : 4'd0;

// text cell -> 8 values (CSP draw_80column_font / draw_40column_font)
function [31:0] text_cell(input [7:0] attr, input [7:0] t2, input [7:0] kj, input [7:0] p0, input [7:0] p1,
                          input [7:0] p2, input [7:0] p3, input ok);
	reg [7:0] pat, pa, pb, pc;
	reg [2:0] c;
	reg [3:0] fg;
	text_cell = 32'd0;
	if (ok) begin
		if (attr[3]) begin
			// 8-colour PCG: PCG1 = B, PCG2 = R, PCG3 = G
			pa = attr[6] ? ~p1 : p1; pb = attr[6] ? ~p2 : p2; pc = attr[6] ? ~p3 : p3;
			for (int i = 0; i < 8; i++) begin
				if (attr[7] && blink) text_cell[i*4 +: 4] = attr[6] ? 4'd7 : trans;
				else begin
					c = {pc[7-i], pb[7-i], pa[7-i]};
					text_cell[i*4 +: 4] = (c != 3'd0) ? {1'b0, c} : trans;
				end
			end
		end
		else begin
			case (attr[5:4])
				2'd1: pat = p1;
				2'd2: pat = p2;
				2'd3: pat = p3;
				default: pat = t2[7] ? kj : p0;
			endcase
			if (attr[6]) pat = (attr[7] && blink) ? 8'hFF : ~pat;
			else         pat = (attr[7] && blink) ? 8'h00 : pat;
			fg = (attr[2:0] != 3'd0) ? {1'b0, attr[2:0]} : 4'd8;
			for (int i = 0; i < 8; i++) text_cell[i*4 +: 4] = pat[7-i] ? fg : trans;
		end
	end
endfunction

// graphics byte group -> 8 pixels (LSB = leftmost)
function [31:0] gpix8(input [7:0] b, input [7:0] r, input [7:0] g, input [7:0] i, input [3:0] m);
	for (int n = 0; n < 8; n++) gpix8[n*4 +: 4] = {i[n] & m[3], g[n] & m[2], r[n] & m[1], b[n] & m[0]};
endfunction

function [31:0] merge2(input [31:0] front, input [31:0] back);
	for (int n = 0; n < 8; n++) merge2[n*4 +: 4] = (front[n*4 +: 4] != 4'd0) ? front[n*4 +: 4] : back[n*4 +: 4];
endfunction

wire [10:0] cell_addr = column80 ? (t_base + {4'd0, f_slot}) :
                        (t_base + {5'd0, f_slot[6:1]} + (f_slot[0] ? 11'h400 : 11'h000));

always @(posedge clk) begin
	g_adv <= 1'b0;
	if (reset) begin
		f_run <= 1'b0;
	end
	else if (slot_start) begin
		f_run  <= (slot < 7'd80);
		f_slot <= slot;
		f_step <= 4'd0;
	end
	else if (f_run) begin
		f_step <= f_step + 4'd1;
		case (f_step)
			4'd0: begin
				tv_b_addr <= cell_addr;
				// graphics: first byte
				if (m320) gv_b_addr <= g_chain | gex;
				else if (m640_4) gv_b_addr <= {1'b0, g_chain[13:0]};
				else if (m640_200) gv_b_addr <= g_chain | gex;
				else gv_b_addr <= g_chain;
				if (m_on && (!m320 || !f_slot[0])) g_adv <= 1'b1;
			end
			4'd2: begin
				f_t1 <= tv_b_dout[0]; f_attr <= tv_b_dout[1]; f_t2 <= tv_b_dout[2];
				kanji_addr <= {tv_b_dout[2][6], 17'd0} + (font8 ? {tv_b_dout[2][5:0], tv_b_dout[0], 3'b000} :
				                                                  {tv_b_dout[2][5:0], tv_b_dout[0][7:1], 4'b0000})
				              + {14'd0, t_gl};
				pcg_b_addr <= font8 ? {tv_b_dout[0], t_gl[2:0]} : {tv_b_dout[0][7:1], t_gl};
				f_b0 <= gv_b_dout[0]; f_r0 <= gv_b_dout[1]; f_g0 <= gv_b_dout[2]; f_i0 <= gv_b_dout[3];
				gv_b_addr <= (g_chain_prev ^ 15'h2000) | gex;   // second screen of the 320-dot modes
			end
			4'd4: begin
				tres[f_slot[0]] <= text_cell(f_attr, f_t2, kanji_data, pcg_b_dout[0], pcg_b_dout[1], pcg_b_dout[2],
				                             pcg_b_dout[3], t_rowok);
				if (m640_200 || m640_16)
					gres[f_slot[0]] <= gpix8(f_b0, f_r0, f_g0, f_i0, cgreg[24][3:0]);
				else if (m640_4)
					gres[f_slot[0]] <= gpix8(g_hi_prev ? f_g0 : f_b0, g_hi_prev ? f_i0 : f_r0, 8'd0, 8'd0,
					                         {2'b00, cgreg[24][1:0]});
				else if (m320 && !f_slot[0]) begin
					if (pl1_front)
						g320[f_slot[1]] <= merge2(gpix8(gv_b_dout[0], gv_b_dout[1], gv_b_dout[2], gv_b_dout[3], cgreg[24][7:4]),
						                          gpix8(f_b0, f_r0, f_g0, f_i0, cgreg[24][3:0]));
					else
						g320[f_slot[1]] <= merge2(gpix8(f_b0, f_r0, f_g0, f_i0, cgreg[24][3:0]),
						                          gpix8(gv_b_dout[0], gv_b_dout[1], gv_b_dout[2], gv_b_dout[3], cgreg[24][7:4]));
				end
				else if (!m_on) gres[f_slot[0]] <= 32'd0;
				f_run <= 1'b0;
			end
			default: ;
		endcase
	end
end

// chain value used for this slot's first read (g_chain has advanced by then)
always @(posedge clk) if (f_run && f_step == 4'd0) begin g_chain_prev <= g_chain; g_hi_prev <= g_chain[14]; end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Dot pipeline: load the shifters at the last dot of each cell, mix, output
///////////////////////////////////////////////////////////////////////////////////////////////////

reg  [31:0] tcur1, tcur2;     // text values: 80 columns (tcur1) or 40-column screens 1 and 2
reg  [31:0] gcur, gprev, gprev2;

// text window (CSP draw_text), in buffer lines and 8-dot columns
wire signed [9:0] SLr = lines400 ? ($signed({2'b0, textreg[3]}) - 10'sd17) : ($signed({2'b0, textreg[3]}) - 10'sd38);
wire signed [9:0] ELr = lines400 ? ($signed({2'b0, textreg[5]}) - 10'sd17) : ($signed({2'b0, textreg[5]}) - 10'sd38);
wire signed [9:0] SCr = $signed({3'b0, textreg[7][6:0]}) - (column80 ? (lines400 ? 10'sd9 : 10'sd11) : (lines400 ? 10'sd8 : 10'sd10));
wire signed [9:0] ECr = $signed({3'b0, textreg[8][6:0]}) - (column80 ? (lines400 ? 10'sd9 : 10'sd11) : (lines400 ? 10'sd8 : 10'sd10));
function [9:0] clampv(input signed [9:0] a, input [9:0] hi);
	clampv = (a < 0) ? 10'd0 : (a > $signed(hi)) ? hi : a[9:0];
endfunction
wire [9:0] SL = clampv(SLr <<< 1, 10'd400);
wire [9:0] EL = clampv(ELr <<< 1, 10'd400);
wire [9:0] SC = clampv(SCr, 10'd80);
wire [9:0] EC = clampv(ECr, 10'd80);

wire [9:0] xc = {3'd0, x[9:3]};
wire t_vin = (EL >= SL) ? ({1'b0, yb} >= SL && {1'b0, yb} < EL) : !({1'b0, yb} >= EL && {1'b0, yb} < SL);
wire t_hin = (EC >= SC) ? (xc >= SC && xc < EC) : !(xc >= EC && xc < SC);

// graphics window (CSP draw_screen)
wire [9:0] vs = (GDEVS <= GDEVE) ? (gfx400 ? {1'b0, GDEVS} : {GDEVS, 1'b0}) : 10'd0;
wire [9:0] ve = (GDEVS <= GDEVE) ? (gfx400 ? {1'b0, GDEVE} : {GDEVE, 1'b0}) : 10'd400;
wire [9:0] hs = (GDEHS <= GDEHE && GDEHS < 7'd80) ? {GDEHS, 3'b000} : 10'd0;
wire [9:0] he = (GDEHS <= GDEHE && GDEHE < 7'd80) ? {GDEHE, 3'b000} : 10'd640;
wire g_in = {1'b0, yb} >= vs && {1'b0, yb} < ve && x[9:0] >= hs && x[9:0] < he;

// current text value
wire [2:0] tx80 = x[2:0];
wire [2:0] tx40 = x[3:1];
wire [3:0] tv1 = column80 ? tcur1[tx80*4 +: 4] : tcur1[tx40*4 +: 4];
wire [3:0] tv2 = tcur2[tx40*4 +: 4];
reg  [3:0] tval;
always @(*) begin
	if (column80) tval = tv1;
	else case (textreg[0][3:2])
		2'b01: tval = tv1;
		2'b10: tval = tv2;
		default: tval = (tv1[2:0] != 3'd0) ? tv1 : (tv2[2:0] != 3'd0) ? tv2 : (tv1 & 4'd8) | (tv2 & 4'd8);
	endcase
	if (!(t_vin && t_hin)) tval = trans;
end

// current graphics pixel, with the horizontal scroll (dots inserted at the left)
wire [3:0] hd = g_hsc ? (m320 ? {HDSC, 1'b0} : {1'b0, HDSC}) : 4'd0;
wire signed [5:0] gidx = $signed({3'b0, x[2:0]}) - $signed({2'b0, hd});
reg  [3:0] gval;
always @(*) begin
	if (gidx >= 0)       gval = gcur[gidx[2:0]*4 +: 4];
	else if (gidx >= -8) gval = gprev[gidx[2:0]*4 +: 4];
	else                 gval = gprev2[gidx[2:0]*4 +: 4];
	if (!m_on) gval = 4'd0;
end

// 16-colour palette (CSP analogue monitor) and text colours
function [23:0] pal16(input [3:0] i);
	if (i == 4'd8) pal16 = {8'd152, 8'd152, 8'd152};
	else begin
		pal16[23:16] = ((i & 4'hA) == 4'hA) ? 8'd255 : ((i & 4'hA) == 4'h2) ? 8'd127 : 8'd0;
		pal16[15:8]  = ((i & 4'hC) == 4'hC) ? 8'd255 : ((i & 4'hC) == 4'h4) ? 8'd127 : 8'd0;
		pal16[7:0]   = ((i & 4'h9) == 4'h9) ? 8'd255 : ((i & 4'h9) == 4'h1) ? 8'd127 : 8'd0;
	end
endfunction
function [23:0] digital(input [2:0] c);
	digital = {c[1] ? 8'hFF : 8'h00, c[2] ? 8'hFF : 8'h00, c[0] ? 8'hFF : 8'h00};
endfunction

wire [3:0] back16 = {textreg[11][0], textreg[12][0], textreg[11][5], textreg[11][2]};
wire [3:0] pg     = palreg[gval][3:0];
wire [23:0] gcolor16 = pal16((pg != 4'd0) ? (pg & cg_mask) : (back16 & cg_mask));

// 4096-colour board (CSP palette4096tmp): every colour goes through a palette register, text colour t (1-7)
// through register t + 8 and non-transparent black through register 0; components are 4 bits (<< 4).
function [3:0] gmap(input [3:0] c);
	gmap = (palreg[c][3:0] != 4'd0) ? (palreg[c][3:0] & cg_mask) : (back16 & cg_mask);
endfunction
function [23:0] c4096(input [3:0] i);
	c4096 = {p4r[i], 4'h0, p4g[i], 4'h0, p4b[i], 4'h0};
endfunction
wire [23:0] gcolor = pal4096 ? c4096(gmap(gval)) : gcolor16;
wire [23:0] tcolor = pal4096 ? c4096(gmap({1'b1, tval[2:0]})) : digital(tval[2:0]);
wire [23:0] bcolor = pal4096 ? c4096(palreg[back16][3:0]) : pal16(palreg[back16][3:0]);
wire [23:0] kcolor = pal4096 ? c4096(gmap(4'd0)) : 24'd0;     // non-transparent black inside the window

// Simulation only: +notext / +nogfx on the Vtop command line hide a layer (debugging).
reg dbg_notext = 1'b0, dbg_nogfx = 1'b0;
`ifdef VERILATOR
initial begin
	dbg_notext = $test$plusargs("notext");
	dbg_nogfx  = $test$plusargs("nogfx");
end
`endif

reg [23:0] rgb;
always @(*) begin
	if (dbg_notext) rgb = g_in ? gcolor : bcolor;
	else if (dbg_nogfx) rgb = (tval == 4'd0 || tval == 4'd8) ? 24'd0 : digital(tval[2:0]);
	else if (g_in) begin
		if (tval == 4'd0 || palreg[gval][4]) rgb = gcolor;
		else if (tval == 4'd8)               rgb = kcolor;
		else                                 rgb = tcolor;
	end
	else begin
		if (tval == 4'd0)      rgb = bcolor;
		else if (tval == 4'd8) rgb = 24'd0;
		else                   rgb = tcolor;
	end
	if (screen_mask) rgb = 24'd0;
end

wire act = y_act && x >= 0 && x < 640;

always @(posedge clk) begin
	if (ce_pix) begin
		// load the next cell at its last dot
		if (y_act && x[2:0] == 3'd7 && x >= -1 && x < 639) begin
			if (column80) tcur1 <= tres[slot_next[0]];
			else if (x[3] == 1'b1 || x == -1) begin tcur1 <= tres[0]; tcur2 <= tres[1]; end
			gprev2 <= (x == -1) ? 32'd0 : gprev;
			gprev  <= (x == -1) ? 32'd0 : gcur;
			if (m320) gcur <= expand320(g320[slot_next[1]], slot_next[0]);
			else      gcur <= gres[slot_next[0]];
		end

		{R, G, B} <= act ? rgb : 24'd0;
		HBlank <= !(x >= 0 && x < 640);
		VBlank <= !y_act;
		HSync  <= lines400 ? (hc >= 10'd736 && hc < 10'd800) : (hc >= 10'd768 && hc < 10'd832);
		VSync  <= lines400 ? (v >= 9'd442 && v < 9'd445) : (v >= 9'd250 && v < 9'd253);
	end
end


// 320-dot modes: half h (0 = pixels 0-3, 1 = pixels 4-7) of an 8-pixel group, each pixel doubled
function [31:0] expand320(input [31:0] p, input h);
	for (int n = 0; n < 8; n++) expand320[n*4 +: 4] = p[(h*4 + n/2)*4 +: 4];
endfunction

endmodule
