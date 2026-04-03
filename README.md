# CLI Update Checker

A shell script that checks for and installs updates across all CLI applications on macOS.

## What It Checks & Updates

| Tool | Check Method | Update Command |
|---|---|---|
| **Homebrew Formulae** | `brew outdated --formula` | `brew upgrade --formula` |
| **Homebrew Casks** | `brew outdated --cask` | `brew upgrade --cask` |
| **pip3 Packages** | `pip3 list --outdated` | Reports only — managed by Homebrew |
| **Python** | Compares brew formula versions | `brew upgrade python@X.XX` |
| **Salesforce CLI** | `sf version` before/after | `sf update` + `sf plugins update` |
| **Claude Code** | `claude update` | `claude update` |
| **GitHub CLI** | Compares against latest GitHub release | `brew upgrade gh` |
| **1Password CLI** | Compares against brew cask info | `brew upgrade --cask 1password-cli` |
| **Warp Terminal** | Compares installed vs latest brew cask | `brew upgrade --cask warp` |
| **Java (Azul Zulu)** | Compares brew cask installed vs latest | `brew upgrade --cask zulu@XX` |
| **Slack CLI** | Compares against brew cask info | `brew upgrade --cask slack-cli` |
| **Playwright CLI** | Compares against npm registry | `npm install -g @playwright/test@latest` + browser update |
| **Google Cloud CLI** | `gcloud version` before/after | `gcloud components update --quiet` |

## Run Manually (One-Off)

```bash
curl -sL https://raw.githubusercontent.com/guy2c9/Autocheck-cli-updates/main/check-cli-updates.sh -o /tmp/check-cli-updates.sh && bash /tmp/check-cli-updates.sh
```

To also reset the daily check so it runs again next time you open `claude`/`cca`:

```bash
rm -f ~/.cli-update-last-run; curl -sL https://raw.githubusercontent.com/guy2c9/Autocheck-cli-updates/main/check-cli-updates.sh -o /tmp/check-cli-updates.sh && bash /tmp/check-cli-updates.sh
```

## Run Automatically (Once Per Day)

This setup runs the update check once per day, triggered the first time you type `claude` or `cca` in your terminal. Every subsequent use that same day skips straight to the command.

Works with **Warp**, **Terminal.app**, **iTerm2**, or any macOS terminal that uses zsh.

### Setup Steps

1. Open **Warp** (or your preferred terminal)
2. If you're running Warp, open a new tab (**Cmd + T**)
3. Type the following at the bottom of the page to open your shell config for editing:
   ```
   nano ~/.zshrc
   ```
4. Find this line (if it exists):
   ```
   alias cca="claude"
   ```
5. Replace it with the following block (or add it if the line doesn't exist):
   ```bash
   # CLI update check — runs once per day before first claude/cca invocation
   _cli_update_check() {
     local last_run_file="$HOME/.cli-update-last-run"
     local today=$(date +%Y-%m-%d)
     if [ "$(cat "$last_run_file" 2>/dev/null)" != "$today" ]; then
       local tmp="/tmp/check-cli-updates.sh"
       if curl -sL https://raw.githubusercontent.com/guy2c9/Autocheck-cli-updates/main/check-cli-updates.sh -o "$tmp" && [ -s "$tmp" ]; then
         bash "$tmp"
       else
         echo "⚠ CLI update check: could not fetch script"
       fi
       echo "$today" > "$last_run_file"
     fi
   }

   claude() {
     _cli_update_check
     command claude "$@"
   }

   alias cca="claude"
   ```
6. Exit the editor: press **Ctrl + X**, then **Y** to save, then **Enter** to confirm the filename
7. Open a new tab (**Cmd + T**) or reload your config:
   ```
   source ~/.zshrc
   ```
8. Test it — type `claude` or `cca`. The update script should run first, then Claude Code launches. Run it again and it should skip straight to Claude Code.

### Remove Automatic Updates

1. Open your shell config:
   ```
   nano ~/.zshrc
   ```
2. Delete the `_cli_update_check` function, the `claude` function, and the `alias cca="claude"` line
3. If you still want the `cca` shortcut without the update check, add back:
   ```
   alias cca="claude"
   ```
4. Exit and save: **Ctrl + X**, **Y**, **Enter**

## Behaviour

- Skips any tool that isn't installed — no errors, just moves to the next
- Colour-coded output: green for up to date, yellow for outdated/upgrading
- Prints a summary at the end showing the status of every detected tool
- Safe to run repeatedly — idempotent, won't break anything if already up to date

## Requirements

- macOS
- [Homebrew](https://brew.sh) (primary package manager)
