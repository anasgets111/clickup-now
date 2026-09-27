-- ClickUp transport for Mantle. Python's standard library makes the HTTP request;
-- the UI and its state stay in Lua. Chunked output stays below Mantle's 64 KiB line cap.
local M = {}
local token = os.getenv("CLICKUP_TOKEN")
local secret_name = "clickup-now-token"
local stored_available = false
M.NULL = {}
local transport = [[
import json, os, subprocess, sys, urllib.error, urllib.request
method, path, body, secret_name = sys.argv[1:5]
token = os.environ.get("CLICKUP_TOKEN")
if not token:
    found = subprocess.run(["secret-tool", "lookup", "name", secret_name],
                           capture_output=True, check=False)
    token = found.stdout.decode("utf-8").rstrip("\n") if found.returncode == 0 else None
if not token:
    print(0)
    print(json.dumps({"err": "No ClickUp token is saved"}))
    sys.exit(0)
request = urllib.request.Request(
    "https://api.clickup.com/api/v2" + path,
    data=body.encode("utf-8") if body else None,
    headers={"Authorization": token, "Content-Type": "application/json"},
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
	return (token and token ~= "") or stored_available
end

function M.has_env_token()
	return token ~= nil and token ~= ""
end

function M.discover(done)
	if M.has_env_token() then
		done(true)
		return
	end
	local found = false
	process.run("python3", {
		"-c",
		[=[import subprocess, sys
result = subprocess.run(["secret-tool", "lookup", "name", sys.argv[1]], capture_output=True, check=False)
print("stored" if result.returncode == 0 and result.stdout.strip() else "missing")]=],
		secret_name,
	}, function(line, stream)
		if stream == "stdout" and line == "stored" then
			found = true
		end
	end, function()
		stored_available = found
		done(found)
	end)
end

function M.forget(done)
	process.run("secret-tool", { "clear", "name", secret_name }, function() end, function(code)
		if code == 0 then
			stored_available = false
		end
		done(code == 0)
	end)
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
		done("Connect ClickUp first")
		return
	end
	local output = {}
	process.run(
		"python3",
		{ "-c", transport, method, path, body and M.json_object(body) or "", secret_name },
		function(line, stream)
			if stream == "stdout" then
				output[#output + 1] = line
			end
		end,
		function(code)
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
		end
	)
end

return M
