// Locate BLE protocol artefacts (128-bit UUIDs, magic command headers, audio codec
// hints) in a native library from the Boya app, e.g. lib/arm64-v8a/libxxx.so from
// the APK, or the decrypted iOS binary.
//
// Ghidra: Script Manager → place this file in ~/ghidra_scripts → run on the program.
// Results go to the console and are bookmarked under the "NotraBLE" category.
//@category Analysis
//@menupath Tools.Notra.Find BLE protocol

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;

import java.util.regex.Pattern;

public class FindBleProtocol extends GhidraScript {

	private static final Pattern UUID128 = Pattern.compile(
		"(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");
	private static final Pattern UUID16 = Pattern.compile("(?i)^(0x)?[0-9a-f]{4}$");
	private static final String[] KEYWORDS = {
		"opus", "adpcm", "pcm", "sbc", "lc3", "wav", "mp3", "file_list", "filelist",
		"get_file", "download", "sync", "record", "ota", "mtu", "notify", "crc", "aes", "key"
	};

	@Override
	protected void run() throws Exception {
		println("=== Strings: UUIDs and protocol keywords ===");
		DataIterator it = currentProgram.getListing().getDefinedData(true);
		while (it.hasNext() && !monitor.isCancelled()) {
			Data d = it.next();
			if (!d.hasStringValue()) {
				continue;
			}
			String s = String.valueOf(d.getValue());
			boolean hit = UUID128.matcher(s).find() || UUID16.matcher(s).matches();
			String lower = s.toLowerCase();
			for (String k : KEYWORDS) {
				hit |= lower.contains(k);
			}
			if (hit) {
				report(d.getAddress(), "\"" + s + "\"");
			}
		}

		println("=== Raw little-endian 128-bit UUIDs based on the BT base UUID ===");
		// xxxxxxxx-0000-1000-8000-00805f9b34fb stored LE: fb 34 9b 5f 80 00 00 80 00 10 00 00 ...
		byte[] baseLe = { (byte) 0xfb, 0x34, (byte) 0x9b, 0x5f, (byte) 0x80, 0x00, 0x00,
			(byte) 0x80, 0x00, 0x10, 0x00, 0x00 };
		Memory mem = currentProgram.getMemory();
		Address a = mem.getMinAddress();
		while (a != null && !monitor.isCancelled()) {
			a = mem.findBytes(a, baseLe, null, true, monitor);
			if (a == null) {
				break;
			}
			byte[] short16 = new byte[4];
			mem.getBytes(a.add(12), short16);
			report(a, String.format("BT-base UUID, 16/32-bit part = %02x%02x%02x%02x",
				short16[3], short16[2], short16[1], short16[0]));
			a = a.add(1);
		}
		println("Done. Next: open each referencing function, look for the byte arrays it "
			+ "builds before calling the write/notify JNI or CoreBluetooth wrapper — those are the commands.");
	}

	private void report(Address addr, String what) {
		StringBuilder refs = new StringBuilder();
		for (Reference r : getReferencesTo(addr)) {
			Function f = getFunctionContaining(r.getFromAddress());
			refs.append(" ").append(f != null ? f.getName() : r.getFromAddress().toString());
		}
		println(addr + "  " + what + (refs.length() > 0 ? "  refs:" + refs : ""));
		createBookmark(addr, "NotraBLE", what);
	}
}
