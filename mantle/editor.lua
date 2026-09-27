-- Edit a task's Markdown in a terminal editor, then save it through the model.
local M = {}

local write_script = [[
import os, sys
path, content = sys.argv[1:3]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as file:
    file.write(content)
]]

local read_script = [[
import json, os, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as file:
    payload = json.dumps(file.read(), ensure_ascii=True)
os.unlink(path)
for offset in range(0, len(payload), 32000):
    print(payload[offset:offset + 32000])
]]

function M.edit(task, model)
	local id = tostring(task.id or "")
	if id == "" then
		return
	end
	local path = "/tmp/clickup-now-" .. tostring(mantle.pid) .. "-" .. id:gsub("%W", "") .. ".md"
	local original = task.markdown_description or task.description or ""
	local editor = os.getenv("NOW_EDITOR") or "nvim"
	local terminal = os.getenv("NOW_TERMINAL") or "kitty"
	model.message:set("Opening description editor…")
	process.run("python3", { "-c", write_script, path, original }, function() end, function(write_code)
		if write_code ~= 0 then
			model.message:set("Could not prepare the description editor.")
			return
		end
		model.message:set("Save and close the editor to update the description.")
		process.run(terminal, { "-e", editor, path }, function() end, function(edit_code)
			if edit_code ~= 0 then
				model.message:set("Description editor closed without saving.")
				process.run(
					"python3",
					{ "-c", "import os,sys; os.unlink(sys.argv[1])", path },
					function() end,
					function() end
				)
				return
			end
			local chunks = {}
			process.run("python3", { "-c", read_script, path }, function(line, stream)
				if stream == "stdout" then
					chunks[#chunks + 1] = line
				end
			end, function(read_code)
				if read_code ~= 0 then
					model.message:set("Could not read the edited description.")
					return
				end
				local updated = json.decode(table.concat(chunks))
				if type(updated) ~= "string" then
					model.message:set("Edited description was invalid.")
				elseif updated == original then
					model.message:set("Description unchanged.")
				else
					model.mutate("PUT", "/task/" .. id, { markdown_content = updated }, "Description saved")
				end
			end)
		end)
	end)
end

return M
