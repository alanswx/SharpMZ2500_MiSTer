//=======================================================================================================
//
// dpram.sv - inferred dual-port block RAM, one clock.
//
// Port A reads and writes, port B only reads (raster side). Both reads have one clock of latency.
// Read-during-write results are unspecified (no_rw_check): nothing in the core reads an address on the clock it
// is written (the graphics read-modify-write uses data read on earlier clocks of the CPU cycle). Without it
// Quartus duplicates each RAM, or builds it from registers, to get "old data" on the write port.
//
// Copyright (C) 2026 Alan Steremberg. GPL-3.0-or-later (see LICENSE).
//=======================================================================================================

module dpram #(parameter AW = 11, parameter DW = 8)
(
	input               clk,

	input      [AW-1:0] a_addr,
	input               a_we,
	input      [DW-1:0] a_din,
	output reg [DW-1:0] a_dout,

	input      [AW-1:0] b_addr,
	output reg [DW-1:0] b_dout
);

(* ramstyle = "no_rw_check" *) reg [DW-1:0] mem[0:(1 << AW) - 1];

always @(posedge clk) begin
	a_dout <= mem[a_addr];
	if (a_we) mem[a_addr] <= a_din;
end

always @(posedge clk) b_dout <= mem[b_addr];

endmodule

// Single-port version (CPU-only memories: IPL, main RAM).
module spram #(parameter AW = 11, parameter DW = 8)
(
	input               clk,
	input      [AW-1:0] addr,
	input               we,
	input      [DW-1:0] din,
	output reg [DW-1:0] dout
);

(* ramstyle = "no_rw_check" *) reg [DW-1:0] mem[0:(1 << AW) - 1];

always @(posedge clk) begin
	dout <= mem[addr];
	if (we) mem[addr] <= din;
end

endmodule
