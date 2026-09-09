# Now

ClickUp tasks assigned to you. Task list left, open task right. Built because ClickUp's own list
view puts a whole company's work on screen at once.

## Setup

```sh
cp .env.example .env   # paste a personal token: ClickUp avatar, Settings, Apps
node server.mjs        # http://localhost:4400
```

Four files, `server.mjs` plus three in `public/`. No runtime dependencies, no build step. Node
20.12+ for `process.loadEnvFile`. `npm install` fetches the type checker and nothing else.

`server.mjs` holds the token and proxies every call, so the browser never sees it. It binds to
127.0.0.1 and rejects any request carrying a foreign `Origin`, because any page you visit can
reach localhost and a no-cors POST would otherwise land.

## Layout

| | |
|---|---|
| Rail, left | Your tasks, in flight first. Pinned lists and `watching` get their own sections. Filter matches name, list, folder, tags. |
| Stage, middle | Rename, edit the description as markdown, tick subtasks, comment, run a timer. |
| Properties, right | Status, priority, due, custom fields, files. Sticky while you scroll. |
| Status bar | `open` `in flight` `blocked` `late` `done`. Each is a filter. Click again to clear. |

## Deliberate choices

| | |
|---|---|
| Nothing moves unless you move it | The 90s poll only raises a badge. New data waits for a click. |
| Colour is which field, not which value | `dysk`, not `lsblk`. Location lavender, a person their own ClickUp colour, estimate teal, logged green, due sky until late. |
| A proportion gets a gauge | Subtask progress is a bar. |
| Priority shows at urgent and high only | Normal and low are noise. |
| Sort is overdue, priority, then date | 3 of 33 tasks here carry a due date. |
| Blocked is a state, not a field | Any custom field matching `/block/i` with text in it. Rename the field in ClickUp and this stops working. |

## API notes

Things that cost time to find.

| | |
|---|---|
| `markdown_description` | Single-task fetch only. List fetches return `description` and `text_content` markdown-stripped and byte-identical to each other. |
| Update reply | The whole task except `markdown_description`, so an edit is one request. |
| `date_updated_gt` | Inclusive. Pass watermark + 1 or the newest task returns every time and the badge sticks. |
| `include_closed` | Gates `closed` ("cancelled") only. `done` ("complete") always returns. |
| Names | Stored HTML-escaped. `testimonials &amp; partners` arrives literally, so decode once before display. Status names sent back stay raw. |
| Statuses | Belong to the list. No task payload shows one was added or recoloured, so the poll re-reads the open list. |
| Rate limit | 100/min. A poll is one request, plus one per pinned list, plus one for the open list. |
| Poll | Asks whether anything changed, not what. 32 bytes idle. A task unassigned from you stays on screen until you refresh. |
| Markdown | Everything is escaped before any rule runs, so raw HTML in a description shows as text. No sanitiser dependency. |

## Checking

```sh
npm run check
```

- `check.mjs` evaluates `public/app.js` against a stub DOM. `node --check` only parses, and missed
  a temporal dead zone that shipped as a blank page.
- `tsc --noEmit` with `checkJs`. No build step, no `.ts`, the browser loads the same file.
  `noImplicitAny` is off, and turning it on reports 184 unannotated parameters. `server.mjs` is
  annotated and passes with it on, because it holds the token.

## Fiddling

`localStorage` holds `teamId` and `pins`. Clear either and reload.

From the console, `now.poll()` checks ClickUp immediately and `now.preview(3)` shows the change
badge.
