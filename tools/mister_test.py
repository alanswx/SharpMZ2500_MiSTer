#!/usr/bin/env python3
"""Drive the MZ-2500 core on a MiSTer: launch MGLs, type through a virtual keyboard, take screenshots.

Runs on the MiSTer (python3, no extra modules). The keyboard is a /dev/uinput device that MiSTer Main picks up like
a USB keyboard; MGL loading and screenshots go through /dev/MiSTer_cmd. Screenshots land in
/media/fat/screenshots/SharpMZ2500/.

  mister_test.py SCRIPT [SCRIPT...]     run step files (one step per line, '#' comments)
  mister_test.py -e 'load Ys III' -e 'wait 30' -e 'shot ys3'

Steps:
  load NAME          load /media/fat/_Computer/_SharpMZ2500/NAME.mgl (or a full .mgl/.rbf path; 'core': the newest
                     _Computer/SharpMZ2500_*.rbf with no image)
  wait SECONDS       sleep
  key KEY [HOLD]     press and release one key (names below; HOLD in seconds, default 0.08)
  combo K1+K2        hold K1 (e.g. LEFTSHIFT), tap K2
  type TEXT          type text; \\n = Enter. Upper case letters are sent as plain keys (the MZ is upper case)
  shot NAME          screenshot (MiSTer saves NAME.png under screenshots/<core>/)
  osd                F12 (open/close the OSD)
  cfg OPTION VALUE   set an OSD option in config/SharpMZ2500.CFG before a load (Main reads it when the core
                     starts): bootmode 2500|2000|80b, lines 400|200

Key names: A-Z, 0-9, ENTER, SPACE, ESC, BACKSPACE, TAB, UP, DOWN, LEFT, RIGHT, F1-F12, LEFTSHIFT, LEFTCTRL,
LEFTALT, MINUS, EQUAL, COMMA, DOT, SLASH, SEMICOLON, APOSTROPHE, KP0-KP9, KPENTER, HOME, END, INSERT, DELETE,
PAGEUP, PAGEDOWN.
"""
import fcntl, glob, os, struct, sys, time

KEYS = {
    'ESC': 1, 'MINUS': 12, 'EQUAL': 13, 'BACKSPACE': 14, 'TAB': 15, 'ENTER': 28, 'LEFTCTRL': 29,
    'SEMICOLON': 39, 'APOSTROPHE': 40, 'GRAVE': 41, 'LEFTSHIFT': 42, 'BACKSLASH': 43, 'COMMA': 51, 'DOT': 52,
    'SLASH': 53, 'RIGHTSHIFT': 54, 'KPASTERISK': 55, 'LEFTALT': 56, 'SPACE': 57, 'CAPSLOCK': 58,
    'F1': 59, 'F2': 60, 'F3': 61, 'F4': 62, 'F5': 63, 'F6': 64, 'F7': 65, 'F8': 66, 'F9': 67, 'F10': 68,
    'KP7': 71, 'KP8': 72, 'KP9': 73, 'KPMINUS': 74, 'KP4': 75, 'KP5': 76, 'KP6': 77, 'KPPLUS': 78,
    'KP1': 79, 'KP2': 80, 'KP3': 81, 'KP0': 82, 'KPDOT': 83, 'F11': 87, 'F12': 88, 'KPENTER': 96,
    'RIGHTCTRL': 97, 'RIGHTALT': 100, 'HOME': 102, 'UP': 103, 'PAGEUP': 104, 'LEFT': 105, 'RIGHT': 106,
    'END': 107, 'DOWN': 108, 'PAGEDOWN': 109, 'INSERT': 110, 'DELETE': 111, 'LEFTBRACE': 26, 'RIGHTBRACE': 27,
}
for i, c in enumerate('1234567890'):
    KEYS[c] = 2 + i
for row, start in (('QWERTYUIOP', 16), ('ASDFGHJKL', 30), ('ZXCVBNM', 44)):
    for i, c in enumerate(row):
        KEYS[c] = start + i
# characters that need shift on a US keyboard (MiSTer Main sends US PS/2 codes; the core maps them)
SHIFTED = {'"': '2', '!': '1', '#': '3', '$': '4', '%': '5', '&': '7', '(': '9', ')': '0', '*': '8', '+': 'EQUAL',
           ':': 'SEMICOLON', '<': 'COMMA', '>': 'DOT', '?': 'SLASH', '_': 'MINUS', '@': '2'}
PLAIN = {' ': 'SPACE', '\n': 'ENTER', '-': 'MINUS', '=': 'EQUAL', ',': 'COMMA', '.': 'DOT', '/': 'SLASH',
         ';': 'SEMICOLON', "'": 'APOSTROPHE'}

EV_SYN, EV_KEY = 0, 1
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
MGL_DIR = '/media/fat/_Computer/_SharpMZ2500'
CFG = '/media/fat/config/SharpMZ2500.CFG'
# OSD options as status bits (CONF_STR in SharpMZ2500.sv): name -> (low bit, width, {value: field})
OPTIONS = {'bootmode': (2, 2, {'2500': 0, '2000': 1, '80b': 2}), 'lines': (1, 1, {'400': 0, '200': 1})}


def set_option(name, value):
    lo, width, values = OPTIONS[name]
    try:
        st = bytearray(open(CFG, 'rb').read()[:16].ljust(16, b'\0'))
    except OSError:
        st = bytearray(16)
    v = int.from_bytes(st, 'little')
    mask = ((1 << width) - 1) << lo
    v = (v & ~mask & ~1) | (values[value.lower()] << lo)          # bit 0 (reset) cleared
    open(CFG, 'wb').write(v.to_bytes(16, 'little'))


class Keyboard:
    def __init__(self):
        self.fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_SYN)
        for code in range(1, 256):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        # struct uinput_user_dev: name[80], input_id (bustype, vendor, product, version), ff_effects_max, abs[4][64]
        dev = struct.pack('80sHHHHi', b'mister_test keyboard', 0x03, 0x1209, 0x2500, 1, 0) + b'\0' * (4 * 64 * 4)
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(2.0)   # let Main find the new device

    def _ev(self, typ, code, val):
        t = time.time()
        os.write(self.fd, struct.pack('llHHi', int(t), int((t % 1) * 1e6), typ, code, val))

    def set(self, code, down):
        self._ev(EV_KEY, code, 1 if down else 0)
        self._ev(EV_SYN, 0, 0)

    def tap(self, name, hold=0.08):
        code = KEYS[name.upper()]
        self.set(code, True); time.sleep(hold); self.set(code, False); time.sleep(0.08)

    def combo(self, mod, name, hold=0.08):
        self.set(KEYS[mod.upper()], True); time.sleep(0.05)
        self.tap(name, hold)
        self.set(KEYS[mod.upper()], False); time.sleep(0.08)

    def type(self, text):
        for ch in text:
            if ch.upper() in KEYS and len(ch) == 1 and ch.isalnum():
                self.tap(ch.upper())
            elif ch in PLAIN:
                self.tap(PLAIN[ch])
            elif ch in SHIFTED:
                self.combo('LEFTSHIFT', SHIFTED[ch])
            else:
                print('  (no key for %r)' % ch)

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def cmd(line):
    with open('/dev/MiSTer_cmd', 'w') as f:
        f.write(line + '\n')


def run(steps, kb):
    for raw in steps:
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        op, _, arg = line.partition(' ')
        op = op.lower()
        print('[%s] %s' % (time.strftime('%H:%M:%S'), line), flush=True)
        if op == 'load':
            if arg == 'core':      # the newest _Computer/SharpMZ2500_*.rbf
                path = sorted(glob.glob('/media/fat/_Computer/SharpMZ2500_*.rbf'))[-1]
            else:
                path = arg if arg.startswith('/') else os.path.join(MGL_DIR, arg + ('' if arg.endswith('.mgl') else '.mgl'))
            if not os.path.exists(path):
                sys.exit('no such MGL: ' + path)
            cmd('load_core ' + path)
        elif op == 'wait':
            time.sleep(float(arg))
        elif op == 'key':
            parts = arg.split()
            kb.tap(parts[0], float(parts[1]) if len(parts) > 1 else 0.08)
        elif op == 'combo':
            mod, key = arg.split('+')
            kb.combo(mod, key)
        elif op == 'type':
            kb.type(arg.encode().decode('unicode_escape'))
        elif op == 'shot':
            cmd('screenshot ' + arg)
            time.sleep(1.5)
        elif op == 'cfg':
            name, value = arg.split()
            set_option(name.lower(), value)
        elif op == 'osd':
            kb.tap('F12')
        else:
            sys.exit('unknown step: ' + line)


def main():
    args = sys.argv[1:]
    steps = []
    while args:
        a = args.pop(0)
        if a == '-e':
            steps.append(args.pop(0))
        else:
            steps.extend(open(a).read().splitlines())
    kb = Keyboard()
    try:
        run(steps, kb)
    finally:
        kb.close()


if __name__ == '__main__':
    main()
