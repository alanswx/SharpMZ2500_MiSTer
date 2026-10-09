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
  mouse DX DY        move the virtual mouse (relative, in steps of at most 10)
  click [left|right] [HOLD]  mouse button
  joy NAME [HOLD]    gamepad: up, down, left, right, a, b, x, y, start, select or a button code 0x1nn
                     (held HOLD seconds, default 0.3)
  cfg OPTION VALUE   set an OSD option in config/SharpMZ2500.CFG before a load (Main reads it when the core
                     starts): bootmode 2500|2000|80b, lines 400|200, keyboard jp|us,
                     model 2500|2520

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
# characters as typed on a US keyboard (Main sends US PS/2 codes; the core's Keyboard option decides what the MZ sees)
SHIFTED = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
           '_': 'MINUS', '+': 'EQUAL', '{': 'LEFTBRACE', '}': 'RIGHTBRACE', '|': 'BACKSLASH', ':': 'SEMICOLON',
           '"': 'APOSTROPHE', '~': 'GRAVE', '<': 'COMMA', '>': 'DOT', '?': 'SLASH'}
PLAIN = {' ': 'SPACE', '\n': 'ENTER', '-': 'MINUS', '=': 'EQUAL', ',': 'COMMA', '.': 'DOT', '/': 'SLASH',
         ';': 'SEMICOLON', "'": 'APOSTROPHE', '[': 'LEFTBRACE', ']': 'RIGHTBRACE', '`': 'GRAVE', '\\': 'BACKSLASH'}

EV_SYN, EV_KEY, EV_REL, EV_ABS = 0, 1, 2, 3
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
UI_SET_RELBIT, UI_SET_ABSBIT = 0x40045566, 0x40045567
BTN_LEFT, BTN_RIGHT = 0x110, 0x111
BTN_SOUTH, BTN_EAST, BTN_START, BTN_SELECT = 0x130, 0x131, 0x13B, 0x13A
ABS_X, ABS_Y = 0, 1
MGL_DIR = '/media/fat/_Computer/_SharpMZ2500'
CFG = '/media/fat/config/SharpMZ2500.CFG'
# OSD options as status bits (CONF_STR in SharpMZ2500.sv): name -> (low bit, width, {value: field})
OPTIONS = {'bootmode': (2, 2, {'2500': 0, '2000': 1, '80b': 2}), 'lines': (1, 1, {'400': 0, '200': 1}),
           'keyboard': (7, 1, {'jp': 0, 'us': 1}), 'model': (8, 1, {'2500': 0, '2520': 1})}


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


def uinput_device(name, product, keys=(), rels=(), abss=(), vendor=0x1209):
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    if keys:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        for code in keys:
            fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    if rels:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
        for code in rels:
            fcntl.ioctl(fd, UI_SET_RELBIT, code)
    absmax, absmin = [0] * 64, [0] * 64
    if abss:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
        for code in abss:
            fcntl.ioctl(fd, UI_SET_ABSBIT, code)
            absmin[code], absmax[code] = (-1, 1) if code in (16, 17) else (-32768, 32767)
    # struct uinput_user_dev: name[80], input_id (bustype, vendor, product, version), ff_effects_max, abs[4][64]
    dev = struct.pack('80sHHHHi', name.encode(), 0x03, vendor, product, 1, 0)
    dev += struct.pack('64i', *absmax) + struct.pack('64i', *absmin) + b'\0' * (2 * 64 * 4)
    os.write(fd, dev)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


class Device:
    def __init__(self, fd):
        self.fd = fd

    def ev(self, typ, code, val):
        t = time.time()
        os.write(self.fd, struct.pack('llHHi', int(t), int((t % 1) * 1e6), typ, code, val))

    def syn(self):
        self.ev(EV_SYN, 0, 0)

    def close(self):
        self.mouse.close()
        self.pad.close()
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


class Mouse(Device):
    def __init__(self):
        super().__init__(uinput_device('mister_test mouse', 0x2501, keys=(BTN_LEFT, BTN_RIGHT), rels=(0, 1)))

    def move(self, dx, dy):
        while dx or dy:
            sx = max(-10, min(10, dx)); sy = max(-10, min(10, dy))
            self.ev(EV_REL, 0, sx); self.ev(EV_REL, 1, sy); self.syn()
            dx -= sx; dy -= sy
            time.sleep(0.02)

    def click(self, button, hold):
        self.ev(EV_KEY, button, 1); self.syn(); time.sleep(hold)
        self.ev(EV_KEY, button, 0); self.syn(); time.sleep(0.1)


PAD_MAP = '/media/fat/config/inputs/SharpMZ2500_input_045e_028e_v3.map'
# MiSTer input map, v3 format: 32-bit codes; 0-3 right/left/down/up (D-pad), 4.. the core's buttons (J1 in CONF_STR:
# Trigger A = B / east, Trigger B = A / south), then menu buttons
PAD_MAP_DATA = struct.pack('<12I', 0x321, 0x320, 0x323, 0x322, 0x131, 0x130, 0x134, 0x133, 0x136, 0x137, 0x13a, 0x13b) + \
    b'\0' * (96 - 48) + struct.pack('<8I', 0x20000, 0x20001, 0x20003, 0x20004, 0x20000, 0x20001, 0, 0)


def ensure_pad_map():
    if not os.path.exists(PAD_MAP):
        os.makedirs(os.path.dirname(PAD_MAP), exist_ok=True)
        open(PAD_MAP, 'wb').write(PAD_MAP_DATA)


class Pad(Device):
    # Presents itself as an Xbox 360 pad (045e:028e, the xpad button and axis codes): MiSTer has a default map
    # for it, an unknown pad would first need mapping in the menu.
    def __init__(self):
        super().__init__(uinput_device('Microsoft X-Box 360 pad', 0x028e, vendor=0x045e,
                                       keys=(BTN_SOUTH, BTN_EAST, 0x133, 0x134, 0x136, 0x137, BTN_SELECT, BTN_START,
                                             0x13C, 0x13D, 0x13E),
                                       abss=(ABS_X, ABS_Y, 2, 3, 4, 5, 16, 17)))

    def press(self, name, hold):
        # the D-pad (hat axes, as xpad reports it)
        axis = {'left': (16, -1), 'right': (16, 1), 'up': (17, -1), 'down': (17, 1)}
        if name in axis:
            code, v = axis[name]
            self.ev(EV_ABS, code, v); self.syn(); time.sleep(hold)
            self.ev(EV_ABS, code, 0); self.syn()
        else:
            code = int(name, 0) if name.startswith('0x') else \
                {'a': BTN_SOUTH, 'b': BTN_EAST, 'x': 0x133, 'y': 0x134, 'start': BTN_START, 'select': BTN_SELECT}[name]
            self.ev(EV_KEY, code, 1); self.syn(); time.sleep(hold)
            self.ev(EV_KEY, code, 0); self.syn()
        time.sleep(0.1)


class Keyboard:
    def __init__(self):
        self.fd = uinput_device('mister_test keyboard', 0x2500, keys=range(1, 256))
        self.mouse = Mouse()
        ensure_pad_map()       # read by Main when the core loads
        self.pad = Pad()
        time.sleep(2.0)   # let Main find the new devices

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
        elif op == 'mouse':
            dx, dy = arg.split()
            kb.mouse.move(int(dx), int(dy))
        elif op == 'click':
            parts = arg.split()
            btn = BTN_RIGHT if parts and parts[0] == 'right' else BTN_LEFT
            kb.mouse.click(btn, float(parts[1]) if len(parts) > 1 else 0.1)
        elif op == 'joy':
            parts = arg.split()
            kb.pad.press(parts[0].lower(), float(parts[1]) if len(parts) > 1 else 0.3)
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
