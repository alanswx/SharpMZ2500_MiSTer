//=======================================================================================================
//
// rp5c15.sv - Ricoh RP5C15 real-time clock (MZ-2500 port CC, register number on A11-A8).
//
// Registers (4 bits): bank 0 (D bit 0 = 0) 0-C = time digits: second, 10 s, minute, 10 min, hour, 10 h (+ PM bit 1
// in 12-hour mode), day of week, day, 10 day, month, 10 month, year, 10 year. Bank 1: 0 clock out, 1 adjust, 2-8 alarm
// digits, A bit 0 = 24-hour mode, B leap-year counter (reads the years since the last leap year), C unused.
// D: bit 0 bank, bit 2 AE (alarm enable), bit 3 TE (timer enable). E: test. F: bit 0 alarm reset, bit 1 reset,
// bit 2 = 1 disables the 16 Hz pulse, bit 3 = 1 disables the 1 Hz pulse.
//
// Behaviour follows CSP rp5c01.cpp (HAS_RP5C15): reset values A = 1 (24 h), D = 8, F = 0Ch; the clock keeps a 24-hour
// BCD calendar internally, 12-hour reads are converted; the pulse output (active low) is the alarm (when AE) or the
// enabled 1 Hz / 16 Hz square waves, and like CSP it only changes when one of those events happens (the MZ-2500 reads
// it as OPN port B bit 3). The time is loaded from MiSTer's RTC (hps_io RTC: BCD second, minute, hour, date, month,
// year, weekday; bit 64 toggles on an update) and counts from there; CPU writes to the time digits set it.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module rp5c15 #(parameter integer CLK_HZ = 85909091)
(
	input            clk,
	input            reset,
	input      [3:0] addr,
	input      [3:0] din,
	input            wr_stb,
	output reg [3:0] dout,
	input     [64:0] rtc,
	output reg       pulse_n
);

// time, BCD, 24-hour
reg [7:0] sec, min, hour, day, mon, year;
reg [2:0] dow;
reg [3:0] alrm[2:8];
reg [3:0] reg_a, reg_d, reg_e, reg_f;
reg       rtc_tog;
reg       alarm, p1hz, p16hz;

// ---- one-second and 32 Hz ticks ----
localparam integer DIV32 = CLK_HZ / 32;
reg [$clog2(DIV32)-1:0] div;
reg [4:0] n32;
wire tick32  = (div == DIV32 - 1);
wire tick1s  = tick32 && n32 == 5'd31;

// ---- BCD helpers ----
function [7:0] bcd_inc(input [7:0] v);
	bcd_inc = (v[3:0] == 4'd9) ? {v[7:4] + 4'd1, 4'd0} : v + 8'd1;
endfunction
function [4:0] bcd2bin5(input [7:0] v);       // 0-31
	bcd2bin5 = {v[5:4], 3'b000} + {v[5:4], 1'b0} + v[3:0];
endfunction
wire [3:0] yr_mod4 = (({3'd0, year[4]} << 1) + year[3:0]) & 4'd3;   // (10*t + o) mod 4 = (2t + o) mod 4
reg  [4:0] mdays;
always @(*) begin
	case (mon)
		8'h02:                       mdays = (yr_mod4 == 4'd0) ? 5'd29 : 5'd28;
		8'h04, 8'h06, 8'h09, 8'h11:  mdays = 5'd30;
		default:                     mdays = 5'd31;
	endcase
end

// 12-hour view of the hour
wire       h12  = !reg_a[0];
wire       pm   = hour >= 8'h12;
reg  [7:0] hour_rd;
always @(*) begin
	hour_rd = hour;
	if (h12) begin
		case (hour)
			8'h12: hour_rd = 8'h00; 8'h13: hour_rd = 8'h01; 8'h14: hour_rd = 8'h02; 8'h15: hour_rd = 8'h03;
			8'h16: hour_rd = 8'h04; 8'h17: hour_rd = 8'h05; 8'h18: hour_rd = 8'h06; 8'h19: hour_rd = 8'h07;
			8'h20: hour_rd = 8'h08; 8'h21: hour_rd = 8'h09; 8'h22: hour_rd = 8'h10; 8'h23: hour_rd = 8'h11;
			default: hour_rd = hour;
		endcase
	end
end

always @(*) begin
	dout = 4'd0;
	if (addr <= 4'hC && !reg_d[0]) begin
		case (addr)
			4'h0: dout = sec[3:0];
			4'h1: dout = sec[7:4];
			4'h2: dout = min[3:0];
			4'h3: dout = min[7:4];
			4'h4: dout = hour_rd[3:0];
			4'h5: dout = {2'b00, h12 && pm, 1'b0} | hour_rd[7:4];
			4'h6: dout = {1'b0, dow};
			4'h7: dout = day[3:0];
			4'h8: dout = day[7:4];
			4'h9: dout = mon[3:0];
			4'hA: dout = mon[7:4];
			4'hB: dout = year[3:0];
			4'hC: dout = year[7:4];
			default: ;
		endcase
	end
	else begin
		case (addr)
			4'hA: dout = reg_a;
			4'hB: dout = {2'b00, yr_mod4[1:0]};
			4'hD: dout = reg_d;
			4'hE: dout = reg_e;
			4'hF: dout = reg_f;
			default: dout = (addr >= 4'h2 && addr <= 4'h8) ? alrm[addr] : 4'd0;
		endcase
	end
end

// alarm match on minute .. 10-day digits (CSP: registers 3-8 compared with masks; 2 = minute digit counted too)
wire alarm_hit = min[7:4] == {1'b0, alrm[3][2:0]} && hour[3:0] == alrm[4] && hour[5:4] == alrm[5][1:0] &&
                 {1'b0, dow} == {1'b0, alrm[6][2:0]} && day[3:0] == alrm[7] && day[5:4] == alrm[8][1:0];

always @(posedge clk) begin
	if (reset) begin
		div <= 0; n32 <= 5'd0;
		reg_a <= 4'd1; reg_d <= 4'd8; reg_e <= 4'd0; reg_f <= 4'hC;
		for (int i = 2; i <= 8; i++) alrm[i] <= 4'd0;
		alarm <= 1'b0; p1hz <= 1'b0; p16hz <= 1'b0;
		pulse_n <= 1'b0;                 // CSP: OPN port B bit 3 starts at 0 (37h) until the first pulse update
		sec <= rtc[7:0]; min <= rtc[15:8]; hour <= rtc[23:16]; day <= rtc[31:24]; mon <= rtc[39:32];
		year <= rtc[47:40]; dow <= rtc[50:48];
		rtc_tog <= rtc[64];
	end
	else begin
		div <= tick32 ? '0 : div + 1'd1;
		if (tick32) begin
			n32 <= n32 + 5'd1;
			if (n32[0]) begin             // 16 Hz square wave: toggle every 1/32 s; 1 Hz: toggle every 1/2 s
				p16hz <= ~p16hz;
				if (!reg_f[2]) pulse_n <= ~((reg_d[2] & alarm) | (!reg_f[3] & p1hz) | ~p16hz);
			end
			if (n32 == 5'd15 || n32 == 5'd31) begin
				p1hz <= ~p1hz;
				if (!reg_f[3]) pulse_n <= ~((reg_d[2] & alarm) | ~p1hz | (!reg_f[2] & p16hz));
			end
		end

		if (rtc[64] != rtc_tog) begin
			rtc_tog <= rtc[64];
			sec <= rtc[7:0]; min <= rtc[15:8]; hour <= rtc[23:16]; day <= rtc[31:24]; mon <= rtc[39:32];
			year <= rtc[47:40]; dow <= rtc[50:48];
		end
		else if (tick1s) begin
			if (sec == 8'h59) begin
				sec <= 8'h00;
				if (min == 8'h59) begin
					min <= 8'h00;
					if (hour == 8'h23) begin
						hour <= 8'h00;
						dow  <= (dow == 3'd6) ? 3'd0 : dow + 3'd1;
						if (bcd2bin5(day) == mdays) begin
							day <= 8'h01;
							if (mon == 8'h12) begin mon <= 8'h01; year <= (year == 8'h99) ? 8'h00 : bcd_inc(year); end
							else mon <= bcd_inc(mon);
						end
						else day <= bcd_inc(day);
					end
					else hour <= bcd_inc(hour);
				end
				else min <= bcd_inc(min);
			end
			else sec <= bcd_inc(sec);
			if (reg_d[3] && alarm_hit) alarm <= 1'b1;
			if (reg_d[3] && reg_d[2]) pulse_n <= ~(alarm | alarm_hit | (!reg_f[3] & p1hz) | (!reg_f[2] & p16hz));
		end

		if (wr_stb) begin
			if (addr <= 4'hC && !reg_d[0]) begin
				case (addr)
					4'h0: sec[3:0]  <= din;
					4'h1: sec[7:4]  <= {1'b0, din[2:0]};
					4'h2: min[3:0]  <= din;
					4'h3: min[7:4]  <= {1'b0, din[2:0]};
					4'h4: hour[3:0] <= din;      // 24-hour digits (12-hour writes: PM bit in register 5 bit 1)
					4'h5: hour[7:4] <= h12 ? {3'd0, din[0]} : {2'd0, din[1:0]};
					4'h6: dow       <= din[2:0];
					4'h7: day[3:0]  <= din;
					4'h8: day[7:4]  <= {2'd0, din[1:0]};
					4'h9: mon[3:0]  <= din;
					4'hA: mon[7:4]  <= {3'd0, din[0]};
					4'hB: year[3:0] <= din;
					4'hC: year[7:4] <= din;
					default: ;
				endcase
				div <= '0; n32 <= 5'd0;   // CSP restarts the one-second event on a time write
			end
			else begin
				case (addr)
					4'hA: reg_a <= din;
					4'hD: reg_d <= din;
					4'hE: reg_e <= din;
					4'hF: begin
						reg_f <= din;
						if (reg_d[0] && din[0] && alarm) begin alarm <= 1'b0; if (reg_d[2]) pulse_n <= 1'b1; end
					end
					default: if (addr >= 4'h2 && addr <= 4'h8) alrm[addr] <= din;
				endcase
			end
		end
	end
end

endmodule
