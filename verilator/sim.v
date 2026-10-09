`timescale 1ns/1ns
//
// Simulation top for the MZ-2500 core: the machine (rtl/mz2500.sv) with its ports made visible to the C++
// harness (sim_headless.cpp). It stands in for SharpMZ2500.sv; the harness plays hps_io (ps2_key, the ioctl
// ROM download, later the sd_* floppy bus).
//
// VHDL leaves (T80 and later the 8255/8253/PIO) come in as a Verilog netlist made by "ghdl synth" (Makefile).
//
module top(
   input         clk_sys /*verilator public_flat*/,
   input         reset /*verilator public_flat*/,
   input         lines400,
   input   [1:0] boot_mode,

   output [7:0]  VGA_R /*verilator public_flat*/,
   output [7:0]  VGA_G /*verilator public_flat*/,
   output [7:0]  VGA_B /*verilator public_flat*/,
   output        VGA_HS /*verilator public_flat*/,
   output        VGA_VS /*verilator public_flat*/,
   output        VGA_HB /*verilator public_flat*/,
   output        VGA_VB /*verilator public_flat*/,
   output        ce_pix /*verilator public_flat*/,

   output [15:0] AUDIO_L /*verilator public_flat*/,
   output [15:0] AUDIO_R /*verilator public_flat*/,

   input  [10:0] ps2_key,
   input         kbd_us,
   input         model_2520,
   input  [24:0] ps2_mouse,
   input         dbg_dump,       // one clock: write main RAM to out/ram_dump.hex and print the MMU pages

   input         ioctl_download,
   input   [7:0] ioctl_index,
   input         ioctl_wr,
   input  [24:0] ioctl_addr,
   input   [7:0] ioctl_dout,
   output        ioctl_wait /*verilator public_flat*/,

   // floppy image slots (hps_io sd_* bus), flattened for the C++ harness
   input   [1:0] img_mounted,
   input         img_readonly,
   input  [63:0] img_size,
   output [31:0] fdd_lba0,
   output [31:0] fdd_lba1,
   output  [1:0] fdd_rd,
   output  [1:0] fdd_wr,
   input   [1:0] fdd_ack,
   input   [8:0] sd_buff_addr,
   input   [7:0] sd_buff_dout,
   output  [7:0] fdd_buff_din0,
   output  [7:0] fdd_buff_din1,
   input         sd_buff_wr,

   output [15:0] cpu_pc /*verilator public_flat*/,
   output        cpu_ce /*verilator public_flat*/,
   output        cpu_m1_n /*verilator public_flat*/,
   output        dbg_io_wr /*verilator public_flat*/,
   output [7:0]  dbg_io_port /*verilator public_flat*/,
   output [7:0]  dbg_io_data /*verilator public_flat*/
);

// SDRAM: behavioural model of rtl/sdram.sv's client side (the core instantiates the real controller).
wire        dram_rd, dram_we, dram_ready;
wire [24:0] dram_addr;
wire  [7:0] dram_din, dram_dout;
sdram_model sdram
(
   .clk(clk_sys), .addr(dram_addr), .din(dram_din), .dout(dram_dout), .rd(dram_rd), .we(dram_we), .ready(dram_ready)
);

// drives 3-4 exist in the core; the harness serves drives 1-2
wire [31:0] fdd_lba[4];
wire  [7:0] fdd_buff_din[4];
wire  [3:0] fdd_rd4, fdd_wr4;
assign fdd_rd = fdd_rd4[1:0];
assign fdd_wr = fdd_wr4[1:0];
assign fdd_lba0 = fdd_lba[0];
assign fdd_lba1 = fdd_lba[1];
assign fdd_buff_din0 = fdd_buff_din[0];
assign fdd_buff_din1 = fdd_buff_din[1];

mz2500 mz2500
(
   .clk_sys(clk_sys),
   .reset(reset),
   .lines400(lines400),
   .boot_mode(boot_mode),
   .ps2_key(ps2_key),
   .kbd_us(kbd_us),
   .model_2520(model_2520),
   .joy0(6'd0), .joy1(6'd0), .ps2_mouse(ps2_mouse),
   // fixed RTC so runs are reproducible: 1990-04-01 (Sunday) 12:00:00
   .rtc({1'b0, 8'h00, 8'h00, 8'h90, 8'h04, 8'h01, 8'h12, 8'h00, 8'h00}),

   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
   .ioctl_wait(ioctl_wait),

   .img_mounted({2'b00, img_mounted}), .img_readonly(img_readonly), .img_size(img_size),
   .sd_lba(fdd_lba), .sd_rd(fdd_rd4), .sd_wr(fdd_wr4), .sd_ack({2'b00, fdd_ack}),
   .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(fdd_buff_din), .sd_buff_wr(sd_buff_wr),
   .fdd_busy(),

   .ram_rd(dram_rd), .ram_we(dram_we), .ram_addr(dram_addr), .ram_din(dram_din), .ram_dout(dram_dout), .ram_ready(dram_ready),

   .ce_pix(ce_pix),
   .R(VGA_R), .G(VGA_G), .B(VGA_B),
   .HSync(VGA_HS), .VSync(VGA_VS),
   .HBlank(VGA_HB), .VBlank(VGA_VB),

   .audio_l(AUDIO_L),
   .audio_r(AUDIO_R),

   .cpu_pc(cpu_pc),
   .cpu_ce(cpu_ce),
   .cpu_m1_n(cpu_m1_n),
   .dbg_io_wr(dbg_io_wr),
   .dbg_io_port(dbg_io_port),
   .dbg_io_data(dbg_io_data)
);

// +fdctrace: print FDC register reads (value as the CPU sees it, inverted bus) when it changes
reg fdctrace = 0;
reg [7:0] fdc_last = 0;
initial fdctrace = $test$plusargs("fdctrace");
always @(posedge clk_sys) if (fdctrace && mz2500.io_rd_end && mz2500.port[7:2] == 6'b110110) begin
   if (mz2500.io_dout != fdc_last || mz2500.port[1:0] != 2'd0)
      $display("[fdc] %0d rd %02x = %02x (status %02x)", cpu_cyc, mz2500.port, mz2500.io_dout, ~mz2500.io_dout);
   fdc_last <= mz2500.io_dout;
end
always @(posedge clk_sys) if (fdctrace && mz2500.ce_cpu && mz2500.io_rd && mz2500.port == 8'hD8 && cpu_cyc > 22007000 && cpu_cyc < 22009000)
   $display("[fdc] %0d  ce in-cycle D8 din %02x wait_n %0d", cpu_cyc, mz2500.cpu_din, mz2500.wait_n);
always @(posedge clk_sys) if (fdctrace && mz2500.io_wr_end && mz2500.port[7:2] == 6'b110110)
   $display("[fdc] %0d wr %02x = %02x (%02x)", cpu_cyc, mz2500.port, mz2500.cpu_dout, ~mz2500.cpu_dout);

// +f4trace: print F4 status reads when the value changes
reg f4trace = 0; reg [7:0] f4_last = 8'h55;
initial f4trace = $test$plusargs("f4trace");
always @(posedge clk_sys) if (f4trace && mz2500.io_rd_end && mz2500.port == 8'hF4) begin
   if (mz2500.io_dout != f4_last) $display("[f4] %0d %02x pc %04x", cpu_cyc, mz2500.io_dout, cpu_pc);
   f4_last <= mz2500.io_dout;
end

// +cmttrace: tape signal edges (clk_sys count at each change of PB6) and port A writes
reg cmttrace = 0; reg cmt_last = 0; reg [4:0] cmt_ph = 0; reg [63:0] clk_cnt = 0;
initial cmttrace = $test$plusargs("cmttrace");
always @(posedge clk_sys) begin
   clk_cnt <= clk_cnt + 1;
   if (cmttrace) begin
      cmt_last <= mz2500.cmt_read;
      if (mz2500.cmt_read != cmt_last) $display("[cmt] %0d %0d", clk_cnt, mz2500.cmt_read);
      if (mz2500.io_wr_end && mz2500.port == 8'hE0) $display("[cmtpa] %0d %02x", clk_cnt, mz2500.cpu_dout);
      cmt_ph <= mz2500.cmt.phase;
      if (mz2500.cmt.phase != cmt_ph) $display("[cmtph] %0d phase %0d rec %05x size %04x playing %0d", clk_cnt, mz2500.cmt.phase, mz2500.cmt.rec, mz2500.cmt.size, mz2500.cmt.playing);
   end
end

// +wrtrace=AAAA:BBBB: memory writes made with the PC in AAAA-BBBB (address, page, data)
reg [31:0] wr_lo = 0, wr_hi = 0; reg wrtrace = 0; reg [15:0] m1_pc = 0;
always @(posedge clk_sys) if (!mz2500.m1_n && !mz2500.mreq_n) m1_pc <= mz2500.cpu_a;
initial if ($value$plusargs("wrlo=%h", wr_lo) && $value$plusargs("wrhi=%h", wr_hi)) wrtrace = 1;
always @(posedge clk_sys) if (wrtrace && mz2500.mem_wr_end && m1_pc >= wr_lo[15:0] && m1_pc <= wr_hi[15:0])
   $display("[wr] %0d pc %04x a %04x page %02x off %04x d %02x", cpu_cyc, m1_pc, mz2500.cpu_a, mz2500.cur_page, mz2500.cur_off, mz2500.cpu_dout);

// +inttrace: print interrupt acknowledges and RETIs
reg inttrace = 0;
reg [47:0] cpu_cyc = 0;
initial inttrace = $test$plusargs("inttrace");
always @(posedge clk_sys) if (cpu_ce) cpu_cyc <= cpu_cyc + 1;
always @(posedge clk_sys) if (inttrace) begin
   if (mz2500.inta_end) $display("[int] %0d ack vec %02x mine %0d req %b insvc %b enb %b", cpu_cyc, mz2500.int_vector, mz2500.int_ack_mine,
                                  mz2500.intc.req, mz2500.intc.insvc, mz2500.intc.enb);
   if (mz2500.reti_stb) $display("[int] %0d reti insvc %b pc %04x", cpu_cyc, mz2500.intc.insvc, cpu_pc);
end

always @(posedge clk_sys) if (dbg_dump) begin
   $writememh("out/ram_dump.hex", sdram.mem);
   $display("[sim] PAGES %02x %02x %02x %02x %02x %02x %02x %02x  PC %04x", mz2500.page[0], mz2500.page[1], mz2500.page[2],
            mz2500.page[3], mz2500.page[4], mz2500.page[5], mz2500.page[6], mz2500.page[7], cpu_pc);
end

endmodule
