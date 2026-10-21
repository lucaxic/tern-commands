local parser = require("./parser")
local runner = require("./runner")
local MAX_BYTES = 256 * 1024

local function commandPath(cx)
	local pane = cx.session:pane("@focused")
	if not pane or not pane.cwd or pane.cwd == "" then
		cx:toast("error", "Select a pane with a working directory first.")
		return nil
	end
	local path = pane.cwd .. "/COMMANDS.md"
	if not tern.fs.exists(path) then
		cx:toast("info", "No COMMANDS.md in the current directory.")
		return nil
	end
	return pane, path
end

local function idleTerminal(cx, source)
	for _, pane in cx.session:panes() do
		if pane.tab == source.tab and pane.kind == "terminal" and pane.exited == nil and not pane.busy and pane.at_prompt then
			return pane.pane
		end
	end
	return nil
end

tern.command({
	id = "open",
	title = "Open Commands...",
	icon = "terminal",
	run = function(cx)
		local pane, path = commandPath(cx)
		if not pane then
			return
		end
		cx:new_block("commands.panel", { path }, "beside")
	end,
})

tern.command({
	id = "select",
	title = "Select Commands...",
	icon = "terminal",
	run = function(cx)
		local source, path = commandPath(cx)
		if not source then
			return
		end
		local ok, text = pcall(tern.fs.read, path, MAX_BYTES)
		if not ok then
			return cx:toast("error", "Cannot read COMMANDS.md: " .. tostring(text))
		end
		local items = {}
		local headings = {}
		for _, segment in parser.parse(text) do
			if segment.kind == "heading" then
				while #headings > 0 and headings[#headings].level >= segment.level do
					table.remove(headings)
				end
				local parent = headings[#headings]
				table.insert(headings, {
					level = segment.level,
					group = if parent then parent.group .. " / " .. segment.title else segment.title,
				})
			elseif segment.kind == "command" then
				table.insert(items, {
					label = segment.title,
					detail = segment.lang .. ": " .. segment.text:gsub("%s+", " "),
					group = if #headings > 0 then headings[#headings].group else nil,
					command = segment,
				})
			end
		end
		if #items == 0 then
			return cx:toast("info", "No runnable commands in COMMANDS.md.")
		end
		cx:pick({ items = items, placeholder = "Select Commands...", icon = "terminal", action = "run" }):next(function(item, err, nextCx)
			if err then
				nextCx:toast("error", "Cannot select a command: " .. tostring(err))
			elseif item then
				local pane = nextCx.session:pane(source.pane)
				if not pane or not pane.tab then
					return nextCx:toast("error", "The original pane is no longer available.")
				end
				runner.run(item.command, source.cwd, pane.pane, idleTerminal(nextCx, pane), nextCx)
			end
		end)
	end,
})

tern.bind(if tern.runtime.os == "macos" then "ctrl+shift+cmd+c" else "ctrl+alt+shift+c", "plugin.commands.select")

-- Pane kinds and tab membership are available only in the window context.
tern.route.link(function(link, cx)
	local id = link.url:match("^tern%-commands://run/(%d+)$")
	if not id then
		return nil
	end
	local source = link.pane and cx.session:pane(link.pane)
	if not source or source.block ~= "commands.panel" or not source.tab then
		return { handled = true }
	end
	local target = idleTerminal(cx, source) or 0
	cx.session:event(source.pane, { ev = "action", act = "execute", value = id .. ":" .. tostring(target) })
	return { handled = true }
end)
