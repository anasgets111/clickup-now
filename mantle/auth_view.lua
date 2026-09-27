-- The first-run view. The secure field sends the token to Secret Service;
-- no Lua callback or state receives its bytes.
return function(model, action_button)
	local C, motion = model.C, model.motion
	local secret_status = mantle.secrets:map(function(secrets)
		return secrets and secrets.entries and secrets.entries["clickup-now-token"] or nil
	end)
	local feedback = computed({ model.auth_state, model.auth_error, secret_status }, function(auth, err, stored)
		if err ~= "" then
			return err
		end
		if stored == "pending" then
			return "Saving token securely…"
		end
		if auth == "checking" then
			return "Checking for a saved token…"
		end
		if auth == "connecting" then
			return "Connecting to ClickUp…"
		end
		return "Paste your token and press Enter, or choose Connect."
	end)

	local function label(value, color, size)
		return text({ content = value, foreground = color or C.dim, font_size = size or 12 })
	end

	local function step(number, title, detail)
		return row({
			width = "Fill",
			spacing = 14,
			children = {
				rect({
					width = 32,
					height = 32,
					radius = 9,
					background = C.surface,
					children = {
						column({
							height = "Fill",
							align_v = "Center",
							align_h = "Center",
							children = { label(number, C.mauve, 13) },
						}),
					},
				}),
				column({
					width = "Fill",
					spacing = 5,
					children = {
						label(title, C.text, 15),
						text({ content = detail, width = "Fill", wrap = "Word", foreground = C.dim, font_size = 13 }),
					},
				}),
			},
		})
	end

	local content = column({
		width = "Fill",
		max_width = 630,
		align_v = "Center",
		spacing = 22,
		children = {
			column({
				width = "Fill",
				spacing = 12,
				children = {
					label("CLICKUP  /  CONNECTION", C.mauve, 12),
					text({
						content = "Connect ClickUp",
						font = "Noto Sans",
						foreground = C.text,
						font_size = 38,
					}),
					text({
						content = "See your assigned work, keep time, and make quick updates from one window.",
						width = "Fill",
						wrap = "Word",
						foreground = C.dim,
						font_size = 15,
					}),
				},
			}),
			column({
				width = "Fill",
				padding = 24,
				radius = 16,
				background = C.card,
				border_width = 1,
				border_color = C.border,
				spacing = 20,
				opacity = 1,
				translate = { x = 0, y = 0 },
				animate = motion and {
					opacity = { duration = 180, easing = "OutCubic", from = 0 },
					translate = { duration = 220, easing = "OutCubic", from = { x = 0, y = 10 } },
				} or nil,
				children = {
					step("01", "Get a personal token", "In ClickUp, open Settings → Apps and copy your API token."),
					row({
						width = "Fill",
						padding = { left = 46 },
						children = {
							action_button("Open ClickUp settings ↗", function()
								process.detach("xdg-open", { "https://app.clickup.com/settings/apps" })
							end, {
								id = "open_clickup_token_settings",
								background = C.mauve,
								hover = C.sky,
								color = C.bg,
								height = 36,
							}),
						},
					}),
					rect({ width = "Fill", height = 1, background = C.border }),
					step("02", "Add it to Now", "Paste your token below. It will be saved securely on this device."),
					row({
						width = "Fill",
						spacing = 8,
						children = {
							rect({
								width = "Fill",
								height = 40,
								padding = { left = 12, right = 12 },
								radius = 9,
								background = C.side,
								border_width = 1,
								border_color = C.border,
								children = {
									textfield({
										id = "clickup_token",
										width = "Fill",
										height = "Fill",
										placeholder = "Paste personal API token",
										foreground = C.text,
										font_size = 13,
										secure_submit = {
											capability = "secrets",
											action = "store",
											name = "clickup-now-token",
										},
									}),
								},
							}),
							button({
								id = "connect_clickup",
								height = 40,
								padding = { left = 16, right = 16 },
								radius = 9,
								background = C.mauve,
								submit = true,
								children = {
									column({
										height = "Fill",
										align_v = "Center",
										children = { label("Connect", C.bg, 12) },
									}),
								},
							}),
						},
					}),
					text({
						content = feedback,
						width = "Fill",
						wrap = "Word",
						foreground = model.auth_error:map(function(err)
							return err ~= "" and C.red or C.dim
						end),
						font_size = 12,
					}),
				},
			}),
		},
	})

	return column({
		width = "Fill",
		height = "Fill",
		background = C.bg,
		children = {
			row({
				width = "Fill",
				padding = { left = 26, right = 26, top = 20, bottom = 20 },
				spacing = 10,
				align_v = "Center",
				children = {
					rect({ width = 8, height = 8, radius = 4, background = C.mauve }),
					text({ content = "Now", font = "Noto Sans", foreground = C.text, font_size = 21 }),
					rect({ width = "Fill" }),
					label("CLICKUP", C.muted, 11),
				},
			}),
			row({
				width = "Fill",
				height = "Fill",
				padding = { left = 24, right = 24 },
				align_h = "Center",
				align_v = "Center",
				children = { content },
			}),
			row({
				width = "Fill",
				align_h = "Center",
				padding = { bottom = 24 },
				children = { label("A personal ClickUp token is required to load your tasks.", C.muted, 11) },
			}),
		},
	})
end
