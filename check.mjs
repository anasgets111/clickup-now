/* Evaluates app.js against a stub DOM. `node --check` only parses — it cannot see a
   temporal dead zone, a missing element, or anything else that throws at module
   evaluation. This actually runs the top level. */
const listeners = [];
const el = (id) => ({
  id,
  hidden: false,
  dataset: {},
  style: { setProperty() {} },
  classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
  set innerHTML(v) { this._html = v; },
  get innerHTML() { return this._html ?? ''; },
  textContent: '',
  value: '',
  checked: false,
  files: [],
  addEventListener: (type) => listeners.push(`${id}:${type}`),
  querySelector: () => null,
  querySelectorAll: () => [],
  closest: () => null,
  append() {},
  insertAdjacentHTML() {},
  focus() {},
  remove() {},
});

const nodes = new Map();
const get = (sel) => {
  const id = sel.replace(/^#/, '');
  if (!nodes.has(id)) nodes.set(id, el(id));
  return nodes.get(id);
};

globalThis.document = {
  hidden: false,
  querySelector: (sel) => (sel.startsWith('#') ? get(sel) : null),
  querySelectorAll: () => [],
  addEventListener: (type) => listeners.push(`document:${type}`),
};
globalThis.window = globalThis;
globalThis.localStorage = { getItem: () => null, setItem() {}, removeItem() {} };
globalThis.setInterval = () => 0;
globalThis.location = { reload() {} };

// Boot fetches /user then /team; fail them so the module takes its error path and stops.
globalThis.fetch = async () => ({ ok: false, status: 503, text: async () => 'stub' });

const url = new URL('./public/app.js', import.meta.url).href;
try {
  await import(url);
  console.log('module evaluated without throwing');
  console.log('listeners registered:', listeners.length);
  console.log('  ' + listeners.join('\n  '));
  console.log('window.now exposed:', typeof globalThis.now === 'object');
} catch (err) {
  console.log('MODULE THREW AT EVALUATION:', err.constructor.name);
  console.log('  ' + err.message);
  process.exit(1);
}
