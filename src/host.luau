local parser = require("./parser")
local launch = require("./launch")
local ui = tern.ui
local MAX_BYTES = 256 * 1024

local function reload(state)
	local ok, text = pcall(tern.fs.read, state.path, MAX_BYTES)
	if state.readOk == ok and state.source == text then
		return false
	end
	state.readOk, state.source = ok, text
	state.error = nil
	state.commands = {}
	state.segments = {}
	if not ok then
		state.error = "Cannot read COMMANDS.md: " .. tostring(text) .. " (press r to retry)"
		return true
	end
	state.segments = parser.parse(text)
	for _, segment in state.segments do
		if segment.kind == "command" then
			state.commands[segment.id] = segment
		end
	end
	return true
end

local function run(state, id, cx, target)
	reload(state)
	local command = state.commands[id]
	if not command then
		return
	end
	if command.text:find("[%z\1-\8\11-\31\127]") then
		cx:toast("error", "The command contains unsupported control characters.")
		return
	end
	local cli = if tern.runtime.os == "windows" then "tern.com" else "tern"
	local function call(args, label, done)
		local started, err = pcall(tern.process.run, args, { cwd = state.cwd, timeout_ms = 20000 }, function(result)
			if result.status ~= 0 then
				cx:toast("error", label .. ": " .. (if result.stderr ~= "" then result.stderr else result.stdout))
			elseif done then
				done(result.stdout)
			end
		end)
		if not started then
			cx:toast("error", label .. ": " .. tostring(err))
		end
	end
	local function execute(pane)
		call({ cli, "wait", tostring(pane), "--until", "prompt", "--timeout", "15" }, "Failed to wait for the shell prompt", function()
			for _, info in tern.pane.list() do
				if info.pane == pane and launch.matches(command.lang, info.program) then
					call({ cli, "send", tostring(pane), "paste", command.text }, "Failed to paste the command", function()
						call({ cli, "send", tostring(pane), "keys", "Enter" }, "Failed to execute the command")
					end)
					return
				end
			end
			local words = {}
			for _, arg in launch.args(command, tern.runtime.os) do
				-- Windows payloads contain only plain switches and Base64. On
				-- POSIX, quote source as one shell argument without expanding it.
				table.insert(words, if arg:find("[^%w_./:=+%-]") then "'" .. arg:gsub("'", "'\\''") .. "'" else arg)
			end
			call({ cli, "run", tostring(pane), table.concat(words, " ") }, "Failed to submit the command")
		end)
	end
	if target then
		call({ cli, "focus", tostring(target) }, "Failed to focus the terminal", function()
			execute(target)
		end)
	else
		call({ cli, "split", tostring(cx.pane), "right", "--cwd", state.cwd }, "Failed to create a terminal pane", function(stdout)
			local pane = tonumber(stdout:match("^%s*(%d+)%s*$"))
			if not pane then
				cx:toast("error", "Tern did not return a new pane ID.")
				return
			end
			execute(pane)
		end)
	end
end

local function initialPath(cx, args, saved)
	local path = args[1]
	if not path or path == "" then
		path = if type(saved) == "table" and type(saved.path) == "string" then saved.path else nil
	end
	if not path or path == "" then
		return (cx.cwd or tern.plugin.dir) .. "/COMMANDS.md"
	end
	if not path:match("^[/\\]") and not path:match("^%a:[/\\]") then
		return (cx.cwd or tern.plugin.dir) .. "/" .. path
	end
	return path
end

tern.block.define("panel", {
	init = function(cx, args, saved)
		local path = initialPath(cx, args, saved)
		local state = { path = path, cwd = path:match("^(.*[/\\])[^/\\]+$") or cx.cwd or tern.plugin.dir }
		reload(state)
		local function refresh()
			for _, pane in tern.pane.list() do
				if pane.pane == cx.pane and pane.exited == nil then
					if reload(state) then
						cx:render()
					end
					tern.timer(1000, refresh)
					return
				end
			end
		end
		tern.timer(1000, refresh)
		return state
	end,
	title = function(_state)
		return "Commands"
	end,
	view = function(state, _cx)
		local children = {}
		if state.error then
			table.insert(children, ui.text(ui.span(state.error, "error")))
		end
		local groups = {}
		local container = children
		local row = nil
		for index, segment in state.segments do
			if segment.kind == "heading" then
				row = nil
				while #groups > 0 and groups[#groups].level >= segment.level do
					table.remove(groups)
				end
				container = if #groups > 0 then groups[#groups].children else children
				local node = ui.section(if segment.title ~= "" then segment.title else "Untitled group", {})
				node.p.collapsible = true
				node.p.role = "command-group"
				node.p.mark = "heading-" .. tostring(segment.level)
				node.p.key = "segment-" .. tostring(index)
				node.c = {}
				table.insert(container, node)
				container = node.c
				table.insert(groups, { level = segment.level, children = node.c })
			elseif segment.kind == "separator" then
				row = nil
				table.insert(container, ui.node("rule", {
					key = "separator-" .. tostring(index),
					role = "command-separator",
				}))
			elseif segment.kind == "command" then
				if not row then
					row = ui.el("div", { class = "command-row", key = "row-" .. tostring(index) })
					row.c = {}
					table.insert(container, row)
				end
				table.insert(row.c, ui.el("div", { class = "command-entry", key = "command-" .. tostring(segment.id) }, {
					ui.el("button", {
						text = segment.title,
						class = "command-button",
						actions = { click = "run=" .. tostring(segment.id) },
					}),
					ui.el("pre", {
						text = segment.text,
						class = "command-tooltip",
						attrs = { role = "tooltip" },
					}),
				}))
			end
		end
		if next(state.commands) == nil and not state.error then
			table.insert(children, ui.text("No runnable commands. Edit COMMANDS.md and press r to reload."))
		end
		return { main = ui.col(children) }
	end,
	event = function(state, ev, cx)
		if ev.ev ~= "action" then
			return
		end
		if ev.act == "run" and tonumber(ev.value) then
			cx:open("tern-commands://run/" .. ev.value)
		elseif ev.act == "execute" then
			local id, target = ev.value:match("^(%d+):(%d+)$")
			if id then
				run(state, tonumber(id), cx, if target == "0" then nil else tonumber(target))
			end
		end
	end,
	key = function(state, key, _cx)
		if key.name == "r" and not key.ctrl and not key.alt and not key.meta and not key.shift then
			reload(state)
			return true
		end
		return false
	end,
	save = function(state)
		return { path = state.path }
	end,
})
