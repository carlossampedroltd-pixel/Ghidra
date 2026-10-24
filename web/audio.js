// Audio helpers: duration, decoding to 16 kHz mono for Whisper, mic recording,
// WAV packing and container sniffing.

export function durationOf(blob) {
  return new Promise((resolve) => {
    const a = new Audio();
    const url = URL.createObjectURL(blob);
    const done = (d) => { URL.revokeObjectURL(url); resolve(Number.isFinite(d) ? d : 0); };
    a.preload = 'metadata';
    a.onloadedmetadata = () => done(a.duration);
    a.onerror = () => done(0);
    a.src = url;
  });
}

/** Decodes any supported file into a Float32Array at 16 kHz mono (Whisper input). */
export async function decodeTo16kMono(blob) {
  const buf = await blob.arrayBuffer();
  const Ctx = window.AudioContext || window.webkitAudioContext;
  const ctx = new Ctx();
  try {
    const decoded = await ctx.decodeAudioData(buf);
    const length = Math.ceil(decoded.duration * 16000);
    const off = new OfflineAudioContext(1, length, 16000);
    const src = off.createBufferSource();
    src.buffer = decoded;
    src.connect(off.destination);
    src.start();
    const rendered = await off.startRendering();
    return rendered.getChannelData(0);
  } finally {
    ctx.close();
  }
}

export class PhoneRecorder {
  constructor() { this.rec = null; this.chunks = []; this.startedAt = 0; }
  get isRecording() { return this.rec?.state === 'recording'; }

  async start() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
    const mimeType = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'].find((t) => MediaRecorder.isTypeSupported?.(t));
    this.rec = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
    this.chunks = [];
    this.rec.ondataavailable = (e) => e.data.size && this.chunks.push(e.data);
    this.rec.start(1000);
    this.startedAt = Date.now();
  }

  stop() {
    return new Promise((resolve) => {
      const rec = this.rec;
      rec.onstop = () => {
        rec.stream.getTracks().forEach((t) => t.stop());
        resolve(new Blob(this.chunks, { type: rec.mimeType || 'audio/mp4' }));
      };
      rec.stop();
    });
  }
}

export function pcm16ToWav(pcm, sampleRate, channels) {
  const h = new DataView(new ArrayBuffer(44));
  const str = (o, s) => [...s].forEach((c, i) => h.setUint8(o + i, c.charCodeAt(0)));
  str(0, 'RIFF'); h.setUint32(4, 36 + pcm.byteLength, true); str(8, 'WAVEfmt ');
  h.setUint32(16, 16, true); h.setUint16(20, 1, true); h.setUint16(22, channels, true);
  h.setUint32(24, sampleRate, true); h.setUint32(28, sampleRate * channels * 2, true);
  h.setUint16(32, channels * 2, true); h.setUint16(34, 16, true);
  str(36, 'data'); h.setUint32(40, pcm.byteLength, true);
  return new Blob([h.buffer, pcm], { type: 'audio/wav' });
}

/** Detects common containers by magic bytes. */
export function sniffExt(bytes) {
  const b = bytes;
  const eq = (o, arr) => arr.every((v, i) => b[o + i] === v);
  if (b.length < 4) return null;
  if (eq(0, [0x52, 0x49, 0x46, 0x46])) return 'wav';
  if (eq(0, [0x4f, 0x67, 0x67, 0x53])) return 'ogg';
  if (eq(0, [0x49, 0x44, 0x33]) || (b[0] === 0xff && (b[1] & 0xe0) === 0xe0)) return 'mp3';
  if (b.length >= 8 && eq(4, [0x66, 0x74, 0x79, 0x70])) return 'm4a';
  if (eq(0, [0x23, 0x21, 0x41, 0x4d])) return 'amr';
  return null;
}

export const MIME = { wav: 'audio/wav', mp3: 'audio/mpeg', m4a: 'audio/mp4', mp4: 'audio/mp4', ogg: 'audio/ogg', opus: 'audio/ogg', amr: 'audio/amr', webm: 'audio/webm' };

export function extFor(blob, name = '') {
  const fromName = name.includes('.') ? name.split('.').pop().toLowerCase() : '';
  if (fromName) return fromName;
  const t = blob.type || '';
  return Object.keys(MIME).find((k) => MIME[k] === t.split(';')[0]) || 'm4a';
}
