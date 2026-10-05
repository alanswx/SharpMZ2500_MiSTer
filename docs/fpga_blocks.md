# FPGA building blocks

Existing HDL the core can vendor, with licences. The core is GPL-3.0 (LICENSE); everything below is GPL-2.0+/GPL-3.0/LGPL compatible except
where flagged.

| Block | Implementation | Licence | Where | Notes |
|---|---|---|---|---|
| YM2203 (OPN) | jotego **jt03** in jt12 | GPL-3.0 | https://github.com/jotego/jt12 (shallow clone `refs/fpga/jt12`, dc9be7c, 2026-09-01; submodule jt49 7f6abfd, 2025-02-01). Local integration: `~/dev2/FM-7_MiSTer/rtl/jt12/` | FM-7 copy: `jt03.v` identical to current; `jt12_top.v`/`jt12_mmr.v` older (no `FULLFM` parameter, has `flag_mask`); its `jt49/` has `jt49_dcrm*.v`/`jt49_dly.v` that the current jt49 dropped. FM-7_MiSTer files.qip lists the needed files and `AUDIOMIX.v` shows mixing. jt03 ports: `clk, cen, din, addr, cs_n, wr_n, dout, irq_n, IOA_in/out/oe, IOB_in/out/oe, psg_A/B/C, fm_snd, psg_snd, snd, snd_sample`. Feed cen so the chip sees φM = 2 MHz (jt03 divides internally like the real chip) |
| SSG part | jotego jt49 (submodule of jt12) | GPL-3.0 | https://github.com/jotego/jt49 | used by jt03 |
| RP5C15 RTC | X68000_MiSTer `rtl/rtc/rp5c15.vhd` + `rtcbody.vhd` (by Puu-san, X68000 core) | **no licence header, repo has no LICENSE file**: ask before vendoring | https://github.com/MiSTer-devel/X68000_MiSTer/tree/master/rtl/rtc, copied to `refs/fpga/rtc/x68000_*.vhd` | Already the RP5C15, 4-bit bus, `RTCIN[64:0]` = MiSTer hps_io RTC, `alarm`, `clkout` (the 1/16 Hz pulse for OPN port B bit 3). Closest fit |
| RP5C01 RTC | MSX_MiSTer `rtl/peripheral/rtc.vhd` (Takayuki Hara, 2008, from OCM/ESE MSX) | BSD-style, **non-commercial clause** ("may not be sold") | https://github.com/MiSTer-devel/MSX_MiSTer, `refs/fpga/rtc/msx_rtc.vhd` | RP5C01 is register-compatible with the RP5C15 for time/alarm; avoid because of the licence clause |
| RP5C15 RTC | Suska `wf5c15-139xip` (Wolfgang Foerster, Inventronik) | LGPL-2.1+ | local `~/dev2/Sun-2_FPGA/Inputs/Suska_Configware/RTC5C15-139x/` | Atari Suska RTC; VHDL; would need MiSTer RTC seeding added |
| SDRAM controller | sorgelig `sdram.sv` (MiSTer standard, 2015-2019) | GPL-3.0+ | local `~/dev2/FM-7_MiSTer/rtl/sdram.sv`, `~/dev2/ColecoAdam_MiSTer/rtl/sdram.sv`; MSX1_MiSTer `rtl/sdram.sv`; MiSTer Template | 2-3 ports, 16-bit, fine for a 6 MHz Z80 + kanji prefetch. FM-7_MiSTer adds `SDRAM_MUX.v` and moved its kanji ROM to SDRAM (same problem as here) |
| FDC (MB8876) | sorgelig `wd1793.sv` (Viacheslav Slavinsky 2007-2008, Sorgelig 2016), D88 support from FM-7_MiSTer | GPL-2.0+ | local `~/dev2/SharpMZ_MiSTer/rtl/wd1793.sv` (+ `wd1793_mem.v`), `~/dev2/FM-7_MiSTer/rtl/wd1793.sv` (+ `wd1793_dpram.v`); MSX1_MiSTer `rtl/cart/wd1793.sv` | MB8876 = WD1793-compatible with inverted data bus: invert D on the CPU side. Add 80-cylinder 2DD, 4 drives, DE density |
| Z80 | T80 (Daniel Wallner et al.) | BSD-style (T80 licence) | `~/dev2/SharpMZ_MiSTer/rtl/T80` and every MiSTer Z80 core | WAIT_n for the wait states, IM 2 |
| i8255 / i8253 | SharpMZ_MiSTer `rtl/i8255`, `rtl/i8254` | GPL-3.0 (SharpMZ) | local | |
| Z80 PIO | NibblesLab `z8420.vhd` (2005-2014) | check header (NibblesLab, free use) | `~/dev2/SharpMZ_MiSTer/rtl/z8420/`, also NibblesLab/mz80b_de0 | needs the IM 2 daisy-chain (IEI/IEO) to sit above the SIO and the custom interrupt block |
| Z80 SIO | none found as reusable MiSTer HDL (GitHub code search for z80sio/z8440 HDL: nothing usable) | | | only channel B receive + DTR are needed for the mouse (CSP model); write a minimal one |
| Data recorder | SharpMZ_MiSTer `rtl/cmt.vhd`, `rtl/tape_image.sv` | GPL-3.0 | local | MZ-80B/2000 signalling and APSS |
| MiSTer framework | Template_MiSTer `sys/` | GPL-2.0/3.0 | https://github.com/MiSTer-devel/Template_MiSTer | hps_io RTC output feeds the RP5C15 |

Not found anywhere: an existing MZ-2500 FPGA core or video controller. NibblesLab has only `mz80b_de0`/`mz80c_de0`; the eaw.app v2.0 SharpMZ
emulator lists the MZ-2500 as planned only.
