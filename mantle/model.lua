-- Now: a small, independent Mantle window for the tasks assigned to you.
local api = require("api")

local C = {
	bg = "#1e1e2e",
	side = "#181825",
	card = "#242434",
	surface = "#313244",
	border = "#45475a",
	text = "#cdd6f4",
	dim = "#a6adc8",
	muted = "#7f849c",
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
	defaults = { team_id = "", closed = false },
})

local tasks = state("now_tasks", {})
local selected = state("now_selected", "")
local description_open = state("now_description_open", false)
local subtasks_open = state("now_subtasks_open", false)
local detail = state("now_detail", nil)
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
local closed = prefs.closed:map(function(value)
	return value == true
end)
local request_id, detail_id = 0, 0

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

local function overdue(task)
	return task.due_date and tonumber(task.due_date) and tonumber(task.due_date) < os.time() * 1000 and not done(task)
end

local function blocked(task)
	for _, field in ipairs(task.custom_fields or {}) do
		if tostring(field.name or ""):lower():find("block", 1, true) and field.value and field.value ~= "" then
			return tostring(field.value)
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

local function refresh(closed_override)
	local id = team_id:get()
	local user = me:get()
	if id == "" or not user then
		return
	end
	request_id = request_id + 1
	local seq = request_id
	loading:set(true)
	local path = "/team/"
		.. id
		.. "/task?subtasks=true&include_closed="
		.. tostring(closed_override == nil and closed:get() or closed_override)
		.. "&order_by=due_date&assignees%5B%5D="
		.. tostring(user.id)
	query_pages(path, 0, {}, function(err, result)
		if seq ~= request_id then
			return
		end
		loading:set(false)
		if err then
			message:set(err)
			return
		end
		tasks:set(result)
		changes:set(0)
		message:set("")
		local wanted = selected:get()
		local found = false
		for _, task in ipairs(result) do
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
			if wanted == "" and result[1] then
				wanted = result[1].id
			end
		end
		if wanted ~= "" then
			open_task(wanted)
		else
			selected:set("")
			detail:set(nil)
		end
		load_timer()
	end)
end

local function choose_team(id)
	prefs:set("team_id", id)
	team_id:set(id)
	selected:set("")
	refresh()
end

local function start()
	if not api.ready() then
		message:set("Set CLICKUP_TOKEN, then restart this app.")
		return
	end
	api.request("GET", "/user", nil, function(err, result)
		if err then
			message:set(err)
			return
		end
		me:set(result.user)
		api.request("GET", "/team", nil, function(team_err, data)
			if team_err then
				message:set(team_err)
				return
			end
			local all = data.teams or {}
			teams:set(all)
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

local function mutate(method, path, body, success)
	if busy:get() then
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
	if id ~= "" and user and #all > 0 and not loading:get() then
		local newest = 0
		for _, task in ipairs(all) do
			newest = math.max(newest, tonumber(task.date_updated) or 0)
		end
		local path = "/team/"
			.. id
			.. "/task?subtasks=false&include_closed="
			.. tostring(closed:get())
			.. "&assignees%5B%5D="
			.. tostring(user.id)
			.. "&date_updated_gt="
			.. (newest + 1)
		api.request("GET", path, nil, function(err, data)
			if not err and data.tasks then
				changes:set(#data.tasks)
			end
		end)
	end
	timer(90000, poll)
end
local filtered = computed({ tasks, query, lens }, function(all, q, mode)
	local out = {}
	q = (q or ""):lower()
	for _, task in ipairs(all or {}) do
		local hay = (name(task.name) .. " " .. name(task.list and task.list.name) .. " " .. name(
			task.folder and task.folder.name
		)):lower()
		local match = q == "" or hay:find(q, 1, true)
		local pass = mode == "all"
			or (mode == "open" and not done(task))
			or (mode == "flight" and status_type(task) == "custom")
			or (mode == "late" and overdue(task))
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
		local al, bl = overdue(a) and 1 or 0, overdue(b) and 1 or 0
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
end)

return {
	api = api,
	C = C,
	prefs = prefs,
	tasks = tasks,
	selected = selected,
	description_open = description_open,
	subtasks_open = subtasks_open,
	detail = detail,
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
	choose_team = choose_team,
	start = start,
	poll = poll,
	mutate = mutate,
	update_task = update_task,
}
