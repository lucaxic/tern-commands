local launch = require("../src/launch")

-- Regression: Windows PowerShell's native forwarding stripped the quotes in
-- `Write-Output "..."`. The payload must also preserve UTF-16 surrogate pairs.
local args = launch.args({ lang = "powershell", text = 'Write-Output "caf\u{00E9}\u{1D11E}"' }, "windows")
local encodedAt = table.find(args, "-EncodedCommand")
assert(encodedAt, "source must not cross Windows native argument quoting")
assert(args[encodedAt + 1] == "VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiAGMAYQBmAOkANNge3SIA", "quoted Unicode source was corrupted")
print("PASS Windows quoted Unicode command")

assert(launch.matches("powershell", "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"))
assert(launch.matches("pwsh", "POWERSHELL.EXE"))
assert(launch.matches("powershell", "/usr/bin/pwsh"))
assert(launch.matches("cmd", "C:\\Windows\\System32\\cmd.exe"))
assert(launch.matches("bash", "/bin/bash"))
assert(launch.matches("zsh", "-zsh"))
assert(launch.matches("sh", "/bin/dash"))
assert(launch.matches("sh", "/bin/bash"))
assert(not launch.matches("bash", "/bin/sh"), "bash syntax must not run directly in sh")
assert(not launch.matches("zsh", "/bin/bash"), "zsh syntax must not run directly in bash")
assert(not launch.matches("sh", "/usr/bin/fish"), "fish is not POSIX shell")
assert(not launch.matches("cmd", "powershell.exe"))
assert(not launch.matches("powershell", "not-powershell.exe"))
print("PASS compatible shell matching and incompatible boundaries")
