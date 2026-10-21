# 🧰 Project Commands

Buttons use the first terminal in this tab, keeping its current directory and session state. If there is no terminal, one is created in this file's directory. A busy terminal is left untouched.

## ⚡ Automatic Wrapping

These consecutive buttons share a row. Narrow the pane to see them wrap automatically; blank lines do not force a new row.

📂 Show current directory
```powershell
Get-Location
```

📁 List files
```powershell
Get-ChildItem
```

📅 Show current date
```powershell
Get-Date
```

⚙️ Check PowerShell version
```powershell
$PSVersionTable.PSVersion
```

💻 Show machine name
```powershell
[Environment]::MachineName
```

👤 Show current user
```powershell
[Environment]::UserName
```

---

The separator above forces a new row even when space is available.

👋 Print a greeting
```powershell
Write-Output "Hello from COMMANDS.md"
```

📜 Run a multiline command
```powershell
$commandMessage = "Multiple lines, one button"
Write-Output $commandMessage
```

***

The asterisk separator also forces a new row.

🔎 Show Git status
```powershell
git status --short
```

## 📌 A New Heading Starts a New Row

Headings start new collapsible groups independently of automatic wrapping.

🌿 Show Git branch
```powershell
git branch --show-current
```
