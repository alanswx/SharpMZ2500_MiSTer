`timescale 1ns/1ns
//
// Simulation top for the MZ-2500 core: the machine (rtl/mz2500.sv) with its ports made visible to the C++
// harness (sim_headless.cpp). It stands in for SharpMZ2500.sv; the harness plays hps_io (ps2_key, later the
// ioctl ROM download and the sd_* floppy bus).
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

   output [15:0] cpu_pc /*verilator public_flat*/,
   output        cpu_ce /*verilator public_flat*/,
   output        cpu_m1_n /*verilator public_flat*/,
   output        dbg_io_wr /*verilator public_flat*/,
   output [7:0]  dbg_io_port /*verilator public_flat*/,
   output [7:0]  dbg_io_data /*verilator public_flat*/
);

mz2500 mz2500
(
   .clk_sys(clk_sys),
   .reset(reset),
   .lines400(lines400),
   .ps2_key(ps2_key),

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

endmodule
