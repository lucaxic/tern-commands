local launch = require("./launch")

local function run(command, cwd, source, target, cx)
	if command.text:find("[%z\1-\8\11-\31\127]") then
		cx:toast("error", "The command contains unsupported control characters.")
		return
	end
	local cli = if tern.runtime.os == "windows" then "tern.com" else "tern"
	local function call(args, label, done)
		-- The macOS daemon lacks PATH entries from the user's interactive login shell.
		-- Keep arguments separate: zsh resolves tern, not command text.
		if tern.runtime.os == "macos" then
			local argv = { "/bin/zsh", "-lic", 'exec "$@"', "tern-commands" }
			for _, arg in args do
				table.insert(argv, arg)
			end
			args = argv
		end
		local started, err = pcall(tern.process.run, args, { cwd = cwd, timeout_ms = 20000 }, function(result, nextCx)
			-- Calls form one serial chain; refresh the window context before continuing.
			cx = nextCx or cx
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
		local id = tostring(pane)
		call({ cli, "wait", id, "--until", "prompt", "--timeout", "15" }, "Failed to wait for the shell prompt", function()
			local panes = if tern.context == "window" then cx.session:panes() else tern.pane.list()
			for _, info in panes do
				if info.pane == pane and launch.matches(command.lang, info.program) then
					call({ cli, "send", id, "paste", command.text }, "Failed to paste the command", function()
						call({ cli, "send", id, "keys", "Enter" }, "Failed to execute the command")
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
			call({ cli, "run", id, table.concat(words, " ") }, "Failed to submit the command")
		end)
	end
	if target then
		call({ cli, "focus", tostring(target) }, "Failed to focus the terminal", function()
			execute(target)
		end)
	else
		call({ cli, "split", tostring(source), "right", "--cwd", cwd }, "Failed to create a terminal pane", function(stdout)
			local pane = tonumber(stdout:match("^%s*(%d+)%s*$"))
			if not pane then
				cx:toast("error", "Tern did not return a new pane ID.")
				return
			end
			execute(pane)
		end)
	end
end

return { run = run }
