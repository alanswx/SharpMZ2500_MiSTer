// Headless MZ-2500 simulation: run frames, type keys, capture PNG screenshots and frame hashes.
//
// Same organisation and option names as SharpMZ_MiSTer's verilator/sim_headless.cpp, so the regression
// scripts and habits carry over. Examples:
//
//   ./obj_dir_headless/Vtop --stop-at-frame 60 --screenshot 60
//   ./obj_dir_headless/Vtop --lines 200 --stop-at-frame 30 --frame-log out/frames.csv --trace-io out/io.csv
//   ./obj_dir_headless/Vtop --type '100:LOAD\n' --stop-at-frame 400 --dump-every 50
//
// A frame ends when vertical blanking starts; frame 0 is the first one after reset. Each PNG is the active
// (unblanked) picture as the core outputs it: 640x400 in 400-line mode, 640x200 in 200-line mode.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <map>
#include <deque>
#include <cstring>
#include <algorithm>
#include <sys/stat.h>

#include "Vtop.h"
#include "verilated.h"
#include "verilated_save.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include "ps2_keys.h"

#ifdef MZ_FAST_SIM
static const double CLK_HZ = 42954545.0;   // clk_sys at half rate ('make fast')
#else
static const double CLK_HZ = 85909091.0;   // clk_sys (24 x 3.579545 MHz)
#endif

struct TypeCmd { uint32_t frame; std::string text; };

struct Options {
    bool        lines400 = true;          // --lines 400|200 (front-panel switch)
    uint32_t    stop_frame = 60;
    bool        quiet = false;
    std::set<uint32_t> screenshots;       // --screenshot N
    std::string ipl2520_file;
    bool        mz2520 = false;          // --mz2520: MZ-2520 model (its IPL from boot.rom 008000 / --ipl2520)
    bool        kbd_us = false;          // --kbd-us: US symbol keyboard layout (OSD option)
    bool        dump_range = false;
    uint32_t    dump_from = 0, dump_to = 0;
    uint32_t    dump_every = 0;
    std::string out_dir = "out";
    std::string frame_log;
    std::vector<TypeCmd> types;
    uint32_t    type_press = 3, type_release = 3;
    std::string trace_file;               // --trace-cpu
    std::string io_file;                  // --trace-io
    uint32_t    trace_from = 0, trace_to = 0xFFFFFFFF;
    std::string rom_file;                 // --rom: boot.rom image (IPL at 0, kanji at 0x10000)
    std::string ipl_file, kanji_file;     // --ipl / --kanji: separate ROM files
    std::string fdd[2];                   // --fdd / --fdd-b: D88 images in drives 1 and 2
    bool        fdd_readonly = false;     // --fdd-readonly: never write back to the image files
    std::string wav_file;                 // --wav: audio output, 48 kHz 16-bit stereo
    std::string tape_file;                // --tape: MZT image (ioctl index 1)
    int         boot_mode = 0;            // --boot-mode 2500|2000|80b
    uint32_t    save_frame = 0;           // --save-state FRAME:FILE
    std::string save_file;
    std::string load_file;                // --load-state FILE
    uint64_t    dump_cycle = 0;           // --dump-at-cpu-cycle N: RAM dump + MMU pages (sim.v)
    struct MouseEv { uint32_t frame; int dx, dy, buttons; };
    std::vector<MouseEv> mouse;           // --mouse FRAME:DX:DY:BUTTONS
};

static void usage()
{
    fprintf(stderr,
"usage: Vtop [options]\n"
"  --lines 400|200        front-panel display switch (default 400: 24.86 kHz; 200: 15.98 kHz)\n"
"  --stop-at-frame N      exit after frame N (default 60)\n"
"  --quiet                no progress on stderr\n"
"  --kbd-us               keyboard: US symbol layout (the OSD option)\n"
"  --mz2520               MZ-2520 model: IPL from the boot.rom 2520 slot (or --ipl2520 FILE)\n"
"  --type FRAME:TEXT      type TEXT from FRAME; \\n or {RETURN}, {BREAK}, {DEL}, {WAITn} ...\n"
"  --type-rate P:R        frames per key press:release (default 3:3)\n"
"  --screenshot N         PNG of frame N (repeatable)\n"
"  --dump-frames A:B      PNG of every frame A..B\n"
"  --dump-every K         PNG of every Kth frame\n"
"  --out DIR              output directory (default ./out)\n"
"  --frame-log FILE       frame,fb_hash,cpu_cycles,pc per frame\n"
"  --trace-cpu FILE       PC of each instruction fetch (M1)\n"
"  --trace-io FILE        each I/O write: frame,pc,port,data\n"
"  --trace-from N         start tracing at frame N; --trace-to N stops after frame N\n"
"  --rom FILE             boot.rom image: IPL at 000000, kanji ROM at 010000 (tools/make_bootrom.sh)\n"
"  --fdd FILE             D88 image in drive 1; --fdd-b FILE: drive 2; --fdd-readonly: don't write to them\n"
"  --save-state N:FILE    save the machine state at the start of frame N; --load-state FILE resumes from it\n"
"                         (give the same --fdd/--fdd-b images; frame numbers continue)\n"
"  --dump-at-cpu-cycle N  write main RAM (SDRAM model) to out/ram_dump.hex and print the MMU pages at CPU cycle N\n"
"  --mouse F:DX:DY:B      PS/2 mouse packet at frame F (DX right, DY up, B: 1 left, 2 right), repeatable\n"
"  --tape FILE            MZT tape image in the data recorder (loaded through ioctl index 1)\n"
"  --boot-mode M          front-panel boot switch: 2500 (default), 2000 or 80b\n"
"  --wav FILE             record the audio output (48 kHz, 16-bit stereo WAV)\n"
"  --ipl FILE, --kanji FILE   load IPL.ROM / KANJI.ROM separately (default: ../software/roms/extracted/...)\n"
"fb_hash is FNV-1a 32 over the RGB888 bytes of the active picture.\n");
}

static uint32_t parse_num(const std::string &s) { return (uint32_t)std::stoul(s, nullptr, 0); }

static bool parse_args(int argc, char **argv, Options &o)
{
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) { fprintf(stderr, "%s needs an argument\n", a.c_str()); exit(2); }
            return argv[++i];
        };
        if (a == "--help" || a == "-h") { usage(); exit(0); }
        else if (a == "--headless") {}
        else if (a == "--lines") o.lines400 = next() != "200";
        else if (a == "--stop-at-frame") o.stop_frame = parse_num(next());
        else if (a == "--quiet") o.quiet = true;
        else if (a == "--kbd-us") o.kbd_us = true;
        else if (a == "--mz2520") o.mz2520 = true;
        else if (a == "--ipl2520") o.ipl2520_file = next();
        else if (a == "--type") {
            std::string s = next();
            size_t c = s.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--type wants FRAME:TEXT\n"); return false; }
            o.types.push_back({parse_num(s.substr(0, c)), s.substr(c + 1)});
        }
        else if (a == "--type-rate") {
            std::string s = next();
            size_t c = s.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--type-rate wants P:R\n"); return false; }
            o.type_press = parse_num(s.substr(0, c)); o.type_release = parse_num(s.substr(c + 1));
        }
        else if (a == "--screenshot") o.screenshots.insert(parse_num(next()));
        else if (a == "--dump-frames") {
            std::string s = next();
            size_t c = s.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--dump-frames wants A:B\n"); return false; }
            o.dump_range = true; o.dump_from = parse_num(s.substr(0, c)); o.dump_to = parse_num(s.substr(c + 1));
        }
        else if (a == "--dump-every") o.dump_every = parse_num(next());
        else if (a == "--out") o.out_dir = next();
        else if (a == "--frame-log") o.frame_log = next();
        else if (a == "--trace-cpu") o.trace_file = next();
        else if (a == "--trace-io") o.io_file = next();
        else if (a == "--trace-from") o.trace_from = parse_num(next());
        else if (a == "--trace-to") o.trace_to = parse_num(next());
        else if (a == "--rom") o.rom_file = next();
        else if (a == "--fdd") o.fdd[0] = next();
        else if (a == "--fdd-b") o.fdd[1] = next();
        else if (a == "--fdd-readonly") o.fdd_readonly = true;
        else if (a == "--wav") o.wav_file = next();
        else if (a == "--tape") o.tape_file = next();
        else if (a == "--boot-mode") { std::string m = next(); o.boot_mode = (m == "2000") ? 1 : (m == "80b" || m == "80B") ? 2 : 0; }
        else if (a == "--save-state") {
            std::string v = next();
            size_t c = v.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--save-state wants FRAME:FILE\n"); return false; }
            o.save_frame = parse_num(v.substr(0, c)); o.save_file = v.substr(c + 1);
        }
        else if (a == "--load-state") o.load_file = next();
        else if (a == "--mouse") {
            Options::MouseEv m{};
            if (sscanf(next().c_str(), "%u:%d:%d:%d", &m.frame, &m.dx, &m.dy, &m.buttons) != 4) {
                fprintf(stderr, "--mouse wants FRAME:DX:DY:BUTTONS\n"); return false;
            }
            o.mouse.push_back(m);
        }
        else if (a == "--dump-at-cpu-cycle") o.dump_cycle = std::stoull(next(), nullptr, 0);
        else if (a == "--ipl") o.ipl_file = next();
        else if (a == "--kanji") o.kanji_file = next();
        else if (a[0] == '+') {}   // Verilator plusargs (+notext, +nogfx)
        else { fprintf(stderr, "unknown option %s (try --help)\n", a.c_str()); return false; }
    }
    return true;
}

struct Ps2Event { uint8_t code; bool ext; bool press; };

class Sim {
public:
    explicit Sim(const Options &o) : opt(o) { top = new Vtop; }
    ~Sim() { top->final(); delete top; }
    int run();

private:
    const Options &opt;
    Vtop     *top;
    uint64_t  cycle = 0, cpu_cycles = 0;
    uint32_t  frame = 0;
    int       exit_code = 0;
    bool      started = false;            // frames are counted from the first full one after reset

    std::vector<uint8_t> fb, line;
    int       fb_w = 0, fb_h = 0;
    bool      prev_hb = false, prev_vb = false;

    FILE     *flog = nullptr, *ftrace = nullptr, *fio = nullptr;
    bool      prev_m1 = true, prev_io_wr = false;

    std::multimap<uint32_t, Ps2Event> ps2_schedule;
    std::deque<Ps2Event> ps2_queue;
    uint64_t  ps2_next_ok = 0;
    bool      ps2_toggle = false;

    void clock();
    void end_frame();
    bool tracing() const { return frame >= opt.trace_from && frame <= opt.trace_to; }
    bool want_png(uint32_t f) const;
    void write_png(uint32_t f);
    void schedule_typing();
    bool load_roms();

    // hps_io sd_* block interface for the floppy slots: 512-byte blocks, one byte per clock
    FILE     *fdd[2] = {nullptr, nullptr};
    uint64_t  fdd_size[2] = {0, 0};
    enum { SD_IDLE, SD_READ, SD_READ_END, SD_WRITE } sd_state = SD_IDLE;
    int       sd_slot = 0, sd_idx = 0;
    uint32_t  sd_lba = 0;
    uint8_t   sd_data[512];
    void      sd_step();
    bool      mount_fdd(int k);

    FILE     *fwav = nullptr;
    uint32_t  wav_samples = 0;
    double    wav_next = 0;
    void      wav_close();

    // Harness state saved next to the model (--save-state / --load-state)
    struct HState {
        uint64_t cycle, cpu_cycles, ps2_next_ok;
        uint32_t frame;
        uint8_t  prev_hb, prev_vb, prev_m1, prev_io_wr, ps2_toggle;
        int32_t  fb_w;
        uint64_t fdd_size[2];
    };
    void      save_state();
    bool      load_state();
    bool      open_fdd(int k);
    bool      opt_save_pending = false;
    bool      dump_done = false;
    bool      mouse_tog = false;
    int       finish();
    void ioctl_load(uint32_t base, const std::vector<uint8_t> &data, int index = 0);
};

void Sim::sd_step()
{
    auto req_rd = [&](int k) -> bool { return (top->fdd_rd >> k) & 1; };
    auto req_wr = [&](int k) -> bool { return (top->fdd_wr >> k) & 1; };
    auto ack    = [&](int k, int v) { top->fdd_ack = v ? (1 << k) : 0; };

    top->sd_buff_wr = 0;
    switch (sd_state) {
    case SD_IDLE:
        for (int k = 0; k < 2; k++) {
            if (!fdd[k] || !(req_rd(k) || req_wr(k))) continue;
            sd_slot = k;
            sd_lba = k ? top->fdd_lba1 : top->fdd_lba0;
            sd_idx = 0;
            ack(k, 1);
            if (req_rd(k)) {
                memset(sd_data, 0, sizeof(sd_data));
                uint64_t off = (uint64_t)sd_lba * 512;
                if (off < fdd_size[k]) {
                    fseeko(fdd[k], (off_t)off, SEEK_SET);
                    size_t n = fread(sd_data, 1, (size_t)std::min<uint64_t>(512, fdd_size[k] - off), fdd[k]);
                    (void)n;
                }
                sd_state = SD_READ;
            }
            else sd_state = SD_WRITE;
            break;
        }
        break;
    case SD_READ:
        top->sd_buff_addr = sd_idx;
        top->sd_buff_dout = sd_data[sd_idx];
        top->sd_buff_wr = 1;
        if (++sd_idx == 512) sd_state = SD_READ_END;
        break;
    case SD_READ_END:
        ack(sd_slot, 0);
        sd_state = SD_IDLE;
        break;
    case SD_WRITE:
        // sd_buff_din is registered: it holds the byte addressed on the previous clock.
        if (sd_idx > 0) sd_data[sd_idx - 1] = sd_slot ? top->fdd_buff_din1 : top->fdd_buff_din0;
        if (sd_idx < 512) top->sd_buff_addr = sd_idx++;
        else {
            uint64_t off = (uint64_t)sd_lba * 512;
            if (!opt.fdd_readonly && off < fdd_size[sd_slot]) {
                fseeko(fdd[sd_slot], (off_t)off, SEEK_SET);
                fwrite(sd_data, 1, (size_t)std::min<uint64_t>(512, fdd_size[sd_slot] - off), fdd[sd_slot]);
                fflush(fdd[sd_slot]);
            }
            ack(sd_slot, 0);
            sd_state = SD_IDLE;
        }
        break;
    }
}

bool Sim::open_fdd(int k)
{
    fdd[k] = fopen(opt.fdd[k].c_str(), opt.fdd_readonly ? "rb" : "r+b");
    if (!fdd[k]) { fprintf(stderr, "cannot open disk image %s\n", opt.fdd[k].c_str()); return false; }
    fseeko(fdd[k], 0, SEEK_END);
    fdd_size[k] = (uint64_t)ftello(fdd[k]);
    return true;
}

void Sim::save_state()
{
    if (sd_state != SD_IDLE) { opt_save_pending = true; return; }   // not in the middle of a block transfer
    VerilatedSave os;
    os.open(opt.save_file.c_str());
    os << *top;
    HState h = {cycle, cpu_cycles, ps2_next_ok, frame, prev_hb, prev_vb, prev_m1, prev_io_wr, ps2_toggle, fb_w,
                {fdd_size[0], fdd_size[1]}};
    os.write(&h, sizeof(h));
    os.close();
    if (!opt.quiet) fprintf(stderr, "[sim] state saved at frame %u to %s\n", frame, opt.save_file.c_str());
}

bool Sim::load_state()
{
    VerilatedRestore is;
    is.open(opt.load_file.c_str());
    if (!is.isOpen()) { fprintf(stderr, "cannot read %s\n", opt.load_file.c_str()); return false; }
    is >> *top;
    HState h;
    is.read(&h, sizeof(h));
    is.close();
    cycle = h.cycle; cpu_cycles = h.cpu_cycles; ps2_next_ok = h.ps2_next_ok; frame = h.frame;
    prev_hb = h.prev_hb; prev_vb = h.prev_vb; prev_m1 = h.prev_m1; prev_io_wr = h.prev_io_wr;
    ps2_toggle = h.ps2_toggle; fb_w = h.fb_w;
    for (int k = 0; k < 2; k++) {
        if (opt.fdd[k].empty()) continue;
        if (!open_fdd(k)) return false;
        if (fdd_size[k] != h.fdd_size[k]) fprintf(stderr, "warning: drive %d image size differs from the saved state\n", k + 1);
    }
    if (!opt.quiet) fprintf(stderr, "[sim] state loaded from %s, frame %u\n", opt.load_file.c_str(), frame);
    return true;
}

// As hps_io: img_size on a shared bus, one img_mounted strobe per slot.
bool Sim::mount_fdd(int k)
{
    if (!open_fdd(k)) return false;
    top->img_size = fdd_size[k];
    top->img_readonly = opt.fdd_readonly;
    top->img_mounted = 1 << k;
    clock();
    top->img_mounted = 0;
    for (int i = 0; i < 4; i++) clock();
    if (!opt.quiet) fprintf(stderr, "[sim] drive %d: '%s', %llu bytes\n", k + 1, opt.fdd[k].c_str(), (unsigned long long)fdd_size[k]);
    return true;
}

static void wav_header(FILE *f, uint32_t samples)
{
    uint32_t data = samples * 4, riff = 36 + data, fmt_len = 16, rate = 48000, brate = 48000 * 4;
    uint16_t pcm = 1, ch = 2, align = 4, bits = 16;
    fseek(f, 0, SEEK_SET);
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmt_len, 4, 1, f); fwrite(&pcm, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f);
    fwrite(&brate, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
}

void Sim::wav_close()
{
    if (!fwav) return;
    wav_header(fwav, wav_samples);
    fclose(fwav);
    fwav = nullptr;
}

static bool read_file(const std::string &name, std::vector<uint8_t> &out)
{
    FILE *f = fopen(name.c_str(), "rb");
    if (!f) return false;
    uint8_t buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) out.insert(out.end(), buf, buf + n);
    fclose(f);
    return true;
}

// hps_io style download: one byte every 4 clocks, machine held in reset by ioctl_download.
void Sim::ioctl_load(uint32_t base, const std::vector<uint8_t> &data, int index)
{
    top->ioctl_index = index;
    top->ioctl_download = 1;
    for (size_t i = 0; i < data.size(); i++) {
        top->ioctl_addr = base + (uint32_t)i;
        top->ioctl_dout = data[i];
        top->ioctl_wr = 1;
        clock();
        top->ioctl_wr = 0;
        clock(); clock(); clock();
        while (top->ioctl_wait) clock();
    }
    top->ioctl_download = 0;
}

bool Sim::load_roms()
{
    std::vector<uint8_t> d;
    if (!opt.rom_file.empty()) {
        if (!read_file(opt.rom_file, d)) { fprintf(stderr, "cannot read %s\n", opt.rom_file.c_str()); return false; }
        if (d.size() > 0x50000) d.resize(0x50000);
        ioctl_load(0, d);
        return true;
    }
    std::string ipl = opt.ipl_file.empty() ? "../software/roms/extracted/IPL/IPL.ROM" : opt.ipl_file;
    std::string kanji = opt.kanji_file.empty() ? "../software/roms/extracted/KANJI/KANJI.ROM" : opt.kanji_file;
    if (!read_file(ipl, d)) { fprintf(stderr, "cannot read IPL ROM %s (see docs/roms.md)\n", ipl.c_str()); return false; }
    d.resize(0x8000, 0xFF);
    ioctl_load(0, d);
    d.clear();
    std::string ipl2520 = opt.ipl2520_file.empty() ? "../software/roms/extracted/MZ-2520_IPL/IPL.ROM" : opt.ipl2520_file;
    if (read_file(ipl2520, d)) { d.resize(0x8000, 0xFF); ioctl_load(0x8000, d); }
    else if (opt.mz2520) fprintf(stderr, "warning: no MZ-2520 IPL %s\n", ipl2520.c_str());
    d.clear();
    if (!read_file(kanji, d)) fprintf(stderr, "warning: no kanji ROM %s: no text font\n", kanji.c_str());
    else { d.resize(0x40000, 0xFF); ioctl_load(0x10000, d); }
    return true;
}

void Sim::clock()
{
    // Sample what the video pipeline sees at this rising edge: MiSTer's video_mixer latches RGB on the
    // clk_sys edge where CE_PIXEL is high.
    top->clk_sys = 0;
    top->eval();
    if (top->ce_pix) {
        bool hb = top->VGA_HB, vb = top->VGA_VB;
        if (!hb && !vb) {
            line.push_back(top->VGA_R);
            line.push_back(top->VGA_G);
            line.push_back(top->VGA_B);
        }
        if (hb && !prev_hb && !line.empty()) {
            int w = (int)line.size() / 3;
            if (fb_h == 0) fb_w = w;
            line.resize((size_t)fb_w * 3, 0);
            fb.insert(fb.end(), line.begin(), line.end());
            fb_h++;
            line.clear();
        }
        prev_hb = hb;
        if (vb && !prev_vb) end_frame();
        prev_vb = vb;
    }

    top->clk_sys = 1;
    top->eval();
    cycle++;

    if (top->cpu_ce) cpu_cycles++;
    top->dbg_dump = 0;
    if (opt.dump_cycle && cpu_cycles >= opt.dump_cycle && !dump_done) { top->dbg_dump = 1; dump_done = true; }
    sd_step();
    if (opt_save_pending && sd_state == SD_IDLE) { opt_save_pending = false; save_state(); }
    if (fwav && started && cycle >= wav_next) {
        int16_t lr[2] = {(int16_t)top->AUDIO_L, (int16_t)top->AUDIO_R};
        fwrite(lr, 2, 2, fwav);
        wav_samples++;
        wav_next += CLK_HZ / 48000.0;
    }
    if (ftrace && tracing()) {
        bool m1 = top->cpu_m1_n;
        if (!m1 && prev_m1) fprintf(ftrace, "%u,%llu,%04X\n", frame, (unsigned long long)cpu_cycles, top->cpu_pc);
        prev_m1 = m1;
    }
    if (fio && tracing()) {
        bool w = top->dbg_io_wr;
        if (w && !prev_io_wr) fprintf(fio, "%u,%04X,%02X,%02X\n", frame, top->cpu_pc, top->dbg_io_port, top->dbg_io_data);
        prev_io_wr = w;
    }

    // hps_io style ps2_key: bit 10 toggles per event, 9 = pressed, 8 = extended. One event per ~1 ms.
    if (!ps2_queue.empty() && cycle >= ps2_next_ok) {
        Ps2Event e = ps2_queue.front();
        ps2_queue.pop_front();
        ps2_toggle = !ps2_toggle;
        top->ps2_key = (uint16_t)((ps2_toggle << 10) | (e.press << 9) | (e.ext << 8) | e.code);
        ps2_next_ok = cycle + (uint64_t)(CLK_HZ / 1000);
    }
}

void Sim::end_frame()
{
    if (!started) { fb.clear(); fb_h = 0; line.clear(); return; }
    uint32_t h = 2166136261u;
    for (uint8_t b : fb) { h ^= b; h *= 16777619u; }
    if (flog) fprintf(flog, "%u,%08x,%llu,%04X\n", frame, h, (unsigned long long)cpu_cycles, top->cpu_pc);
    if (want_png(frame)) write_png(frame);
    if (!opt.quiet && frame % 10 == 0)
        fprintf(stderr, "[sim] frame %u  %.3fs emulated  %dx%d  pc %04X  hash %08x\n",
                frame, cycle / CLK_HZ, fb_w, fb_h, top->cpu_pc, h);
    fb.clear(); fb_h = 0; line.clear();
    frame++;
    if (!opt.save_file.empty() && frame == opt.save_frame) save_state();
    for (auto &m : opt.mouse) if (m.frame == frame) {
        // hps_io ps2_mouse: [24] toggle, [23:16] Y, [15:8] X, [7:0] Yovf Xovf Ysign Xsign 1 M R L
        mouse_tog = !mouse_tog;
        int dx = std::max(-255, std::min(255, m.dx)), dy = std::max(-255, std::min(255, m.dy));
        uint32_t b0 = 0x08 | (m.buttons & 7) | ((dx < 0) << 4) | ((dy < 0) << 5);
        top->ps2_mouse = ((uint32_t)mouse_tog << 24) | ((uint32_t)(dy & 0xFF) << 16) | ((uint32_t)(dx & 0xFF) << 8) | b0;
    }
    auto range = ps2_schedule.equal_range(frame);
    for (auto it = range.first; it != range.second; ++it) ps2_queue.push_back(it->second);
}

bool Sim::want_png(uint32_t f) const
{
    if (opt.screenshots.count(f)) return true;
    if (opt.dump_range && f >= opt.dump_from && f <= opt.dump_to) return true;
    if (opt.dump_every && f % opt.dump_every == 0) return true;
    return false;
}

void Sim::write_png(uint32_t f)
{
    if (fb_w == 0 || fb_h == 0) return;
    char name[1024];
    snprintf(name, sizeof(name), "%s/frame_%06u.png", opt.out_dir.c_str(), f);
    if (!stbi_write_png(name, fb_w, fb_h, 3, fb.data(), fb_w * 3)) {
        fprintf(stderr, "cannot write %s\n", name);
        exit_code = 3;
    }
    else if (!opt.quiet) fprintf(stderr, "[sim] wrote %s (%dx%d)\n", name, fb_w, fb_h);
}

void Sim::schedule_typing()
{
    for (auto &t : opt.types) {
        uint32_t f = t.frame;
        const std::string &s = t.text;
        for (size_t i = 0; i < s.size(); i++) {
            Ps2Key k;
            bool ok = false;
            if (s[i] == '\\' && i + 1 < s.size()) {
                char c = s[++i];
                ok = ps2_from_ascii(c == 'n' || c == 'r' ? '\n' : c, k);
            } else if (s[i] == '{') {
                size_t e = s.find('}', i);
                std::string name = s.substr(i + 1, e - i - 1);
                i = e;
                if (name.rfind("WAIT", 0) == 0) { f += parse_num(name.substr(4)); continue; }
                ok = ps2_from_name(name, k);
                if (!ok) fprintf(stderr, "--type: unknown key {%s}\n", name.c_str());
            } else {
                ok = ps2_from_ascii(s[i], k);
                if (!ok) fprintf(stderr, "--type: no key for '%c'\n", s[i]);
            }
            if (!ok) continue;
            if (k.shift) ps2_schedule.insert({f, {PS2_LSHIFT, false, true}});
            ps2_schedule.insert({f, {k.code, k.extended, true}});
            ps2_schedule.insert({f + opt.type_press, {k.code, k.extended, false}});
            if (k.shift) ps2_schedule.insert({f + opt.type_press, {PS2_LSHIFT, false, false}});
            f += opt.type_press + opt.type_release;
        }
    }
}

int Sim::run()
{
    mkdir(opt.out_dir.c_str(), 0777);
    if (!opt.frame_log.empty()) {
        if (!(flog = fopen(opt.frame_log.c_str(), "w"))) { fprintf(stderr, "cannot write %s\n", opt.frame_log.c_str()); return 2; }
        fprintf(flog, "frame,fb_hash,cpu_cycles,pc\n");
    }
    if (!opt.trace_file.empty()) {
        if (!(ftrace = fopen(opt.trace_file.c_str(), "w"))) { fprintf(stderr, "cannot write %s\n", opt.trace_file.c_str()); return 2; }
        fprintf(ftrace, "frame,cpu_cycle,pc\n");
    }
    if (!opt.wav_file.empty()) {
        if (!(fwav = fopen(opt.wav_file.c_str(), "wb"))) { fprintf(stderr, "cannot write %s\n", opt.wav_file.c_str()); return 2; }
        wav_header(fwav, 0);
    }
    if (!opt.io_file.empty()) {
        if (!(fio = fopen(opt.io_file.c_str(), "w"))) { fprintf(stderr, "cannot write %s\n", opt.io_file.c_str()); return 2; }
        fprintf(fio, "frame,pc,port,data\n");
    }

    if (!opt.load_file.empty()) {
        if (!load_state()) return 2;
        started = true;
        wav_next = (double)cycle;
        schedule_typing();
        while (frame <= opt.stop_frame && !Verilated::gotFinish()) clock();
        return finish();
    }

    top->reset = 1;
    top->lines400 = opt.lines400;
    top->boot_mode = opt.boot_mode;
    top->ps2_key = 0;
    top->kbd_us = opt.kbd_us;
    top->model_2520 = opt.mz2520;
    top->ioctl_download = 0; top->ioctl_wr = 0;
    for (int i = 0; i < 256; i++) clock();
    // As on the MiSTer: Main holds the core in reset (status bit 0) while it sends boot.rom, then releases it.
    if (!load_roms()) return 2;
    for (int i = 0; i < 256; i++) clock();
    top->reset = 0;
    for (int k = 0; k < 2; k++)
        if (!opt.fdd[k].empty() && !mount_fdd(k)) return 2;
    if (!opt.tape_file.empty()) {
        std::vector<uint8_t> t;
        if (!read_file(opt.tape_file, t)) { fprintf(stderr, "cannot read %s\n", opt.tape_file.c_str()); return 2; }
        ioctl_load(0, t, 1);
        top->ioctl_index = 0;
        if (!opt.quiet) fprintf(stderr, "[sim] tape '%s', %zu bytes\n", opt.tape_file.c_str(), t.size());
    }
    // Discard the partial picture before the first full frame.
    while (!top->VGA_VB) clock();
    while (top->VGA_VB) clock();
    frame = 0; cpu_cycles = 0; fb.clear(); fb_h = 0; line.clear();
    started = true;
    wav_next = (double)cycle;

    schedule_typing();
    auto range = ps2_schedule.equal_range(0);
    for (auto it = range.first; it != range.second; ++it) ps2_queue.push_back(it->second);

    while (frame <= opt.stop_frame && !Verilated::gotFinish()) clock();
    return finish();
}

int Sim::finish()
{
    wav_close();
    if (flog) fclose(flog);
    if (ftrace) fclose(ftrace);
    if (fio) fclose(fio);
    if (!opt.quiet) fprintf(stderr, "[sim] done: %u frames, %llu clk_sys cycles, %llu CPU cycles\n",
                            frame, (unsigned long long)cycle, (unsigned long long)cpu_cycles);
    return exit_code;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Options opt;
    if (!parse_args(argc, argv, opt)) return 2;
    Sim sim(opt);
    return sim.run();
}
