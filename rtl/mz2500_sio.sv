//=======================================================================================================
//
// mz2500_sio.sv - minimal Z80 SIO for the MZ-2500 (A0-A3 or B0-B3, selected by port CD bit 7) and the mouse.
//
// Enough of the SIO for the mouse on channel B (CSP mouse.cpp, z80sio.cpp): write registers WR0-WR7 for both
// channels, WR0 commands (channel reset, error reset, return from interrupt), a 3-byte receive FIFO per channel,
// RR0 (receive character available, interrupt pending on channel A, transmit buffer empty), RR1 (all sent), RR2
// (channel B: the vector). Receive interrupts (any receive interrupt mode, WR1 bits 4-3 != 00) with the IM 2
// vector from WR2 and status-affects-vector (channel B WR1 bit 2). Transmitted bytes are dropped (no
// RS-232C yet); no sync modes, no external/status interrupts.
//
// Mouse (CSP mouse.cpp): when OPN port A bit 3 selects the mouse and channel B's DTR goes active (WR5 bit 7 0 -> 1),
// the mouse sends 3 bytes into channel B's receiver: buttons and overflow bits (bit 0 left, 1 right, 4/5 X over/
// underflow, 6/7 Y over/underflow), then X and Y movement (X68000 mouse format, Y positive = down). Movement comes
// from hps_io's ps2_mouse and is accumulated between packets.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500_sio
(
	input            clk,
	input            reset,

	input      [7:0] io_addr,
	input      [7:0] din,
	input            wr_stb,       // end of an I/O write
	input            rd_stb,       // end of an I/O read
	output reg [7:0] dout,
	output           sel,          // io_addr is an SIO register in the current range

	input            mouse_sel,    // OPN port A bit 3
	input     [24:0] ps2_mouse,

	// interrupts (daisy chain: PIO -> SIO -> interrupt block)
	output           int_n,
	output           ack_mine,     // SIO answers the current acknowledge
	output     [7:0] vector,
	input            ack_stb,
	input            reti_stb,
	output           ieo           // low while an SIO interrupt is in service
);

reg        range_b;                // port CD bit 7: SIO at B0-B3
wire       in_range = range_b ? (io_addr[7:2] == 6'b101100) : (io_addr[7:2] == 6'b101000);
assign     sel = in_range;
wire       ch  = io_addr[1];
wire       ctl = io_addr[0];

reg  [7:0] wr[0:1][0:7];
reg  [2:0] ptr[0:1];
reg  [7:0] fifo[0:1][0:2];
reg  [1:0] fcnt[0:1];
reg  [1:0] insvc;                  // channel in service

// ---- mouse ----
reg  [11:0] mdx, mdy;
reg         mtog;
reg         dtr_b_d;
wire signed [8:0] px = {ps2_mouse[4], ps2_mouse[15:8]};
wire signed [8:0] py = {ps2_mouse[5], ps2_mouse[23:16]};
function [7:0] sat8(input signed [11:0] v);
	sat8 = (v > 12'sd127) ? 8'd127 : (v < -12'sd128) ? 8'h80 : v[7:0];
endfunction
wire signed [11:0] sdx = mdx;
wire signed [11:0] sdy = mdy;
wire [7:0] m_d0 = {sdy < -12'sd128, sdy > 12'sd127, sdx < -12'sd128, sdx > 12'sd127, 2'b00, ps2_mouse[1], ps2_mouse[0]};

// ---- interrupts ----
function rx_int_en(input [7:0] w1);
	rx_int_en = w1[4:3] != 2'b00;
endfunction
wire req_a = rx_int_en(wr[0][1]) && fcnt[0] != 2'd0;
wire req_b = rx_int_en(wr[1][1]) && fcnt[1] != 2'd0;
wire       any_svc = |insvc;
assign int_n    = ~((req_a || req_b) && !any_svc);
assign ack_mine = (req_a || req_b) && !any_svc;
wire       ack_ch  = req_a ? 1'b0 : 1'b1;       // channel A has priority
// status affects vector (WR1 channel B bit 2): V3-V1 = 110 channel A receive, 010 channel B receive
assign vector   = wr[1][1][2] ? {wr[1][2][7:4], ack_ch ? 3'b010 : 3'b110, wr[1][2][0]} : wr[1][2];
assign ieo      = !any_svc;

always @(*) begin
	dout = 8'hFF;
	if (!ctl) dout = (fcnt[ch] != 2'd0) ? fifo[ch][0] : 8'h00;
	else case (ptr[ch])
		3'd0: dout = {5'b00000, 1'b1, (ch == 1'b0) && (req_a || req_b), fcnt[ch] != 2'd0};
		3'd1: dout = 8'h8F;
		3'd2: dout = vector;
		default: dout = 8'h00;
	endcase
end

always @(posedge clk) begin
	if (reset) begin
		range_b <= 1'b0;
		for (int c = 0; c < 2; c++) begin
			for (int r = 0; r < 8; r++) wr[c][r] <= 8'd0;
			ptr[c] <= 3'd0; fcnt[c] <= 2'd0;
		end
		insvc <= 2'b00;
		mdx <= 12'd0; mdy <= 12'd0;
		mtog <= ps2_mouse[24];
		dtr_b_d <= 1'b0;
	end
	else begin
		// mouse movement
		mtog <= ps2_mouse[24];
		if (ps2_mouse[24] != mtog) begin
			mdx <= mdx + {{3{px[8]}}, px};
			mdy <= mdy - {{3{py[8]}}, py};     // PS/2 Y is up, X68000 mouse Y is down
		end

		if (wr_stb && io_addr == 8'hCD) range_b <= din[7];

		if (wr_stb && in_range) begin
			if (!ctl) ;                                   // transmit: dropped
			else begin
				if (ptr[ch] == 3'd0) begin
					case (din[5:3])
						3'b011: begin                       // channel reset
							for (int r = 0; r < 8; r++) wr[ch][r] <= 8'd0;
							fcnt[ch] <= 2'd0;
						end
						3'b111: if (ch == 1'b0) begin       // return from interrupt
							if (insvc[0]) insvc[0] <= 1'b0; else insvc[1] <= 1'b0;
						end
						default: ;
					endcase
					ptr[ch] <= din[2:0];
				end
				else ptr[ch] <= 3'd0;
				wr[ch][ptr[ch]] <= din;
			end
		end

		// receive data read: pop the FIFO
		if (rd_stb && in_range && !ctl && fcnt[ch] != 2'd0) begin
			fifo[ch][0] <= fifo[ch][1];
			fifo[ch][1] <= fifo[ch][2];
			fcnt[ch] <= fcnt[ch] - 2'd1;
		end
		if (rd_stb && in_range && ctl) ptr[ch] <= 3'd0;

		// mouse packet on channel B DTR becoming active
		dtr_b_d <= wr[1][5][7];
		if (wr[1][5][7] && !dtr_b_d && mouse_sel) begin
			fifo[1][0] <= m_d0;
			fifo[1][1] <= sat8(sdx);
			fifo[1][2] <= sat8(sdy);
			fcnt[1] <= 2'd3;
			mdx <= 12'd0; mdy <= 12'd0;
		end

		if (ack_stb && ack_mine) insvc[ack_ch] <= 1'b1;
		if (reti_stb && any_svc) begin
			if (insvc[0]) insvc[0] <= 1'b0; else insvc[1] <= 1'b0;
		end
	end
end

endmodule
