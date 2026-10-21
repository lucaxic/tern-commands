tern.command({
	id = "open",
	title = "Open Commands...",
	icon = "terminal",
	run = function(cx)
		local pane = cx.session:pane("@focused")
		if not pane or not pane.cwd or pane.cwd == "" then
			return cx:toast("error", "Select a pane with a working directory first.")
		end
		local path = pane.cwd .. "/COMMANDS.md"
		if not tern.fs.exists(path) then
			return cx:toast("info", "No COMMANDS.md in the current directory.")
		end
		cx:new_block("commands.panel", { path }, "beside")
	end,
})

tern.bind(if tern.runtime.os == "macos" then "alt+cmd+c" else "ctrl+alt+shift+c", "plugin.commands.open")

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
	local target = 0
	for _, pane in cx.session:panes() do
		if pane.tab == source.tab and pane.kind == "terminal" and pane.exited == nil and not pane.busy and pane.at_prompt then
			target = pane.pane
			break
		end
	end
	cx.session:event(source.pane, { ev = "action", act = "execute", value = id .. ":" .. tostring(target) })
	return { handled = true }
end)
