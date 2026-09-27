-- The selected task, its reading view, and its properties.
local markdown = require("markdown")

return function(model, widgets)
	local api, C = model.api, model.C
	local selected, detail, list_info, comments = model.selected, model.detail, model.list_info, model.comments
	local running, description_open, subtasks_open = model.running, model.description_open, model.subtasks_open
	local name, done, overdue, blocked, date_label =
		model.name, model.done, model.overdue, model.blocked, model.date_label
	local team_id, mutate, update_task = model.team_id, model.mutate, model.update_task
	local caption, action_button, note = widgets.caption, widgets.action_button, widgets.note

	local function section_title(label)
		return text({ content = label, foreground = C.dim, font_size = 13 })
	end

	local function header_nodes(task, current)
		if not task then
			return {}
		end
		local nodes = {}
		local function add(node)
			nodes[#nodes + 1] = node
		end
		add(text({
			content = name(task.name),
			width = "Fill",
			wrap = "Word",
			max_lines = 3,
			font = "Noto Sans",
			foreground = C.text,
			font_size = 29,
		}))
		add(row({
			width = "Fill",
			spacing = 9,
			children = {
				caption(name(task.status and task.status.status):lower(), C.yellow, 12),
				caption("/", C.muted),
				caption(name(task.list and task.list.name), C.mauve, 12),
				caption(date_label(task.due_date), overdue(task) and C.red or C.sky, 12),
			},
		}))
		local on_this = current and current.task and current.task.id == task.id
		local controls = {
			action_button(on_this and "Stop timer" or "Start timer", function()
				local id = team_id:get()
				local path = "/team/" .. id .. "/time_entries/" .. (on_this and "stop" or "start")
				mutate("POST", path, on_this and nil or { tid = task.id }, "Timer updated")
			end, { color = on_this and C.green or C.text, border = true }),
			action_button("Open in ClickUp", function()
				if task.url then
					process.detach("xdg-open", { task.url })
				end
			end, { border = true }),
		}
		add(row({ width = "Fill", spacing = 8, children = controls }))
		return nodes
	end

	local function detail_nodes(task, info, notes, expanded, show_subtasks)
		if not task then
			return { note(selected:get() == "" and "Choose a task to begin." or "Opening task…") }
		end
		local nodes = {}
		local function add(node)
			nodes[#nodes + 1] = node
		end
		local blocked_reason = blocked(task)
		if blocked_reason then
			add(column({
				width = "Fill",
				padding = 12,
				radius = 10,
				background = C.card,
				spacing = 4,
				children = {
					caption("Blocked", C.peach, 12),
					note(blocked_reason, C.text),
				},
			}))
		end
		add(section_title("Description"))
		local description = task.markdown_description or task.description or ""
		local blocks = markdown.blocks(description)
		local shown = expanded and #blocks or math.min(#blocks, 9)
		local reading = {}
		for i = 1, shown do
			reading[#reading + 1] = markdown.node(blocks[i], C)
		end
		if #reading == 0 then
			reading[1] = note("No description yet.", C.muted)
		end
		if #blocks > 9 then
			reading[#reading + 1] = action_button(expanded and "Show less ↑" or "Show all ↓", function()
				description_open:set(not description_open:get())
			end, { id = "description_toggle", color = C.mauve, background = C.surface })
		end
		add(column({ width = "Fill", padding = 18, radius = 12, background = C.card, spacing = 9, children = reading }))
		local kids = task.subtasks or {}
		if #kids > 0 then
			local count = 0
			for _, child in ipairs(kids) do
				if done(child) then
					count = count + 1
				end
			end
			add(section_title("Subtasks  ·  " .. count .. " / " .. #kids))
			add(row({
				width = "Fill",
				height = 5,
				radius = 3,
				background = C.surface,
				children = {
					rect({
						width = string.format("%d%%", math.floor(count * 100 / #kids)),
						height = "Fill",
						radius = 3,
						background = C.green,
					}),
				},
			}))
			local child_nodes = {}
			local done_status, open_status
			for _, status in ipairs(info and info.statuses or {}) do
				if status.type == "done" then
					done_status = status.status
				end
				if status.type == "open" then
					open_status = status.status
				end
			end
			local visible_kids = show_subtasks and #kids or math.min(#kids, 5)
			for i = 1, visible_kids do
				local child = kids[i]
				local target = done(child) and open_status or done_status
				child_nodes[#child_nodes + 1] = action_button(
					(done(child) and "✓  " or "○  ") .. name(child.name),
					function()
						if target then
							mutate("PUT", "/task/" .. child.id, { status = target })
						end
					end,
					{
						id = "subtask_" .. child.id,
						color = done(child) and C.muted or C.text,
						background = C.card,
						height = 34,
						width = "Fill",
					}
				)
			end
			if #kids > 5 then
				child_nodes[#child_nodes + 1] = action_button(
					show_subtasks and "Show fewer ↑" or ("Show " .. (#kids - 5) .. " more ↓"),
					function()
						subtasks_open:set(not subtasks_open:get())
					end,
					{ id = "subtasks_toggle", color = C.mauve }
				)
			end
			add(column({ width = "Fill", spacing = 4, children = child_nodes }))
		end
		add(section_title("Activity"))
		local recent = {}
		for i = 1, math.min(#notes, 5) do
			local entry = notes[i]
			recent[#recent + 1] = column({
				width = "Fill",
				padding = 10,
				radius = 8,
				background = C.card,
				spacing = 4,
				children = {
					caption(name(entry.user and entry.user.username), C.mauve, 11),
					note(entry.comment_text or "", C.text),
				},
			})
		end
		if #recent == 0 then
			recent[1] = note("No comments yet.", C.muted)
		end
		add(column({ width = "Fill", spacing = 6, children = recent }))
		add(rect({
			width = "Fill",
			height = 35,
			radius = 8,
			background = C.side,
			padding = { left = 10, right = 10 },
			children = {
				textfield({
					id = "comment_field",
					width = "Fill",
					height = "Fill",
					font_size = 13,
					foreground = C.text,
					placeholder = "Write an update and press Enter",
					on_submit = function(value)
						value = value:match("^%s*(.-)%s*$")
						if value ~= "" then
							mutate(
								"POST",
								"/task/" .. task.id .. "/comment",
								{ comment_text = value, notify_all = false },
								"Comment posted"
							)
						end
					end,
				}),
			},
		}))
		return nodes
	end

	local function properties_nodes(task, info)
		if not task then
			return {}
		end
		local nodes = {}
		if info and info.statuses then
			nodes[#nodes + 1] = section_title("Status")
			local options = {}
			for _, status in ipairs(info.statuses) do
				options[#options + 1] = {
					value = status.status,
					label = name(status.status):lower(),
					color = status.type == "done" and C.green or status.type == "custom" and C.yellow or C.mauve,
				}
			end
			-- Statuses vary by list. A vertical stack stays usable when there are many.
			local chips = {}
			for _, item in ipairs(options) do
				chips[#chips + 1] = action_button(item.label, function()
					if task.status.status ~= item.value then
						update_task({ status = item.value })
					end
				end, {
					id = "status_" .. item.value:gsub("%W", "_"),
					width = "Fill",
					height = 30,
					color = task.status.status == item.value and C.bg or item.color,
					background = task.status.status == item.value and item.color or C.side,
				})
			end
			nodes[#nodes + 1] = column({ width = "Fill", spacing = 4, children = chips })
		end
		nodes[#nodes + 1] = section_title("Priority")
		local priority = tonumber(task.priority and task.priority.id) or 0
		local priorities = {
			{ value = 1, label = "Urgent", color = C.red },
			{ value = 2, label = "High", color = C.peach },
			{ value = 3, label = "Normal", color = C.sky },
			{ value = 4, label = "Low", color = C.dim },
			{ value = 0, label = "None", color = C.muted },
		}
		local priority_nodes = {}
		for _, item in ipairs(priorities) do
			priority_nodes[#priority_nodes + 1] = action_button(item.label, function()
				if priority ~= item.value then
					update_task({ priority = item.value == 0 and api.NULL or item.value })
				end
			end, {
				id = "priority_" .. item.value,
				width = "Fill",
				height = 29,
				color = priority == item.value and C.bg or item.color,
				background = priority == item.value and item.color or C.side,
			})
		end
		nodes[#nodes + 1] = column({ width = "Fill", spacing = 4, children = priority_nodes })
		nodes[#nodes + 1] = section_title("Due")
		nodes[#nodes + 1] = caption(task.due_date and date_label(task.due_date) or "No date", C.sky, 13)
		nodes[#nodes + 1] = action_button("Set for today", function()
			local day = os.date("*t")
			day.hour, day.min, day.sec = 23, 59, 0
			update_task({ due_date = os.time(day) * 1000, due_date_time = false })
		end, { border = true })
		if task.due_date then
			nodes[#nodes + 1] = action_button("Clear date", function()
				update_task({ due_date = api.NULL, due_date_time = false })
			end, { color = C.muted })
		end
		nodes[#nodes + 1] = section_title("Rename")
		nodes[#nodes + 1] = rect({
			width = "Fill",
			height = 34,
			radius = 8,
			background = C.side,
			padding = { left = 10, right = 10 },
			children = {
				textfield({
					id = "rename_field",
					width = "Fill",
					height = "Fill",
					font_size = 12,
					foreground = C.text,
					placeholder = "New name, then Enter",
					on_submit = function(value)
						value = value:match("^%s*(.-)%s*$")
						if value ~= "" and value ~= name(task.name) then
							update_task({ name = value })
						end
					end,
				}),
			},
		})
		if task.time_spent and tonumber(task.time_spent) and tonumber(task.time_spent) > 0 then
			nodes[#nodes + 1] =
				caption("Logged " .. math.floor(tonumber(task.time_spent) / 60000) .. " min", C.green, 12)
		end
		return nodes
	end

	local current_header = computed({ detail, running }, header_nodes)
	local current_detail = computed({ detail, list_info, comments, description_open, subtasks_open }, detail_nodes)
	local current_props = computed({ detail, list_info }, properties_nodes)

	return current_header, current_detail, current_props
end
