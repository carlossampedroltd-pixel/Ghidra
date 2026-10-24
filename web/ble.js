// Web Bluetooth client driven by the same JSON profile as the iOS app.
// Safari/iOS has NO Web Bluetooth: on iPhone open the web in the Bluefy browser.
// Web Bluetooth only exposes services listed up front, so the service UUIDs must
// be known (get them with the free nRF Connect app, see docs).
import { settings } from './settings.js';
import { pcm16ToWav, sniffExt, MIME } from './audio.js';

export const supported = () => !!navigator.bluetooth;

export function fullUUID(u) {
  if (!u) return null;
  const s = String(u).trim().toLowerCase();
  if (/^[0-9a-f]{4}$/.test(s)) return `0000${s}-0000-1000-8000-00805f9b34fb`;
  if (/^[0-9a-f]{8}$/.test(s)) return `${s}-0000-1000-8000-00805f9b34fb`;
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(s)) return s;
  return null;
}

export function hexToBytes(hex) {
  const clean = (hex || '').replace(/[^0-9a-f]/gi, '');
  if (clean.length % 2) return null;
  return new Uint8Array(clean.match(/../g)?.map((b) => parseInt(b, 16)) || []);
}

export const bytesToHex = (b) => [...b].map((x) => x.toString(16).padStart(2, '0')).join(' ');

function downloadCommand(index) {
  const t = settings.profile.downloadCommandHex;
  if (!t) return null;
  const le = (_, bytes) => Array.from({ length: bytes }, (_, i) => (index >>> (8 * i)) & 0xff);
  const hex = (arr) => arr.map((x) => x.toString(16).padStart(2, '0')).join('');
  return hexToBytes(t
    .replaceAll('{idx16le}', hex(le(index, 2)))
    .replaceAll('{idx16be}', hex(le(index, 2).reverse()))
    .replaceAll('{idx32le}', hex(le(index, 4)))
    .replaceAll('{idx32be}', hex(le(index, 4).reverse())));
}

export class Recorder {
  constructor(onLog, onChange) {
    this.onLog = onLog;
    this.onChange = onChange;
    this.device = null;
    this.chars = [];          // { service, uuid, props, char }
    this.transfer = null;
  }

  log(dir, text, uuid) { this.onLog({ t: new Date(), dir, text, uuid }); }

  get connected() { return !!this.device?.gatt?.connected; }

  async connect() {
    const p = settings.profile;
    const services = [p.serviceUUID, ...(p.exploreServiceUUIDs || [])].map(fullUUID).filter(Boolean);
    const filters = (p.namePrefixes || []).map((namePrefix) => ({ namePrefix }));
    this.device = await navigator.bluetooth.requestDevice(
      filters.length ? { filters, optionalServices: services } : { acceptAllDevices: true, optionalServices: services });
    this.device.addEventListener('gattserverdisconnected', () => { this.log('•', 'Desconectado'); this.onChange(); });
    this.log('•', `Conectando a ${this.device.name || this.device.id}…`);
    const server = await this.device.gatt.connect();
    this.chars = [];
    let primary = [];
    try { primary = await server.getPrimaryServices(); } catch (e) { this.log('•', `Sin servicios accesibles (${e.message}). Añade sus UUID en Ajustes › Perfil BLE.`); }
    for (const svc of primary) {
      this.log('•', `Servicio ${svc.uuid}`);
      for (const ch of await svc.getCharacteristics()) {
        const pr = ch.properties;
        const props = ['read', 'write', 'writeWithoutResponse', 'notify', 'indicate'].filter((k) => pr[k]);
        this.chars.push({ service: svc.uuid, uuid: ch.uuid, props, char: ch });
        this.log('•', `  Char ${ch.uuid} [${props.join(',')}]`);
        if (pr.notify || pr.indicate) {
          ch.addEventListener('characteristicvaluechanged', (e) => this.onValue(ch, new Uint8Array(e.target.value.buffer)));
          await ch.startNotifications().catch((e) => this.log('•', `notify ${ch.uuid}: ${e.message}`));
        }
      }
    }
    this.onChange();
  }

  disconnect() { this.device?.gatt?.disconnect(); }

  find(uuid) { const u = fullUUID(uuid); return this.chars.find((c) => c.uuid === u)?.char; }

  async write(uuid, bytes, withResponse = settings.profile.writeWithResponse) {
    const ch = this.find(uuid);
    if (!ch) throw new Error(`Característica ${uuid} no encontrada`);
    if (withResponse && ch.writeValueWithResponse) await ch.writeValueWithResponse(bytes);
    else if (ch.writeValueWithoutResponse) await ch.writeValueWithoutResponse(bytes);
    else await ch.writeValue(bytes);
    this.log('→', bytesToHex(bytes), ch.uuid);
  }

  async read(uuid) {
    const v = await this.find(uuid).readValue();
    this.onValue(this.find(uuid), new Uint8Array(v.buffer));
  }

  onValue(ch, bytes) {
    const tr = this.transfer;
    if (tr && ch.uuid === fullUUID(settings.profile.notifyUUID)) {
      tr.last = Date.now();
      tr.packets++;
      const end = hexToBytes(settings.profile.endOfTransferHex || '');
      if (end?.length && end.every((b, i) => bytes[i] === b)) { tr.ended = true; return; }
      tr.parts.push(bytes.slice(Math.min(settings.profile.headerBytesPerPacket || 0, bytes.length)));
      tr.bytes += bytes.length;
      if (tr.packets % 50 === 1) this.log('←', `[#${tr.packets}, ${tr.bytes} B] ${bytesToHex(bytes.slice(0, 24))}…`, ch.uuid);
      tr.onProgress?.(tr.bytes);
      const ack = hexToBytes(settings.profile.ackCommandHex || '');
      if (ack?.length) this.write(settings.profile.writeUUID, ack).catch(() => {});
      return;
    }
    const printable = bytes.every((b) => b >= 0x20 && b <= 0x7e);
    this.log('←', bytesToHex(bytes) + (printable ? `  "${new TextDecoder().decode(bytes)}"` : ''), ch.uuid);
  }

  /** Downloads recording `index` per the profile and returns { blob, ext }. */
  async downloadRecording(index, onProgress) {
    const p = settings.profile;
    for (const f of ['writeUUID', 'notifyUUID', 'downloadCommandHex']) {
      if (!p[f]) throw new Error(`Falta '${f}' en el Perfil BLE (Ajustes).`);
    }
    if (!this.find(p.notifyUUID)) throw new Error('notifyUUID no encontrado en el dispositivo.');
    this.transfer = { parts: [], bytes: 0, packets: 0, last: Date.now(), ended: false, onProgress };
    try {
      await this.write(p.writeUUID, downloadCommand(index));
      while (!this.transfer.ended && Date.now() - this.transfer.last < (p.idleTimeout || 3) * 1000) {
        await new Promise((r) => setTimeout(r, 200));
      }
      const data = new Uint8Array(await new Blob(this.transfer.parts).arrayBuffer());
      if (!data.length) throw new Error('No se recibieron datos.');
      this.log('•', `Transferencia completa: ${data.length} bytes`);
      if (p.audioFormat === 'pcm16') return { blob: pcm16ToWav(data, p.sampleRate, p.channels), ext: 'wav' };
      if (p.audioFormat === 'rawFile') {
        const ext = sniffExt(data) || p.fileExtension || 'bin';
        return { blob: new Blob([data], { type: MIME[ext] || 'application/octet-stream' }), ext };
      }
      // Undecoded codec: hand back the raw dump so it can be analysed offline.
      return { blob: new Blob([data], { type: 'application/octet-stream' }), ext: `${p.audioFormat}.bin`, raw: true };
    } finally {
      this.transfer = null;
    }
  }
}
