//=======================================================================================================
//
// mz2500_cmt.sv - MZ-2500 built-in data recorder: plays an MZT tape image held in SDRAM.
//
// Control (CSP cmt.cpp, MZ-2000/2500 rules; the MZ-80B boot mode uses level/edge rules on the same bits):
//   8255 port A falling edges: bit 0 REW, bit 1 FF, bit 2 PLAY, bit 3 STOP; bit 7 = 0 makes REW/FF an APSS search
//   (stop at the next record and pulse READ for 350 ms); bit 5 = 0 rewinds at the end of the tape, bit 6 = 0 plays
//   when the rewind reaches the top.
//   8255 port B (to the CPU): bit 6 READ (tape signal while playing), bit 5 TREADY (0 = cassette in), bit 4 WREADY
//   (1 = write protected: playback only here), bit 3 TEND (0 while the motor runs).
//
// Tape signal (BubiZ-2500 / CSP datarec.cpp MZT conversion as built for the MZ-2500, which the 2500 IPL reads):
// per record 1 s silence, 10000 short bits, 40 long, 40 short, 1 long, the 128-byte header (+ a 16-bit count of 1
// bits), 1 long, 256 short, the header again, 1 long, 1 s silence, 10000 short, 20 long, 20 short, 1 long, the data
// (+ count), 1 long. A byte is a long start bit and 8 bits MSB first. Long bit: 500 us high, 604 us low; short bit:
// 229 us high, 313 us low (24/29 and 11/15 samples at 48 kHz).
// MZ-2000/80B boot modes (fmt80b, CSP datarec.cpp for _MZ80B/_MZ2000): 1 s silence, 22000 short, 40 long, 41 short,
// the header (+ count), 1 long, a 1 ms pulse, 1 s silence, 11000 short, 20 long, 21 short, the data (+ count), 1 long.
// Long bit 16 + 16 samples, short bit 8 + 8.
//
// The image (MZF records back to back) is read one byte at a time through rd_req/rd_addr/rd_ack.
// Not done: recording, the voice track, motor sounds.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500_cmt #(parameter integer CLK_HZ = 85909091)
(
	input             clk,
	input             reset,
	input             mz80b,           // MZ-80B boot mode: level/edge control rules
	input             fmt80b,          // MZ-2000/80B boot modes: MZ-80B tape format

	input       [7:0] pa,              // 8255 port A
	input             loaded,          // a tape image is in SDRAM
	input      [19:0] tape_len,

	output reg        rd_req,
	output reg [19:0] rd_addr,
	input             rd_ack,
	input       [7:0] rd_data,

	output reg        read,            // 8255 PB6
	output            tready_n,        // 8255 PB5
	output            wready_n,        // 8255 PB4
	output            tend,            // 8255 PB3: 1 = stopped
	output            motor
);

// ---- 48 kHz sample tick ----
reg [27:0] acc;
reg        tick;
always @(posedge clk) begin
	tick <= 1'b0;
	if (acc >= CLK_HZ - 48000) begin acc <= acc - (CLK_HZ - 48000); tick <= 1'b1; end
	else acc <= acc + 48000;
end

// ---- transport ----
reg  [7:0] pa_d;
reg        playing, rewinding, apss;
reg        ffwd;                     // fast forward without APSS: winds one record per 0.5 s until STOP or the end
reg [15:0] ff_cnt;
reg  [1:0] skip;                     // APSS fast forward: reading the record's size (bytes 12h, 13h), then moving on
reg [15:0] apss_cnt;                 // 350 ms of READ high after an APSS stop, in samples
assign tready_n = !loaded;
assign wready_n = 1'b1;
assign tend     = !(playing || ffwd);
assign motor    = playing || ffwd;

// ---- signal generator ----
// phases of one record
localparam [4:0] P_SIL1 = 5'd0,  P_GAP1 = 5'd1,  P_TM_L = 5'd2,  P_TM_S = 5'd3,  P_L1 = 5'd4,  P_HDR1 = 5'd5,
                 P_L2   = 5'd6,  P_S256 = 5'd7,  P_HDR2 = 5'd8,  P_L3   = 5'd9,  P_SIL2 = 5'd10, P_GAP2 = 5'd11,
                 P_DM_L = 5'd12, P_DM_S = 5'd13, P_L4  = 5'd14, P_DATA = 5'd15, P_L5  = 5'd16,
                 P_PULSE = 5'd17;
reg  [4:0] phase;
reg [15:0] cnt;                      // bits (or samples for silence) left in this phase
reg [19:0] rec;                      // offset of the current record in the image
reg [15:0] size;                     // data size of the current record (from its header)
reg [16:0] idx;                      // byte index inside the block (header or data), then the 2 checksum bytes
reg [15:0] ones;                     // 1 bits sent in this block
reg  [7:0] shreg;                    // byte being sent
reg  [3:0] bitn;                     // 0 = start bit, 1-8 = data bits
reg        cur_bit;                  // bit being sent
reg        half;                     // 0 = high half, 1 = low half
reg  [5:0] samp;                     // samples left in this half
reg  [7:0] byte_next;                // prefetched byte
reg        byte_ok;

wire        in_block = (phase == P_HDR1 || phase == P_HDR2 || phase == P_DATA);
wire [16:0] blk_len  = (phase == P_DATA) ? {1'b0, size} : 17'd128;
wire [19:0] blk_base = (phase == P_DATA) ? rec + 20'd128 : rec;

function [5:0] half_len(input b, input h);
	if (fmt80b) half_len = b ? 6'd16 : 6'd8;
	else        half_len = b ? (h ? 6'd29 : 6'd24) : (h ? 6'd15 : 6'd11);
endfunction

task start_bit(input b);
	begin cur_bit <= b; half <= 1'b0; samp <= half_len(b, 1'b0); end
endtask

task begin_phase(input [4:0] p);
	begin
		phase <= p;
		case (p)
			P_SIL1, P_SIL2:          begin cnt <= 16'd48000; read <= 1'b0; end
			P_GAP1:                  begin cnt <= fmt80b ? 16'd22000 : 16'd10000; start_bit(1'b0); end
			P_GAP2:                  begin cnt <= fmt80b ? 16'd11000 : 16'd10000; start_bit(1'b0); end
			P_TM_L:                  begin cnt <= 16'd40;    start_bit(1'b1); end
			P_TM_S:                  begin cnt <= fmt80b ? 16'd41 : 16'd40; start_bit(1'b0); end
			P_DM_L:                  begin cnt <= 16'd20;    start_bit(1'b1); end
			P_DM_S:                  begin cnt <= fmt80b ? 16'd21 : 16'd20; start_bit(1'b0); end
			P_PULSE:                 begin cnt <= 16'd1; cur_bit <= 1'b1; half <= 1'b0; samp <= 6'd48; end
			P_S256:                  begin cnt <= 16'd256;   start_bit(1'b0); end
			P_HDR1, P_HDR2, P_DATA:  begin idx <= 17'd0; ones <= 16'd0; bitn <= 4'd0; start_bit(1'b1); end
			default:                 begin cnt <= 16'd1;     start_bit(1'b1); end     // P_L1-P_L5
		endcase
	end
endtask

wire at_end = rec + 20'd128 > tape_len;

always @(posedge clk) begin
	if (reset || !loaded) begin
		pa_d <= 8'hFF;
		playing <= 1'b0; rewinding <= 1'b0; apss <= 1'b0; apss_cnt <= 16'd0;
		rec <= 20'd0; read <= 1'b0; rd_req <= 1'b0; byte_ok <= 1'b0; skip <= 2'd0; size <= 16'd0; ffwd <= 1'b0; ff_cnt <= 16'd0;
		phase <= P_SIL1; cnt <= 16'd48000;
	end
	else begin
		pa_d <= pa;
		// ---- control ----
		if (!mz80b) begin
			// CSP applies the edges of one write in this order, each cancelling the motion before it: REW, FF, PLAY,
			// STOP. The MZ-2000 mode IPL writes 10h (all four) to leave the deck stopped where it is.
			if (pa_d[3] && !pa[3]) begin playing <= 1'b0; rewinding <= 1'b0; read <= 1'b0; skip <= 2'd0; ffwd <= 1'b0; end // STOP
			else if (pa_d[2] && !pa[2]) begin playing <= 1'b1; rewinding <= 1'b0; skip <= 2'd0; ffwd <= 1'b0; end           // PLAY
			else if (pa_d[1] && !pa[1]) begin                                                                              // FF
				playing <= 1'b0; rewinding <= 1'b0; apss <= !pa[7];
				if (!pa[7]) begin
					// to the next record: its size is in its header
					if (!at_end) begin skip <= 2'd1; rd_req <= 1'b1; rd_addr <= rec + 20'h12; byte_ok <= 1'b0; end
					phase <= P_SIL1; cnt <= 16'd48000;
				end
				else begin ffwd <= 1'b1; ff_cnt <= 16'd0; end
			end
			else if (pa_d[0] && !pa[0]) begin rewinding <= 1'b1; playing <= 1'b0; apss <= !pa[7]; skip <= 2'd0; ffwd <= 1'b0; end // REW
		end
		else begin
			// the 8255 clears port A at reset, so the IPL's first FFh write is an FF edge here: it is stopped right after
			if (!pa_d[3] && pa[3]) begin playing <= 1'b0; rewinding <= 1'b0; read <= 1'b0; ffwd <= 1'b0; skip <= 2'd0; end
			else if (!pa_d[2] && pa[2]) begin playing <= 1'b1; rewinding <= 1'b0; ffwd <= 1'b0; skip <= 2'd0; end
			else if (!pa_d[0] && pa[0]) begin
				playing <= 1'b0; apss <= 1'b0;
				if (pa[1]) begin ffwd <= 1'b1; ff_cnt <= 16'd0; end
				else begin rewinding <= 1'b1; ffwd <= 1'b0; skip <= 2'd0; end
			end
		end

		// rewind: instant, to the top (APSS: to the start of the previous record is not tracked; go to the top)
		if (rewinding) begin
			rewinding <= 1'b0;
			rec <= 20'd0; phase <= P_SIL1; cnt <= 16'd48000; read <= 1'b0;
			if (apss) apss_cnt <= 16'd16800;
			else if (!pa[6] && !mz80b) playing <= 1'b1;   // auto play at the top
		end

		if (tick && apss_cnt != 16'd0) begin
			apss_cnt <= apss_cnt - 16'd1;
			read <= (apss_cnt != 16'd1);
		end

		// ---- byte prefetch ----
		if (rd_ack) begin rd_req <= 1'b0; byte_next <= rd_data; byte_ok <= 1'b1; end
		if (rd_ack && skip == 2'd1) begin size[7:0] <= rd_data; skip <= 2'd2; rd_req <= 1'b1; rd_addr <= rec + 20'h13; end
		if (rd_ack && skip == 2'd2) begin
			skip <= 2'd0;
			rec <= rec + 20'd128 + {4'd0, rd_data, size[7:0]};
			phase <= P_SIL1; cnt <= 16'd48000;
			if (apss) apss_cnt <= 16'd16800;              // the gap is found: READ high for 350 ms
		end
		// fast forward: one record per 0.5 s of winding
		if (tick && ffwd) begin
			if (ff_cnt != 16'd24000) ff_cnt <= ff_cnt + 16'd1;
			else if (at_end) ffwd <= 1'b0;
			else if (skip == 2'd0) begin
				ff_cnt <= 16'd0;
				skip <= 2'd1; rd_req <= 1'b1; rd_addr <= rec + 20'h12; byte_ok <= 1'b0;
			end
		end

		// ---- signal ----
		if (tick && playing && apss_cnt == 16'd0) begin
			if (phase == P_SIL1 || phase == P_SIL2) begin
				read <= 1'b0;
				if (phase == P_SIL1 && at_end) begin
					playing <= 1'b0;                          // end of tape
					if (!pa[5] && !mz80b) rewinding <= 1'b1;
				end
				else if (cnt == 16'd1) begin_phase(phase + 5'd1);
				else cnt <= cnt - 16'd1;
				// prefetch the first header byte during the silence
				if (phase == P_SIL1 && cnt == 16'd100) begin rd_req <= 1'b1; rd_addr <= rec; byte_ok <= 1'b0; end
				if (phase == P_SIL2 && cnt == 16'd100) begin rd_req <= 1'b1; rd_addr <= rec + 20'd128; byte_ok <= 1'b0; end
			end
			else begin
				read <= !half;
				if (samp > 6'd1) samp <= samp - 6'd1;
				else if (!half) begin half <= 1'b1; samp <= (phase == P_PULSE) ? 6'd48 : half_len(cur_bit, 1'b1); end
				else begin
					// a bit is complete
					if (in_block) begin
						if (bitn == 4'd0) begin
							// start bit done: take the byte
							shreg <= (idx < blk_len) ? byte_next : (idx == blk_len) ? ones[15:8] : ones[7:0];
							bitn <= 4'd1;
							start_bit((idx < blk_len) ? byte_next[7] : (idx == blk_len) ? ones[15] : ones[7]);
							if (idx < blk_len && byte_next[7]) ones <= ones + 16'd1;
							// header bytes 12h/13h: data size
							if (phase == P_HDR1 && idx == 17'h12) size[7:0] <= byte_next;
							if (phase == P_HDR1 && idx == 17'h13) size[15:8] <= byte_next;
							// fetch the next byte
							if (idx + 17'd1 < blk_len) begin rd_req <= 1'b1; rd_addr <= blk_base + idx[15:0] + 20'd1; byte_ok <= 1'b0; end
						end
						else if (bitn != 4'd8) begin
							bitn <= bitn + 4'd1;
							start_bit(shreg[7 - bitn]);
							if (idx < blk_len && shreg[7 - bitn]) ones <= ones + 16'd1;
						end
						else begin
							// byte done
							if (idx + 17'd1 == blk_len + 17'd2) begin
								case (phase)
									P_HDR1: begin_phase(P_L2);
									P_HDR2: begin_phase(P_L3);
									default: begin_phase(P_L5);
								endcase
							end
							else begin idx <= idx + 17'd1; bitn <= 4'd0; start_bit(1'b1); end
						end
					end
					else if (cnt != 16'd1) begin cnt <= cnt - 16'd1; start_bit(cur_bit); end
					else begin
						case (phase)
							P_TM_S:  begin_phase(fmt80b ? P_HDR1 : P_L1);
							P_L2:    begin_phase(fmt80b ? P_PULSE : P_S256);
							P_PULSE: begin_phase(P_SIL2);
							P_DM_S:  begin_phase(fmt80b ? P_DATA : P_L4);
							P_S256: begin
								begin_phase(P_HDR2);
								rd_req <= 1'b1; rd_addr <= rec; byte_ok <= 1'b0;    // the header again
							end
							P_L3:   begin_phase(P_SIL2);
							P_L5:   begin                                           // record done: next one
								rec <= rec + 20'd128 + {4'd0, size};
								begin_phase(P_SIL1);
							end
							default: begin_phase(phase + 5'd1);
						endcase
					end
				end
			end
		end
	end
end

endmodule
