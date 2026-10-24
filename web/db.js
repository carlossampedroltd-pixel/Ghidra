// Local library in IndexedDB: recording metadata + audio blobs.
const DB_NAME = 'notrafree';
let dbPromise;

function open() {
  dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      req.result.createObjectStore('recordings', { keyPath: 'id' });
      req.result.createObjectStore('audio');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

async function tx(store, mode, fn) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, mode);
    const result = fn(t.objectStore(store));
    t.oncomplete = () => resolve(result?.result ?? result);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

export async function listRecordings() {
  const all = await tx('recordings', 'readonly', (s) => s.getAll());
  return all.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export const putRecording = (rec) => tx('recordings', 'readwrite', (s) => { s.put(rec); });
export const getAudio = (id) => tx('audio', 'readonly', (s) => s.get(id));
export const putAudio = (id, blob) => tx('audio', 'readwrite', (s) => { s.put(blob, id); });

export async function deleteRecording(id) {
  await tx('recordings', 'readwrite', (s) => { s.delete(id); });
  await tx('audio', 'readwrite', (s) => { s.delete(id); });
}

// Ask Safari not to evict the library under storage pressure.
export function requestPersistence() {
  navigator.storage?.persist?.().catch(() => {});
}
