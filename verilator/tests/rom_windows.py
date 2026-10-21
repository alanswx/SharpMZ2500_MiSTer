#!/usr/bin/env python3
"""rom_windows test (run_tests.sh): the optional ROMs as the CPU sees them.

  tests/rom_windows.py image OUT.bin     write the RAM image (--ramimg, runs at 0000)
  tests/rom_windows.py check RAM_DUMP    compare what it stored at 8000h with the ROM files: prints 'match'

The program (MMU mode 0) maps dictionary bank 5 (CE) at E000 and copies 16 bytes to 8000, the phone ROM page 3C
(offset 100h) to 8010, reads the MZ-1R13 kanji ROM at word 1234h through B8/B9 twice (B9 steps the address) to
8020, then 4 bytes of phone page 3F (past the 16 KB dump: FFh) and of page 3B (nothing: FFh). Expected bytes come
from the ROM files in ../software/roms/extracted/ (docs/roms.md), so no ROM data is kept here.
"""
import sys

CODE = bytes.fromhex(''.join('''
    F3 3E00 D3B7 3E05 D3CE 3E07 D3B4 3E3A D3B5 2100E0 110080 011000 EDB0
    3E07 D3B4 3E3C D3B5 2100E1 011000 EDB0
    3E34 D3B8 3E12 D3B9 DBB8 12 13 DBB9 12 13 DBB8 12 13 DBB9 12 13
    3E07 D3B4 3E3F D3B5 2100E0 010400 EDB0
    3E07 D3B4 3E3B D3B5 2100E0 010400 EDB0
    18FE'''.split()))
ROMS = '../software/roms/extracted/'


def expected():
    dic = open(ROMS + 'DICT/DICT.ROM', 'rb').read()
    phone = open(ROMS + 'MZ-1E26/PHONE.ROM', 'rb').read()
    k2 = open(ROMS + 'KANJI2/KANJI2.ROM', 'rb').read()
    return dic[0xA000:0xA010] + phone[0x100:0x110] + k2[0x2468:0x246C] + b'\xff' * 8


def main():
    if sys.argv[1] == 'image':
        open(sys.argv[2], 'wb').write(CODE + bytes(0x10000 - len(CODE)))
        return
    mem = open(sys.argv[2]).read().split()
    got = bytes(int(x, 16) for x in mem[0x8000:0x802C])
    exp = expected()
    print('match' if got == exp else 'mismatch: got %s, expected %s' % (got.hex(), exp.hex()))


if __name__ == '__main__':
    main()
