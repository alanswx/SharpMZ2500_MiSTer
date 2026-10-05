//=======================================================================================================
//
// mz2500_kbd.sv - PS/2 (hps_io ps2_key) to the MZ-2500 keyboard matrix.
//
// 14 rows x 8 bits, active low (docs/hardware.md 10.3). The Z80 PIO port A selects the row: bit 4 = 1 reads
// row bits 3-0, bit 4 = 0 reads the AND of all rows ("any key"). The layout is positional like CSP's
// (a Japanese MZ keyboard on PC keys): the JIS symbols sit where a JP keyboard has them.
//
// PC key -> MZ key for the non-obvious ones: F11 = HELP, F12 = COPY, End or Pause = BREAK, Home = CLR/HOME,
// Delete/Insert = INST/DEL, Alt = GRAPH, Caps Lock = LOCK, Left GUI or the JP Kanji key = LOGO,
// JP Kana / Muhenkan / Henkan keys as themselves.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module mz2500_kbd
(
	input            clk,
	input            reset,
	input     [10:0] ps2_key,      // [10] toggles per event, [9] pressed, [8] extended, [7:0] code
	input      [4:0] column,       // Z80 PIO port A bits 4-0
	output     [7:0] data          // active low key bits
);

reg  [7:0] keys[0:13];
reg        toggle_d;

// Row and bit of a key, or row 15 for "not mapped".
reg  [3:0] row;
reg  [2:0] bit_n;
always @(*) begin
	row = 4'd15; bit_n = 3'd0;
	if (!ps2_key[8]) begin
		case (ps2_key[7:0])
			8'h05: begin row = 4'd0;  bit_n = 3'd0; end   // F1
			8'h06: begin row = 4'd0;  bit_n = 3'd1; end   // F2
			8'h04: begin row = 4'd0;  bit_n = 3'd2; end   // F3
			8'h0C: begin row = 4'd0;  bit_n = 3'd3; end   // F4
			8'h03: begin row = 4'd0;  bit_n = 3'd4; end   // F5
			8'h0B: begin row = 4'd0;  bit_n = 3'd5; end   // F6
			8'h83: begin row = 4'd0;  bit_n = 3'd6; end   // F7
			8'h0A: begin row = 4'd0;  bit_n = 3'd7; end   // F8
			8'h01: begin row = 4'd1;  bit_n = 3'd0; end   // F9
			8'h09: begin row = 4'd1;  bit_n = 3'd1; end   // F10
			8'h75: begin row = 4'd1;  bit_n = 3'd2; end   // KP 8
			8'h7D: begin row = 4'd1;  bit_n = 3'd3; end   // KP 9
			8'h71: begin row = 4'd1;  bit_n = 3'd5; end   // KP .
			8'h79: begin row = 4'd1;  bit_n = 3'd6; end   // KP +
			8'h7B: begin row = 4'd1;  bit_n = 3'd7; end   // KP -
			8'h70: begin row = 4'd2;  bit_n = 3'd0; end   // KP 0
			8'h69: begin row = 4'd2;  bit_n = 3'd1; end   // KP 1
			8'h72: begin row = 4'd2;  bit_n = 3'd2; end   // KP 2
			8'h7A: begin row = 4'd2;  bit_n = 3'd3; end   // KP 3
			8'h6B: begin row = 4'd2;  bit_n = 3'd4; end   // KP 4
			8'h73: begin row = 4'd2;  bit_n = 3'd5; end   // KP 5
			8'h74: begin row = 4'd2;  bit_n = 3'd6; end   // KP 6
			8'h6C: begin row = 4'd2;  bit_n = 3'd7; end   // KP 7
			8'h0D: begin row = 4'd3;  bit_n = 3'd0; end   // TAB
			8'h29: begin row = 4'd3;  bit_n = 3'd1; end   // SPACE
			8'h5A: begin row = 4'd3;  bit_n = 3'd2; end   // RETURN
			8'h4A: begin row = 4'd4;  bit_n = 3'd0; end   // /
			8'h1C: begin row = 4'd4;  bit_n = 3'd1; end   // A
			8'h32: begin row = 4'd4;  bit_n = 3'd2; end   // B
			8'h21: begin row = 4'd4;  bit_n = 3'd3; end   // C
			8'h23: begin row = 4'd4;  bit_n = 3'd4; end   // D
			8'h24: begin row = 4'd4;  bit_n = 3'd5; end   // E
			8'h2B: begin row = 4'd4;  bit_n = 3'd6; end   // F
			8'h34: begin row = 4'd4;  bit_n = 3'd7; end   // G
			8'h33: begin row = 4'd5;  bit_n = 3'd0; end   // H
			8'h43: begin row = 4'd5;  bit_n = 3'd1; end   // I
			8'h3B: begin row = 4'd5;  bit_n = 3'd2; end   // J
			8'h42: begin row = 4'd5;  bit_n = 3'd3; end   // K
			8'h4B: begin row = 4'd5;  bit_n = 3'd4; end   // L
			8'h3A: begin row = 4'd5;  bit_n = 3'd5; end   // M
			8'h31: begin row = 4'd5;  bit_n = 3'd6; end   // N
			8'h44: begin row = 4'd5;  bit_n = 3'd7; end   // O
			8'h4D: begin row = 4'd6;  bit_n = 3'd0; end   // P
			8'h15: begin row = 4'd6;  bit_n = 3'd1; end   // Q
			8'h2D: begin row = 4'd6;  bit_n = 3'd2; end   // R
			8'h1B: begin row = 4'd6;  bit_n = 3'd3; end   // S
			8'h2C: begin row = 4'd6;  bit_n = 3'd4; end   // T
			8'h3C: begin row = 4'd6;  bit_n = 3'd5; end   // U
			8'h2A: begin row = 4'd6;  bit_n = 3'd6; end   // V
			8'h1D: begin row = 4'd6;  bit_n = 3'd7; end   // W
			8'h22: begin row = 4'd7;  bit_n = 3'd0; end   // X
			8'h35: begin row = 4'd7;  bit_n = 3'd1; end   // Y
			8'h1A: begin row = 4'd7;  bit_n = 3'd2; end   // Z
			8'h52: begin row = 4'd7;  bit_n = 3'd3; end   // ^  (' key)
			8'h5D: begin row = 4'd7;  bit_n = 3'd4; end   // yen (\ key)
			8'h6A: begin row = 4'd7;  bit_n = 3'd4; end   // yen (JP yen key)
			8'h61: begin row = 4'd7;  bit_n = 3'd5; end   // _  (ISO extra key)
			8'h51: begin row = 4'd7;  bit_n = 3'd5; end   // _  (JP ro key)
			8'h49: begin row = 4'd7;  bit_n = 3'd6; end   // .
			8'h41: begin row = 4'd7;  bit_n = 3'd7; end   // ,
			8'h45: begin row = 4'd8;  bit_n = 3'd0; end   // 0
			8'h16: begin row = 4'd8;  bit_n = 3'd1; end   // 1
			8'h1E: begin row = 4'd8;  bit_n = 3'd2; end   // 2
			8'h26: begin row = 4'd8;  bit_n = 3'd3; end   // 3
			8'h25: begin row = 4'd8;  bit_n = 3'd4; end   // 4
			8'h2E: begin row = 4'd8;  bit_n = 3'd5; end   // 5
			8'h36: begin row = 4'd8;  bit_n = 3'd6; end   // 6
			8'h3D: begin row = 4'd8;  bit_n = 3'd7; end   // 7
			8'h3E: begin row = 4'd9;  bit_n = 3'd0; end   // 8
			8'h46: begin row = 4'd9;  bit_n = 3'd1; end   // 9
			8'h4C: begin row = 4'd9;  bit_n = 3'd2; end   // :  (; key)
			8'h55: begin row = 4'd9;  bit_n = 3'd3; end   // ;  (= key)
			8'h4E: begin row = 4'd9;  bit_n = 3'd4; end   // -
			8'h0E: begin row = 4'd9;  bit_n = 3'd5; end   // @  (` key)
			8'h54: begin row = 4'd9;  bit_n = 3'd6; end   // [
			8'h5B: begin row = 4'd10; bit_n = 3'd0; end   // ]
			8'h07: begin row = 4'd10; bit_n = 3'd1; end   // COPY (F12)
			8'h66: begin row = 4'd10; bit_n = 3'd4; end   // BS
			8'h76: begin row = 4'd10; bit_n = 3'd5; end   // ESC
			8'h7C: begin row = 4'd10; bit_n = 3'd6; end   // KP *
			8'h11: begin row = 4'd11; bit_n = 3'd0; end   // GRAPH (left Alt)
			8'h58: begin row = 4'd11; bit_n = 3'd1; end   // LOCK (Caps Lock)
			8'h12: begin row = 4'd11; bit_n = 3'd2; end   // SHIFT (left)
			8'h59: begin row = 4'd11; bit_n = 3'd2; end   // SHIFT (right)
			8'h13: begin row = 4'd11; bit_n = 3'd3; end   // KANA (JP kana key)
			8'h14: begin row = 4'd11; bit_n = 3'd4; end   // CTRL (left)
			8'h67: begin row = 4'd12; bit_n = 3'd0; end   // MUHENKAN
			8'h64: begin row = 4'd12; bit_n = 3'd1; end   // HENKAN
			8'h78: begin row = 4'd13; bit_n = 3'd1; end   // HELP (F11)
			default: ;
		endcase
	end
	else begin
		case (ps2_key[7:0])
			8'h5A: begin row = 4'd3;  bit_n = 3'd2; end   // KP Enter = RETURN
			8'h75: begin row = 4'd3;  bit_n = 3'd3; end   // UP
			8'h72: begin row = 4'd3;  bit_n = 3'd4; end   // DOWN
			8'h6B: begin row = 4'd3;  bit_n = 3'd5; end   // LEFT
			8'h74: begin row = 4'd3;  bit_n = 3'd6; end   // RIGHT
			8'h69: begin row = 4'd3;  bit_n = 3'd7; end   // BREAK (End)
			8'h77: begin row = 4'd3;  bit_n = 3'd7; end   // BREAK (Pause)
			8'h6C: begin row = 4'd10; bit_n = 3'd2; end   // CLR/HOME (Home)
			8'h71: begin row = 4'd10; bit_n = 3'd3; end   // INST/DEL (Delete)
			8'h70: begin row = 4'd10; bit_n = 3'd3; end   // INST/DEL (Insert)
			8'h4A: begin row = 4'd10; bit_n = 3'd7; end   // KP /
			8'h7A: begin row = 4'd1;  bit_n = 3'd4; end   // KP , (Page Down, as maroon's adapter)
			8'h11: begin row = 4'd11; bit_n = 3'd0; end   // GRAPH (right Alt)
			8'h14: begin row = 4'd11; bit_n = 3'd4; end   // CTRL (right)
			8'h1F: begin row = 4'd13; bit_n = 3'd0; end   // LOGO (left GUI)
			8'h27: begin row = 4'd13; bit_n = 3'd0; end   // LOGO (right GUI)
			default: ;
		endcase
	end
end

always @(posedge clk) begin
	if (reset) begin
		for (int r = 0; r < 14; r++) keys[r] <= 8'hFF;
		toggle_d <= ps2_key[10];
	end
	else begin
		toggle_d <= ps2_key[10];
		if (ps2_key[10] != toggle_d && row != 4'd15)
			keys[row][bit_n] <= ~ps2_key[9];
	end
end

reg [7:0] all_rows;
always @(*) begin
	all_rows = 8'hFF;
	for (int r = 0; r < 14; r++) all_rows = all_rows & keys[r];
end

assign data = column[4] ? ((column[3:0] < 4'd14) ? keys[column[3:0]] : 8'hFF) : all_rows;

endmodule
