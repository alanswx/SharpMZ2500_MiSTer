// Behavioural model of rtl/sdram.sv (Sorgelig's controller, 8-bit mode) for the Verilator simulation.
//
// Same client handshake: a request starts on a rising edge of rd or we (address and data sampled on that
// clock), 'ready' drops on the next clock and comes back when the access is done. Latency is close to the
// controller's at CAS 2: a read returns 7 clocks after the request, a write completes after 4, and every
// 650 clocks a refresh holds the controller for 8 clocks (a request arriving then waits). An 8-bit read of
// the word last read (no write since) is a cache hit and keeps 'ready' high, as in the controller.

// MZ_FAST_SIM: clk_sys at half rate, so every latency is halved too (same time in ns).
module sdram_model #(parameter AW = 19)    // 512 KB is enough for main RAM + IPL
(
	input             clk,
	input      [24:0] addr,
	input       [7:0] din,
	output reg  [7:0] dout,
	input             rd,
	input             we,
	output reg        ready = 1'b1
);

reg [7:0] mem[0:(1 << AW) - 1];

reg        old_rd = 0, old_we = 0;
reg        busy = 0, pend_rd = 0, pend_we = 0, last_was_read = 0;
reg [24:0] a;
reg  [7:0] d;
reg  [3:0] cnt;
reg  [9:0] refresh = 0;
reg  [3:0] refresh_busy = 0;

`ifdef MZ_FAST_SIM
localparam [9:0] REF_PERIOD = 10'd324; localparam [3:0] REF_LEN = 4'd4, RD_LAT = 4'd2, WR_LAT = 4'd1;
`else
localparam [9:0] REF_PERIOD = 10'd649; localparam [3:0] REF_LEN = 4'd8, RD_LAT = 4'd6, WR_LAT = 4'd3;
`endif

always @(posedge clk) begin
	old_rd <= rd;
	old_we <= we;

	refresh <= (refresh == REF_PERIOD) ? 10'd0 : refresh + 10'd1;
	if (refresh == REF_PERIOD) refresh_busy <= REF_LEN;
	else if (refresh_busy != 4'd0) refresh_busy <= refresh_busy - 4'd1;

	if (we && !old_we) begin
		a <= addr; d <= din; pend_we <= 1'b1; ready <= 1'b0;
	end
	if (rd && !old_rd) begin
		a <= addr;
		if (!(ready && last_was_read && a[24:1] == addr[24:1])) begin pend_rd <= 1'b1; ready <= 1'b0; end
		else dout <= mem[addr[AW-1:0]];
	end

	if (!busy && refresh_busy == 4'd0 && (pend_rd || pend_we)) begin
		busy <= 1'b1;
		cnt  <= pend_we ? WR_LAT : RD_LAT;
	end
	else if (busy) begin
		if (cnt != 4'd0) cnt <= cnt - 4'd1;
		else begin
			busy <= 1'b0;
			if (pend_we) begin mem[a[AW-1:0]] <= d; pend_we <= 1'b0; last_was_read <= 1'b0; end
			else begin dout <= mem[a[AW-1:0]]; pend_rd <= 1'b0; last_was_read <= 1'b1; end
			ready <= 1'b1;
		end
	end
end

endmodule
