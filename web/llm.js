// Main-thread side of the local AI: picks the model for this device, runs
// prompts in llm-worker.js, and implements summaries and "ask your notes".
import { settings } from './settings.js';
import { STOP, norm } from './summarize.js';

// Qwen3 1.7B: the smallest model that summarized Spanish faithfully in our tests
// (Qwen 2.5 0.5B/1.5B and Qwen3 0.6B invented figures or ignored the format).
const MODEL = 'onnx-community/Qwen3-1.7B-ONNX';

let worker = null;
let nextId = 1;
let configPromise = null;

/**
 * Model/precision/backend for this device, or { unavailable: reason }.
 * On the iPhone only the WebGPU + f16 build (1.4 GB) is practical; the CPU build
 * is a single 2.1 GB file, so it is only offered as an explicit desktop option.
 */
export function config() {
  configPromise ??= (async () => {
    if (settings.llm === 'off') return { unavailable: 'IA local apagada en Ajustes.' };
    if (settings.llm === 'cpu') return { model: MODEL, dtype: 'q4', device: 'wasm', label: 'Qwen3 1.7B · CPU (lento, ~2,1 GB)' };
    let adapter = null;
    try { adapter = await navigator.gpu?.requestAdapter(); } catch { /* no WebGPU */ }
    if (!adapter) return { unavailable: 'Este navegador no tiene WebGPU, que la IA local necesita. Se usará el resumen básico.' };
    if (!adapter.features.has('shader-f16')) return { unavailable: 'La GPU de este dispositivo no admite el formato del modelo (shader-f16). Se usará el resumen básico.' };
    return { model: MODEL, dtype: 'q4f16', device: 'webgpu', label: 'Qwen3 1.7B · GPU (~1,4 GB)' };
  })();
  return configPromise;
}

export const enabled = async () => !(await config()).unavailable;

/** Qwen3 may emit an (empty) reasoning block; never show it. */
export const clean = (t) => t.replace(/<think>[\s\S]*?(<\/think>|$)/g, '').trimStart();

export function resetConfig() { configPromise = null; release(); }

/** Frees the model's memory (the iPhone can't comfortably hold Whisper and the LLM at once). */
export function release() {
  worker?.terminate();
  worker = null;
}

/** Runs a chat completion. `messages` = [{role, content}]; omit it to just download/load the model. */
export async function chat(messages, { maxTokens = 512, onToken, onStatus } = {}) {
  const cfg = await config();
  if (cfg.unavailable) throw new Error(cfg.unavailable);
  // Qwen3: skip the slow "thinking" phase; we want direct answers.
  if (messages?.length) {
    const last = messages.at(-1);
    messages = [...messages.slice(0, -1), { ...last, content: `${last.content}\n/no_think` }];
  }
  worker ??= new Worker(new URL('./llm-worker.js', import.meta.url), { type: 'module' });
  const id = nextId++;
  return new Promise((resolve, reject) => {
    worker.onmessage = ({ data }) => {
      if (data.id !== undefined && data.id !== id) return;
      if (data.type === 'download') onStatus?.(`Descargando IA (solo la 1ª vez): ${Math.round(data.progress || 0)}%`);
      else if (data.type === 'status') onStatus?.(data.text);
      else if (data.type === 'token') onToken?.(data.text);
      else if (data.type === 'done') resolve(clean(data.text).trim());
      else if (data.type === 'error') { release(); reject(new Error(`IA local: ${data.message}`)); }
    };
    worker.onerror = (e) => { release(); reject(new Error(`IA local: ${e.message || 'error del worker'}`)); };
    worker.postMessage({ id, messages, maxTokens, config: cfg });
  });
}

const SYSTEM_SUMMARY = 'Eres un asistente que resume notas de voz. Responde siempre en el mismo idioma que la transcripción. '
  + 'Sé fiel al contenido: no inventes nombres, cifras ni fechas.';

const FORMAT = 'Responde exactamente con este formato:\n'
  + 'TÍTULO: <máximo 8 palabras>\n\nRESUMEN:\n<3 a 5 frases>\n\nPUNTOS CLAVE:\n- <un punto por línea>\n\n'
  + 'TAREAS:\n- <cada cosa que alguien tiene que hacer. Busca frases como "tenemos que", "hay que", "tengo que", "no olvidar". '
  + 'Añade responsable y fecha solo si se dicen en la transcripción; no los inventes. Si no hay ninguna, escribe "- Ninguna">';

function chunks(text, size = 5000) {
  const out = [];
  let cur = '';
  for (const sentence of text.split(/(?<=[.!?])\s+/)) {
    if (cur.length + sentence.length > size && cur) { out.push(cur); cur = ''; }
    cur += (cur ? ' ' : '') + sentence;
  }
  if (cur) out.push(cur);
  return out;
}

/** Summary of a transcript; long ones are summarized in parts and then merged. Returns { title, summary }. */
export async function summarizeTranscript(transcript, onStatus) {
  const parts = chunks(transcript);
  const partials = [];
  for (const [i, part] of parts.entries()) {
    onStatus?.(parts.length > 1 ? `Resumiendo con IA (parte ${i + 1}/${parts.length})…` : 'Resumiendo con IA…');
    partials.push(await chat([
      { role: 'system', content: SYSTEM_SUMMARY },
      { role: 'user', content: `Transcripción:\n"""\n${part}\n"""\n\n${FORMAT}` },
    ], { maxTokens: 450, onStatus }));
  }
  let text = partials[0];
  if (partials.length > 1) {
    onStatus?.('Uniendo resúmenes…');
    text = await chat([
      { role: 'system', content: SYSTEM_SUMMARY },
      { role: 'user', content: `Estos son resúmenes de partes consecutivas de una misma grabación:\n\n${partials.join('\n\n---\n\n')}\n\nÚnelos en uno solo. ${FORMAT}` },
    ], { maxTokens: 600, onStatus });
  }
  const m = text.match(/^\s*T[ÍI]TULO:\s*(.+)$/im);
  const title = m ? m[1].replace(/[*"#]/g, '').trim().slice(0, 80) : null;
  const summary = text.replace(/^\s*T[ÍI]TULO:.*$/im, '').trim();
  return { title, summary };
}

const keywords = (s) => new Set((s || '').split(/\s+/).map(norm).filter((w) => w.length > 2 && !STOP.has(w)));

/** Picks the notes most related to the question (simple keyword overlap). */
export function relevantNotes(question, recordings, max = 4) {
  const q = keywords(question);
  return recordings
    .filter((r) => r.transcript || r.summary)
    .map((r) => {
      const words = keywords(`${r.title} ${r.summary || ''} ${r.transcript || ''}`);
      let score = 0;
      for (const w of q) if (words.has(w)) score++;
      return { r, score };
    })
    .sort((a, b) => b.score - a.score || b.r.createdAt.localeCompare(a.r.createdAt))
    .slice(0, max)
    .map((x) => x.r);
}

/** Answers a question using the user's notes as the only source. */
export async function askNotes(question, recordings, history, { onToken, onStatus } = {}) {
  const notes = relevantNotes(question, recordings);
  if (!notes.length) return { text: 'Todavía no hay notas transcritas para consultar.', notes: [] };
  const budget = Math.floor(6000 / notes.length);
  const context = notes.map((r) => {
    const body = r.summary ? `${r.summary}\n\nExtracto: ${(r.transcript || '').slice(0, Math.max(0, budget - r.summary.length))}` : (r.transcript || '').slice(0, budget);
    return `### ${r.title} (${new Date(r.createdAt).toLocaleDateString('es-ES')})\n${body}`;
  }).join('\n\n');
  const messages = [
    { role: 'system', content: 'Eres un asistente que responde preguntas sobre las notas de voz del usuario. Usa SOLO la información de las notas. '
      + 'Si la respuesta no está en las notas, dilo claramente. Menciona el título de la nota de la que sacas cada dato. Responde en español y de forma breve.' },
    ...history.slice(-4),
    { role: 'user', content: `Notas:\n${context}\n\nPregunta: ${question}` },
  ];
  const text = await chat(messages, { maxTokens: 400, onToken, onStatus });
  return { text, notes };
}
