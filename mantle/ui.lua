-- Mantle nodes for the Now window. Data and ClickUp actions live in model.lua.
return function(model)
	local C, prefs, motion = model.C, model.prefs, model.motion
	local selected = model.selected
	local teams, me, team_id, query, lens = model.teams, model.me, model.team_id, model.query, model.lens
	local busy, loading, message, changes = model.busy, model.loading, model.message, model.changes
	local running = model.running
	local groups, pins, watch = model.groups, model.pins, model.watch
	local picker_open = state("now_list_picker_open", false)
	local spaces = state("now_picker_spaces", {})
	local picker_lists = state("now_picker_lists", {})
	local picker_error = state("now_picker_error", "")
	local picker_space = state("now_picker_space", "")
	local picker_space_name = state("now_picker_space_name", "")
	local picker_loading = state("now_picker_loading", false)
	local picker_query = state("now_picker_query", "")
	if picker_open:get() then
		scroll("now_list_picker"):reveal(1)
	end
	local name, status_type, done, overdue, date_label =
		model.name, model.status_type, model.done, model.overdue, model.date_label
	local visible_picker_lists = computed({ picker_lists, picker_query }, function(all, search)
		local out = {}
		search = name(search):lower()
		for _, item in ipairs(all) do
			local label = name(item.under or "") .. " " .. name(item.name)
			if search == "" or label:lower():find(search, 1, true) then
				out[#out + 1] = item
			end
		end
		return out
	end)
	local closed, filtered = model.closed, model.filtered
	local open_task, refresh, choose_team = model.open_task, model.refresh, model.choose_team

	local function caption(value, color, size)
		return text({ content = tostring(value or ""), foreground = color or C.dim, font_size = size or 13 })
	end

	local function action_button(label, fn, opts)
		opts = opts or {}
		local key = "now_hover_" .. (opts.id or (type(label) == "string" and label:gsub("%W", "_") or "action"))
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
			opacity = opts.mutation and busy:map(function(saving)
				return saving and 0.65 or 1
			end) or 1,
			animate = motion and { background = { duration = 140, easing = "OutCubic" } } or nil,
			border_width = opts.border and 1 or 0,
			border_color = opts.border and C.border or nil,
			on_click = function(_, which)
				if which == "left" and (not opts.mutation or not busy:get()) then
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
		local hovering = hover("now_task_hover_" .. tostring(task.id))
		return button({
			width = "Fill",
			height = 72,
			radius = 10,
			hover = hovering,
			background = computed({ selected, hovering }, function(id, over)
				return id == task.id and C.surface or over and C.card or C.side
			end),
			animate = motion and { background = { duration = 180, easing = "OutCubic" } } or nil,
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
							width = 4,
							height = 42,
							radius = 2,
							background = selected:map(function(id)
								return id == task.id and C.mauve
									or is_late and C.red
									or status_type(task) == "custom" and C.yellow
									or C.border
							end),
							animate = motion and { background = 180 } or nil,
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
	local current_header, current_detail, current_props, compact_props =
		task_view(model, { caption = caption, action_button = action_button, note = note })
	local window_bounds = geometry("now_window_bounds")
	local compact = window_bounds:map(function(bounds)
		return bounds and bounds.width > 0 and bounds.width < 1320
	end)
	local compact_panel_height = window_bounds:map(function(bounds)
		local height = bounds and bounds.height or 900
		return math.min(320, math.max(180, math.floor(height * 0.31)))
	end)
	local settings_open = state("now_settings_open", false)
	local compact_settings_control_visible = computed({ compact, selected }, function(narrow, id)
		return narrow and id ~= ""
	end)
	-- A zero-height mounted panel keeps the parent's spacing stable at the end of a close.
	local compact_panel_motion = motion
			and settings_open:map(function(open)
				local duration = open and 220 or 180
				local easing = open and "OutCubic" or "InCubic"
				return {
					height = { duration = duration, easing = easing, from = 0 },
					margin = { duration = duration, easing = easing, from = { bottom = -14 } },
					padding = { duration = duration, easing = easing, from = { left = 12, right = 12 } },
					opacity = { duration = open and 150 or 100, delay = open and 35 or 0, easing = easing, from = 0 },
					translate = { duration = duration, easing = easing, from = { x = 0, y = -8 } },
				}
			end)
		or nil
	local empty_message = computed(
		{ filtered, me, team_id, loading, query, lens, selected },
		function(all, user, workspace, fetching, search, mode, open_id)
			if #all > 0 then
				return ""
			elseif fetching then
				return "Loading tasks…"
			elseif not user then
				return "Connect ClickUp to load tasks."
			elseif workspace == "" then
				return "Choose a workspace above."
			elseif search ~= "" then
				return open_id ~= "" and "No tasks match that search. The open task stays visible."
					or "No tasks match that search."
			elseif mode ~= "all" then
				return open_id ~= "" and "No tasks in this view. Try All; the open task stays visible."
					or "No tasks in this view. Try All."
			end
			return "No assigned tasks found."
		end
	)
	local rail_items = groups:map(function(sections)
		local items = {}
		for index, section in ipairs(sections or {}) do
			if #section.list > 0 or section.pin then
				items[#items + 1] = { kind = "heading", key = "heading_" .. index, section = section }
				for _, task in ipairs(section.list) do
					items[#items + 1] = { kind = "task", key = "task_" .. tostring(task.id), task = task }
				end
			end
		end
		return items
	end)
	local function open_picker()
		if picker_open:get() then
			picker_open:set(false)
			return
		end
		picker_open:set(true)
		scroll("now_list_picker"):reveal(1)
		picker_space:set("")
		picker_space_name:set("")
		picker_query:set("")
		picker_loading:set(true)
		picker_error:set("")
		spaces:set({})
		picker_lists:set({})
		model.load_spaces(function(err, found)
			picker_loading:set(false)
			if err then
				picker_error:set(err)
			else
				spaces:set(found)
			end
		end)
	end
	local function choose_space(id, label)
		picker_space:set(id)
		scroll("now_list_picker"):reveal(1)
		picker_space_name:set(label)
		picker_query:set("")
		picker_loading:set(true)
		picker_error:set("")
		picker_lists:set({})
		model.load_lists(id, function(err, found)
			picker_loading:set(false)
			if err then
				picker_error:set(err)
			else
				picker_lists:set(found)
			end
		end)
	end

	local function lens_button(key, label)
		return button({
			height = 28,
			padding = { left = 10, right = 10 },
			radius = 14,
			background = lens:map(function(current)
				return current == key and C.mauve or C.card
			end),
			animate = motion and { background = { duration = 170, easing = "OutCubic" } } or nil,
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

	local closed_hover = hover("now_closed_hover")
	local closed_button = button({
		height = 28,
		padding = { left = 10, right = 10 },
		radius = 14,
		hover = closed_hover,
		background = computed({ closed, closed_hover }, function(active, over)
			return active and C.mauve or over and C.surface or C.card
		end),
		animate = motion and { background = 170 } or nil,
		on_click = function(_, which)
			if which == "left" then
				local next_value = not closed:get()
				prefs:set("closed", next_value)
				refresh(next_value)
			end
		end,
		children = {
			column({
				height = "Fill",
				align_v = "Center",
				children = {
					text({
						content = "Closed",
						font_size = 11,
						foreground = closed:map(function(active)
							return active and C.bg or C.dim
						end),
					}),
				},
			}),
		},
	})

	local sidebar = column({
		width = 316,
		height = "Fill",
		background = C.side,
		padding = { left = 18, right = 18, top = 22, bottom = 18 },
		spacing = 14,
		children = {
			row({
				width = "Fill",
				align_v = "Center",
				children = {
					text({ content = "Now", font = "Noto Sans", foreground = C.text, font_size = 31 }),
					rect({ width = "Fill" }),
					action_button(
						loading:map(function(active)
							return active and "Refreshing…" or "Refresh"
						end),
						refresh,
						{ id = "refresh", color = C.mauve, size = 11, border = true }
					),
				},
			}),
			row({
				width = "Fill",
				children = {
					text({
						content = me:map(function(user)
							return user and name(user.username) or "Your ClickUp work"
						end),
						width = "Fill",
						elide = "End",
						foreground = C.dim,
						font_size = 12,
					}),
					text({
						content = mantle.system:map(function(system)
							return os.date("%d %b", system and system.time or os.time())
						end),
						foreground = C.muted,
						font_size = 12,
					}),
				},
			}),
			row({
				width = "Fill",
				visible = running:map(function(entry)
					return entry ~= nil and entry.task ~= nil and entry.task.id ~= nil
				end),
				children = {
					action_button(
						computed({ running, mantle.system }, function(entry, system)
							if not entry or not entry.task then
								return ""
							end
							local elapsed = math.max(
								0,
								(system and system.time or os.time()) - math.floor((tonumber(entry.start) or 0) / 1000)
							)
							return "●  " .. math.floor(elapsed / 60) .. "m  ·  " .. name(entry.task.name)
						end),
						function()
							local entry = running:get()
							if entry and entry.task and entry.task.id then
								open_task(entry.task.id)
							end
						end,
						{ id = "running_task", width = "Fill", color = C.green, background = C.card }
					),
				},
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
					closed_button,
				},
			}),
			row({
				width = "Fill",
				spacing = 7,
				children = {
					action_button(
						picker_open:map(function(open)
							return open and "Close lists ↑" or "+ List"
						end),
						open_picker,
						{ id = "list_picker_toggle", color = C.mauve, height = 28 }
					),
					action_button(
						watch:map(function(enabled)
							return enabled and "Watching ✓" or "Watching"
						end),
						function()
							model.set_watch(not watch:get())
						end,
						{ id = "watch_toggle", color = C.sky, height = 28, background = C.card }
					),
				},
			}),
			column({
				width = "Fill",
				max_height = 320,
				visible = picker_open,
				scroll = scroll("now_list_picker"),
				padding = 10,
				radius = 9,
				background = C.bg,
				spacing = 8,
				children = {
					row({
						width = "Fill",
						align_v = "Center",
						children = {
							caption("PIN A LIST", C.mauve, 11),
							rect({ width = "Fill" }),
							text({
								content = picker_space:map(function(id)
									return id == "" and "1 / 2" or "2 / 2"
								end),
								foreground = C.muted,
								font_size = 11,
							}),
						},
					}),
					text({
						content = picker_space:map(function(id)
							return id == "" and "Choose a space" or "Select lists to show in your task rail"
						end),
						foreground = C.dim,
						font_size = 12,
					}),
					text({
						content = picker_loading:map(function(active)
							return active and "Loading…" or ""
						end),
						visible = picker_loading,
						foreground = C.sky,
						font_size = 11,
					}),
					text({
						content = picker_error,
						visible = picker_error:map(function(value)
							return value ~= ""
						end),
						foreground = C.red,
						font_size = 11,
						width = "Fill",
						wrap = "Word",
					}),
					list({
						width = "Fill",
						visible = picker_space:map(function(id)
							return id == ""
						end),
						source = spaces,
						spacing = 4,
						key = function(item)
							return tostring(item.id)
						end,
						itemfn = function(item)
							local over = hover("space_" .. tostring(item.id))
							return button({
								id = "space_" .. item.id,
								width = "Fill",
								height = 39,
								radius = 9,
								hover = over,
								background = over:map(function(active)
									return active and C.surface or C.card
								end),
								animate = motion and { background = { duration = 140, easing = "OutCubic" } } or nil,
								on_click = function(_, which)
									if which == "left" then
										choose_space(tostring(item.id), name(item.name))
									end
								end,
								children = {
									row({
										width = "Fill",
										height = "Fill",
										align_v = "Center",
										spacing = 9,
										padding = { left = 9, right = 12 },
										children = {
											rect({ width = 3, height = 18, radius = 2, background = C.mauve }),
											text({
												content = name(item.name),
												width = "Fill",
												elide = "End",
												foreground = C.text,
												font_size = 12,
											}),
											caption("→", C.mauve, 14),
										},
									}),
								},
							})
						end,
					}),
					row({
						width = "Fill",
						visible = picker_space:map(function(id)
							return id ~= ""
						end),
						children = {
							action_button(
								picker_space_name:map(function(label)
									return "←  " .. label
								end),
								function()
									picker_space:set("")
									picker_query:set("")
									picker_error:set("")
								end,
								{
									id = "picker_back",
									width = "Fill",
									height = 30,
									color = C.mauve,
									background = C.side,
								}
							),
						},
					}),
					rect({
						width = "Fill",
						height = 32,
						visible = picker_space:map(function(id)
							return id ~= ""
						end),
						background = C.side,
						radius = 8,
						padding = { left = 9, right = 9 },
						children = {
							textfield({
								id = "picker_search",
								width = "Fill",
								height = "Fill",
								font_size = 12,
								foreground = C.text,
								placeholder = "Find a list…",
								on_change = function(value)
									picker_query:set(value)
								end,
							}),
						},
					}),
					text({
						content = computed(
							{ picker_space, picker_loading, visible_picker_lists },
							function(id, loading_lists, found)
								return id ~= ""
										and not loading_lists
										and #found == 0
										and "No matching lists in this space."
									or ""
							end
						),
						visible = computed(
							{ picker_space, picker_loading, visible_picker_lists },
							function(id, loading_lists, found)
								return id ~= "" and not loading_lists and #found == 0
							end
						),
						foreground = C.muted,
						font_size = 11,
						width = "Fill",
					}),
					list({
						width = "Fill",
						visible = picker_space:map(function(id)
							return id ~= ""
						end),
						source = visible_picker_lists,
						spacing = 4,
						key = function(item)
							return tostring(item.id)
						end,
						itemfn = function(item)
							return action_button(
								pins:map(function(current)
									for _, pin in ipairs(current) do
										if tostring(pin.id) == tostring(item.id) then
											return "✓  " .. name(item.name) .. "  ·  pinned"
										end
									end
									return "+  " .. name(item.name)
								end),
								function()
									model.toggle_pin(
										item.id,
										item.under and (name(item.under) .. "/" .. name(item.name)) or name(item.name)
									)
								end,
								{
									id = "pin_" .. item.id,
									width = "Fill",
									height = 34,
									color = C.mauve,
									background = C.card,
								}
							)
						end,
					}),
				},
			}),
			text({
				content = "Choose a workspace",
				visible = computed({ teams, team_id }, function(all, chosen)
					return chosen == "" and #all > 1
				end),
				foreground = C.dim,
				font_size = 12,
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
			row({
				width = "Fill",
				children = {
					text({
						content = loading:map(function(v)
							return v and "Refreshing…" or "Tasks"
						end),
						width = "Fill",
						foreground = C.dim,
						font_size = 12,
					}),
					text({
						content = filtered:map(function(all)
							return tostring(#all)
						end),
						foreground = C.mauve,
						font_size = 12,
					}),
				},
			}),
			text({
				content = empty_message,
				visible = empty_message:map(function(value)
					return value ~= ""
				end),
				foreground = C.dim,
				font_size = 12,
				width = "Fill",
				wrap = "Word",
			}),
			list({
				width = "Fill",
				height = "Fill",
				scroll = scroll("now_task_list"),
				source = rail_items,
				key = function(item)
					return item.key
				end,
				itemfn = function(item)
					if item.kind == "task" then
						return task_row(item.task)
					end
					local section = item.section
					local children = {
						text({
							content = section.label .. "  " .. #section.list,
							width = "Fill",
							elide = "End",
							foreground = C.dim,
							font_size = 11,
						}),
					}
					if section.pin then
						children[#children + 1] = action_button("×", function()
							model.remove_pin(section.pin)
						end, { id = "unpin_" .. section.pin, color = C.muted, height = 24 })
					end
					return row({
						width = "Fill",
						align_v = "Center",
						padding = { top = 10, bottom = 3 },
						children = children,
					})
				end,
				spacing = 4,
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
			row({
				width = "Fill",
				visible = not model.api.has_env_token(),
				children = {
					action_button("Forget API token", model.forget_token, {
						id = "forget_api_token",
						color = C.muted,
						height = 28,
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
						visible = compact_settings_control_visible,
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
						height = computed({ settings_open, compact_panel_height }, function(open, height)
							return open and height or 0
						end),
						visible = compact_settings_control_visible,
						margin = settings_open:map(function(open)
							return { bottom = open and 0 or -14 }
						end),
						opacity = settings_open:map(function(open)
							return open and 1 or 0
						end),
						translate = settings_open:map(function(open)
							return { x = 0, y = open and 0 or -8 }
						end),
						animate = compact_panel_motion,
						scroll = scroll("now_compact_settings"),
						padding = settings_open:map(function(open)
							return { left = 12, right = 12, top = open and 12 or 0, bottom = open and 12 or 0 }
						end),
						radius = 10,
						background = C.side,
						spacing = 12,
						children = compact_props,
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
						content = computed({ message, busy }, function(value, saving)
							return saving and "Saving…" or value
						end),
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
		visible = computed({ compact, selected }, function(narrow, id)
			return not narrow and id ~= ""
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

	local connected_view = row({
		width = "Fill",
		height = "Fill",
		geometry = window_bounds,
		background = C.bg,
		children = { sidebar, stage, properties },
	})
	local connection_view = require("auth_view")(model, action_button)

	return window({
		id = "clickup_now",
		title = "Now · ClickUp",
		app_id = "clickup-now",
		min_size = model.auth_state:map(function(auth)
			return { width = auth == "connected" and 1040 or 560, height = 620 }
		end),
		on_close = function()
			process.detach("mantle", { "stop", "--pid", tostring(mantle.pid) })
		end,
		child = model.auth_state:map(function(auth)
			return auth == "connected" and connected_view or connection_view
		end),
	})
end
