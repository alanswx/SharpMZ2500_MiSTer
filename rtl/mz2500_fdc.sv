//=======================================================================================================
//
// mz2500_fdc.sv - MZ-2500 floppy interface: MB8876 at D8-DB, drive/motor DC, side DD, density DE.
//
//   D8-DB  MB8876 (WD179x family) status/command, track, sector, data. The data bus between the CPU and the
//          chip is inverted both ways (CSP writes ~data and reads ~data).
//   DC     bit 7 motor, bits 1-0 drive number; XOR 2 when OPN port A bit 1 (DRSEL) is set (CSP floppy.cpp).
//   DD     bit 0 side.
//   DE     bit 0 density (0 = MFM): latched only; the D88 sectors carry their own density.
//
// Two drives (four with the MZ_FOUR_DRIVES macro, files.qip) on the MiSTer image slots, D88 images (3.5" 2DD: 80 cylinders x 2 sides x 16 x 256 bytes, or any
// layout the D88 track table describes). The chip is Sorgelig's wd1793.sv with FM-7_MiSTer's D77/D88 support,
// as SharpMZ_MiSTer uses it: one instance per drive. Commands go to the selected drive; track, sector and data
// writes go to all, as a single chip has one register set. An empty slot reads not ready. The FDC's IRQ/DRQ are
// not wired to anything on the MZ-2500 (software polls).
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE). wd1793.sv: GPL-2.0-or-later.
//=======================================================================================================

module mz2500_fdc
(
	input         clk_sys,
	input         reset,
	input         ce_cpu,         // the controller's timing runs at the CPU clock

	input   [7:0] io_addr,
	input         io_rd,          // I/O read strobe level (IORQ & RD)
	input         io_wr,          // I/O write strobe level
	input   [7:0] io_dout,        // CPU data out
	output  [7:0] io_din,         // data for the CPU (valid for D8-DB)
	input         drsel,          // OPN port A bit 1: swap drives 0-1 / 2-3

	// MiSTer image slots (hps_io), one per drive
	input   [3:0] img_mounted,
	input         img_readonly,
	input  [63:0] img_size,
	output [31:0] sd_lba[4],
	output  [3:0] sd_rd,
	output  [3:0] sd_wr,
	input   [3:0] sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[4],
	input         sd_buff_wr,

	output        busy            // drive activity (LED)
);

reg  [3:0] mounted = 0;
reg  [3:0] wprot = 0;
always @(posedge clk_sys) begin
	for (int i = 0; i < 4; i++)
		if (img_mounted[i]) begin
			mounted[i] <= |img_size;
			wprot[i]   <= img_readonly;
		end
end

wire       chip  = io_addr[7:2] == 6'b110110;          // D8-DB
wire [1:0] reg_a = io_addr[1:0];

reg        motor, side, density;
reg  [1:0] drive;
reg        old_wr;
always @(posedge clk_sys) begin
	old_wr <= io_wr;
	if (reset) begin
		motor <= 1'b0; side <= 1'b0; density <= 1'b0; drive <= 2'd0;
	end
	else if (io_wr & ~old_wr) begin
		case (io_addr)
			8'hDC: begin motor <= io_dout[7]; drive <= io_dout[1:0] ^ {drsel, 1'b0}; end
			8'hDD: side <= io_dout[0];
			8'hDE: density <= io_dout[0];
			default: ;
		endcase
	end
end

wire [7:0] fdc_dout[4];
wire [3:0] fdc_busy, fdc_prepare;

`ifdef MZ_FOUR_DRIVES
localparam NDRV = 4;
`else
localparam NDRV = 2;             // drives 3-4 cost ~4600 ALMs and 66 M10Ks (track buffers): a build option
`endif

genvar d;
generate
	for (d = NDRV; d < 4; d = d + 1) begin : nodrv
		assign fdc_dout[d] = 8'h80;  // not ready
		assign fdc_busy[d] = 1'b0;
		assign fdc_prepare[d] = 1'b0;
		assign sd_lba[d] = 32'd0;
		assign sd_rd[d] = 1'b0;
		assign sd_wr[d] = 1'b0;
		assign sd_buff_din[d] = 8'h00;
	end
	for (d = 0; d < NDRV; d = d + 1) begin : drv
		wire selected = (drive == d);
		wire io_en = chip & (selected | (io_wr & reg_a != 2'd0));

		// WDT: 2 MFM byte times (64 us) at the 6 MHz ce: the IPL skips a sector by issuing READ SECTOR and only
		// waiting for BUSY to drop, which takes ~8 ms on a real drive
		wd1793 #(.RWMODE(1), .EDSK(1), .WDT(384)) fdc
		(
			.clk_sys(clk_sys),
			.ce(ce_cpu | fdc_prepare[d]),
			.reset(reset),
			.io_en(io_en),
			.rd(io_rd),
			.wr(io_wr),
			.addr(reg_a),
			.din(~io_dout),
			.crc_report(1'b1),
			.dout(fdc_dout[d]),
			.drq(),
			.intrq(),
			.busy(fdc_busy[d]),
			.wp(wprot[d]),
			.fmt_wp(),
			.size_code(3'd1),
			.layout(1'b0),
			.side(side),
			.ready(mounted[d] & ~fdc_prepare[d]),

			.img_mounted(img_mounted[d]),
			.img_size(img_size[20:0]),
			.img_size_id(img_size[23:0]),
			.disk_index(3'd0),
			.prepare(fdc_prepare[d]),
			.sd_lba(sd_lba[d]),
			.sd_rd(sd_rd[d]),
			.sd_wr(sd_wr[d]),
			.sd_ack(sd_ack[d]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[d]),
			.sd_buff_wr(sd_buff_wr),

			.input_active(1'b0),
			.input_addr(21'd0),
			.input_data(8'd0),
			.input_wr(1'b0),
			.buff_addr(),
			.buff_read(),
			.buff_din(8'd0)
		);
	end
endgenerate

wire [7:0] dout_sel = fdc_dout[drive];
assign io_din = ~dout_sel;
assign busy   = |(fdc_busy & mounted);

endmodule
