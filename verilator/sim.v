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
   input         dbg_dump,       // one clock: write main RAM to out/ram_dump.hex and print the MMU pages

   input         ioctl_download,
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

wire [31:0] fdd_lba[2];
wire  [7:0] fdd_buff_din[2];
assign fdd_lba0 = fdd_lba[0];
assign fdd_lba1 = fdd_lba[1];
assign fdd_buff_din0 = fdd_buff_din[0];
assign fdd_buff_din1 = fdd_buff_din[1];

mz2500 mz2500
(
   .clk_sys(clk_sys),
   .reset(reset),
   .lines400(lines400),
   .ps2_key(ps2_key),

   .ioctl_download(ioctl_download),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
   .ioctl_wait(ioctl_wait),

   .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
   .sd_lba(fdd_lba), .sd_rd(fdd_rd), .sd_wr(fdd_wr), .sd_ack(fdd_ack),
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
