#!/usr/bin/env python3
"""
Probe the Boya Notra NEO from a Mac/PC/Linux box with Bleak:
  * list nearby devices,
  * dump the full GATT table (services, characteristics, descriptors, readable values),
  * subscribe to every notify characteristic and log what arrives,
  * optionally send hex commands (to replay what you saw in the btsnoop capture).

  pip install bleak
  python3 tools/ble_probe.py scan
  python3 tools/ble_probe.py dump  <ADDRESS>
  python3 tools/ble_probe.py talk  <ADDRESS> --write <CHAR_UUID> --hex "aa 55 01 00" [--save out.bin]
"""
import argparse
import asyncio
import sys
import time

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    sys.exit("pip install bleak")


async def scan():
    found = await BleakScanner.discover(timeout=8, return_adv=True)
    for addr, (dev, adv) in sorted(found.items(), key=lambda kv: -kv[1][1].rssi):
        name = adv.local_name or dev.name or "?"
        star = "*" if any(k in name.upper() for k in ("NOTRA", "BOYA")) else " "
        print(f"{star} {addr}  {adv.rssi:4} dBm  {name}  services={adv.service_uuids} mfr={ {k: v.hex() for k, v in adv.manufacturer_data.items()} }")


async def dump(addr):
    async with BleakClient(addr) as c:
        print(f"Connected, MTU={c.mtu_size}")
        for s in c.services:
            print(f"[service] {s.uuid}  {s.description}")
            for ch in s.characteristics:
                val = ""
                if "read" in ch.properties:
                    try:
                        v = await c.read_gatt_char(ch)
                        val = f" = {v.hex(' ')}  {v!r}"
                    except Exception as e:  # noqa: BLE001
                        val = f" (read error {e})"
                print(f"   [char] {ch.uuid} handle={ch.handle:#06x} {','.join(ch.properties)}{val}")
                for d in ch.descriptors:
                    print(f"      [desc] {d.uuid} handle={d.handle:#06x}")


async def talk(addr, write_uuid, hexes, save, wait):
    out = bytearray()
    last = [time.time()]

    def on_notify(ch, data: bytearray):
        last[0] = time.time()
        out.extend(data)
        print(f"← {ch.uuid[:8]} [{len(data):3}] {data[:48].hex(' ')}")

    async with BleakClient(addr) as c:
        for s in c.services:
            for ch in s.characteristics:
                if {"notify", "indicate"} & set(ch.properties):
                    await c.start_notify(ch, on_notify)
        for h in hexes:
            data = bytes.fromhex(h)
            print(f"→ {write_uuid[:8]} {data.hex(' ')}")
            await c.write_gatt_char(write_uuid, data, response=False)
            await asyncio.sleep(0.3)
        while time.time() - last[0] < wait:
            await asyncio.sleep(0.2)
    if save:
        open(save, "wb").write(out)
        print(f"Saved {len(out)} bytes to {save}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scan")
    d = sub.add_parser("dump"); d.add_argument("address")
    t = sub.add_parser("talk"); t.add_argument("address")
    t.add_argument("--write", required=True, help="characteristic UUID to write to")
    t.add_argument("--hex", action="append", default=[], help="command in hex (repeatable)")
    t.add_argument("--save", help="write all notification bytes to this file")
    t.add_argument("--wait", type=float, default=5, help="idle seconds before disconnecting")
    a = ap.parse_args()
    if a.cmd == "scan":
        asyncio.run(scan())
    elif a.cmd == "dump":
        asyncio.run(dump(a.address))
    else:
        asyncio.run(talk(a.address, a.write, a.hex, a.save, a.wait))


if __name__ == "__main__":
    main()
