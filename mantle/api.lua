-- ClickUp transport for Mantle. Python's standard library makes the HTTP request;
-- the UI and its state stay in Lua. Chunked output stays below Mantle's 64 KiB line cap.
local M = {}
local token = os.getenv("CLICKUP_TOKEN")
M.NULL = {}
local transport = [[
import json, os, sys, urllib.error, urllib.request
method, path, body = sys.argv[1:4]
request = urllib.request.Request(
    "https://api.clickup.com/api/v2" + path,
    data=body.encode("utf-8") if body else None,
    headers={"Authorization": os.environ["CLICKUP_TOKEN"], "Content-Type": "application/json"},
    method=method,
)
try:
    with urllib.request.urlopen(request, timeout=20) as response:
        status, payload = response.status, response.read().decode("utf-8")
except urllib.error.HTTPError as error:
    status, payload = error.code, error.read().decode("utf-8", "replace")
except Exception as error:
    status, payload = 0, json.dumps({"err": str(error)})
try:
    payload = json.dumps(json.loads(payload), ensure_ascii=True, separators=(",", ":"))
except ValueError:
    payload = json.dumps({"err": "Invalid JSON response"})
print(status)
for offset in range(0, len(payload), 32000):
    print(payload[offset:offset + 32000])
]]

function M.ready()
	return token and token ~= ""
end

local function quote(value)
	local str = tostring(value)
	return '"'
		.. str:gsub('[%z\1-\31\\"]', function(ch)
			local escapes = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return escapes[ch] or string.format("\\u%04x", ch:byte())
		end)
		.. '"'
end

function M.json_object(fields)
	local parts = {}
	for key, value in pairs(fields) do
		local encoded = value == M.NULL and "null" or type(value) == "string" and quote(value) or tostring(value)
		parts[#parts + 1] = quote(key) .. ":" .. encoded
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function M.request(method, path, body, done)
	if not M.ready() then
		done("Set CLICKUP_TOKEN before starting Mantle")
		return
	end
	local output = {}
	process.run("python3", { "-c", transport, method, path, body and M.json_object(body) or "" }, function(line, stream)
		if stream == "stdout" then
			output[#output + 1] = line
		end
	end, function(code)
		local status = tonumber(output[1])
		table.remove(output, 1)
		local payload = table.concat(output)
		local data = payload ~= "" and json.decode(payload) or {}
		if code ~= 0 or not status then
			done("Could not reach ClickUp (request " .. tostring(code) .. ")")
		elseif status == 0 then
			done(type(data) == "table" and tostring(data.err) or "Could not reach ClickUp")
		elseif status < 200 or status >= 300 then
			local message = type(data) == "table" and (data.err or data.error) or nil
			done("ClickUp " .. status .. (message and ": " .. tostring(message) or ""))
		elseif type(data) ~= "table" then
			done("ClickUp returned invalid JSON")
		else
			done(nil, data)
		end
	end)
end

return M
