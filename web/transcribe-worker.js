// Whisper running inside the browser (transformers.js). The model is downloaded
// once from Hugging Face and cached by the browser; audio never leaves the device.
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.0.2';

env.allowLocalModels = false;

let asr = null;
let loadedKey = '';

async function load(model, device) {
  const key = `${model}|${device}`;
  if (asr && loadedKey === key) return asr;
  const dtype = device === 'webgpu'
    ? { encoder_model: 'fp32', decoder_model_merged: 'q4' }
    : 'q8';
  asr = await pipeline('automatic-speech-recognition', model, {
    device,
    dtype,
    progress_callback: (p) => {
      if (p.status === 'progress') postMessage({ type: 'download', file: p.file, progress: p.progress });
    },
  });
  loadedKey = key;
  return asr;
}

self.onmessage = async ({ data }) => {
  const { audio, model, language, device } = data;
  const run = async (dev) => {
    const pipe = await load(model, dev);
    postMessage({ type: 'status', text: `Transcribiendo (${dev === 'webgpu' ? 'GPU' : 'CPU'})…` });
    const out = await pipe(audio, {
      language,
      task: 'transcribe',
      chunk_length_s: 30,
      stride_length_s: 5,
    });
    return Array.isArray(out) ? out.map((o) => o.text).join(' ') : out.text;
  };
  try {
    let text;
    try {
      text = await run(device);
    } catch (e) {
      if (device !== 'webgpu') throw e;
      postMessage({ type: 'status', text: 'WebGPU falló, usando CPU…' });
      asr = null;
      text = await run('wasm');
    }
    postMessage({ type: 'done', text: text.trim() });
  } catch (e) {
    postMessage({ type: 'error', message: String(e?.message || e) });
  }
};
