# CLI Update Checker

A shell script that checks for and installs updates across all CLI applications on macOS.

## Usage

```bash
./check-cli-updates.sh
```

## What It Checks & Updates

| Tool | Check Method | Update Command |
|---|---|---|
| **Homebrew Formulae** | `brew outdated --formula` | `brew upgrade --formula` |
| **Homebrew Casks** | `brew outdated --cask` | `brew upgrade --cask` |
| **pip3 Packages** | `pip3 list --outdated` | `pip3 install --upgrade` |
| **Python** | Compares brew formula versions | `brew upgrade python@X.XX` |
| **Salesforce CLI** | `sf update --available` | `sf update --stable` |
| **Claude Code** | `claude update` | `claude update` |
| **GitHub CLI** | Compares against latest GitHub release | `brew upgrade gh` |
| **1Password CLI** | Compares against brew cask info | `brew upgrade --cask 1password-cli` |
| **Warp Terminal** | Compares installed vs latest brew cask | `brew upgrade --cask warp` |
| **Java (Azul Zulu)** | Compares brew cask installed vs latest | `brew upgrade --cask zulu@XX` |
| **Slack CLI** | Compares against brew cask info | `brew upgrade --cask slack-cli` |
| **Google Cloud CLI** | `gcloud version` before/after | `gcloud components update --quiet` |

## Behaviour

- Skips any tool that isn't installed — no errors, just moves to the next
- Colour-coded output: green for up to date, yellow for outdated/upgrading
- Prints a summary at the end showing the status of every detected tool
- Safe to run repeatedly — idempotent, won't break anything if already up to date

## Requirements

- macOS
- [Homebrew](https://brew.sh) (primary package manager)
