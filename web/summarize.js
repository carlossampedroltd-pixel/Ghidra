// Free, offline summary: frequency-scored key sentences plus detected action items.
// No model download and no API: good enough to skim a recording.

export const STOP = new Set(`a al algo algunas algunos ante antes como con contra cual cuando de del desde donde
durante e el ella ellas ellos en entre era es esa esas ese eso esos esta estaba estado estamos estan
estar este esto estos fue fueron ha hay la las le les lo los mas me mi mis mucho muy nada ni no nos
o os otra otro para pero poco por porque que quien se sea ser si sido sin sobre son su sus tambien
te tiene tienen todo todos tu un una uno unos y ya yo vale bueno pues entonces osea eh
hoy hemos he han has va vamos voy era fue ser sera mas
the a an and or but if of to in on at for with is are was were be been it this that these those i you
he she we they so just like yeah okay um uh what your you my me not can do our us there here from have has had will would`.split(/\s+/));

const ACTION = /\b(hay que|tengo que|tenemos que|tienes que|debemos|deber[ií]a|pendiente|recordar|recu[eé]rda|no olvid|enviar|mandar|llamar|revisar|preparar|need to|have to|should|todo|follow up|remember)\b/i;

export const norm = (w) => w.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9ñ]/g, '');

export function summarize(text) {
  const sentences = text
    .replace(/\s+/g, ' ')
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter((s) => s.split(' ').length >= 5);
  if (!sentences.length) return text.trim();

  const freq = new Map();
  for (const s of sentences) {
    for (const w of s.split(' ').map(norm)) {
      if (w.length > 2 && !STOP.has(w)) freq.set(w, (freq.get(w) || 0) + 1);
    }
  }
  const score = (s) => {
    const words = s.split(' ').map(norm).filter((w) => w.length > 2 && !STOP.has(w));
    return words.reduce((n, w) => n + (freq.get(w) || 0), 0) / Math.max(4, words.length);
  };

  const keep = Math.min(6, Math.max(2, Math.round(sentences.length / 8)));
  const key = sentences
    .map((s, i) => ({ s, i, v: score(s) }))
    .sort((a, b) => b.v - a.v)
    .slice(0, keep)
    .sort((a, b) => a.i - b.i)
    .map((x) => `• ${x.s}`);

  const topics = [...freq.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6).map(([w]) => w);
  const actions = sentences.filter((s) => ACTION.test(s)).slice(0, 8).map((s) => `☐ ${s}`);

  return [
    `Temas: ${topics.join(', ')}`,
    '',
    'Puntos clave:',
    ...key,
    ...(actions.length ? ['', 'Tareas:', ...actions] : []),
  ].join('\n');
}
