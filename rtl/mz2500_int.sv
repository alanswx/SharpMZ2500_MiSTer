//=======================================================================================================
//
// mz2500_int.sv - MZ-2500 interrupt block (ports C6/C7): four sources with IM 2 vectors.
//
//   C6 W: bits 7-4 select which vector a C7 write sets (7 CRTC, 6 8253, 5 printer, 4 RTC);
//         bits 3-0 enable the sources (3 CRTC, 2 8253, 1 printer, 0 RTC).
//   C7 W: vector for the selected source(s).
//
// Behaviour follows CSP interrupt.cpp, except for how a request ends: a rising source level sets the request,
// the acknowledge clears it and puts the source in service, RETI clears the in-service source. Priority CRTC >
// 8253 > printer > RTC; a source in service blocks everything below it (and a pending one above it, as in
// CSP). The block is last in the daisy chain (PIO -> SIO -> this), iei comes from the chain.
//
// CSP also clears a pending request when its source level falls. CSP can afford that because it checks and
// acknowledges an interrupt atomically at an instruction boundary; a real Z80 (and the T80) commits to the
// interrupt when it samples INT and acknowledges later, so a request withdrawn in between leaves the
// acknowledge with no vector: the CPU reads FFh and jumps through the wrong table entry. Ys III runs the 8253
// at 2 kHz and hits this within seconds (frame 374: OUT0 fell while interrupts were disabled after a RETI).
// So here a request stays latched until it is acknowledged; at worst a timer tick is taken late.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500_int
(
	input            clk,
	input            reset,

	input            wr_stb,       // one clock: I/O write to C6 (a0 = 0) or C7 (a0 = 1)
	input            a0,
	input      [7:0] din,

	input      [3:0] src,          // request levels: 0 CRTC (graphics V-blank), 1 8253 OUT0, 2 printer, 3 RTC alarm
	input            iei,
	input            ack_stb,      // one clock at the end of an interrupt acknowledge cycle answered by this block
	input            reti_stb,     // one clock when the CPU executed RETI

	output           int_n,
	output           ack_mine,     // this block drives the vector in an acknowledge cycle
	output     [7:0] vector
);

reg  [3:0] enb, req, insvc, src_d;
reg  [7:0] sel;
reg  [7:0] vec[0:3];

// First source (in priority order) that is in service or pending.
reg  [2:0] first;      // 0-3 = channel, 4 = none
reg        first_svc;  // that channel is in service (not pending)
always @(*) begin
	first = 3'd4; first_svc = 1'b0;
	for (int ch = 3; ch >= 0; ch--) begin
		if (insvc[ch])                 begin first = ch[2:0]; first_svc = 1'b1; end
		else if (enb[ch] & req[ch])    begin first = ch[2:0]; first_svc = 1'b0; end
	end
end

assign int_n    = ~(iei && first != 3'd4 && !first_svc);
assign ack_mine = iei && first != 3'd4 && !first_svc;
assign vector   = (first < 3'd4) ? vec[first[1:0]] : 8'hFF;

always @(posedge clk) begin
	if (reset) begin
		enb <= 4'd0; req <= 4'd0; insvc <= 4'd0; sel <= 8'd0; src_d <= 4'd0;
		vec[0] <= 8'd0; vec[1] <= 8'd0; vec[2] <= 8'd0; vec[3] <= 8'd0;
	end
	else begin
		src_d <= src;
		for (int ch = 0; ch < 4; ch++)
			if (src[ch] && !src_d[ch]) req[ch] <= 1'b1;

		if (wr_stb) begin
			if (!a0) begin
				// enable bits are in reverse order: bit 3 = channel 0 (CRTC)
				enb <= {din[0], din[1], din[2], din[3]};
				sel <= din;
			end
			else begin
				if (sel[7]) vec[0] <= din;
				if (sel[6]) vec[1] <= din;
				if (sel[5]) vec[2] <= din;
				if (sel[4]) vec[3] <= din;
			end
		end

		if (ack_stb && ack_mine) begin
			req[first[1:0]]   <= 1'b0;
			insvc[first[1:0]] <= 1'b1;
		end

		if (reti_stb) begin
			// clear the highest-priority in-service source
			if (insvc[0])      insvc[0] <= 1'b0;
			else if (insvc[1]) insvc[1] <= 1'b0;
			else if (insvc[2]) insvc[2] <= 1'b0;
			else if (insvc[3]) insvc[3] <= 1'b0;
		end
	end
end

endmodule
