import * as db from './db.js';
import * as drive from './drive.js';
import * as ble from './ble.js';
import { PhoneRecorder, durationOf, decodeTo16kMono, extFor, MIME } from './audio.js';
import { summarize } from './summarize.js';
import * as llm from './llm.js';
import { settings, saveSettings, DEFAULT_PROFILE } from './settings.js';

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtDur = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const fmtDate = (iso) => new Date(iso).toLocaleString('es-ES', { dateStyle: 'medium', timeStyle: 'short' });
const LANG_NAMES = { es: 'spanish', en: 'english', pt: 'portuguese', fr: 'french', de: 'german', it: 'italian', ca: 'catalan' };
const SOURCE_LABEL = { device: 'Notra NEO', imported: 'Importado', phone: 'iPhone', drive: 'Drive' };

const state = { tab: 'notes', recordings: [], selectedId: null, search: '', showText: 'summary', driveEmail: null };

// ---------------------------------------------------------------- UI helpers

let toastTimer;
function toast(msg, ms = 4000) {
  const t = $('#toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, ms);
}

function status(msg) {
  const s = $('#status');
  s.hidden = !msg;
  s.textContent = msg || '';
}

function switchTab(tab) {
  state.tab = tab;
  document.querySelectorAll('.tabs button').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
  document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${tab}`));
  if (tab === 'drive') renderDrive();
}

// ---------------------------------------------------------------- Library

async function reload() {
  state.recordings = await db.listRecordings();
  renderList();
}

const getRec = (id) => state.recordings.find((r) => r.id === id);

async function updateRec(rec) {
  await db.putRecording(rec);
  const i = state.recordings.findIndex((r) => r.id === rec.id);
  if (i >= 0) state.recordings[i] = rec;
  renderList();
  if (state.selectedId === rec.id) renderDetail({ keepAudio: true });
}

async function addRecording(blob, { title, source, ext, driveAudioId = null }) {
  const rec = {
    id: crypto.randomUUID(),
    title: title || `Nota ${new Date().toLocaleString('es-ES', { dateStyle: 'short', timeStyle: 'short' })}`,
    createdAt: new Date().toISOString(),
    duration: await durationOf(blob),
    ext: ext || extFor(blob),
    mime: blob.type || MIME[ext] || 'audio/mp4',
    source,
    transcript: null,
    summary: null,
    driveAudioId,
    driveNoteId: null,
  };
  await db.putAudio(rec.id, blob);
  await db.putRecording(rec);
  state.recordings.unshift(rec);
  renderList();
  if (settings.autoProcess) enqueue(() => processAll(rec.id));
  return rec;
}

function renderList() {
  const q = state.search.toLowerCase();
  const items = state.recordings.filter((r) => !q || r.title.toLowerCase().includes(q) || (r.transcript || '').toLowerCase().includes(q));
  $('#empty').hidden = state.recordings.length > 0;
  $('#rec-list').innerHTML = items.map((r) => `
    <li data-id="${r.id}" class="${r.id === state.selectedId ? 'selected' : ''}">
      <div class="title"><span>${esc(r.title)}</span>${r.driveAudioId ? '<span class="synced">☁︎ Drive</span>' : ''}</div>
      <div class="meta">${fmtDate(r.createdAt)} · ${fmtDur(r.duration)} · ${SOURCE_LABEL[r.source] || ''}</div>
      ${r.summary || r.transcript ? `<div class="snippet">${esc((r.transcript || r.summary).slice(0, 200))}</div>` : ''}
    </li>`).join('');
}

let audioUrl = null;
async function renderDetail({ keepAudio = false } = {}) {
  const pane = $('#detail');
  const rec = getRec(state.selectedId);
  $('#view-notes').classList.toggle('has-selection', !!rec);
  if (!rec) { pane.innerHTML = '<div class="placeholder">Elige una nota</div>'; return; }

  const oldAudio = pane.querySelector('audio');
  const resume = keepAudio && oldAudio && oldAudio.dataset.id === rec.id ? { t: oldAudio.currentTime, playing: !oldAudio.paused } : null;
  if (!resume) {
    if (audioUrl) URL.revokeObjectURL(audioUrl);
    const blob = await db.getAudio(rec.id);
    audioUrl = blob ? URL.createObjectURL(blob) : '';
  }

  pane.innerHTML = `
    <div class="detail">
      <button class="back" data-act="back">‹ Notas</button>
      <input class="title-input" value="${esc(rec.title)}" data-act="title" aria-label="Título">
      <div class="hint">${fmtDate(rec.createdAt)} · ${fmtDur(rec.duration)} · ${SOURCE_LABEL[rec.source] || ''}</div>
      <audio controls preload="metadata" src="${audioUrl}" data-id="${rec.id}"></audio>
      <div class="row">
        <button class="btn" data-act="transcribe">${rec.transcript ? 'Volver a transcribir' : 'Transcribir'}</button>
        <button class="btn" data-act="summarize" ${rec.transcript ? '' : 'disabled'}>Resumir</button>
        <button class="btn" data-act="sync">${rec.driveAudioId ? 'Actualizar en Drive' : 'Subir a Drive'}</button>
        <button class="btn" data-act="share">Compartir</button>
        <button class="btn danger" data-act="delete">Borrar</button>
      </div>
      <div class="seg">
        <button data-show="summary" class="${state.showText === 'summary' ? 'on' : ''}">Resumen</button>
        <button data-show="transcript" class="${state.showText === 'transcript' ? 'on' : ''}">Transcripción</button>
      </div>
      <div class="texts" data-show="${state.showText}">
        <article class="t-summary"><h3>Resumen</h3>${esc(rec.summary || '—')}</article>
        <article class="t-transcript"><h3>Transcripción</h3>${esc(rec.transcript || '—')}</article>
      </div>
    </div>`;
  if (resume) {
    const a = pane.querySelector('audio');
    a.currentTime = resume.t;
    if (resume.playing) a.play().catch(() => {});
  }
}

function select(id) {
  state.selectedId = id;
  renderList();
  renderDetail();
}

// ---------------------------------------------------------------- Processing

let queue = Promise.resolve();
function enqueue(job) {
  queue = queue.then(job).catch((e) => toast(e.message || String(e), 7000)).finally(() => status(''));
  return queue;
}

// 'gpu' in navigator isn't enough: some browsers expose WebGPU without an adapter.
let devicePromise;
const pickDevice = () => (devicePromise ??= (async () => {
  try { return (await navigator.gpu?.requestAdapter()) ? 'webgpu' : 'wasm'; } catch { return 'wasm'; }
})());

let worker = null;
// Whisper and the LLM are never kept in memory together (iPhone tab memory limit).
function releaseWhisper() { worker?.terminate(); worker = null; }

async function transcribeAudio(pcm) {
  const device = await pickDevice();
  llm.release();
  worker ??= new Worker(new URL('./transcribe-worker.js', import.meta.url), { type: 'module' });
  return new Promise((resolve, reject) => {
    worker.onmessage = ({ data }) => {
      if (data.type === 'download') status(`Descargando modelo (solo la 1ª vez): ${Math.round(data.progress || 0)}%`);
      else if (data.type === 'status') status(data.text);
      else if (data.type === 'done') resolve(data.text);
      else if (data.type === 'error') {
        // A failed runtime can't always re-initialise; start the next job on a fresh worker.
        worker.terminate();
        worker = null;
        devicePromise = Promise.resolve('wasm');
        reject(new Error(`Transcripción: ${data.message}`));
      }
    };
    worker.onerror = (e) => reject(new Error(`Transcripción: ${e.message || 'error del worker'}`));
    worker.postMessage({
      audio: pcm,
      model: settings.model,
      language: LANG_NAMES[settings.language] || 'spanish',
      device,
    }, [pcm.buffer]);
  });
}

async function doTranscribe(id) {
  const rec = getRec(id);
  status('Preparando audio…');
  const blob = await db.getAudio(id);
  const pcm = await decodeTo16kMono(blob);
  status('Cargando Whisper…');
  const t0 = Date.now();
  const text = await transcribeAudio(pcm);
  await updateRec({ ...getRec(id), transcript: text || '(sin voz detectada)' });
  toast(`"${rec.title}" transcrita en ${Math.round((Date.now() - t0) / 1000)} s`);
}

// Titles we generated ourselves; the AI may replace them with a better one.
const AUTO_TITLE = /^(Nota |Notra #|iphone-|Grabación|New Recording|REC|\d)/i;

async function doSummarize(id) {
  const rec = getRec(id);
  if (!rec.transcript) return;
  if (llm.enabled()) {
    releaseWhisper();
    try {
      const { title, summary } = await llm.summarizeTranscript(rec.transcript, status);
      const fresh = getRec(id);
      await updateRec({ ...fresh, summary, title: title && AUTO_TITLE.test(fresh.title) ? title : fresh.title });
      return;
    } catch (e) {
      toast(`${e.message}\nUsando el resumen básico.`, 7000);
    }
  }
  await updateRec({ ...getRec(id), summary: summarize(rec.transcript) });
}

function noteMarkdown(rec) {
  return `# ${rec.title}\n\nFecha: ${fmtDate(rec.createdAt)}\nDuración: ${fmtDur(rec.duration)}\n\n## Resumen\n\n${rec.summary || '_(sin resumen)_'}\n\n## Transcripción\n\n${rec.transcript || '_(sin transcripción)_'}\n`;
}

async function doSync(id) {
  let rec = getRec(id);
  if (!drive.isSignedIn()) throw new Error('Inicia sesión en la pestaña Drive para subir.');
  const d = new Date(rec.createdAt);
  const stamp = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}.${String(d.getMinutes()).padStart(2, '0')}`;
  const base = `${stamp} ${rec.title}`.replace(/[/\\]/g, '-');
  if (!rec.driveAudioId) {
    status('Subiendo audio a Drive…');
    const blob = await db.getAudio(id);
    rec = { ...rec, driveAudioId: await drive.upload(blob, `${base}.${rec.ext}`, rec.mime) };
    await updateRec(rec);
  }
  if (rec.transcript || rec.summary) {
    status('Subiendo nota a Drive…');
    const md = new Blob([noteMarkdown(rec)], { type: 'text/markdown' });
    rec = { ...rec, driveNoteId: await drive.upload(md, `${base}.md`, 'text/markdown', rec.driveNoteId) };
    await updateRec(rec);
  }
}

async function processAll(id) {
  try { await doTranscribe(id); } catch (e) { toast(e.message, 7000); }
  await doSummarize(id);
  if (drive.isSignedIn()) await doSync(id);
}

// ---------------------------------------------------------------- Notes events

const phone = new PhoneRecorder();
let recTimer;

function wireNotes() {
  $('#btn-import').onclick = () => $('#file-input').click();
  $('#file-input').onchange = async (e) => {
    for (const f of e.target.files) {
      await addRecording(f, { title: f.name.replace(/\.[^.]+$/, ''), source: 'imported', ext: extFor(f, f.name) });
    }
    e.target.value = '';
  };
  $('#btn-record').onclick = async () => {
    const btn = $('#btn-record');
    if (phone.isRecording) {
      clearInterval(recTimer);
      btn.classList.remove('recording');
      btn.textContent = '● Grabar';
      status('');
      const blob = await phone.stop();
      await addRecording(blob, { source: 'phone', ext: extFor(blob) });
    } else {
      try {
        await phone.start();
        btn.classList.add('recording');
        btn.textContent = '■ Parar';
        recTimer = setInterval(() => status(`● Grabando ${fmtDur((Date.now() - phone.startedAt) / 1000)}`), 500);
      } catch (e) { toast(`Micrófono: ${e.message}`); }
    }
  };
  $('#search').oninput = (e) => { state.search = e.target.value; renderList(); };
  $('#rec-list').onclick = (e) => { const li = e.target.closest('li[data-id]'); if (li) select(li.dataset.id); };

  $('#detail').addEventListener('click', async (e) => {
    const show = e.target.closest('[data-show]')?.dataset.show;
    if (show && e.target.closest('.seg')) {
      state.showText = show;
      $('.texts').dataset.show = show;
      document.querySelectorAll('.seg button').forEach((b) => b.classList.toggle('on', b.dataset.show === show));
      return;
    }
    const act = e.target.closest('[data-act]')?.dataset.act;
    const id = state.selectedId;
    if (!act || !id || act === 'title') return;
    if (act === 'back') return select(null);
    if (act === 'transcribe') return enqueue(() => doTranscribe(id));
    if (act === 'summarize') return enqueue(() => doSummarize(id));
    if (act === 'sync') return enqueue(() => doSync(id).then(() => toast('Subido a Google Drive')));
    if (act === 'share') return share(id);
    if (act === 'delete' && confirm('¿Borrar esta nota del iPhone? (No se borra de Drive)')) {
      await db.deleteRecording(id);
      state.recordings = state.recordings.filter((r) => r.id !== id);
      select(null);
    }
  });
  $('#detail').addEventListener('change', (e) => {
    if (e.target.dataset.act === 'title' && state.selectedId) {
      updateRec({ ...getRec(state.selectedId), title: e.target.value.trim() || 'Sin título' });
    }
  });
}

async function share(id) {
  const rec = getRec(id);
  const blob = await db.getAudio(id);
  const file = new File([blob], `${rec.title}.${rec.ext}`, { type: rec.mime });
  if (navigator.canShare?.({ files: [file] })) {
    navigator.share({ files: [file], title: rec.title, text: rec.summary || '' }).catch(() => {});
  } else {
    const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(file), download: file.name });
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  }
}

// ---------------------------------------------------------------- Drive tab

async function renderDrive() {
  const signed = drive.isSignedIn();
  $('#drive-signin').hidden = signed;
  $('#drive-signout').hidden = !signed;
  $('#drive-actions').hidden = !signed;
  $('#drive-user').textContent = signed ? (state.driveEmail || 'Conectado') : (settings.clientId ? 'Sin sesión' : 'Falta el Client ID (Ajustes)');
  if (!signed) { $('#drive-list').innerHTML = ''; return; }
  try {
    state.driveEmail ??= await drive.whoAmI();
    $('#drive-user').textContent = state.driveEmail;
    const files = await drive.listFiles();
    const have = new Set(state.recordings.map((r) => r.driveAudioId).filter(Boolean));
    $('#drive-list').innerHTML = files.map((f) => `
      <li>
        <div class="title"><span>${esc(f.name)}</span>
          ${f.mimeType.startsWith('audio/') && !have.has(f.id) ? `<button class="btn" data-pull="${f.id}" data-name="${esc(f.name)}" data-mime="${esc(f.mimeType)}">Traer</button>` : ''}
        </div>
        <div class="meta">${f.createdTime ? fmtDate(f.createdTime) : ''}${f.size ? ` · ${(f.size / 1048576).toFixed(1)} MB` : ''}</div>
      </li>`).join('') || '<li class="meta">La carpeta está vacía.</li>';
  } catch (e) { toast(e.message, 7000); }
}

function wireDrive() {
  $('#drive-signin').onclick = async () => {
    try { await drive.signIn(); state.driveEmail = null; await renderDrive(); } catch (e) { toast(e.message, 7000); }
  };
  $('#drive-signout').onclick = () => { drive.signOut(); state.driveEmail = null; renderDrive(); };
  $('#drive-refresh').onclick = () => renderDrive();
  $('#drive-sync').onclick = () => enqueue(async () => {
    const pending = state.recordings.filter((r) => !r.driveAudioId || ((r.transcript || r.summary) && !r.driveNoteId));
    for (const r of pending) await doSync(r.id);
    toast(pending.length ? `${pending.length} nota(s) subidas` : 'Todo estaba sincronizado');
    renderDrive();
  });
  $('#drive-list').onclick = (e) => {
    const b = e.target.closest('[data-pull]');
    if (!b) return;
    enqueue(async () => {
      status('Descargando de Drive…');
      const blob = await drive.download(b.dataset.pull);
      const typed = new Blob([blob], { type: b.dataset.mime });
      await addRecording(typed, { title: b.dataset.name.replace(/\.[^.]+$/, ''), source: 'drive', ext: extFor(typed, b.dataset.name), driveAudioId: b.dataset.pull });
      renderDrive();
    });
  };
}

// ---------------------------------------------------------------- Recorder (BLE) tab

const bleLog = [];
const recorder = new ble.Recorder((line) => {
  bleLog.push(line);
  if (bleLog.length > 2000) bleLog.shift();
  const el = $('#ble-log');
  el.textContent = bleLog.slice(-300).map(fmtLog).reverse().join('\n');
}, renderBle);

function fmtLog(l) {
  return `${l.t.toLocaleTimeString('es-ES', { hour12: false })}.${String(l.t.getMilliseconds()).padStart(3, '0')} ${l.dir} ${l.uuid ? `[${l.uuid.slice(0, 8)}] ` : ''}${l.text}`;
}

function renderBle() {
  const ok = ble.supported();
  $('#ble-unsupported').hidden = ok;
  $('#ble-panel').hidden = !ok;
  if (!ok) return;
  $('#ble-state').textContent = recorder.connected ? `Conectado: ${recorder.device.name || recorder.device.id}` : 'Desconectado';
  $('#ble-connect').textContent = recorder.connected ? 'Desconectar' : 'Buscar y conectar';
  $('#ble-chars').innerHTML = recorder.chars.map((c) => `
    <div class="c"><div class="mono">${c.uuid}</div><div class="hint">${c.props.join(', ')} · servicio ${c.service.slice(0, 8)}</div>
      <div class="row">
        ${c.props.includes('read') ? `<button class="btn" data-read="${c.uuid}">Leer</button>` : ''}
        ${c.props.some((p) => p.startsWith('write')) ? `<button class="btn" data-setw="${c.uuid}" data-svc="${c.service}">Usar como write</button>` : ''}
        ${c.props.includes('notify') || c.props.includes('indicate') ? `<button class="btn" data-setn="${c.uuid}" data-svc="${c.service}">Usar como notify</button>` : ''}
      </div></div>`).join('');
  const writable = recorder.chars.filter((c) => c.props.some((p) => p.startsWith('write')));
  $('#ble-target').innerHTML = writable.map((c) => `<option value="${c.uuid}" ${c.uuid === ble.fullUUID(settings.profile.writeUUID) ? 'selected' : ''}>${c.uuid}</option>`).join('') || '<option value="">(conecta primero)</option>';
}

function setProfile(patch) {
  saveSettings({ profile: { ...settings.profile, ...patch } });
  $('#set-profile').value = JSON.stringify(settings.profile, null, 2);
  toast('Perfil BLE actualizado');
}

function wireBle() {
  $('#ble-connect').onclick = async () => {
    if (recorder.connected) { recorder.disconnect(); return renderBle(); }
    try { await recorder.connect(); } catch (e) { toast(`Bluetooth: ${e.message}`, 7000); }
    renderBle();
  };
  $('#ble-send').onclick = async () => {
    const bytes = ble.hexToBytes($('#ble-hex').value);
    if (!bytes?.length) return toast('Hex inválido');
    try { await recorder.write($('#ble-target').value, bytes); } catch (e) { toast(e.message); }
  };
  $('#ble-chars').onclick = (e) => {
    const t = e.target;
    if (t.dataset.read) recorder.read(t.dataset.read).catch((err) => toast(err.message));
    if (t.dataset.setw) setProfile({ writeUUID: t.dataset.setw, serviceUUID: settings.profile.serviceUUID || t.dataset.svc });
    if (t.dataset.setn) setProfile({ notifyUUID: t.dataset.setn, serviceUUID: t.dataset.svc });
  };
  $('#ble-clear').onclick = () => { bleLog.length = 0; $('#ble-log').textContent = ''; };
  $('#ble-export').onclick = () => {
    const file = new File([bleLog.map(fmtLog).join('\n')], 'notra-ble-log.txt', { type: 'text/plain' });
    if (navigator.canShare?.({ files: [file] })) navigator.share({ files: [file] }).catch(() => {});
    else Object.assign(document.createElement('a'), { href: URL.createObjectURL(file), download: file.name }).click();
  };
  $('#ble-download').onclick = () => enqueue(async () => {
    const idx = Number($('#ble-index').value) || 0;
    status('Descargando de la grabadora…');
    const { blob, ext, raw } = await recorder.downloadRecording(idx, (n) => {
      $('#ble-progress').textContent = `${Math.round(n / 1024)} KB recibidos`;
      status(`Descargando… ${Math.round(n / 1024)} KB`);
    });
    if (raw) {
      const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: `notra-${idx}.${ext}` });
      a.click();
      toast('Formato aún no soportado: se ha guardado el volcado crudo para analizarlo.', 8000);
      return;
    }
    await addRecording(blob, { title: `Notra #${idx}`, source: 'device', ext });
    toast('Grabación descargada');
  });
}

// ---------------------------------------------------------------- AI tab (ask your notes)

const aiHistory = [];  // [{role, content}] shown in the chat and fed back as context

async function renderAI() {
  const on = llm.enabled();
  $('#ai-off').hidden = on;
  $('#ai-panel').hidden = !on;
  if (on) $('#ai-model').textContent = (await llm.config()).label;
}

function addBubble(role, text) {
  const div = document.createElement('div');
  div.className = `bubble ${role}`;
  div.textContent = text;
  $('#ai-chat').append(div);
  div.scrollIntoView({ block: 'end' });
  return div;
}

function wireAI() {
  $('#ai-preload').onclick = () => enqueue(async () => {
    releaseWhisper();
    await llm.chat(null, { onStatus: status });
    toast('IA lista y guardada en el iPhone');
  });
  $('#ai-form').onsubmit = (e) => {
    e.preventDefault();
    const q = $('#ai-input').value.trim();
    if (!q) return;
    $('#ai-input').value = '';
    addBubble('user', q);
    const bubble = addBubble('assistant', '…');
    enqueue(async () => {
      releaseWhisper();
      let streamed = '';
      try {
        const { text, notes } = await llm.askNotes(q, state.recordings, aiHistory, {
          onStatus: status,
          onToken: (t) => { streamed += t; bubble.textContent = streamed; bubble.scrollIntoView({ block: 'end' }); },
        });
        bubble.textContent = text;
        if (notes.length) {
          const src = document.createElement('div');
          src.className = 'sources';
          src.textContent = `Notas consultadas: ${notes.map((n) => n.title).join(' · ')}`;
          bubble.append(src);
        }
        aiHistory.push({ role: 'user', content: q }, { role: 'assistant', content: text });
      } catch (err) {
        bubble.textContent = `⚠︎ ${err.message}`;
      }
    });
  };
  $('#ai-clear').onclick = () => { aiHistory.length = 0; $('#ai-chat').innerHTML = ''; };
}

// ---------------------------------------------------------------- Settings tab

function renderSettings() {
  $('#set-language').value = settings.language;
  $('#set-model').value = settings.model;
  $('#set-llm').value = settings.llm;
  $('#set-auto').checked = settings.autoProcess;
  $('#set-client').value = settings.clientId;
  $('#set-folder').value = settings.folder;
  $('#set-profile').value = JSON.stringify(settings.profile, null, 2);
}

function wireSettings() {
  $('#set-save').onclick = () => {
    saveSettings({
      language: $('#set-language').value,
      model: $('#set-model').value,
      llm: $('#set-llm').value,
      autoProcess: $('#set-auto').checked,
      clientId: $('#set-client').value.trim(),
      folder: $('#set-folder').value.trim() || 'Boya Notra',
    });
    llm.resetConfig();
    renderAI();
    toast('Ajustes guardados');
  };
  $('#set-profile-save').onclick = () => {
    try { saveSettings({ profile: { ...DEFAULT_PROFILE, ...JSON.parse($('#set-profile').value) } }); toast('Perfil BLE guardado'); renderBle(); } catch (e) { toast(`JSON inválido: ${e.message}`, 7000); }
  };
  $('#set-profile-reset').onclick = () => { if (confirm('¿Restaurar el perfil borrador?')) setProfile(structuredClone(DEFAULT_PROFILE)); };
}

// ---------------------------------------------------------------- Boot

document.querySelectorAll('.tabs button').forEach((b) => { b.onclick = () => switchTab(b.dataset.tab); });
wireNotes();
wireDrive();
wireBle();
wireSettings();
wireAI();
renderSettings();
renderAI();
renderBle();
db.requestPersistence();
reload().catch((e) => toast(`Base de datos: ${e.message}`));

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
