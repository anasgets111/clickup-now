-- Mantle nodes for the Now window. Data and ClickUp actions live in model.lua.
return function(model)
	local api, C, prefs = model.api, model.C, model.prefs
	local tasks, selected, detail, list_info, comments =
		model.tasks, model.selected, model.detail, model.list_info, model.comments
	local teams, me, team_id, query, lens = model.teams, model.me, model.team_id, model.query, model.lens
	local busy, loading, message, running, changes =
		model.busy, model.loading, model.message, model.running, model.changes
	local closed, filtered = model.closed, model.filtered
	local description_open = model.description_open
	local subtasks_open = model.subtasks_open
	local name, status_type, done, overdue, blocked, date_label =
		model.name, model.status_type, model.done, model.overdue, model.blocked, model.date_label
	local open_task, refresh, choose_team, mutate, update_task =
		model.open_task, model.refresh, model.choose_team, model.mutate, model.update_task

	local function caption(value, color, size)
		return text({ content = tostring(value or ""), foreground = color or C.dim, font_size = size or 13 })
	end

	local function action_button(label, fn, opts)
		opts = opts or {}
		local key = "now_hover_" .. (opts.id or label:gsub("%W", "_"))
		return button({
			id = opts.id,
			width = opts.width,
			hover = hover(key),
			height = opts.height or 32,
			padding = { left = 12, right = 12 },
			radius = 9,
			background = hover(key):map(function(h)
				return h and (opts.hover or C.surface) or (opts.background or C.card)
			end),
			border_width = opts.border and 1 or 0,
			border_color = opts.border and C.border or nil,
			on_click = function(_, which)
				if which == "left" and not busy:get() then
					fn()
				end
			end,
			children = {
				column({
					width = opts.width == "Fill" and "Fill" or nil,
					height = "Fill",
					align_v = "Center",
					children = {
						text({
							content = label,
							width = opts.width == "Fill" and "Fill" or nil,
							elide = opts.width == "Fill" and "End" or nil,
							foreground = opts.color or C.text,
							font_size = opts.size or 12,
						}),
					},
				}),
			},
		})
	end

	local function note(value, color)
		return text({ content = value, width = "Fill", wrap = "Word", foreground = color or C.dim, font_size = 13 })
	end

	local function task_row(task)
		local where = name(task.list and task.list.name)
		local is_late = overdue(task)
		return button({
			width = "Fill",
			height = 64,
			radius = 10,
			background = selected:map(function(id)
				return id == task.id and C.surface or C.side
			end),
			on_click = function(_, which)
				if which == "left" then
					open_task(task.id)
				end
			end,
			children = {
				row({
					width = "Fill",
					height = "Fill",
					spacing = 10,
					padding = { left = 12, right = 10 },
					children = {
						rect({
							width = 3,
							height = 35,
							radius = 2,
							background = is_late and C.red or status_type(task) == "custom" and C.yellow or C.mauve,
							align_v = "Center",
						}),
						column({
							width = "Fill",
							align_v = "Center",
							spacing = 4,
							children = {
								text({
									content = name(task.name),
									width = "Fill",
									font_size = 14,
									foreground = done(task) and C.muted or C.text,
									elide = "End",
								}),
								row({
									width = "Fill",
									spacing = 8,
									children = {
										text({
											content = name(task.status and task.status.status):lower(),
											font_size = 11,
											foreground = status_type(task) == "custom" and C.yellow or C.dim,
										}),
										text({
											content = where,
											width = "Fill",
											font_size = 11,
											foreground = C.mauve,
											elide = "End",
										}),
										text({
											content = date_label(task.due_date),
											font_size = 11,
											foreground = is_late and C.red or C.sky,
										}),
									},
								}),
							},
						}),
					},
				}),
			},
		})
	end

	local task_view = require("task_view")
	local current_header, current_detail, current_props =
		task_view(model, { caption = caption, action_button = action_button, note = note })
	local window_bounds = geometry("now_window_bounds")
	local compact = window_bounds:map(function(bounds)
		return bounds and bounds.width > 0 and bounds.width < 1320
	end)
	local settings_open = state("now_settings_open", false)
	local compact_settings_visible = computed({ compact, settings_open }, function(narrow, open)
		return narrow and open
	end)

	local function lens_button(key, label)
		return button({
			height = 28,
			padding = { left = 10, right = 10 },
			radius = 14,
			background = lens:map(function(current)
				return current == key and C.mauve or C.card
			end),
			on_click = function(_, which)
				if which == "left" then
					lens:set(key)
				end
			end,
			children = {
				column({
					height = "Fill",
					align_v = "Center",
					children = {
						text({
							content = label,
							font_size = 11,
							foreground = lens:map(function(current)
								return current == key and C.bg or C.dim
							end),
						}),
					},
				}),
			},
		})
	end

	local sidebar = column({
		width = 340,
		height = "Fill",
		background = C.side,
		padding = { left = 18, right = 18, top = 20, bottom = 18 },
		spacing = 13,
		children = {
			row({
				width = "Fill",
				children = {
					text({ content = "NOW", foreground = C.mauve, font_size = 24 }),
					rect({ width = "Fill" }),
					action_button("↻", refresh, { id = "refresh", color = C.mauve, size = 19 }),
				},
			}),
			text({
				content = computed({ me, tasks }, function(user, all)
					return user and (name(user.username) .. "  ·  " .. #all .. " assigned") or "Your ClickUp work"
				end),
				foreground = C.dim,
				font_size = 12,
			}),
			rect({
				width = "Fill",
				height = 38,
				padding = { left = 12, right = 12 },
				radius = 9,
				background = C.bg,
				border_width = 1,
				border_color = C.border,
				children = {
					textfield({
						id = "search",
						width = "Fill",
						height = "Fill",
						font_size = 13,
						foreground = C.text,
						placeholder = "Find a task…",
						on_change = function(value)
							query:set(value)
						end,
					}),
				},
			}),
			row({
				width = "Fill",
				spacing = 4,
				children = {
					lens_button("open", "Open"),
					lens_button("flight", "In flight"),
					lens_button("late", "Late"),
					lens_button("all", "All"),
				},
			}),
			row({
				width = "Fill",
				spacing = 4,
				children = {
					lens_button("blocked", "Blocked"),
					lens_button("done", "Done"),
					action_button("Closed", function()
						local next_value = not closed:get()
						prefs:set("closed", next_value)
						refresh(next_value)
					end, { id = "closed_toggle", color = C.dim, size = 11 }),
				},
			}),
			list({
				width = "Fill",
				max_height = 180,
				spacing = 4,
				source = computed({ teams, team_id }, function(all, chosen)
					return chosen == "" and all or {}
				end),
				key = function(item)
					return tostring(item.id)
				end,
				itemfn = function(item)
					return action_button(name(item.name), function()
						choose_team(tostring(item.id))
					end, { id = "team_" .. item.id, color = C.mauve, border = true })
				end,
			}),
			text({
				content = loading:map(function(v)
					return v and "Refreshing…" or "Tasks"
				end),
				foreground = C.muted,
				font_size = 11,
			}),
			list({
				width = "Fill",
				height = "Fill",
				scroll = scroll("now_task_list"),
				source = filtered,
				key = function(task)
					return tostring(task.id)
				end,
				itemfn = task_row,
				spacing = 4,
			}),
			text({
				content = filtered:map(function(all)
					return #all == 0 and "Nothing matches this view." or ""
				end),
				foreground = C.muted,
				font_size = 12,
			}),
			row({
				width = "Fill",
				spacing = 8,
				children = {
					caption("ClickUp", C.muted, 11),
					caption("·", C.muted, 11),
					text({
						content = changes:map(function(n)
							return n > 0 and (n .. " changed · refresh") or "Up to date"
						end),
						foreground = C.mauve,
						font_size = 11,
					}),
				},
			}),
		},
	})

	local stage = row({
		width = "Fill",
		height = "Fill",
		padding = 24,
		align_h = "Center",
		background = C.bg,
		children = {
			column({
				width = "90%",
				max_width = 900,
				height = "Fill",
				spacing = 14,
				children = {
					column({ width = "Fill", spacing = 10, children = current_header }),
					row({
						width = "Fill",
						visible = compact,
						children = {
							action_button(
								settings_open:map(function(open)
									return open and "Hide task settings ↑" or "Task settings ↓"
								end),
								function()
									settings_open:set(not settings_open:get())
								end,
								{ id = "compact_settings", color = C.mauve, border = true }
							),
						},
					}),
					column({
						width = "Fill",
						height = 280,
						visible = compact_settings_visible,
						scroll = scroll("now_compact_settings"),
						padding = 12,
						radius = 10,
						background = C.side,
						spacing = 12,
						children = current_props,
					}),
					rect({ width = "Fill", height = 1, background = C.surface }),
					column({
						width = "Fill",
						height = "Fill",
						scroll = scroll("now_detail_scroll"),
						spacing = 16,
						children = current_detail,
					}),
					text({
						content = message,
						width = "Fill",
						foreground = C.peach,
						font_size = 12,
						wrap = "Word",
						max_lines = 2,
					}),
				},
			}),
		},
	})

	local properties = column({
		width = 250,
		height = "Fill",
		padding = 18,
		spacing = 12,
		background = C.side,
		visible = compact:map(function(narrow)
			return not narrow
		end),
		children = {
			text({ content = "Task settings", foreground = C.dim, font_size = 16 }),
			column({
				width = "Fill",
				height = "Fill",
				scroll = scroll("now_properties"),
				spacing = 12,
				children = current_props,
			}),
		},
	})

	return window({
		id = "clickup_now",
		title = "Now · ClickUp",
		app_id = "clickup-now",
		min_size = { width = 1040, height = 620 },
		on_close = function()
			process.detach("mantle", { "stop", "--pid", tostring(mantle.pid) })
		end,
		child = row({
			width = "Fill",
			height = "Fill",
			geometry = window_bounds,
			background = C.bg,
			children = { sidebar, stage, properties },
		}),
	})
end
