// Google Drive from the browser: Google Identity Services token client + Drive v3 REST.
// Scope drive.file: the app only sees files it created. No server involved.
import { settings } from './settings.js';

const SCOPE = 'https://www.googleapis.com/auth/drive.file';
const TOKEN_KEY = 'notrafree.driveToken';
let tokenClient = null;
let folderId = null;
let folderIdFor = '';

function savedToken() {
  try {
    const t = JSON.parse(sessionStorage.getItem(TOKEN_KEY) || 'null');
    return t && t.expiresAt > Date.now() + 60_000 ? t : null;
  } catch { return null; }
}

export const isSignedIn = () => !!savedToken();

function waitForGis() {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    (function poll() {
      if (window.google?.accounts?.oauth2) return resolve();
      if (Date.now() - started > 10_000) return reject(new Error('No se pudo cargar Google Sign-In.'));
      setTimeout(poll, 100);
    })();
  });
}

/** Opens the Google consent popup (must be called from a tap). */
export async function signIn({ silent = false } = {}) {
  if (!settings.clientId) throw new Error('Configura el Client ID de Google en Ajustes.');
  await waitForGis();
  return new Promise((resolve, reject) => {
    tokenClient = google.accounts.oauth2.initTokenClient({
      client_id: settings.clientId,
      scope: SCOPE,
      callback: (resp) => {
        if (resp.error) return reject(new Error(resp.error_description || resp.error));
        const t = { token: resp.access_token, expiresAt: Date.now() + resp.expires_in * 1000 };
        try { sessionStorage.setItem(TOKEN_KEY, JSON.stringify(t)); } catch { /* ignore */ }
        resolve(t);
      },
      error_callback: (e) => reject(new Error(e?.message || e?.type || 'Inicio de sesión cancelado')),
    });
    tokenClient.requestAccessToken({ prompt: silent ? '' : undefined });
  });
}

export function signOut() {
  const t = savedToken();
  if (t && window.google?.accounts?.oauth2) google.accounts.oauth2.revoke(t.token, () => {});
  try { sessionStorage.removeItem(TOKEN_KEY); } catch { /* ignore */ }
  folderId = null;
}

async function api(url, init = {}) {
  const t = savedToken();
  if (!t) throw new Error('Sesión de Google caducada: vuelve a iniciar sesión en la pestaña Drive.');
  const resp = await fetch(url, { ...init, headers: { ...(init.headers || {}), Authorization: `Bearer ${t.token}` } });
  if (!resp.ok) throw new Error(`Drive ${resp.status}: ${(await resp.text()).slice(0, 300)}`);
  return resp;
}

export async function whoAmI() {
  const r = await api('https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)');
  return (await r.json()).user?.emailAddress;
}

async function ensureFolder() {
  if (folderId && folderIdFor === settings.folder) return folderId;
  const q = `name = '${settings.folder.replace(/'/g, "\\'")}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
  const r = await api(`https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(q)}&fields=files(id)`);
  const found = (await r.json()).files?.[0];
  if (found) {
    folderId = found.id;
  } else {
    const c = await api('https://www.googleapis.com/drive/v3/files?fields=id', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: settings.folder, mimeType: 'application/vnd.google-apps.folder' }),
    });
    folderId = (await c.json()).id;
  }
  folderIdFor = settings.folder;
  return folderId;
}

/** Creates a file in the folder, or replaces the content of `existingId`. Returns the id. */
export async function upload(blob, name, mimeType, existingId) {
  const meta = { name };
  if (!existingId) meta.parents = [await ensureFolder()];
  const boundary = `notra-${crypto.randomUUID()}`;
  const body = new Blob([
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(meta)}\r\n`,
    `--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`,
    blob,
    `\r\n--${boundary}--\r\n`,
  ]);
  const base = existingId
    ? `https://www.googleapis.com/upload/drive/v3/files/${existingId}`
    : 'https://www.googleapis.com/upload/drive/v3/files';
  const r = await api(`${base}?uploadType=multipart&fields=id`, {
    method: existingId ? 'PATCH' : 'POST',
    headers: { 'Content-Type': `multipart/related; boundary=${boundary}` },
    body,
  });
  return (await r.json()).id;
}

export async function listFiles() {
  const folder = await ensureFolder();
  const q = `'${folder}' in parents and trashed = false`;
  const r = await api(`https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(q)}&orderBy=createdTime desc&pageSize=200&fields=files(id,name,mimeType,createdTime,size)`);
  return (await r.json()).files || [];
}

export async function download(id) {
  const r = await api(`https://www.googleapis.com/drive/v3/files/${id}?alt=media`);
  return r.blob();
}
