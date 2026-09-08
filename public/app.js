const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

async function api(path, opts) {
  const r = await fetch('/api' + path, { headers: { 'content-type': 'application/json' }, ...opts });
  if (!r.ok) throw new Error(`ClickUp said ${r.status}`);
  return r.json();
}

// No content-type: the browser must set multipart itself so the boundary matches.
async function upload(path, form) {
  const r = await fetch('/api' + path, { method: 'POST', body: form });
  if (!r.ok) throw new Error(`ClickUp said ${r.status}`);
  return r.json();
}

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const low = (s) => String(s).toLowerCase();

// ClickUp stores names already HTML-escaped — a task really does come back as
// "testimonials &amp; partners". Escaping that again renders the entity literally,
// so decode once first. Names sent BACK to the API (status values) must stay raw.
const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
const unent = (s) => String(s ?? '').replace(/&(?:#(\d+)|#x([\da-f]+)|(\w+));/gi,
  (m, dec, hex, word) => dec ? String.fromCharCode(+dec)
    : hex ? String.fromCharCode(parseInt(hex, 16))
    : ENT[low(word)] ?? m);
const txt = (s) => esc(unent(s));

/* ── markdown ────────────────────────────────────────────────────────
   A subset renderer for what ClickUp descriptions actually contain:
   headings, fenced code, tables, lists, blockquotes, and inline
   bold/italic/code/strike/links.

   Everything is escaped before a single rule runs, so raw HTML in a
   description (ClickUp does emit some) renders as visible text and can
   never execute. That is what makes this safe without a sanitiser.

   ponytail: lists are flat. Nested bullets render at one level. If a
   spec needs real nesting, track indent on a stack in md(). */

function inline(t, keep) {
  const hold = (s) => `\u0000${keep.push(s) - 1}\u0000`;
  return t
    .replace(/`([^`\n]+)`/g, (_, c) => hold(`<code>${c}</code>`))
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer">$1</a>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/~~([^~]+)~~/g, '<del>$1</del>')
    .replace(/(^|[^\w*])\*([^*\n]+)\*(?!\*)/g, '$1<em>$2</em>')
    .replace(/(^|[^\w_])_([^_\n]+)_(?!\w)/g, '$1<em>$2</em>');
}

const cells = (ln) => ln.trim().replace(/^\||\|$/g, '').split('|');

function md(src) {
  const keep = [];
  const lines = esc(src).replace(/\r/g, '').split('\n');
  const out = [];
  let i = 0;

  while (i < lines.length) {
    const ln = lines[i];

    if (/^\s*```/.test(ln)) {
      const body = [];
      for (i++; i < lines.length && !/^\s*```/.test(lines[i]); i++) body.push(lines[i]);
      i++;
      out.push(`<pre><code>${body.join('\n')}</code></pre>`);
    } else if (/^\s*\|/.test(ln) && /^\s*\|[\s:|-]+\|?\s*$/.test(lines[i + 1] ?? '')) {
      const head = cells(ln);
      i += 2;
      const body = [];
      for (; i < lines.length && /^\s*\|/.test(lines[i]); i++) body.push(cells(lines[i]));
      out.push(`<div class="scroll"><table><thead><tr>${
        head.map((c) => `<th>${inline(c.trim(), keep)}</th>`).join('')}</tr></thead><tbody>${
        body.map((r) => `<tr>${r.map((c) => `<td>${inline(c.trim(), keep)}</td>`).join('')}</tr>`).join('')
      }</tbody></table></div>`);
    } else if (/^\s*(?:[-*+]|\d+\.)\s/.test(ln)) {
      const tag = /^\s*\d+\./.test(ln) ? 'ol' : 'ul';
      const items = [];
      for (; i < lines.length && /^\s*(?:[-*+]|\d+\.)\s/.test(lines[i]); i++) {
        const t = lines[i].replace(/^\s*(?:[-*+]|\d+\.)\s+/, '');
        const box = t.match(/^\[([ xX])\]\s*(.*)$/);
        items.push(box
          ? `<li class="tick"><input type="checkbox" disabled ${box[1] === ' ' ? '' : 'checked'}>${inline(box[2], keep)}</li>`
          : `<li>${inline(t, keep)}</li>`);
      }
      out.push(`<${tag}>${items.join('')}</${tag}>`);
    } else if (/^\s*#{1,6}\s/.test(ln)) {
      const n = Math.min(ln.match(/^\s*(#+)/)[1].length + 1, 6);
      out.push(`<h${n}>${inline(ln.replace(/^\s*#+\s+/, ''), keep)}</h${n}>`);
      i++;
    } else if (/^\s*>\s?/.test(ln)) {
      const body = [];
      for (; i < lines.length && /^\s*>\s?/.test(lines[i]); i++) body.push(lines[i].replace(/^\s*>\s?/, ''));
      out.push(`<blockquote>${inline(body.join(' '), keep)}</blockquote>`);
    } else if (/^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(ln)) {
      out.push('<hr>');
      i++;
    } else if (!ln.trim()) {
      i++;
    } else {
      // Takes the current line unconditionally. Consuming it inside the loop instead
      // would spin forever on a line that starts a block but matched no rule above —
      // a `|` row with no separator under it, a bare `--`, a `#tag` with no space.
      const body = [lines[i++]];
      for (; i < lines.length && lines[i].trim() && !/^\s*(?:[-*+>#]|\d+\.|\||```)/.test(lines[i]); i++) body.push(lines[i]);
      out.push(`<p>${inline(body.join(' '), keep)}</p>`);
    }
  }

  return out.join('').replace(/\u0000(\d+)\u0000/g, (_, n) => keep[n]);
}

/* ── Catppuccin Mocha ────────────────────────────────────────────────
   ClickUp status colours come from ClickUp's own palette and clash badly
   with Mocha, so snap each one to its nearest accent by hue. Anything
   near-grey stays grey rather than picking up a hue it never had. */

// Rosewater, flamingo and maroon are left out on purpose. They crowd the hues around
// red without being tellable apart from it, so they only steal true reds. What is left
// is the set a person can actually distinguish at pip size.
const MOCHA = ['#f38ba8', '#fab387', '#f9e2af', '#a6e3a1', '#94e2d5', '#89dceb',
  '#74c7ec', '#89b4fa', '#b4befe', '#cba6f7', '#f5c2e7'];

function hsl(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), span = max - min;
  const l = (max + min) / 2;
  if (!span) return { h: 0, s: 0, l };
  const h = max === r ? ((g - b) / span + (g < b ? 6 : 0)) : max === g ? (b - r) / span + 2 : (r - g) / span + 4;
  return { h: h * 60, s: span / (1 - Math.abs(2 * l - 1)), l };
}

const HUES = MOCHA.map((c) => ({ c, h: hsl(c).h }));
const snapped = new Map();

function snap(hex) {
  if (!/^#[0-9a-f]{6}$/i.test(hex ?? '')) return '#7f849c';
  if (!snapped.has(hex)) {
    const { h, s, l } = hsl(hex);
    // Mocha's accents all sit at one lightness and differ only in hue, so match on
    // hue alone. RGB distance would drag every dark saturated colour onto a grey.
    const near = HUES.reduce((best, x) => {
      const d = Math.min(Math.abs(x.h - h), 360 - Math.abs(x.h - h));
      return d < best.d ? { c: x.c, d } : best;
    }, { c: '#7f849c', d: Infinity }).c;
    snapped.set(hex, s < 0.18 ? (l > 0.6 ? '#9399b2' : '#7f849c') : near);
  }
  return snapped.get(hex);
}

/* ── time ───────────────────────────────────────────────────────── */

const rel = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
const daysOut = (ms) => Math.round((new Date(Number(ms)).setHours(0, 0, 0, 0) - new Date().setHours(0, 0, 0, 0)) / 864e5);

function due(ms) {
  const d = daysOut(ms);
  if (d < -1 || d > 6) return new Date(Number(ms)).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  if (Math.abs(d) <= 1) return rel.format(d, 'day');
  return new Date(Number(ms)).toLocaleDateString(undefined, { weekday: 'long' });
}

function ago(ms) {
  const mins = Math.round((Number(ms) - Date.now()) / 6e4);
  if (Math.abs(mins) < 60) return rel.format(mins, 'minute');
  if (Math.abs(mins) < 1440) return rel.format(Math.round(mins / 60), 'hour');
  return rel.format(Math.round(mins / 1440), 'day');
}

function clocked(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(s / 3600)}:${String(Math.floor(s / 60) % 60).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

const size = (b) => b > 1e6 ? `${(b / 1e6).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1e3))} KB`;

const PRIOS = [
  { id: 1, name: 'urgent', c: '#f38ba8' },
  { id: 2, name: 'high', c: '#fab387' },
  { id: 3, name: 'normal', c: '#89b4fa' },
  { id: 4, name: 'low', c: '#7f849c' },
];

const shut = (t) => t.status.type === 'done' || t.status.type === 'closed';

/* Custom fields. Every task carries an entry for every field on its list, nearly all
   of them empty, so the only interesting ones are those with a value. Drop-downs store
   an index into their own options; numbers arrive as strings. Types this cannot render
   as a short string (labels, users, relationships) are skipped rather than guessed at. */
function fieldText(f) {
  const v = f.value;
  if (v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length)) return null;
  if (f.type === 'drop_down') {
    const opts = f.type_config?.options ?? [];
    return (opts.find((o) => o.orderindex === v) ?? opts[v])?.name ?? null;
  }
  if (f.type === 'checkbox') return v === true || v === 'true' ? 'yes' : null;
  if (f.type === 'date') return due(v);
  if (typeof v === 'object') return null;
  return String(v);
}

const pct = (done, total) => `${Math.round((done / total) * 100)}%`;

const fieldsOn = (t) => (t.custom_fields ?? []).map((f) => [f, fieldText(f)]).filter(([, v]) => v);

/* ponytail: a workspace convention, not an API concept. Arsel tracks stoppages in a
   field called "Blocked Reason"; anything named like it, with something written in it,
   means the task is stuck. Rename the field and this stops noticing. */
const blockedBy = (t) => (t.custom_fields ?? []).find((f) => /block/i.test(f.name) && fieldText(f));

/* ── state ──────────────────────────────────────────────────────── */

let me, teamId, tasks = [], watched = [], picked = null, fresher = null, timer = null, ctx = null;
let seen = new Map();
let pins = JSON.parse(localStorage.getItem('pins') ?? '[]');
const pool = new Map();          // pinned list id -> its tasks
const lists = new Map();
const notes = new Map();
const bodies = new Map();

const everything = () => [...tasks, ...[...pool.values()].flat(), ...watched];
const byId = (id) => everything().find((t) => t.id === id);

/* Overdue first, then priority, then date. Sorting on date first read well in theory
   but not here: almost nothing in this workspace carries a due date, so everything tied
   on the sentinel and fell through to priority anyway. Priority is the real signal —
   it is set on most tasks — so it leads, and a genuinely late task still jumps it. */
const late = (t) => Boolean(t.due_date) && Number(t.due_date) < Date.now();
const byUrgency = (a, b) =>
  Number(late(b)) - Number(late(a)) ||
  Number(a.priority?.id ?? 9) - Number(b.priority?.id ?? 9) ||
  (a.due_date ? Number(a.due_date) : 9e15) - (b.due_date ? Number(b.due_date) : 9e15);

/* ── rail ───────────────────────────────────────────────────────── */

/* `full` adds what will not fit in a 22rem rail row: tags, estimate, who else is on
   it, when it last moved. The rail gets the short form, the open task the long one. */
function metaOf(t, full = false) {
  const where = t.folder && !t.folder.hidden ? `${t.folder.name}/${t.list.name}` : t.list.name;
  const p = t.priority && PRIOS.find((x) => x.name === t.priority.priority);
  const others = t.assignees.filter((a) => String(a.id) !== String(me.id));
  const moved = Date.now() - Number(t.date_updated) < 864e5;
  return `<span class="meta">
    <span class="st">${txt(low(t.status.status))}</span>
    <span class="where">${txt(where)}</span>
    ${t.due_date ? `<span class="${late(t) ? 'late' : 'when'}">${esc(due(t.due_date))}</span>` : ''}
    ${p && p.id < 3 ? `<span class="prio" style="--p:${p.c}">&#9873; ${p.name}</span>` : ''}
    ${blockedBy(t) ? '<span class="stuck">blocked</span>' : ''}
    ${full && t.time_estimate ? `<span class="est">${Math.round(t.time_estimate / 36e5)}h est</span>` : ''}
    ${full && others.length ? `<span>with ${others.map((a) =>
      `<b class="who" style="--w:${snap(a.color)}">${txt(a.username)}</b>`).join(', ')}</span>` : ''}
    ${full ? `<span class="${moved ? 'warm' : 'cold'}">${esc(ago(t.date_updated))}</span>` : ''}
    ${full ? t.tags.map((g) => `<span class="tag" style="background:${esc(g.tag_bg)};color:${esc(g.tag_fg)}">${txt(g.name)}</span>`).join('') : ''}
  </span>`;
}

const rowOf = (t) => `<button class="row${t.id === picked ? ' on' : ''}" style="--c:${snap(t.status.color)}" data-id="${esc(t.id)}">
  <span class="name">${t.parent ? '<span class="sub-of">&#8627; </span>' : ''}${txt(t.name)}</span>
  ${metaOf(t)}</button>`;

function renderRail() {
  const q = low($('#q').value.trim());
  const hit = (t) => !q || [t.name, t.list.name, t.folder?.name, ...t.tags.map((g) => g.name)]
    .some((s) => s && low(unent(s)).includes(q));

  const mine = tasks.filter(hit).sort(byUrgency);
  const groups = [
    { label: 'in flight', list: mine.filter((t) => t.status.type === 'custom') },
    { label: q ? 'matching' : 'mine', list: mine.filter((t) => t.status.type !== 'custom') },
  ];
  // Each group claims its tasks, then adds them to `already` so later groups do not
  // repeat them. Claiming has to come first: adding a pin's tasks before filtering that
  // same pin excluded every one of them, and a pinned list rendered empty.
  const already = new Set(mine.map((t) => t.id));
  const claim = (from) => {
    const got = from.filter((t) => !already.has(t.id) && hit(t)).sort(byUrgency);
    for (const t of got) already.add(t.id);
    return got;
  };

  for (const p of pins) groups.push({ label: p.name, pin: p.id, list: claim(pool.get(p.id) ?? []) });
  if (watched.length) groups.push({ label: 'watching, this week', list: claim(watched) });

  const parts = groups.filter((g) => g.list.length || g.pin).map((g) => `<div class="group">
    <p class="label">${txt(g.label)} <b>${g.list.length}</b>
      ${g.pin ? `<button class="unpin" data-unpin="${esc(g.pin)}" title="Stop showing this list">&times;</button>` : ''}</p>
    ${g.list.map(rowOf).join('') || '<p class="quiet">nothing here</p>'}</div>`);

  $('#rail').innerHTML = parts.join('') || '<p class="quiet">Nothing on you right now.</p>';
}

/* "late" and "today" sat here reading zero forever, because tasks in this workspace
   rarely carry a due date. These three are always true of the data; late still appears,
   but only when there is something to say. */
function stats() {
  const overdue = tasks.filter(late).length;
  const flight = tasks.filter((t) => t.status.type === 'custom').length;
  const stuck = tasks.filter(blockedBy).length;
  $('#stats').innerHTML = `
    <span class="c-open"><i>&#9679;</i>${tasks.filter((t) => !shut(t)).length} open</span>
    <span class="c-flight"><i>&#9680;</i>${flight} in flight</span>
    <span class="c-stuck"><i>&#8709;</i>${stuck} blocked</span>
    ${overdue ? `<span class="c-late"><i>&#9650;</i>${overdue} late</span>` : ''}`;
}

/* ── stage ──────────────────────────────────────────────────────── */

// Caches hold the promise, not the result, so two callers racing the same id share
// one request instead of firing two.
function once(map, key, make) {
  if (!map.has(key)) map.set(key, make());
  return map.get(key);
}

const listOf = (id) => once(lists, id, () => api(`/list/${id}`));
const notesOf = (id) => once(notes, id, () => api(`/task/${id}/comment`));
// The list endpoint flattens markdown away — description and text_content come back
// identical and stripped. markdown_description only exists on the single-task fetch.
const bodyOf = (id) => once(bodies, id, () => api(`/task/${id}?include_markdown_description=true&include_subtasks=true`));

/* ClickUp answers an update with the whole task — every field the full fetch carries
   except markdown_description, subtasks and attachments included. So an edit needs one
   request, not five: this used to PUT, then reload the workspace, then let adopt() clear
   the caches, which made the next render refetch the list, the comments and the 51KB
   task again. Merging the reply costs nothing. */
async function patch(task, body) {
  const updated = await api(`/task/${task.id}`, { method: 'PUT', body: JSON.stringify(body) });

  Object.assign(task, updated);          // the object the rail and the stage render from
  seen.set(task.id, updated.date_updated); // or the next poll reports your own edit back

  if (bodies.has(task.id)) {
    const held = await bodies.get(task.id);
    // The reply omits markdown_description, so keep the copy we hold — unless this edit
    // is what changed it, in which case what we sent is the truth.
    const merged = { ...held, ...updated };
    if (body.markdown_content !== undefined) merged.markdown_description = body.markdown_content;
    bodies.set(task.id, Promise.resolve(merged));
  }

  stats();
  renderRail();
  await renderStage();
}

async function renderStage() {
  const stage = $('#stage');
  const task = byId(picked);
  if (!task) { stage.innerHTML = '<p class="quiet">Pick something on the left.</p>'; return; }

  const warm = lists.has(task.list.id) && notes.has(task.id) && bodies.has(task.id);
  if (!warm) stage.innerHTML = '<p class="label">opening</p>';
  let list, said, full;
  try {
    [list, said, full] = await Promise.all([listOf(task.list.id), notesOf(task.id), bodyOf(task.id)]);
  } catch (err) {
    stage.innerHTML = `<p class="err">${esc(err.message)}</p>`;
    return;
  }
  if (picked !== task.id) return;   // something else was clicked while we waited

  // ponytail: subtasks carry no list of their own in this payload, so they are assumed
  // to share the parent's list — true for every subtask ClickUp lets you create today.
  const kids = full.subtasks ?? [];
  const done = kids.filter(shut).length;
  const shutStatus = list.statuses.find((s) => s.type === 'done') ?? list.statuses.at(-1);
  const openStatus = list.statuses.find((s) => s.type === 'open') ?? list.statuses[0];
  const files = full.attachments ?? [];
  const src = full.markdown_description ?? '';
  const stuck = blockedBy(full);
  const fields = fieldsOn(full).filter(([f]) => f !== stuck);
  const running = timer?.task?.id === task.id;

  // Local date parts, not toISOString — that shifts to UTC and can show the wrong day.
  const d = task.due_date && new Date(Number(task.due_date));
  const dueVal = d ? `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` : '';

  /* Two children, two columns: everything you read and write on the left at the
     reading measure, the short controls on the right. Below 1400px they stack and it
     is the same page it always was. */
  stage.innerHTML = `
    <div class="col">
      <textarea id="title" rows="1" spellcheck="false" aria-label="Task name">${txt(task.name)}</textarea>
      <div class="crumb" style="--c:${snap(task.status.color)}">${metaOf(task, true)}
        <button id="tick" class="${running ? 'go' : ''}">${running ? 'stop' : 'start'} timer</button>
        ${full.time_spent ? `<span class="spent">${clocked(full.time_spent)} logged</span>` : ''}
      </div>

      ${stuck ? `<p class="stuck-note"><b>blocked</b>${txt(fieldText(stuck))}</p>` : ''}

      <div id="body"></div>

      ${kids.length ? `<div class="kids">
        <em>${done} of ${kids.length} done</em>
        <div class="gauge"><i style="width:${pct(done, kids.length)}"></i></div>
        <ul>${kids.map((k) => `<li style="--c:${snap(k.status.color)}">
          <input type="checkbox" data-kid="${esc(k.id)}" ${shut(k) ? 'checked' : ''}>
          <a href="${esc(k.url)}" target="_blank" rel="noreferrer">${txt(k.name)}</a>
          ${k.status.type === 'custom' ? `<span class="st">${txt(low(k.status.status))}</span>` : ''}
          </li>`).join('')}</ul></div>` : ''}

      <ul class="notes">${said.comments.slice(0, 6).map((c) => `
        <li><em>${txt(c.user?.username ?? 'someone')} &nbsp; ${esc(ago(c.date))}</em>
        <p>${txt(c.comment_text)}</p></li>`).join('')}</ul>

      <form class="say"><input name="text" placeholder="Add an update" autocomplete="off"><button>post</button></form>

      <div class="foot">
        <span>created ${esc(ago(task.date_created))}</span>
        <a class="link" href="${esc(task.url)}" target="_blank" rel="noreferrer">open in clickup</a>
      </div>
    </div>

    <aside class="props">
      <div class="field"><em>status</em><div class="chips">${list.statuses.map((s) => `
        <button class="chip" data-do="status" data-v="${esc(s.status)}" style="--c:${snap(s.color)}"
          aria-current="${s.status === task.status.status}">${txt(low(s.status))}</button>`).join('')}</div></div>

      <div class="field"><em>priority</em><div class="chips">${PRIOS.map((p) => `
        <button class="chip" data-do="priority" data-v="${p.id}" style="--c:${p.c}"
          aria-current="${task.priority?.priority === p.name}">${p.name}</button>`).join('')}
        <button class="chip" data-do="priority" data-v="" style="--c:var(--overlay1)"
          aria-current="${!task.priority}">none</button></div></div>

      <div class="field"><em>due</em><div class="chips">
        <input type="date" value="${dueVal}">
        <button class="chip" data-do="due" data-v="today" style="--c:var(--overlay1)">today</button>
        <button class="chip" data-do="due" data-v="" style="--c:var(--overlay1)" ${dueVal ? '' : 'disabled'}>clear</button>
      </div></div>

      ${fields.length ? `<div class="field"><em>fields</em><div class="chips">${fields.map(([f, v]) => `
        <span class="pill">${txt(f.name)}<b>${txt(v)}</b></span>`).join('')}</div></div>` : ''}

      <div class="field"><em>files</em><div class="chips">
        ${files.map((f) => `<a class="file" href="${esc(f.url)}" target="_blank" rel="noreferrer">
          ${txt(f.title)} <span>${esc(size(Number(f.size) || 0))}</span></a>`).join('')}
        <label class="file add">add<input type="file" id="drop" multiple hidden></label>
      </div></div>
    </aside>`;

  showBody(src);
  fit($('#title'));
  ctx = { task, list, kids, shutStatus, openStatus, src };
}

/* A task name is a heading, so it has to wrap at the reading measure like everything
   else on the stage. An <input> would have scrolled sideways instead, and names here run
   past 50 characters. */
const fit = (el, cap = Infinity) => {
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight + 2, cap)}px`;
};

/* Description: rendered by default, raw markdown when editing. Kept in one place so
   the two states can never drift apart. */
function showBody(src, editing = false) {
  const el = $('#body');
  if (!el) return;
  if (editing) {
    el.innerHTML = `<textarea class="src" spellcheck="false">${esc(src)}</textarea>
      <div class="row-actions"><button class="chip" id="save" style="--c:var(--green)">save</button>
      <button class="chip" id="drop-edit" style="--c:var(--overlay1)">cancel</button></div>`;
    const ta = el.querySelector('.src');
    fit(ta, 600);
    ta.focus();
    return;
  }
  el.innerHTML = src.trim()
    ? `<div class="doc"><div class="desc">${md(src)}</div>
       <div class="row-actions"><button class="more" hidden>show all</button><button class="edit">edit</button></div></div>`
    : `<div class="row-actions"><button class="edit">add a description</button></div>`;
  const desc = el.querySelector('.desc');
  const more = el.querySelector('.more');
  // Only offer the toggle when there is actually something hidden behind the fade.
  if (desc && more && desc.scrollHeight > desc.clientHeight + 4) {
    more.hidden = false;
    desc.classList.add('clipped');
  }
}

/* Listeners are delegated and registered once. Binding them inside renderStage would
   stack a new handler on #stage for every task opened, so one chip click would fire
   as many updates as tasks you had viewed. `ctx` carries what the open task needs. */

/* Shows a button as working, and puts its label back if the call fails — otherwise a
   failed update leaves an ellipsis sitting there for good. */
async function busy(b, run, what) {
  const was = b.textContent;
  b.textContent = '…';
  b.disabled = true;
  try { await run(); } catch (err) { fail(err, what); b.textContent = was; b.disabled = false; }
}

/* The non-button counterpart to busy(): every edit here is "do it, or say what did not
   change". */
const tryTo = (what, run) => run().catch((err) => fail(err, what));

function fail(err, what) {
  // One error line at a time; repeated failures used to pile up until the next render.
  $('#stage .err')?.remove();
  $('#stage').insertAdjacentHTML('beforeend', `<p class="err">${esc(err.message)} &mdash; ${what}</p>`);
}

$('#stage').addEventListener('click', async (e) => {
  const b = e.target.closest('button');
  if (!b || !ctx) return;
  const { task, src } = ctx;

  if (b.classList.contains('edit')) return showBody(src, true);
  if (b.id === 'drop-edit') return showBody(src);
  if (b.id === 'save') return busy(b, () => patch(task, { markdown_content: $('.src').value }), 'description unchanged');
  if (b.classList.contains('more')) {
    const desc = $('.desc');
    desc.classList.toggle('all');
    b.textContent = desc.classList.contains('all') ? 'show less' : 'show all';
    return;
  }
  if (b.id === 'tick') return busy(b, () => toggleTimer(task), 'timer unchanged');
  if (b.dataset.do && b.getAttribute('aria-current') !== 'true') {
    const { do: what, v } = b.dataset;
    const body = what === 'status' ? { status: v }
      : what === 'priority' ? { priority: v ? Number(v) : null }
      : { due_date: v === 'today' ? new Date().setHours(23, 59, 0, 0) : null, due_date_time: false };
    busy(b, () => patch(task, body), 'nothing changed');
  }
});

$('#stage').addEventListener('change', async (e) => {
  if (!ctx) return;
  const { task, kids, shutStatus, openStatus } = ctx;
  const el = e.target;

  if (el.id === 'title') {
    const name = el.value.trim();
    if (!name || name === unent(task.name)) return;
    return tryTo('name unchanged', () => patch(task, { name }));
  }

  if (el.type === 'date') {
    const when = el.value ? new Date(`${el.value}T23:59`).getTime() : null;
    return tryTo('due date unchanged', () => patch(task, { due_date: when, due_date_time: false }));
  }

  if (el.dataset.kid) {
    const to = el.checked ? shutStatus : openStatus;
    el.disabled = true;
    try {
      await api(`/task/${el.dataset.kid}`, { method: 'PUT', body: JSON.stringify({ status: to.status }) });
      const li = el.closest('li');
      li.style.setProperty('--c', snap(to.color));
      li.querySelector('.st')?.remove();
      if (to.type === 'custom') li.insertAdjacentHTML('beforeend', `<span class="st">${txt(low(to.status))}</span>`);
      bodies.delete(task.id);
      const ticked = $$('.kids input').filter((x) => x.checked).length;
      $('.kids em').textContent = `${ticked} of ${kids.length} done`;
      $('.gauge i').style.width = pct(ticked, kids.length);
    } catch (err) {
      el.checked = !el.checked;
      fail(err, 'subtask unchanged');
    }
    el.disabled = false;
    return;
  }

  if (el.id === 'drop') {
    const chosen = [...el.files];
    if (!chosen.length) return;
    const label = el.closest('.file');
    try {
      // One request per file: the endpoint takes a single `attachment` field.
      for (const f of chosen) {
        label.firstChild.textContent = `sending ${f.name} `;
        const form = new FormData();
        form.append('attachment', f, f.name);
        await upload(`/task/${task.id}/attachment`, form);
      }
      bodies.delete(task.id);
      await renderStage();
    } catch (err) { fail(err, 'file not attached'); }
    el.value = '';
  }
});

$('#stage').addEventListener('input', (e) => e.target.id === 'title' && fit(e.target));

// Enter commits the name rather than putting a newline in a heading.
$('#stage').addEventListener('keydown', (e) => {
  if (e.target.id === 'title' && e.key === 'Enter') { e.preventDefault(); e.target.blur(); }
});

$('#stage').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!ctx) return;
  const input = e.target.text;
  const comment_text = input.value.trim();
  if (!comment_text) return;
  input.disabled = true;
  try {
    await api(`/task/${ctx.task.id}/comment`, { method: 'POST', body: JSON.stringify({ comment_text, notify_all: false }) });
    notes.delete(ctx.task.id);
    $('.notes').insertAdjacentHTML('afterbegin',
      `<li><em>${txt(me.username)} &nbsp; just now</em><p>${txt(comment_text)}</p></li>`);
    input.value = '';
  } catch (err) { fail(err, 'not posted'); }
  input.disabled = false;
  input.focus();
});

/* ── timer ──────────────────────────────────────────────────────── */

async function readTimer() {
  timer = (await api(`/team/${teamId}/time_entries/current`)).data ?? null;
  paintClock();
}

async function toggleTimer(task) {
  if (timer?.task?.id === task.id) await api(`/team/${teamId}/time_entries/stop`, { method: 'POST' });
  else await api(`/team/${teamId}/time_entries/start`, { method: 'POST', body: JSON.stringify({ tid: task.id }) });
  bodies.delete(task.id);
  await readTimer();
  await renderStage();
}

function paintClock() {
  const el = $('#clock');
  el.hidden = !timer;
  if (!timer) return;
  // Rebuild only when the entry changes; the elapsed time is a text node updated in
  // place, so this does not re-parse HTML every second.
  if (el.dataset.entry !== timer.id) {
    el.dataset.entry = timer.id;
    el.innerHTML = `<i>&#9678;</i><span class="elapsed"></span> <b>${txt(timer.task?.name ?? 'running')}</b>`;
  }
  $('.elapsed', el).textContent = clocked(Date.now() - Number(timer.start));
}

setInterval(() => timer && paintClock(), 1000);
$('#clock').addEventListener('click', () => {
  if (timer?.task?.id) { picked = timer.task.id; renderRail(); renderStage(); }
});

/* ── pinned lists ───────────────────────────────────────────────── */

async function openPicker() {
  const box = $('#picker');
  if (!box.hidden) { box.hidden = true; return; }
  box.hidden = false;
  box.innerHTML = '<p class="label">loading spaces</p>';
  try {
    const { spaces } = await api(`/team/${teamId}/space`);
    box.innerHTML = `<p class="label">pick a list to show alongside your own</p>
      <div class="spaces">${spaces.map((s) => `<button class="chip" data-space="${esc(s.id)}"
        style="--c:var(--overlay1)">${txt(s.name)}</button>`).join('')}</div>
      <div class="found"></div>`;
  } catch (err) {
    box.innerHTML = `<p class="err">${esc(err.message)}</p>`;
  }
}

$('#picker').addEventListener('click', async (e) => {
  const s = e.target.closest('[data-space]');
  const l = e.target.closest('[data-list]');
  const found = $('.found', $('#picker'));
  if (s) {
    $$('[data-space]', $('#picker')).forEach((b) => b.setAttribute('aria-current', b === s));
    found.innerHTML = '<p class="label">loading lists</p>';
    let all;
    try {
      // Two calls per space: lists sitting in folders, and lists sitting loose in the space.
      const [{ folders }, { lists: loose }] = await Promise.all([
        api(`/space/${s.dataset.space}/folder`),
        api(`/space/${s.dataset.space}/list`),
      ]);
      all = [...folders.flatMap((f) => f.lists.map((x) => ({ ...x, under: f.name }))), ...loose];
    } catch (err) {
      found.innerHTML = `<p class="err">${esc(err.message)}</p>`;
      return;
    }
    found.innerHTML = all.length
      ? `<div class="spaces">${all.map((x) => `<button class="chip" data-list="${esc(x.id)}"
          data-name="${txt(x.under ? `${x.under}/${x.name}` : x.name)}" style="--c:var(--mauve)"
          aria-current="${pins.some((p) => p.id === x.id)}">${txt(x.under ? `${x.under}/${x.name}` : x.name)}</button>`).join('')}</div>`
      : '<p class="quiet">no lists in that space</p>';
  }
  if (l) {
    const id = l.dataset.list;
    pins = pins.some((p) => p.id === id)
      ? pins.filter((p) => p.id !== id)
      : [...pins, { id, name: l.dataset.name }];
    localStorage.setItem('pins', JSON.stringify(pins));
    l.setAttribute('aria-current', pins.some((p) => p.id === id));
    reload();
  }
});

$('#pin').addEventListener('click', openPicker);

$('#rail').addEventListener('click', async (e) => {
  const un = e.target.closest('[data-unpin]');
  if (un) {
    pins = pins.filter((p) => p.id !== un.dataset.unpin);
    pool.delete(un.dataset.unpin);
    localStorage.setItem('pins', JSON.stringify(pins));
    renderRail();
    return;
  }
  const team = e.target.closest('[data-team]');
  if (team) { localStorage.setItem('teamId', team.dataset.team); location.reload(); return; }

  const row = e.target.closest('.row');
  if (!row || row.dataset.id === picked) return;
  picked = row.dataset.id;
  renderRail();
  renderStage();
});

/* ── load ───────────────────────────────────────────────────────── */

async function pages(path, extra = {}) {
  const out = [];
  for (let page = 0; page < 20; page++) {
    const q = new URLSearchParams({ page, subtasks: 'true', include_closed: String($('#closed').checked), ...extra });
    const { tasks: batch } = await api(`${path}?${q}`);
    out.push(...batch);
    if (batch.length < 100) break;
  }
  return out;
}

async function fetchAll() {
  // You watch 100+ tasks, which is not a list anyone can read. Narrowed server-side to
  // the ones that moved this week — date_updated_gt cuts it to about a third.
  const watching = { order_by: 'updated', reverse: 'true', subtasks: 'false',
    date_updated_gt: Date.now() - 7 * 864e5, 'watchers[]': me.id };

  // Top-level only for a pinned list: subtasks belong inside their parent, not as peers.
  const [mine, extra, alsoWatched] = await Promise.all([
    pages(`/team/${teamId}/task`, { order_by: 'due_date', 'assignees[]': me.id }),
    Promise.all(pins.map(async (p) => [p.id, await pages(`/list/${p.id}/task`, { subtasks: 'false' })])),
    $('#watch').checked ? pages(`/team/${teamId}/task`, watching) : [],
  ]);
  return { mine, extra, watched: alsoWatched };
}

function adopt({ mine, extra, watched: alsoWatched }) {
  tasks = mine;
  watched = alsoWatched ?? [];
  pool.clear();
  for (const [id, list] of extra) pool.set(id, list);
  seen = new Map(everything().map((t) => [t.id, t.date_updated]));
  fresher = null;
  $('#news').hidden = true;
  notes.clear();
  bodies.clear();
  // Statuses live on the list, not the task, so a status added or recoloured in ClickUp
  // is invisible until this is dropped. One refetch per list, on the next task opened.
  lists.clear();
  if (!byId(picked)) {
    const order = [...mine].sort(byUrgency);
    picked = (order.find((t) => t.status.type === 'custom') ?? order[0])?.id ?? null;
  }
  stats();
  renderRail();
  renderStage();
}

const load = async () => adopt(await fetchAll());
const reload = () => load().catch((err) => { $('#stats').innerHTML = `<span class="err">${esc(err.message)}</span>`; });

/* Poll quietly and say that something moved, but never move it. Re-rendering under
   someone who is mid-sentence is the thing this app exists to avoid, so the new data
   waits in `fresher` until the badge is clicked. */
async function poll() {
  if (document.hidden || !teamId) return;
  const fresh = await fetchAll();
  const all = [fresh.mine, fresh.watched ?? [], ...fresh.extra.map(([, l]) => l)].flat();
  const live = new Set(all.map((t) => t.id));
  const changed = all.filter((t) => seen.get(t.id) !== t.date_updated).length;
  const gone = everything().filter((t) => !live.has(t.id)).length;
  const restyled = await statusesMoved();
  if (!(changed + gone + restyled)) return;
  fresher = fresh;
  $('#news').textContent = `${changed + gone + restyled} changed`;
  $('#news').hidden = false;
}

/* The open task's own list, checked once a cycle. A status added, renamed or recoloured
   in ClickUp changes the chips you would click, and nothing in the task payload reveals
   it. Costs one request per poll, and only while a task is open. */
async function statusesMoved() {
  const id = ctx?.task?.list?.id;
  if (!id || !lists.has(id)) return 0;
  const shape = (l) => l.statuses.map((x) => `${x.status}:${x.color}:${x.type}`).join('|');
  try {
    const [had, now] = await Promise.all([lists.get(id), api(`/list/${id}`)]);
    if (shape(had) === shape(now)) return 0;
    lists.delete(id);   // next render refetches, and stops this counting twice
    return 1;
  } catch {
    return 0;
  }
}

const tick = () => readTimer().catch(() => {});
setInterval(() => poll().catch(() => {}), 90_000);
setInterval(() => !document.hidden && tick(), 60_000);
// Coming back to the tab is exactly when a stale clock would be visible.
document.addEventListener('visibilitychange', () => !document.hidden && tick());
$('#news').addEventListener('click', () => fresher && adopt(fresher));

let typing;
$('#q').addEventListener('input', () => { clearTimeout(typing); typing = setTimeout(renderRail, 120); });
$('#refresh').addEventListener('click', reload);
$('#closed').addEventListener('change', reload);
$('#watch').addEventListener('change', reload);

// Console handle. `now.preview(3)` shows the change badge without touching ClickUp;
// `now.poll()` checks straight away instead of waiting out the 90s tick.
window.now = {
  poll,
  preview(n = 2) {
    fresher = { mine: tasks, extra: [...pool.entries()], watched };
    $('#news').textContent = `${n} changed`;
    $('#news').hidden = false;
  },
};

/* ── boot ───────────────────────────────────────────────────────── */

try {
  me = (await api('/user')).user;
  const { teams } = await api('/team');
  teamId = teams.find((t) => t.id === localStorage.getItem('teamId'))?.id ?? (teams.length === 1 ? teams[0].id : null);
  $('#who').textContent = low(me.username.split(' ')[0]);

  if (teamId) {
    localStorage.setItem('teamId', teamId);
    await load();
    tick();
  } else {
    // ponytail: one-time picker kept in localStorage; clear with localStorage.removeItem('teamId')
    // The rail's own click handler picks this up; no second listener needed.
    $('#rail').innerHTML = `<p class="label">which workspace</p><div class="field">${teams
      .map((t) => `<button class="chip" style="--c:var(--mauve)" data-team="${esc(t.id)}">${txt(t.name)}</button>`)
      .join('')}</div>`;
  }
} catch (err) {
  $('#stats').innerHTML = `<span class="err">${esc(err.message)} &mdash; check CLICKUP_TOKEN in .env</span>`;
}
