-- Now: a small, independent Mantle window for the tasks assigned to you.
local api = require("api")
local motion = os.getenv("NOW_REDUCED_MOTION") ~= "1"

local C = {
	bg = "#1e1e2e",
	side = "#181825",
	card = "#242434",
	surface = "#313244",
	border = "#45475a",
	text = "#cdd6f4",
	dim = "#a6adc8",
	muted = "#949bb3",
	mauve = "#cba6f7",
	green = "#a6e3a1",
	red = "#f38ba8",
	peach = "#fab387",
	sky = "#89dceb",
	yellow = "#f9e2af",
}

local state_home = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
local prefs = persistent_table({
	path = state_home .. "/clickup-now",
	name = "settings.json",
	defaults = { team_id = "", closed = false, pins = {}, watch = false },
})

local tasks = state("now_tasks", {})
local pinned_tasks = state("now_pinned_tasks", {})
local watched_tasks = state("now_watched_tasks", {})
local pins = state("now_pins", prefs.pins:get() or {})
local selected = state("now_selected", "")
local description_open = state("now_description_open", false)
local subtasks_open = state("now_subtasks_open", false)
local detail = state("now_detail", nil)
local detail_error = state("now_detail_error", "")
local list_info = state("now_list", nil)
local comments = state("now_comments", {})
local teams = state("now_teams", {})
local me = state("now_me", nil)
local team_id = state("now_team_id", "")
local query = state("now_query", "")
local lens = state("now_lens", "open")
local busy = state("now_busy", false)
local loading = state("now_loading", false)
local message = state("now_message", "")
local running = state("now_running", nil)
local changes = state("now_changes", 0)
local initialized = state("now_initialized", false)
local loaded = state("now_loaded", false)
local auth_state = state("now_auth_state", "checking")
local auth_error = state("now_auth_error", "")
local closed = prefs.closed:map(function(value)
	return value == true
end)
local watch = prefs.watch:map(function(value)
	return value == true
end)
local request_id, detail_id = 0, 0
local auth_epoch = 0

local function name(value)
	return tostring(value or "")
		:gsub("&amp;", "&")
		:gsub("&lt;", "<")
		:gsub("&gt;", ">")
		:gsub("&quot;", '"')
		:gsub("&#39;", "'")
end

local function status_type(task)
	return task.status and task.status.type or "open"
end

local function done(task)
	return status_type(task) == "done" or status_type(task) == "closed"
end

local function overdue(task, now_ms)
	return task.due_date
		and tonumber(task.due_date)
		and tonumber(task.due_date) < (now_ms or os.time() * 1000)
		and not done(task)
end

local function field_text(field)
	local value = field.value
	if value == nil or value == "" or (type(value) == "table" and #value == 0) then
		return nil
	end
	if field.type == "drop_down" then
		local options = field.type_config and field.type_config.options or {}
		for _, option in ipairs(options) do
			if tostring(option.orderindex) == tostring(value) then
				return option.name
			end
		end
		local option = options[tonumber(value) and tonumber(value) + 1 or 0]
		return option and option.name or nil
	end
	if field.type == "checkbox" then
		return (value == true or value == "true") and "yes" or nil
	end
	if field.type == "date" then
		local stamp = tonumber(value)
		return stamp and os.date("%d %b", math.floor(stamp / 1000)) or nil
	end
	if type(value) == "table" then
		return nil
	end
	return tostring(value)
end

local function blocked(task)
	for _, field in ipairs(task.custom_fields or {}) do
		if tostring(field.name or ""):lower():find("block", 1, true) then
			local value = field_text(field)
			if value then
				return value
			end
		end
	end
end

local function date_label(ms)
	if not ms then
		return ""
	end
	local stamp = tonumber(ms)
	return stamp and os.date("%d %b", math.floor(stamp / 1000)) or ""
end

local function query_pages(path, page, collected, callback)
	if page >= 20 then
		callback(nil, collected)
		return
	end
	api.request("GET", path .. "&page=" .. page, nil, function(err, payload)
		if err then
			callback(err)
			return
		end
		local batch = payload.tasks or {}
		for _, task in ipairs(batch) do
			collected[#collected + 1] = task
		end
		if #batch < 100 then
			callback(nil, collected)
		else
			query_pages(path, page + 1, collected, callback)
		end
	end)
end

local function open_task(id)
	if id == "" then
		return
	end
	selected:set(id)
	description_open:set(false)
	subtasks_open:set(false)
	detail:set(nil)
	list_info:set(nil)
	comments:set({})
	detail_error:set("")
	message:set("")
	detail_id = detail_id + 1
	local seq = detail_id
	api.request(
		"GET",
		"/task/" .. id .. "?include_markdown_description=true&include_subtasks=true",
		nil,
		function(err, data)
			if seq ~= detail_id then
				return
			end
			if err then
				detail_error:set(err)
				message:set(err)
				return
			end
			detail:set(data)
			scroll("now_detail_scroll"):reveal(1)
			api.request("GET", "/list/" .. tostring(data.list.id), nil, function(list_err, info)
				if seq ~= detail_id then
					return
				end
				if list_err then
					message:set(list_err)
				else
					list_info:set(info)
				end
			end)
			api.request("GET", "/task/" .. id .. "/comment", nil, function(comment_err, result)
				if seq ~= detail_id then
					return
				end
				if not comment_err then
					comments:set(result.comments or {})
				end
			end)
		end
	)
end

local function load_timer()
	local id = team_id:get()
	if id == "" then
		return
	end
	api.request("GET", "/team/" .. id .. "/time_entries/current", nil, function(err, data)
		if not err then
			running:set(data.data)
		end
	end)
end

local function refresh(closed_override, watch_override)
	local id = team_id:get()
	local user = me:get()
	if id == "" or not user then
		message:set(user and "Choose a workspace to load tasks." or "Account is still loading. Try again shortly.")
		return
	end
	request_id = request_id + 1
	local seq = request_id
	loading:set(true)
	local include_closed = tostring(closed_override == nil and closed:get() or closed_override)
	local include_watched = watch_override == nil and watch:get() or watch_override
	local path = "/team/"
		.. id
		.. "/task?subtasks=true&include_closed="
		.. include_closed
		.. "&order_by=due_date&assignees%5B%5D="
		.. tostring(user.id)
	local current_pins = pins:get()
	local extras, watched = {}, {}
	local pending = 1 + #current_pins + (include_watched and 1 or 0)
	local first_error
	local result = {}
	local function finished(err)
		if seq ~= request_id then
			return
		end
		first_error = first_error or err
		pending = pending - 1
		if pending > 0 then
			return
		end
		loading:set(false)
		if first_error then
			message:set(first_error)
			return
		end
		loaded:set(true)
		tasks:set(result)
		pinned_tasks:set(extras)
		watched_tasks:set(watched)
		changes:set(0)
		message:set("")
		local wanted = selected:get()
		local found = false
		local all = {}
		for _, task in ipairs(result) do
			all[#all + 1] = task
		end
		for _, pin in ipairs(current_pins) do
			for _, task in ipairs(extras[tostring(pin.id)] or {}) do
				all[#all + 1] = task
			end
		end
		for _, task in ipairs(watched) do
			all[#all + 1] = task
		end
		for _, task in ipairs(all) do
			if task.id == wanted then
				found = true
				break
			end
		end
		if not found then
			wanted = ""
			for _, task in ipairs(result) do
				if status_type(task) == "custom" then
					wanted = task.id
					break
				end
			end
			if wanted == "" and all[1] then
				wanted = all[1].id
			end
		end
		if wanted ~= "" then
			open_task(wanted)
		else
			selected:set("")
			detail:set(nil)
		end
		load_timer()
	end
	query_pages(path, 0, {}, function(err, mine)
		result = mine or {}
		finished(err)
	end)
	for _, pin in ipairs(current_pins) do
		local pin_id = tostring(pin.id)
		query_pages(
			"/list/" .. pin_id .. "/task?subtasks=false&include_closed=" .. include_closed,
			0,
			{},
			function(err, batch)
				extras[pin_id] = batch or {}
				finished(err)
			end
		)
	end
	if include_watched then
		query_pages(
			"/team/"
				.. id
				.. "/task?subtasks=false&include_closed="
				.. include_closed
				.. "&order_by=updated&reverse=true&date_updated_gt="
				.. tostring(os.time() * 1000 - 7 * 86400000)
				.. "&watchers%5B%5D="
				.. tostring(user.id),
			0,
			{},
			function(err, batch)
				watched = batch or {}
				finished(err)
			end
		)
	end
end

local function toggle_pin(id, label)
	id = tostring(id)
	local next_pins = {}
	local existed = false
	for _, pin in ipairs(pins:get()) do
		if tostring(pin.id) == id then
			existed = true
		else
			next_pins[#next_pins + 1] = pin
		end
	end
	if not existed then
		next_pins[#next_pins + 1] = { id = id, name = tostring(label or id) }
	end
	prefs:set("pins", next_pins)
	pins:set(next_pins)
	refresh()
end

local function remove_pin(id)
	id = tostring(id)
	for _, pin in ipairs(pins:get()) do
		if tostring(pin.id) == id then
			toggle_pin(id)
			return
		end
	end
end

local function set_watch(enabled)
	prefs:set("watch", enabled == true)
	refresh(nil, enabled == true)
end

local function load_spaces(callback)
	local id = team_id:get()
	if id == "" then
		callback("Choose a workspace first.")
		return
	end
	api.request("GET", "/team/" .. id .. "/space", nil, function(err, data)
		callback(err, data and data.spaces or {})
	end)
end

local function load_lists(space_id, callback)
	local folders, loose, pending, first_error = {}, {}, 2, nil
	local function finished(err)
		first_error = first_error or err
		pending = pending - 1
		if pending > 0 then
			return
		end
		if first_error then
			callback(first_error)
			return
		end
		local found = {}
		for _, folder in ipairs(folders) do
			for _, list in ipairs(folder.lists or {}) do
				found[#found + 1] = { id = tostring(list.id), name = list.name, under = folder.name }
			end
		end
		for _, list in ipairs(loose) do
			found[#found + 1] = { id = tostring(list.id), name = list.name }
		end
		callback(nil, found)
	end
	api.request("GET", "/space/" .. tostring(space_id) .. "/folder", nil, function(err, data)
		folders = data and data.folders or {}
		finished(err)
	end)
	api.request("GET", "/space/" .. tostring(space_id) .. "/list", nil, function(err, data)
		loose = data and data.lists or {}
		finished(err)
	end)
end

local function choose_team(id)
	prefs:set("team_id", id)
	team_id:set(id)
	loaded:set(false)
	selected:set("")
	refresh()
end

local function connect(force)
	if not force and (auth_state:get() == "connecting" or auth_state:get() == "connected") then
		return
	end
	auth_epoch = auth_epoch + 1
	local epoch = auth_epoch
	auth_state:set("connecting")
	auth_error:set("")
	if initialized:get() then
		auth_state:set("connected")
		if team_id:get() ~= "" then
			if not loaded:get() or loading:get() then
				refresh()
			elseif selected:get() ~= "" and (detail:get() == nil or list_info:get() == nil) then
				open_task(selected:get())
			end
		end
		return
	end
	api.request("GET", "/user", nil, function(err, result)
		if epoch ~= auth_epoch then
			return
		end
		if err then
			auth_error:set(
				err:match("^ClickUp 401") and "ClickUp couldn't verify this token. Paste a new one and try again."
					or err
			)
			auth_state:set("error")
			return
		end
		me:set(result.user)
		api.request("GET", "/team", nil, function(team_err, data)
			if epoch ~= auth_epoch then
				return
			end
			if team_err then
				auth_error:set(team_err)
				auth_state:set("error")
				return
			end
			local all = data.teams or {}
			teams:set(all)
			initialized:set(true)
			auth_state:set("connected")
			local preferred = prefs.team_id:get() or ""
			local chosen = ""
			for _, item in ipairs(all) do
				if tostring(item.id) == preferred then
					chosen = preferred
				end
			end
			if chosen == "" and #all == 1 then
				chosen = tostring(all[1].id)
			end
			if chosen ~= "" then
				choose_team(chosen)
			end
		end)
	end)
end

local function start()
	auth_epoch = auth_epoch + 1
	local epoch = auth_epoch
	auth_state:set("checking")
	auth_error:set("")
	api.discover(function(found)
		if epoch ~= auth_epoch then
			return
		end
		if found then
			connect()
		else
			initialized:set(false)
			auth_state:set("missing")
		end
	end)
end

local function forget_token()
	if api.has_env_token() then
		auth_error:set("This token comes from CLICKUP_TOKEN. Remove it from the environment and restart Now.")
		return
	end
	api.forget(function(ok)
		if not ok then
			auth_error:set("Could not remove the saved token. Check that Secret Service is available.")
			return
		end
		request_id, detail_id = request_id + 1, detail_id + 1
		auth_epoch = auth_epoch + 1
		initialized:set(false)
		loaded:set(false)
		me:set(nil)
		teams:set({})
		team_id:set("")
		tasks:set({})
		pinned_tasks:set({})
		watched_tasks:set({})
		selected:set("")
		detail:set(nil)
		comments:set({})
		list_info:set(nil)
		running:set(nil)
		message:set("")
		auth_error:set("")
		auth_state:set("missing")
	end)
end

mantle.secrets:on_change(function(secrets)
	local status = secrets and secrets.entries and secrets.entries["clickup-now-token"]
	if status == "pending" then
		auth_error:set("")
	elseif status == "stored" and auth_state:get() ~= "connected" then
		api.discover(function(found)
			if found then
				connect(true)
			end
		end)
	elseif status == "unavailable" then
		auth_error:set("Secret Service is unavailable. Unlock your keyring and try again.")
	elseif status == "timed_out" then
		auth_error:set("Saving the token timed out. Try again.")
	end
end)

local function mutate(method, path, body, success)
	if busy:get() then
		message:set("Saving another change. Try again shortly.")
		return
	end
	busy:set(true)
	message:set("")
	api.request(method, path, body, function(err)
		busy:set(false)
		if err then
			message:set(err)
			return
		end
		message:set(success or "Saved")
		refresh()
	end)
end

local function update_task(body)
	local id = selected:get()
	if id ~= "" then
		mutate("PUT", "/task/" .. id, body)
	end
end

local function poll()
	local id, user = team_id:get(), me:get()
	local all = tasks:get()
	if id ~= "" and user and not loading:get() then
		local newest = 0
		for _, task in ipairs(all) do
			newest = math.max(newest, tonumber(task.date_updated) or 0)
		end
		for _, pin in ipairs(pins:get()) do
			for _, task in ipairs(pinned_tasks:get()[tostring(pin.id)] or {}) do
				newest = math.max(newest, tonumber(task.date_updated) or 0)
			end
		end
		for _, task in ipairs(watched_tasks:get()) do
			newest = math.max(newest, tonumber(task.date_updated) or 0)
		end
		newest = newest == 0 and os.time() * 1000 or newest
		local since = "&date_updated_gt=" .. tostring(newest + 1)
		local paths = {
			"/team/"
				.. id
				.. "/task?subtasks=false&include_closed="
				.. tostring(closed:get())
				.. "&assignees%5B%5D="
				.. tostring(user.id)
				.. since,
		}
		for _, pin in ipairs(pins:get()) do
			paths[#paths + 1] = "/list/"
				.. tostring(pin.id)
				.. "/task?subtasks=false&include_closed="
				.. tostring(closed:get())
				.. since
		end
		if watch:get() then
			paths[#paths + 1] = "/team/"
				.. id
				.. "/task?subtasks=false&include_closed="
				.. tostring(closed:get())
				.. "&watchers%5B%5D="
				.. tostring(user.id)
				.. since
		end
		local pending, moved = #paths, {}
		local old_list = list_info:get()
		if old_list and old_list.id then
			pending = pending + 1
		end
		local status_changed = false
		local seq = request_id
		local function finish_poll()
			pending = pending - 1
			if pending == 0 then
				local count = status_changed and 1 or 0
				for _ in pairs(moved) do
					count = count + 1
				end
				changes:set(count)
			end
		end
		for _, path in ipairs(paths) do
			query_pages(path, 0, {}, function(err, result)
				if seq ~= request_id then
					return
				end
				if not err then
					for _, task in ipairs(result) do
						moved[tostring(task.id)] = true
					end
				end
				finish_poll()
			end)
		end
		if old_list and old_list.id then
			api.request("GET", "/list/" .. tostring(old_list.id), nil, function(err, current)
				if seq ~= request_id then
					return
				end
				if not err and current then
					local function shape(info)
						local entries = {}
						for _, status in ipairs(info.statuses or {}) do
							entries[#entries + 1] = table.concat({
								tostring(status.status),
								tostring(status.color),
								tostring(status.type),
							}, ":")
						end
						return table.concat(entries, "|")
					end
					status_changed = shape(old_list) ~= shape(current)
				end
				finish_poll()
			end)
		end
	end
	timer(90000, poll)
end

local function matching(all, q, mode, now_ms)
	local out = {}
	q = (q or ""):lower()
	for _, task in ipairs(all or {}) do
		local hay = (name(task.name) .. " " .. name(task.list and task.list.name) .. " " .. name(
			task.folder and task.folder.name
		)):lower()
		for _, tag in ipairs(task.tags or {}) do
			hay = hay .. " " .. name(tag.name):lower()
		end
		local match = q == "" or hay:find(q, 1, true)
		local pass = mode == "all"
			or (mode == "open" and not done(task))
			or (mode == "flight" and status_type(task) == "custom")
			or (mode == "late" and overdue(task, now_ms))
			or (mode == "blocked" and blocked(task))
			or (mode == "done" and done(task))
		if match and pass then
			out[#out + 1] = task
		end
	end
	table.sort(out, function(a, b)
		local af, bf = status_type(a) == "custom", status_type(b) == "custom"
		if af ~= bf then
			return af
		end
		local al, bl = overdue(a, now_ms) and 1 or 0, overdue(b, now_ms) and 1 or 0
		if al ~= bl then
			return al > bl
		end
		local ap, bp = tonumber(a.priority and a.priority.id) or 9, tonumber(b.priority and b.priority.id) or 9
		if ap ~= bp then
			return ap < bp
		end
		return (tonumber(a.due_date) or 9e15) < (tonumber(b.due_date) or 9e15)
	end)
	return out
end

local groups = computed(
	{ tasks, pinned_tasks, watched_tasks, pins, query, lens, mantle.system },
	function(mine, extra, watched, pinned, q, mode, system)
		local now_ms = (system and system.time or os.time()) * 1000
		local assigned = matching(mine, q, mode, now_ms)
		local in_flight, rest = {}, {}
		local seen = {}
		for _, task in ipairs(assigned) do
			seen[tostring(task.id)] = true
			if status_type(task) == "custom" then
				in_flight[#in_flight + 1] = task
			else
				rest[#rest + 1] = task
			end
		end
		local out = {
			{ label = "In flight", source = "mine", list = in_flight },
			{ label = q ~= "" and "Matching" or "Mine", source = "mine", list = rest },
		}
		local function claim(from)
			local list = {}
			for _, task in ipairs(matching(from, q, mode, now_ms)) do
				local key = tostring(task.id)
				if not seen[key] then
					seen[key] = true
					list[#list + 1] = task
				end
			end
			return list
		end
		for _, pin in ipairs(pinned or {}) do
			out[#out + 1] = {
				label = tostring(pin.name or pin.id),
				source = "pin",
				pin = tostring(pin.id),
				list = claim((extra or {})[tostring(pin.id)]),
			}
		end
		if #(watched or {}) > 0 then
			out[#out + 1] = { label = "Watching, this week", source = "watch", list = claim(watched) }
		end
		return out
	end
)

local filtered = computed({ groups }, function(sections)
	local out = {}
	for _, section in ipairs(sections or {}) do
		for _, task in ipairs(section.list) do
			out[#out + 1] = task
		end
	end
	return out
end)

return {
	api = api,
	auth_state = auth_state,
	auth_error = auth_error,
	forget_token = forget_token,
	C = C,
	motion = motion,
	prefs = prefs,
	tasks = tasks,
	pinned_tasks = pinned_tasks,
	watched_tasks = watched_tasks,
	pins = pins,
	watch = watch,
	groups = groups,
	selected = selected,
	description_open = description_open,
	subtasks_open = subtasks_open,
	detail = detail,
	detail_error = detail_error,
	list_info = list_info,
	comments = comments,
	teams = teams,
	me = me,
	team_id = team_id,
	query = query,
	lens = lens,
	busy = busy,
	loading = loading,
	message = message,
	running = running,
	changes = changes,
	closed = closed,
	filtered = filtered,
	name = name,
	status_type = status_type,
	done = done,
	overdue = overdue,
	blocked = blocked,
	date_label = date_label,
	open_task = open_task,
	refresh = refresh,
	toggle_pin = toggle_pin,
	remove_pin = remove_pin,
	set_watch = set_watch,
	load_spaces = load_spaces,
	load_lists = load_lists,
	choose_team = choose_team,
	start = start,
	poll = poll,
	mutate = mutate,
	update_task = update_task,
}
