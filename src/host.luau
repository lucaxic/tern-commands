local parser = require("./parser")
local runner = require("./runner")
local ui = tern.ui
local MAX_BYTES = 256 * 1024

local function run(state, id, cx, target)
	local command = state.commands[id]
	if command then
		runner.run(command, state.cwd, cx.pane, target, cx)
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
		local ok, text = pcall(tern.fs.read, path, MAX_BYTES)
		state.commands = {}
		state.segments = if ok then parser.parse(text) else {}
		if not ok then
			state.error = "Cannot read COMMANDS.md: " .. tostring(text) .. " (reopen the panel to retry)"
		end
		for _, segment in state.segments do
			if segment.kind == "command" then
				state.commands[segment.id] = segment
			end
		end
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
			table.insert(children, ui.text("No runnable commands. Edit COMMANDS.md and reopen the panel."))
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
	save = function(state)
		return { path = state.path }
	end,
})
