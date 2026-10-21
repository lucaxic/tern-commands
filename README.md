# Tern Commands

Turn `COMMANDS.md` code blocks into grouped command buttons in [Tern](https://stencil.so/tern).

![Tern Commands panel with grouped command buttons and terminal output](assets/screenshot.png)

## Install

Install directly from GitHub (requires Git):

```sh
tern plugin install https://github.com/lucaxic/tern-commands.git
```

To update an installed copy:

```sh
tern plugin install https://github.com/lucaxic/tern-commands.git --force
```

For local development, run from this plugin's directory:

```sh
tern plugin link .
```

## Usage

Create a `COMMANDS.md` file in your working directory, then choose **Open Commands...** from the command palette or use the shortcut:

- **macOS:** Option+Command+C
- **Windows / Linux:** Ctrl+Alt+Shift+C

Click a button to run its command in the current tab's first idle terminal at a shell prompt. If none is available, a terminal is created. Existing terminals keep their current directory and session state; busy terminals are left untouched.

Hover to preview a command. The panel checks for file changes every second and refreshes automatically; press **r** to refresh immediately. Execution errors appear as notifications; file-loading errors appear in the panel. Normal Markdown opening is unchanged.

## Example

````markdown
# Project

## Development

Show directory
```powershell
Get-Location
```

Git status
```powershell
git status --short
```
````

- Headings create collapsible groups.
- Text immediately above a code block becomes its button label.
- Buttons wrap automatically. Use `---` or `***` to add a divider and start a new row.
- Supported shells: `powershell`, `pwsh`, `cmd`, `sh`, `bash`, and `zsh`.

See [assets/COMMANDS.md](assets/COMMANDS.md) for more examples.
