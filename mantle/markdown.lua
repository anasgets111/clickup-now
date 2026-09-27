-- Render ClickUp Markdown with Mantle text runs and layout nodes. Raw HTML stays
-- visible as text, matching the browser app's escaped Markdown behaviour.
local M = {}

local function decode(value)
	return value
		:gsub("&amp;", "&")
		:gsub("&lt;", "<")
		:gsub("&gt;", ">")
		:gsub("&quot;", '"')
		:gsub("&#39;", "'")
		:gsub("&nbsp;", " ")
end

local function inline(source, colors)
	local runs, plain, i = {}, {}, 1
	local function push(value, style)
		if value == "" then
			return
		end
		local run = { text = decode(value) }
		for key, item in pairs(style or {}) do
			run[key] = item
		end
		runs[#runs + 1] = run
	end
	local function flush()
		push(table.concat(plain))
		plain = {}
	end
	while i <= #source do
		local ch, next_ch = source:sub(i, i), source:sub(i + 1, i + 1)
		local close, after, style
		if ch == "[" then
			local label_end = source:find("](", i + 1, true)
			local url_end = label_end and source:find(")", label_end + 2, true)
			if url_end then
				local href = source:sub(label_end + 2, url_end - 1)
				if href:match("^https?://") then
					flush()
					push(source:sub(i + 1, label_end - 1), { color = colors.mauve, underline = true, href = href })
					i = url_end + 1
					goto continue
				end
			end
		elseif ch == "`" then
			close, after, style = source:find("`", i + 1, true), 1, { color = colors.peach }
		elseif (ch == "*" or ch == "_") and next_ch == ch then
			close, after, style = source:find(ch .. ch, i + 2, true), 2, { bold = true }
		elseif ch == "~" and next_ch == "~" then
			close, after, style = source:find("~~", i + 2, true), 2, { color = colors.muted }
		elseif ch == "*" or ch == "_" then
			close, after, style = source:find(ch, i + 1, true), 1, { italic = true }
		end
		if close and close > i + after then
			flush()
			push(source:sub(i + after, close - 1), style)
			i = close + after
		else
			plain[#plain + 1] = ch
			i = i + 1
		end
		::continue::
	end
	flush()
	return runs
end

local function cells(line)
	local result = {}
	line = line:match("^%s*(.-)%s*$"):gsub("^|", ""):gsub("|$", "")
	for cell in (line .. "|"):gmatch("(.-)|") do
		result[#result + 1] = cell:match("^%s*(.-)%s*$")
	end
	return result
end

local function list_item(line)
	local marker, value = line:match("^%s*([%*%-%+])%s+(.+)$")
	if marker then
		return "•", value
	end
	marker, value = line:match("^%s*(%d+)%.%s+(.+)$")
	if marker then
		return marker .. ".", value
	end
end

local function starts_block(line)
	return line:match("^%s*```")
		or line:match("^%s*#+%s+")
		or line:match("^%s*>")
		or line:match("^%s*|")
		or list_item(line)
end

function M.blocks(source)
	local lines, blocks, i = {}, {}, 1
	for raw in (tostring(source or ""):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = raw
	end
	while i <= #lines do
		local line = lines[i]
		local hashes, heading = line:match("^%s*(#+)%s+(.+)$")
		if line:match("^%s*$") then
			i = i + 1
		elseif line:match("^%s*```") then
			local body = {}
			i = i + 1
			while i <= #lines and not lines[i]:match("^%s*```") do
				body[#body + 1] = lines[i]
				i = i + 1
			end
			blocks[#blocks + 1] = { kind = "code", text = table.concat(body, "\n") }
			i = i + 1
		elseif line:match("^%s*|") and (lines[i + 1] or ""):match("^%s*|?[%s:|%-]+|?%s*$") then
			local rows = { cells(line) }
			i = i + 2
			while i <= #lines and lines[i]:match("^%s*|") do
				rows[#rows + 1] = cells(lines[i])
				i = i + 1
			end
			blocks[#blocks + 1] = { kind = "table", rows = rows }
		elseif hashes then
			blocks[#blocks + 1] = { kind = "heading", level = #hashes, text = heading }
			i = i + 1
		elseif list_item(line) then
			local items = {}
			while i <= #lines do
				local marker, value = list_item(lines[i])
				if not marker then
					break
				end
				local check, rest = value:match("^%[([ xX])%]%s*(.*)$")
				if check then
					marker, value = check == " " and "○" or "✓", rest
				end
				items[#items + 1] = { marker = marker, text = value }
				i = i + 1
			end
			blocks[#blocks + 1] = { kind = "list", items = items }
		elseif line:match("^%s*>") then
			local quote = {}
			while i <= #lines and lines[i]:match("^%s*>") do
				quote[#quote + 1] = lines[i]:gsub("^%s*>%s?", "")
				i = i + 1
			end
			blocks[#blocks + 1] = { kind = "quote", text = table.concat(quote, " ") }
		elseif line:match("^%s*[-*_][-*_%s]+$") then
			blocks[#blocks + 1] = { kind = "rule" }
			i = i + 1
		else
			local paragraph = { line }
			i = i + 1
			while i <= #lines and lines[i]:match("%S") and not starts_block(lines[i]) do
				paragraph[#paragraph + 1] = lines[i]
				i = i + 1
			end
			blocks[#blocks + 1] = { kind = "body", text = table.concat(paragraph, " ") }
		end
	end
	return blocks
end

local function rich(source, colors, size, color)
	return text({
		content = inline(source, colors),
		width = "Fill",
		wrap = "Word",
		font = "Noto Sans",
		font_size = size or 14,
		foreground = color or colors.text,
		on_link = function(href)
			process.detach("xdg-open", { href })
		end,
	})
end

function M.node(block, colors)
	if block.kind == "heading" then
		local size = block.level == 1 and 21 or block.level == 2 and 18 or 16
		return rich(block.text, colors, size, colors.mauve)
	elseif block.kind == "body" then
		return rich(block.text, colors)
	elseif block.kind == "quote" then
		return row({
			width = "Fill",
			padding = { left = 12, top = 6, bottom = 6 },
			background = colors.surface,
			radius = 6,
			children = { rich(block.text, colors, 14, colors.dim) },
		})
	elseif block.kind == "rule" then
		return rect({ width = "Fill", height = 1, background = colors.border })
	elseif block.kind == "code" then
		return column({
			width = "Fill",
			padding = 12,
			radius = 8,
			background = colors.bg,
			children = {
				text({
					content = block.text,
					width = "Fill",
					wrap = "Word",
					font = "JetBrainsMono Nerd Font Mono",
					font_size = 12,
					foreground = colors.peach,
				}),
			},
		})
	elseif block.kind == "list" then
		local children = {}
		for _, item in ipairs(block.items) do
			children[#children + 1] = row({
				width = "Fill",
				spacing = 8,
				children = {
					text({
						content = item.marker,
						width = 18,
						foreground = item.marker == "✓" and colors.green or colors.mauve,
						font_size = 14,
					}),
					rich(item.text, colors),
				},
			})
		end
		return column({ width = "Fill", spacing = 6, children = children })
	elseif block.kind == "table" then
		local lines = {}
		for index, cells_in_row in ipairs(block.rows) do
			local children = {}
			for _, cell in ipairs(cells_in_row) do
				children[#children + 1] = rich(cell, colors, 12, index == 1 and colors.mauve or colors.text)
			end
			lines[#lines + 1] = row({
				width = "Fill",
				spacing = 8,
				padding = 6,
				background = index == 1 and colors.surface or colors.bg,
				children = children,
			})
		end
		return column({ width = "Fill", spacing = 1, radius = 6, children = lines })
	end
	return rich(block.text or "", colors)
end

return M
