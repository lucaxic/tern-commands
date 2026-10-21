-- Windows PowerShell's native argument forwarding removes embedded quotes.
-- EncodedCommand avoids passing source code through that quoting boundary.
local function encodedPowerShell(text)
	local bytes = {}
	for _, codepoint in utf8.codes(text) do
		if codepoint > 0xFFFF then
			codepoint -= 0x10000
			local high = 0xD800 + math.floor(codepoint / 0x400)
			table.insert(bytes, high % 256)
			table.insert(bytes, math.floor(high / 256))
			codepoint = 0xDC00 + codepoint % 0x400
		end
		table.insert(bytes, codepoint % 256)
		table.insert(bytes, math.floor(codepoint / 256))
	end
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local result = {}
	for i = 1, #bytes, 3 do
		local value = bytes[i] * 65536 + (bytes[i + 1] or 0) * 256 + (bytes[i + 2] or 0)
		local a = math.floor(value / 262144) % 64 + 1
		local b = math.floor(value / 4096) % 64 + 1
		local c = math.floor(value / 64) % 64 + 1
		local d = value % 64 + 1
		table.insert(result, alphabet:sub(a, a) .. alphabet:sub(b, b)
			.. (if bytes[i + 1] then alphabet:sub(c, c) else "=")
			.. (if bytes[i + 2] then alphabet:sub(d, d) else "="))
	end
	return table.concat(result)
end

local function args(command, os)
	if command.lang == "powershell" or command.lang == "pwsh" then
		local shell = if command.lang == "powershell" and os == "windows" then "powershell.exe" else "pwsh"
		return { shell, "-NoLogo", "-NoProfile", "-EncodedCommand", encodedPowerShell(command.text) }
	end
	if os == "windows" then
		-- A real script preserves multiline CMD syntax and avoids the same
		-- native quoting problem for Bash/sh. The runner owns its temporary file.
		local isCmd = command.lang == "cmd"
		local source = if isCmd then "@echo off\r\n@chcp 65001>nul\r\n" .. command.text:gsub("\n", "\r\n") else command.text
		local extension = if isCmd then ".cmd" else ".sh"
		local invoke = if isCmd then "& cmd.exe /D /C $p" else "& " .. command.lang .. " ($p.Replace('\\', '/'))"
		local runner = "$ErrorActionPreference = 'Stop'; $p = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '" .. extension .. "'); "
			.. "try { [IO.File]::WriteAllText($p, '" .. source:gsub("'", "''") .. "', [Text.UTF8Encoding]::new($false)); "
			.. invoke .. "; $code = $LASTEXITCODE } "
			.. "finally { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }; exit $code"
		return { "powershell.exe", "-NoLogo", "-NoProfile", "-EncodedCommand", encodedPowerShell(runner) }
	end
	return { command.lang, "-c", command.text }
end

local function matches(lang, program)
	local shell = (program:lower():match("([^/\\]+)$") or ""):gsub("%.exe$", ""):gsub("^%-", "")
	if lang == "powershell" or lang == "pwsh" then
		return shell == "powershell" or shell == "pwsh"
	elseif lang == "sh" then
		return shell == "sh" or shell == "bash" or shell == "zsh"
			or shell == "dash" or shell == "ash" or shell == "ksh"
	end
	return (lang == "cmd" or lang == "bash" or lang == "zsh") and shell == lang
end

return { args = args, matches = matches }
