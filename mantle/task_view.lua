-- The selected task, its reading view, and its properties.
local markdown = require("markdown")
local editor = require("editor")

return function(model, widgets)
	local api, C, motion = model.api, model.C, model.motion
	local selected, detail, detail_error, list_info, comments =
		model.selected, model.detail, model.detail_error, model.list_info, model.comments
	local running, description_open, subtasks_open = model.running, model.description_open, model.subtasks_open
	local name, done, overdue, blocked, date_label =
		model.name, model.done, model.overdue, model.blocked, model.date_label
	local team_id, mutate, update_task = model.team_id, model.mutate, model.update_task
	local caption, action_button, note = widgets.caption, widgets.action_button, widgets.note

	local function section_title(label)
		return text({ content = label, foreground = C.dim, font_size = 13 })
	end
	local function status_color(status)
		local label = name(status and status.status):lower()
		if label:find("cancel", 1, true) or label:find("reject", 1, true) or label:find("abandon", 1, true) then
			return C.dim
		elseif status and (status.type == "done" or status.type == "closed") then
			return C.green
		elseif status and status.type == "custom" then
			return C.yellow
		end
		return C.mauve
	end
	local function field_value(field)
		local value = field.value
		if value == nil or value == "" or type(value) == "table" then
			return nil
		end
		if field.type == "drop_down" then
			for _, option in ipairs(field.type_config and field.type_config.options or {}) do
				if tostring(option.orderindex) == tostring(value) then
					return name(option.name)
				end
			end
			return nil
		elseif field.type == "checkbox" then
			return (value == true or value == "true") and "Yes" or nil
		elseif field.type == "date" then
			return date_label(value)
		end
		return name(value)
	end

	local function choice_label(label, background, foreground, height)
		return rect({
			width = "Fill",
			height = height or 30,
			radius = 9,
			padding = { left = 12, right = 12 },
			background = background,
			children = {
				column({
					height = "Fill",
					align_v = "Center",
					children = {
						text({
							content = label,
							width = "Fill",
							elide = "End",
							foreground = foreground,
							font_size = 12,
						}),
					},
				}),
			},
		})
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
			spacing = 10,
			align_v = "Center",
			children = {
				rect({
					width = 7,
					height = 7,
					radius = 4,
					background = overdue(task) and C.red or status_color(task.status),
					align_v = "Center",
				}),
				caption(name(task.status and task.status.status):lower(), status_color(task.status), 12),
				caption(name(task.list and task.list.name), C.dim, 12),
				caption(date_label(task.due_date), overdue(task) and C.red or C.sky, 12),
			},
		}))
		local on_this = current and current.task and current.task.id == task.id
		local controls = {}
		if not done(task) or on_this then
			controls[#controls + 1] = action_button(on_this and "Stop timer" or "Start timer", function()
				local id = team_id:get()
				local path = "/team/" .. id .. "/time_entries/" .. (on_this and "stop" or "start")
				mutate("POST", path, on_this and nil or { tid = task.id }, "Timer updated")
			end, {
				color = C.bg,
				background = on_this and C.green or C.mauve,
				hover = on_this and C.green or C.dim,
				mutation = true,
			})
		end
		if task.url and task.url ~= "" then
			controls[#controls + 1] = action_button("Open in ClickUp", function()
				process.detach("xdg-open", { task.url })
			end, { border = true })
		end
		if #controls > 0 then
			add(row({ width = "Fill", spacing = 8, children = controls }))
		end
		local has_subtasks = #(task.subtasks or {}) > 0
		local offset = blocked(task) and 1 or 0
		local jumps = {
			caption("Jump to", C.muted, 11),
			action_button("↓ Description", function()
				scroll("now_detail_scroll"):reveal(1 + offset)
			end, { id = "jump_description", color = C.mauve, background = C.bg, height = 28 }),
		}
		if has_subtasks then
			jumps[#jumps + 1] = action_button("↓ Subtasks " .. #(task.subtasks or {}), function()
				scroll("now_detail_scroll"):reveal(3 + offset)
			end, { id = "jump_subtasks", color = C.mauve, background = C.bg, height = 28 })
		end
		jumps[#jumps + 1] = action_button("↓ Activity", function()
			scroll("now_detail_scroll"):reveal((has_subtasks and 6 or 3) + offset)
		end, { id = "jump_activity", color = C.mauve, background = C.bg, height = 28 })
		add(row({ width = "Fill", spacing = 6, align_v = "Center", children = jumps }))
		return nodes
	end

	local function detail_nodes(task, blocks, info, notes, expanded, show_subtasks, err)
		if not task then
			return {
				note(
					err ~= "" and "Could not open this task. Select it again to retry."
						or selected:get() == "" and "Choose a task to begin."
						or "Opening task…"
				),
			}
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
		blocks = blocks or {}
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
		reading[#reading + 1] = action_button("Edit markdown ↗", function()
			editor.edit(task, model)
		end, { id = "edit_description", color = C.mauve, background = C.surface })
		add(column({
			id = "task_description_" .. tostring(task.id),
			width = "Fill",
			padding = 18,
			radius = 12,
			background = C.card,
			spacing = 9,
			opacity = 1,
			translate = { x = 0, y = 0 },
			animate = motion and {
				opacity = { duration = 180, easing = "OutCubic", from = 0 },
				translate = { duration = 220, easing = "OutCubic", from = { x = 0, y = 10 } },
			} or nil,
			children = reading,
		}))
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
						animate = motion and { width = { duration = 240, easing = "OutCubic", from = "0%" } } or nil,
					}),
				},
			}))
			local child_nodes = {}
			local done_status, open_status
			for _, status in ipairs(info and info.statuses or {}) do
				local label = name(status.status):lower()
				local cancelled = label:find("cancel", 1, true)
					or label:find("reject", 1, true)
					or label:find("abandon", 1, true)
				if status.type == "done" or (status.type == "closed" and not cancelled and not done_status) then
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
				local label = (done(child) and "✓  " or "○  ") .. name(child.name)
				if target then
					child_nodes[#child_nodes + 1] = action_button(label, function()
						mutate("PUT", "/task/" .. child.id, { status = target })
					end, {
						id = "subtask_" .. child.id,
						color = done(child) and C.muted or C.text,
						background = C.card,
						height = 34,
						width = "Fill",
						mutation = true,
					})
				else
					child_nodes[#child_nodes + 1] = choice_label(label, C.bg, C.muted, 34)
				end
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
		local nodes, groups = {}, {}
		local function finish_group()
			groups[#groups + 1] = column({ width = "Fill", spacing = 7, children = nodes })
			nodes = {}
		end
		if info and info.statuses then
			nodes[#nodes + 1] = section_title("Status")
			local current_status = task.status and task.status.status or ""
			local options = {}
			for _, status in ipairs(info.statuses) do
				options[#options + 1] = {
					value = status.status,
					label = name(status.status):lower(),
					color = status_color(status),
				}
			end
			-- Statuses vary by list. A vertical stack stays usable when there are many.
			local chips = {}
			for _, item in ipairs(options) do
				if current_status == item.value then
					chips[#chips + 1] = choice_label(item.label .. "  ✓", item.color, C.bg, 30)
				else
					chips[#chips + 1] = action_button(item.label, function()
						update_task({ status = item.value })
					end, {
						id = "status_" .. item.value:gsub("%W", "_"),
						width = "Fill",
						height = 30,
						color = item.color,
						background = C.card,
						mutation = true,
					})
				end
			end
			nodes[#nodes + 1] = column({ width = "Fill", spacing = 4, children = chips })
		else
			nodes[#nodes + 1] = section_title("Status")
			nodes[#nodes + 1] = caption(name(task.status and task.status.status):lower(), C.dim, 12)
		end
		finish_group()
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
			if priority == item.value then
				priority_nodes[#priority_nodes + 1] = choice_label(item.label .. "  ✓", item.color, C.bg, 29)
			else
				priority_nodes[#priority_nodes + 1] = action_button(item.label, function()
					update_task({ priority = item.value == 0 and api.NULL or item.value })
				end, {
					id = "priority_" .. item.value,
					width = "Fill",
					height = 29,
					color = item.color,
					background = C.card,
					mutation = true,
				})
			end
		end
		nodes[#nodes + 1] = column({ width = "Fill", spacing = 4, children = priority_nodes })
		finish_group()
		nodes[#nodes + 1] = section_title("Due")
		nodes[#nodes + 1] = caption(task.due_date and date_label(task.due_date) or "No date", C.sky, 13)
		nodes[#nodes + 1] = rect({
			width = "Fill",
			height = 34,
			radius = 8,
			background = C.bg,
			padding = { left = 10, right = 10 },
			children = {
				textfield({
					id = "due_date_field",
					width = "Fill",
					height = "Fill",
					font_size = 12,
					foreground = C.text,
					placeholder = "YYYY-MM-DD, then Enter",
					on_submit = function(value)
						local year, month, day = value:match("^%s*(%d%d%d%d)%-(%d%d)%-(%d%d)%s*$")
						if not year then
							model.message:set("Use a date like 2026-09-27.")
							return
						end
						local y, m, d = tonumber(year), tonumber(month), tonumber(day)
						local parts = { year = y, month = m, day = d, hour = 23, min = 59, sec = 0 }
						local stamp = os.time(parts)
						local normalized = os.date("*t", stamp)
						if normalized.year ~= y or normalized.month ~= m or normalized.day ~= d then
							model.message:set("That date is not valid.")
							return
						end
						update_task({ due_date = stamp * 1000, due_date_time = false })
					end,
				}),
			},
		})
		local due_today = task.due_date
			and tonumber(task.due_date)
			and os.date("%Y-%m-%d", math.floor(tonumber(task.due_date) / 1000)) == os.date("%Y-%m-%d")
		if not due_today then
			nodes[#nodes + 1] = action_button("Set for today", function()
				local day = os.date("*t")
				day.hour, day.min, day.sec = 23, 59, 0
				update_task({ due_date = os.time(day) * 1000, due_date_time = false })
			end, { border = true, mutation = true })
		end
		if task.due_date then
			nodes[#nodes + 1] = action_button("Clear date", function()
				update_task({ due_date = api.NULL, due_date_time = false })
			end, { color = C.muted, mutation = true })
		end
		local fields = {}
		for _, field in ipairs(task.custom_fields or {}) do
			local value = field_value(field)
			if value and not name(field.name):lower():find("block", 1, true) then
				fields[#fields + 1] = caption(name(field.name) .. ": " .. value, C.dim, 12)
			end
		end
		if #fields > 0 then
			nodes[#nodes + 1] = section_title("Fields")
			for _, field in ipairs(fields) do
				nodes[#nodes + 1] = field
			end
		end
		local files = task.attachments or {}
		if #files > 0 then
			nodes[#nodes + 1] = section_title("Files")
			for _, file in ipairs(files) do
				if file.url and file.url ~= "" then
					nodes[#nodes + 1] = action_button(name(file.title or file.name or "Open file") .. " ↗", function()
						process.detach("xdg-open", { file.url })
					end, { width = "Fill", color = C.mauve })
				end
			end
		end
		finish_group()
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
		if task.time_estimate and tonumber(task.time_estimate) and tonumber(task.time_estimate) > 0 then
			nodes[#nodes + 1] =
				caption("Estimate " .. math.floor(tonumber(task.time_estimate) / 60000) .. " min", C.sky, 12)
		end
		local tags = {}
		for _, tag in ipairs(task.tags or {}) do
			tags[#tags + 1] = name(tag.name)
		end
		if #tags > 0 then
			nodes[#nodes + 1] = note("Tags  " .. table.concat(tags, ", "), C.mauve)
		end
		local people = {}
		for _, person in ipairs(task.assignees or {}) do
			people[#people + 1] = name(person.username)
		end
		if #people > 0 then
			nodes[#nodes + 1] = note("Assigned  " .. table.concat(people, ", "), C.dim)
		end
		if task.date_created then
			nodes[#nodes + 1] = caption("Created " .. date_label(task.date_created), C.muted, 11)
		end
		finish_group()
		return groups
	end

	local current_header = computed({ detail, running }, header_nodes)
	local description_blocks = detail:map(function(task)
		return task and markdown.blocks(task.markdown_description or task.description or "") or {}
	end)
	local current_detail = computed(
		{ detail, description_blocks, list_info, comments, description_open, subtasks_open, detail_error },
		detail_nodes
	)
	local current_props = computed({ detail, list_info }, properties_nodes)
	local compact_props = computed({ detail, list_info }, function(task, info)
		local groups = properties_nodes(task, info)
		if #groups == 0 then
			return {}
		end
		return {
			row({
				width = "Fill",
				spacing = 16,
				children = {
					column({ width = "Fill", spacing = 18, children = { groups[1], groups[3] } }),
					column({ width = "Fill", spacing = 18, children = { groups[2], groups[4] } }),
				},
			}),
		}
	end)

	return current_header, current_detail, current_props, compact_props
end
