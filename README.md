# Now

A calm front end for the ClickUp tasks assigned to you. One list on the left, one open task on
the right, and nothing on screen that isn't yours.

Built because ClickUp's own list view puts a whole company's work in front of you at once.

## Setup

1. In ClickUp: avatar (bottom left) → Settings → Apps → Generate a personal API token. It starts
   with `pk_`.
2. `cp .env.example .env` and paste the token in.
3. `node server.mjs`, then open http://localhost:4400

No dependencies, no build step, four files. Needs Node 20.12+ for `process.loadEnvFile`.

The token lives in `.env` (gitignored) and never reaches the browser — `server.mjs` proxies every
call to ClickUp and is the only thing that holds it. It binds to 127.0.0.1 only.

## What it does

**Rail (left)** — your tasks, in flight first, then the rest. Any list you pin gets its own
section, and `watching` adds the tasks you watch that moved this week. Filter matches name, list,
folder and tags.

**Stage (right)** — the open task. Rename it, rewrite its description in markdown, change status,
priority and due date, tick subtasks off, attach files, post an update, start a timer. Custom
fields with a value are shown, and a blocked task leads with its reason.

**Status bar** — open, in flight and blocked counts (late appears only when something is); a
running timer with elapsed time; and a `● n changed` badge when ClickUp has moved on.

### Things it does on purpose

- **Nothing moves unless you move it.** Polling every 90s only raises the badge. New data waits
  until you click it. Re-rendering under someone mid-sentence is the thing this exists to avoid.
- **Colour says which field you are reading**, the way `dysk` colours a column rather than a
  value. Location is always lavender, a person is always their own ClickUp colour, an estimate is
  teal, time logged is green, a due date is sky until it is late. Learn the palette once and you
  read the line by hue instead of by position. Status colours come from your workspace, snapped
  to the nearest Mocha accent by hue so they sit in the palette without being invented.
- **A proportion gets a gauge**, not a sentence. Subtask progress is a bar.
- **Priority shows only when it's urgent or high.** Normal and low are noise.
- **Sorted by priority, not by date.** Overdue first, then priority, then date. Almost nothing in
  this workspace carries a due date, so leading with the date sorted on a value that is usually
  absent.
- **Blocked is a state, not a field.** Any custom field named like "Blocked Reason" with something
  written in it marks the task, in the rail and at the top of the open task. Rename that field in
  ClickUp and this stops noticing.
- **Descriptions render as real markdown** — headings, tables, code, lists — clamped behind a fade
  until you ask for the rest.

## Notes

- `markdown_description` only exists on the single-task fetch. The list endpoint returns
  `description` and `text_content` already stripped of markdown, byte-identical to each other.
- ClickUp stores names HTML-escaped (`testimonials &amp; partners`), so names are decoded once
  before being re-escaped for display. Status names sent *back* to the API stay raw.
- The markdown renderer escapes everything before applying a single rule, so raw HTML in a
  description shows as text and cannot execute. That is why there's no sanitiser dependency.
- Statuses belong to the list, not the task, so nothing in a task payload reveals that one was
  added or recoloured. The 90s poll re-reads the open task's list to catch it, and a refresh drops
  every cached list definition.
- Rate limit is 100 requests/minute on your plan. A poll costs one request, plus one per pinned
  list, plus one for the open task's list — so a dozen pins would need rethinking.
- The poll asks a question rather than fetching an answer: anything updated after the newest
  thing already held. Idle, that is 32 bytes. The badge does the real fetch when clicked. The
  cost is that a task leaving you — unassigned or deleted — is invisible until you refresh,
  because the query filters by assignee so it simply does not come back.
- `date_updated_gt` is inclusive despite the name, so the watermark is passed with a +1.
- An update is answered with the whole task, so an edit is one request. Opening a task is three
  (list, comments, task) and they are cached until you refresh.

## Fiddling

`localStorage`: `teamId` (the workspace), `pins` (the pinned lists). Clear either and reload.

From the console: `now.poll()` checks ClickUp immediately, `now.preview(3)` shows the change badge
without touching anything.
