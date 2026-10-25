// Local language model (Qwen3 1.7B) running inside the browser with
// transformers.js. Downloaded once from Hugging Face and cached; prompts and
// notes never leave the device.
import { pipeline, TextStreamer, env } from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.1/+esm';

env.allowLocalModels = false;

let generator = null;
let loadedKey = '';

async function load({ model, dtype, device }) {
  const key = `${model}|${dtype}|${device}`;
  if (generator && loadedKey === key) return generator;
  generator = null;
  generator = await pipeline('text-generation', model, {
    dtype,
    device,
    progress_callback: (p) => {
      if (p.status === 'progress' && /\.onnx/.test(p.file)) postMessage({ type: 'download', progress: p.progress });
    },
  });
  loadedKey = key;
  return generator;
}

self.onmessage = async ({ data }) => {
  const { id, messages, maxTokens, config } = data;
  try {
    const gen = await load(config);
    if (!messages) { postMessage({ type: 'done', id, text: '' }); return; } // preload only
    postMessage({ type: 'status', id, text: 'Pensando…' });
    const streamer = new TextStreamer(gen.tokenizer, {
      skip_prompt: true,
      skip_special_tokens: true,
      callback_function: (text) => postMessage({ type: 'token', id, text }),
    });
    const out = await gen(messages, {
      max_new_tokens: maxTokens || 512,
      do_sample: false,
      repetition_penalty: 1.1,
      streamer,
    });
    const last = out[0].generated_text;
    const text = Array.isArray(last) ? last.at(-1).content : String(last);
    postMessage({ type: 'done', id, text: text.trim() });
  } catch (e) {
    postMessage({ type: 'error', id, message: String(e?.message || e) });
  }
};
