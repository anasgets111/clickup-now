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

**Rail (left)** — your tasks, in flight first, then the rest, sorted by due date then priority.
Any list you pin gets its own section below. Filter matches name, list, folder and tags.

**Stage (right)** — the open task. Rename it, rewrite its description in markdown, change status,
priority and due date, tick subtasks off, attach files, post an update, start a timer.

**Status bar** — how many are open, late and due today; a running timer with elapsed time; and a
`● n changed` badge when ClickUp has moved on.

### Things it does on purpose

- **Nothing moves unless you move it.** Polling every 90s only raises the badge. New data waits
  until you click it. Re-rendering under someone mid-sentence is the thing this exists to avoid.
- **Colour is only ever meaning.** Every colour is a status, a priority or a tag. Your workspace's
  status colours are snapped to the nearest Catppuccin Mocha accent by hue, so they sit in the
  palette without being invented.
- **Priority shows only when it's urgent or high.** Normal and low are noise.
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

## Fiddling

`localStorage`: `teamId` (the workspace), `pins` (the pinned lists). Clear either and reload.

From the console: `now.poll()` checks ClickUp immediately, `now.preview(3)` shows the change badge
without touching anything.
