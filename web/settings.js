// User settings, persisted in localStorage. The BLE profile uses the same JSON
// format as the iOS app (DeviceProfile.swift), so a profile works in both.

export const DEFAULT_PROFILE = {
  name: 'Boya Notra NEO (borrador)',
  namePrefixes: ['NOTRA', 'Notra', 'BOYA', 'BY-'],
  serviceUUID: null,
  exploreServiceUUIDs: [],
  writeUUID: null,
  notifyUUID: null,
  writeWithResponse: false,
  listCommandHex: null,
  downloadCommandHex: null,
  ackCommandHex: null,
  endOfTransferHex: null,
  headerBytesPerPacket: 0,
  idleTimeout: 3,
  audioFormat: 'rawFile',
  fileExtension: 'wav',
  sampleRate: 16000,
  channels: 1,
};

const DEFAULTS = {
  clientId: '',
  folder: 'Boya Notra',
  language: 'es',
  model: 'onnx-community/whisper-base',
  llm: 'medium',              // local AI: 'off' | 'small' (0.5B) | 'medium' (1.5B, GPU only)
  autoProcess: true,
  profile: DEFAULT_PROFILE,
};

const KEY = 'notrafree.settings';

function load() {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
    return { ...DEFAULTS, ...saved, profile: { ...DEFAULT_PROFILE, ...(saved.profile || {}) } };
  } catch {
    return structuredClone(DEFAULTS);
  }
}

export const settings = load();

export function saveSettings(patch) {
  Object.assign(settings, patch);
  try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch { /* private mode */ }
}
