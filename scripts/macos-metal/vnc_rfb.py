#!/usr/bin/env python3
"""Minimal RFB 3.8 client: snapshot, click, and type against a local VNC server."""
from __future__ import annotations

import argparse
import socket
import struct
import sys
import time
from pathlib import Path

# A compact X11 keysym map for US keys used in the input proof.
KEYSYMS = {
    "BackSpace": 0xFF08,
    "Tab": 0xFF09,
    "Return": 0xFF0D,
    "Escape": 0xFF1B,
    "Home": 0xFF50,
    "Left": 0xFF51,
    "Up": 0xFF52,
    "Right": 0xFF53,
    "Down": 0xFF54,
    "Page_Up": 0xFF55,
    "Page_Down": 0xFF56,
    "End": 0xFF57,
    "Shift_L": 0xFFE1,
    "Control_L": 0xFFE3,
    "Alt_L": 0xFFE9,
    "space": 0x0020,
    "l": 0x006C,
}


def recvall(sock: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise EOFError(f"VNC closed after {len(buf)}/{n} bytes")
        buf.extend(chunk)
    return bytes(buf)


class Vnc:
    def __init__(self, host: str = "127.0.0.1", port: int = 5900) -> None:
        self.s = socket.create_connection((host, port), timeout=8)
        self.s.settimeout(20)
        ver = recvall(self.s, 12)
        self.s.sendall(b"RFB 003.008\n")
        ntypes = recvall(self.s, 1)[0]
        types = recvall(self.s, ntypes)
        if 1 not in types:
            raise RuntimeError(f"server has no None auth, types={list(types)} ver={ver!r}")
        self.s.sendall(b"\x01")
        result = struct.unpack(">I", recvall(self.s, 4))[0]
        if result != 0:
            raise RuntimeError(f"RFB security result {result}")
        self.s.sendall(b"\x01")  # shared
        hdr = recvall(self.s, 24)
        self.width, self.height = struct.unpack(">HH", hdr[:4])
        (
            self.bpp,
            self.depth,
            self.big,
            self.truecolor,
            rmax,
            gmax,
            bmax,
            rshift,
            gshift,
            bshift,
        ) = struct.unpack(">BBBBHHHBBB", hdr[4:17])
        namelen = struct.unpack(">I", hdr[20:24])[0]
        self.name = recvall(self.s, namelen).decode("utf-8", "replace")
        # Prefer 32-bpp little-endian RGB888 for easy PPM writes.
        self.s.sendall(
            struct.pack(
                ">BBBBHHHBBBxxx",
                0,  # SetPixelFormat
                0,
                0,
                0,
                32,
                24,
                0,  # little endian
                1,  # truecolor
                255,
                255,
                255,
                16,
                8,
                0,
            )
        )
        # encodings: Raw only
        self.s.sendall(struct.pack(">BBH i", 2, 0, 1, 0))
        self.fb = bytearray(self.width * self.height * 4)
        self.bpp = 32

    def close(self) -> None:
        try:
            self.s.close()
        except OSError:
            pass

    def request(self, incremental: bool = False) -> None:
        self.s.sendall(
            struct.pack(">BBHHHH", 3, 1 if incremental else 0, 0, 0, self.width, self.height)
        )
        self._read_until_update()

    def _read_until_update(self) -> None:
        deadline = time.time() + 15
        while time.time() < deadline:
            msg = recvall(self.s, 1)[0]
            if msg == 0:  # FramebufferUpdate
                recvall(self.s, 1)
                nrects = struct.unpack(">H", recvall(self.s, 2))[0]
                for _ in range(nrects):
                    x, y, w, h, enc = struct.unpack(">HHHHi", recvall(self.s, 12))
                    if enc != 0:
                        raise RuntimeError(f"unsupported encoding {enc}")
                    data = recvall(self.s, w * h * 4)
                    for row in range(h):
                        dst = ((y + row) * self.width + x) * 4
                        src = row * w * 4
                        self.fb[dst : dst + w * 4] = data[src : src + w * 4]
                return
            if msg == 1:  # SetColourMapEntries
                recvall(self.s, 1)
                recvall(self.s, 2)
                n = struct.unpack(">H", recvall(self.s, 2))[0]
                recvall(self.s, n * 6)
                continue
            if msg == 2:  # Bell
                continue
            if msg == 3:  # ServerCutText
                recvall(self.s, 3)
                length = struct.unpack(">I", recvall(self.s, 4))[0]
                recvall(self.s, length)
                continue
            raise RuntimeError(f"unknown RFB server message {msg}")
        raise TimeoutError("no framebuffer update")

    def pointer(self, x: int, y: int, mask: int = 0) -> None:
        self.s.sendall(struct.pack(">BBHH", 5, mask, x, y))

    def click(self, x: int, y: int, button: int = 1) -> None:
        self.pointer(x, y, 0)
        self.pointer(x, y, 1 << (button - 1))
        self.pointer(x, y, 0)

    def key(self, keysym: int, down: bool) -> None:
        self.s.sendall(struct.pack(">BBH I", 4, 1 if down else 0, 0, keysym))

    def tap(self, keysym: int) -> None:
        self.key(keysym, True)
        self.key(keysym, False)

    def type_text(self, text: str) -> None:
        for ch in text:
            if ch == "\n":
                self.tap(0xFF0D)
                continue
            code = ord(ch)
            if "A" <= ch <= "Z":
                self.key(0xFFE1, True)
                self.tap(code)
                self.key(0xFFE1, False)
            elif ch in r'!@#$%^&*()_+{}|:"<>?~':
                shifted = {
                    "!": "1",
                    "@": "2",
                    "#": "3",
                    "$": "4",
                    "%": "5",
                    "^": "6",
                    "&": "7",
                    "*": "8",
                    "(": "9",
                    ")": "0",
                    "_": "-",
                    "+": "=",
                    "{": "[",
                    "}": "]",
                    "|": "\\",
                    ":": ";",
                    '"': "'",
                    "<": ",",
                    ">": ".",
                    "?": "/",
                    "~": "`",
                }
                self.key(0xFFE1, True)
                self.tap(ord(shifted[ch]))
                self.key(0xFFE1, False)
            else:
                self.tap(code)

    def write_ppm(self, path: Path) -> None:
        # fb is little-endian 32-bpp: B,G,R,A or R,G,B,A? With rshift=16,gshift=8,bshift=0
        # little endian 32-bit word 0x00RRGGBB is bytes B,G,R,0
        out = bytearray(self.width * self.height * 3)
        fb = self.fb
        for i in range(self.width * self.height):
            b = fb[i * 4]
            g = fb[i * 4 + 1]
            r = fb[i * 4 + 2]
            out[i * 3 : i * 3 + 3] = bytes((r, g, b))
        path.write_bytes(
            f"P6\n{self.width} {self.height}\n255\n".encode("ascii") + bytes(out)
        )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=5900)
    p.add_argument("--snap", type=Path)
    p.add_argument("--click", nargs=2, type=int, metavar=("X", "Y"))
    p.add_argument("--type")
    p.add_argument("--key")
    p.add_argument("--sleep", type=float, default=0.0)
    p.add_argument("--info", action="store_true")
    args = p.parse_args()
    v = Vnc(args.host, args.port)
    try:
        if args.info:
            print(
                f"name={v.name!r} size={v.width}x{v.height} bpp={v.bpp} depth={v.depth}",
                flush=True,
            )
        v.request(False)
        if args.click:
            v.click(args.click[0], args.click[1])
        if args.key:
            if args.key not in KEYSYMS and len(args.key) != 1:
                raise SystemExit(f"unknown key {args.key}")
            v.tap(KEYSYMS.get(args.key, ord(args.key)))
        if args.type:
            v.type_text(args.type)
        if args.sleep:
            time.sleep(args.sleep)
            v.request(True)
        if args.snap:
            if args.click or args.type or args.key:
                time.sleep(0.3)
                v.request(False)
            v.write_ppm(args.snap)
            print(f"wrote {args.snap} {v.width}x{v.height}", flush=True)
        return 0
    finally:
        v.close()


if __name__ == "__main__":
    sys.exit(main())
