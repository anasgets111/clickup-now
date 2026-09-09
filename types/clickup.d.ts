/* The slice of ClickUp's API this app touches, written from real payloads
   rather than from the docs. Several fields are here because a response surprised me.
   Anything not described here is deliberately absent, not forgotten. */

/** A status belongs to the list, not the task. `type` is the only reliable signal for
 *  what a status means: the first is `open`, the last `closed`, ones marked done are
 *  `done`, and everything in between is `custom`. "in flight" is built on that. */
export interface Status {
  status: string;
  color: string;
  type: 'open' | 'custom' | 'done' | 'closed';
  orderindex: number;
}

export interface User {
  id: number;
  username: string;
  email: string;
  color: string | null;
  initials: string;
  profilePicture: string | null;
}

export interface Tag {
  name: string;
  tag_fg: string;
  tag_bg: string;
}

/** `priority.id` arrives as a string: "1" urgent, "2" high, "3" normal, "4" low. */
export interface Priority {
  id: string;
  priority: 'urgent' | 'high' | 'normal' | 'low';
  color: string;
}

export interface FieldOption {
  id: string;
  name: string;
  color: string | null;
  orderindex: number;
}

/** A task carries an entry for every field on its list, nearly all with value absent.
 *  A drop_down's value is the option's orderindex; a number arrives as a string. */
export interface CustomField {
  id: string;
  name: string;
  type: 'drop_down' | 'number' | 'short_text' | 'text' | 'checkbox' | 'date' | 'labels' | 'users' | string;
  type_config: { options?: FieldOption[] };
  value?: unknown;
}

export interface Attachment {
  id: string;
  title: string;
  url: string;
  extension: string;
  size: number | string;
}

/** Dates are epoch milliseconds as strings, not numbers. Number() them before compare. */
export interface Task {
  id: string;
  name: string;
  status: Status;
  priority: Priority | null;
  assignees: User[];
  watchers?: User[];
  tags: Tag[];
  custom_fields?: CustomField[];
  parent: string | null;
  top_level_parent?: string | null;
  due_date: string | null;
  start_date: string | null;
  date_created: string;
  date_updated: string;
  date_closed: string | null;
  time_estimate: number | null;
  time_spent?: number;
  url: string;
  list: { id: string; name: string };
  folder: { id: string; name: string; hidden?: boolean };
  space: { id: string };

  /** Both come back with markdown already stripped, and identical to each other. */
  description?: string;
  text_content?: string;

  /** Only on GET /task/{id}?include_markdown_description=true. Never on a list fetch,
   *  and absent from the reply to an update, which is why patch() keeps the copy it
   *  holds unless the edit is what changed it. */
  markdown_description?: string;

  /** Only with include_subtasks=true. Subtasks carry no `list` of their own. */
  subtasks?: Task[];

  attachments?: Attachment[];
}

export interface TaskPage { tasks: Task[]; last_page?: boolean }
export interface List { id: string; name: string; statuses: Status[] }
export interface Folder { id: string; name: string; lists: List[] }
export interface Space { id: string; name: string }

export interface TimeEntry {
  id: string;
  /** Epoch ms as a string. */
  start: string;
  duration: string | number;
  task?: { id: string; name: string };
  user?: User;
}
