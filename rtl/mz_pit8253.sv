//=======================================================================================================
//
// mz_pit8253.sv - Intel 8253 programmable interval timer, clock-enable style.
//
// Each counter counts on clk_ce[n], a one-clock pulse standing for the falling edge of its CLK input.
// Modes 0-5, read/write LSB, MSB or LSB then MSB, counter latch command. BCD counting is not
// implemented (the MZ-2500 software doesn't use it). gate_trig[n] is a GATE rising edge (the MZ-2500's
// F0-F3 ports pulse GATE0/GATE1 high-low-high): it restarts modes 1, 2, 3 and 5 from the initial count.
//
// Bus side: dout is the value a read of 'addr' returns now; rd_stb (end of the read cycle) and wr_stb
// commit the side effects.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz_pit8253
(
	input            clk,
	input            reset,

	input      [1:0] addr,
	input      [7:0] din,
	output reg [7:0] dout,
	input            wr_stb,
	input            rd_stb,

	input      [2:0] clk_ce,
	input      [2:0] gate,
	input      [2:0] gate_trig,
	output     [2:0] out
);

reg  [2:0] mode[0:2];
reg  [1:0] rw[0:2];
reg [15:0] init[0:2];     // initial count register
reg [15:0] cnt[0:2];      // counting element
reg [15:0] olatch[0:2];   // output latch
reg  [2:0] latched;
reg  [2:0] rd_msb;        // next read returns the MSB (rw = 3)
reg  [2:0] wr_msb;        // next write is the MSB (rw = 3)
reg  [2:0] load;          // new count written: load it on the next clock
reg  [2:0] armed;         // count loaded at least once
reg  [2:0] trig;          // gate trigger pending
reg  [2:0] outr;
reg  [2:0] m0_done;       // mode 0/4 terminal count reached

assign out = outr;

wire [15:0] rval = latched[addr] ? olatch[addr] : cnt[addr];
always @(*) begin
	dout = 8'hFF;
	if (addr != 2'd3) begin
		case (rw[addr])
			2'd1: dout = rval[7:0];
			2'd2: dout = rval[15:8];
			2'd3: dout = rd_msb[addr] ? rval[15:8] : rval[7:0];
			default: dout = 8'hFF;
		endcase
	end
end

always @(posedge clk) begin
	if (reset) begin
		for (int n = 0; n < 3; n++) begin
			mode[n] <= 3'd0; rw[n] <= 2'd3; init[n] <= 16'd0; cnt[n] <= 16'd0; olatch[n] <= 16'd0;
		end
		latched <= 3'd0; rd_msb <= 3'd0; wr_msb <= 3'd0; load <= 3'd0; armed <= 3'd0; trig <= 3'd0;
		outr <= 3'b111; m0_done <= 3'd0;
	end
	else begin
		// ---- counting ----
		for (int n = 0; n < 3; n++) begin
			if (gate_trig[n]) trig[n] <= 1'b1;
			if (clk_ce[n]) begin
				if (load[n] && !(mode[n] == 3'd1 || mode[n] == 3'd5)) begin
					cnt[n]   <= (mode[n][1:0] == 2'd3 && mode[n] != 3'd7) ? {init[n][15:1], 1'b0} : init[n];
					load[n]  <= 1'b0;
					armed[n] <= 1'b1;
					m0_done[n] <= 1'b0;
				end
				else if (trig[n] && armed[n] && (mode[n] == 3'd1 || mode[n] == 3'd5 || mode[n][1] == 1'b1)) begin
					// gate trigger: restart from the initial count
					cnt[n]  <= (mode[n][1:0] == 2'd3) ? {init[n][15:1], 1'b0} : init[n];
					trig[n] <= 1'b0;
					m0_done[n] <= 1'b0;
					if (mode[n] == 3'd1) outr[n] <= 1'b0;
					if (mode[n][1] == 1'b1) outr[n] <= 1'b1;
				end
				else if (armed[n]) begin
					trig[n] <= 1'b0;
					case (mode[n])
						3'd0, 3'd1: begin   // interrupt on terminal count / one-shot
							if (gate[n] || mode[n] == 3'd1) begin
								cnt[n] <= cnt[n] - 16'd1;
								if (cnt[n] == 16'd1 && !m0_done[n]) begin outr[n] <= 1'b1; m0_done[n] <= 1'b1; end
							end
						end
						3'd2, 3'd6: begin   // rate generator: OUT low for the last clock of each period
							if (gate[n]) begin
								if (cnt[n] == 16'd1) begin cnt[n] <= init[n]; outr[n] <= 1'b1; end
								else begin
									cnt[n] <= cnt[n] - 16'd1;
									if (cnt[n] == 16'd2) outr[n] <= 1'b0;
								end
							end
						end
						3'd3, 3'd7: begin   // square wave: count by 2, toggle OUT at the end of each half
							if (gate[n]) begin
								if (cnt[n] == 16'd2 || cnt[n] == 16'd1) begin
									cnt[n]  <= {init[n][15:1], 1'b0};
									outr[n] <= ~outr[n];
								end
								else cnt[n] <= cnt[n] - 16'd2;
							end
						end
						3'd4, 3'd5: begin   // software / hardware triggered strobe
							if (gate[n] || mode[n] == 3'd5) begin
								cnt[n] <= cnt[n] - 16'd1;
								if (cnt[n] == 16'd1 && !m0_done[n]) begin outr[n] <= 1'b0; m0_done[n] <= 1'b1; end
								else outr[n] <= 1'b1;
							end
						end
					endcase
				end
			end
			if (!gate[n] && (mode[n][1] == 1'b1)) outr[n] <= 1'b1;   // modes 2 and 3: GATE low forces OUT high
		end

		// ---- bus ----
		if (wr_stb) begin
			if (addr == 2'd3) begin
				if (din[7:6] != 2'd3) begin
					if (din[5:4] == 2'd0) begin
						// counter latch command
						if (!latched[din[7:6]]) begin
							olatch[din[7:6]]  <= cnt[din[7:6]];
							latched[din[7:6]] <= 1'b1;
						end
					end
					else begin
						mode[din[7:6]]    <= din[3:1];
						rw[din[7:6]]      <= din[5:4];
						rd_msb[din[7:6]]  <= 1'b0;
						wr_msb[din[7:6]]  <= 1'b0;
						latched[din[7:6]] <= 1'b0;
						armed[din[7:6]]   <= 1'b0;
						load[din[7:6]]    <= 1'b0;
						outr[din[7:6]]    <= (din[3:1] == 3'd0) ? 1'b0 : 1'b1;
					end
				end
			end
			else begin
				case (rw[addr])
					2'd1: begin init[addr] <= {8'd0, din}; load[addr] <= 1'b1; end
					2'd2: begin init[addr] <= {din, 8'd0}; load[addr] <= 1'b1; end
					2'd3: begin
						if (!wr_msb[addr]) begin
							init[addr][7:0] <= din;
							wr_msb[addr] <= 1'b1;
						end
						else begin
							init[addr][15:8] <= din;
							wr_msb[addr] <= 1'b0;
							load[addr] <= 1'b1;
						end
					end
					default: ;
				endcase
				if (mode[addr] == 3'd0) outr[addr] <= 1'b0;
				// modes 1 and 5 wait for a gate trigger with the new count
				if (mode[addr] == 3'd1 || mode[addr] == 3'd5) armed[addr] <= 1'b1;
			end
		end

		if (rd_stb && addr != 2'd3) begin
			if (rw[addr] == 2'd3) begin
				rd_msb[addr] <= ~rd_msb[addr];
				if (rd_msb[addr]) latched[addr] <= 1'b0;
			end
			else latched[addr] <= 1'b0;
		end
	end
end

endmodule
