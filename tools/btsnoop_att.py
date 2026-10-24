#!/usr/bin/env python3
"""
Extract BLE ATT traffic (writes / notifications) from an Android
btsnoop_hci.log so you can see exactly what the official Boya app sends to
the Notra NEO and what the recorder answers.

Usage:
  python3 tools/btsnoop_att.py btsnoop_hci.log                 # timeline of ATT ops
  python3 tools/btsnoop_att.py btsnoop_hci.log --stats         # bytes per handle
  python3 tools/btsnoop_att.py btsnoop_hci.log --dump 0x0012 --strip 4 -o out.bin
        # concatenate every notification on handle 0x0012 (dropping a 4-byte
        # per-packet header) into out.bin — that's usually the audio file.

Only the Python standard library is needed.
"""
import argparse
import struct
import sys
from collections import defaultdict
from datetime import datetime, timedelta

ATT_OPS = {
    0x01: "ERROR_RSP", 0x02: "MTU_REQ", 0x03: "MTU_RSP",
    0x08: "READ_BY_TYPE_REQ", 0x09: "READ_BY_TYPE_RSP",
    0x0A: "READ_REQ", 0x0B: "READ_RSP",
    0x10: "READ_BY_GROUP_REQ", 0x11: "READ_BY_GROUP_RSP",
    0x12: "WRITE_REQ", 0x13: "WRITE_RSP",
    0x1B: "NOTIFY", 0x1D: "INDICATE", 0x1E: "CONFIRM",
    0x52: "WRITE_CMD",
}
HANDLE_OPS = {0x0A, 0x12, 0x1B, 0x1D, 0x52}
BTSNOOP_UNIX_OFFSET_US = 0x00DCDDB30F2F8000  # btsnoop counts µs since year 0


def records(path):
    with open(path, "rb") as f:
        hdr = f.read(16)
        if hdr[:8] != b"btsnoop\0":
            sys.exit("Not a btsnoop file")
        _ver, datalink = struct.unpack(">II", hdr[8:])
        while True:
            rh = f.read(24)
            if len(rh) < 24:
                return
            _orig, incl, flags, _drops, ts = struct.unpack(">IIIIq", rh)
            data = f.read(incl)
            received = bool(flags & 1)  # 1 = controller -> host
            if datalink == 1002:  # H4: first byte is the packet type
                ptype, data = data[0], data[1:]
            else:
                ptype = 0x02 if flags & 2 == 0 else 0x04
            yield ts, received, ptype, data


def att_packets(path):
    """Reassemble ACL/L2CAP and yield (ts, received, opcode, handle, value)."""
    partial = {}
    for ts, received, ptype, data in records(path):
        if ptype != 0x02 or len(data) < 4:
            continue
        hf, acl_len = struct.unpack("<HH", data[:4])
        conn, pb = hf & 0x0FFF, (hf >> 12) & 0x3
        payload = data[4:4 + acl_len]
        key = (conn, received)
        if pb == 0x1:  # continuation fragment
            if key not in partial:
                continue
            partial[key][1].extend(payload)
        else:
            if len(payload) < 4:
                continue
            l2_len, = struct.unpack("<H", payload[:2])
            partial[key] = [l2_len, bytearray(payload)]
        l2_len, buf = partial[key]
        if len(buf) < l2_len + 4:
            continue
        del partial[key]
        cid, = struct.unpack("<H", buf[2:4])
        if cid != 0x0004:  # ATT
            continue
        att = bytes(buf[4:4 + l2_len])
        if not att:
            continue
        op = att[0]
        if op in HANDLE_OPS and len(att) >= 3:
            handle, = struct.unpack("<H", att[1:3])
            yield ts, received, op, handle, att[3:]
        else:
            yield ts, received, op, None, att[1:]


def ts_str(ts):
    try:
        return (datetime(1970, 1, 1) + timedelta(microseconds=ts - BTSNOOP_UNIX_OFFSET_US)).strftime("%H:%M:%S.%f")[:-3]
    except OverflowError:
        return str(ts)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log")
    ap.add_argument("--stats", action="store_true", help="summary of bytes per handle/opcode")
    ap.add_argument("--dump", help="handle (e.g. 0x0012) whose notifications to concatenate")
    ap.add_argument("--strip", type=int, default=0, help="bytes to drop from each notification")
    ap.add_argument("-o", "--out", default="dump.bin")
    ap.add_argument("--max", type=int, default=64, help="max value bytes to print per line")
    a = ap.parse_args()

    if a.dump:
        target = int(a.dump, 0)
        out = bytearray()
        n = 0
        for _ts, _rx, op, h, val in att_packets(a.log):
            if op in (0x1B, 0x1D) and h == target:
                out += val[a.strip:]
                n += 1
        open(a.out, "wb").write(out)
        print(f"{n} notifications, {len(out)} bytes -> {a.out}")
        print("First bytes:", out[:16].hex(" "))
        return

    if a.stats:
        stats = defaultdict(lambda: [0, 0])
        for _ts, rx, op, h, val in att_packets(a.log):
            k = ("dev→app" if rx else "app→dev", ATT_OPS.get(op, hex(op)), h)
            stats[k][0] += 1
            stats[k][1] += len(val)
        for (d, op, h), (n, b) in sorted(stats.items(), key=lambda kv: -kv[1][1]):
            print(f"{d:8} {op:18} handle={str(h) if h is None else hex(h):8} packets={n:6} bytes={b}")
        return

    for ts, rx, op, h, val in att_packets(a.log):
        arrow = "←" if rx else "→"
        hs = f"h={h:#06x}" if h is not None else " " * 8
        txt = val[:a.max].hex(" ") + (" …" if len(val) > a.max else "")
        print(f"{ts_str(ts)} {arrow} {ATT_OPS.get(op, hex(op)):18} {hs} [{len(val):3}] {txt}")


if __name__ == "__main__":
    main()
