#!/bin/bash
# check-cli-updates.sh — Check for and install updates across all CLI applications

set -uo pipefail

# Colours (exported to suppress SC2034 — all are used in echo -e strings)
export BOLD='\033[1m'
export CYAN='\033[1;36m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export RED='\033[1;31m'
export RESET='\033[0m'

# Helper: shorten Warp version (e.g. 0.2025.04.01.08.02.stable_02 → 2025.04.01)
shorten_warp_ver() {
  echo "$1" | sed -E 's/^0\.//; s/\.[0-9]{2}\.[0-9]{2}\.stable.*//'
}

# Helper: extract a top-level string field from brew JSON without python3
# Usage: brew_json_field "$json" "version"  or  brew_json_field "$json" "installed"
brew_json_field() {
  local json="$1" field="$2"
  echo "$json" | grep -o "\"${field}\":[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:.*"\(.*\)"/\1/'
}

# Helper: check and update an npm-installed global CLI tool
# Usage: check_npm_tool "Display Name" "version_cmd" "npm_package" [extra_post_update_cmd]
#   version_cmd is evaluated via eval to support multi-word commands like "npx playwright"
check_npm_tool() {
  local display_name="$1" version_cmd="$2" npm_pkg="$3" post_cmd="${4:-}"

  header "$display_name"
  local current latest
  current=$(eval "$version_cmd" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  latest=$(npm view "$npm_pkg" version 2>/dev/null || true)

  if [[ -z "$latest" ]]; then
    echo -e "  Version: ${current:-unknown}"
    echo -e "  ${RED}Could not reach npm registry — skipping update check.${RESET}"
    add_summary "$display_name" "${current:-unknown}" "" "Check failed" "npm registry unreachable"
  elif [[ -n "$current" && "$current" != "$latest" ]]; then
    echo -e "  Current: ${YELLOW}${current}${RESET}"
    echo -e "  Latest:  ${GREEN}${latest}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating ${display_name}...${RESET}"
    npm install -g "${npm_pkg}@latest" 2>&1 || true
    if [[ -n "$post_cmd" ]]; then
      eval "$post_cmd" 2>&1 || true
    fi
    # Verify the update actually applied
    local new_ver
    new_ver=$(eval "$version_cmd" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$new_ver" && "$new_ver" != "$current" ]]; then
      echo -e "${GREEN}  Updated to ${new_ver}.${RESET}"
      add_summary "$display_name" "$current" "$new_ver" "Updated" "Via npm global"
    else
      echo -e "  ${RED}Update may have failed — still on ${current}.${RESET}"
      add_summary "$display_name" "$current" "$latest" "Update failed" "npm install did not change version"
    fi
  else
    echo -e "  Version: ${current}"
    echo -e "${GREEN}  ${display_name} is up to date.${RESET}"
    add_summary "$display_name" "$current" "" "Up to date" ""
  fi
}

# Helper: check and update a Homebrew cask-installed CLI tool
# Usage: check_brew_cask_tool "Display Name" "command" "cask_name" "version_cmd"
# version_cmd should output just the version string
check_brew_cask_tool() {
  local display_name="$1" cmd="$2" cask_name="$3" version_cmd="$4"

  if ! command -v "$cmd" &>/dev/null; then
    return
  fi

  header "$display_name"
  local current latest cask_json
  current=$(eval "$version_cmd" 2>/dev/null || true)
  cask_json=$(brew info --json=v2 --cask "$cask_name" 2>/dev/null || true)
  latest=$(brew_json_field "$cask_json" "version")

  if [[ -z "$latest" ]]; then
    echo -e "  Version: ${current:-unknown}"
    echo -e "  ${RED}Could not fetch cask info for ${cask_name} — skipping update check.${RESET}"
    add_summary "$display_name" "${current:-unknown}" "" "Check failed" "brew cask info unavailable"
  elif [[ -n "$current" && "$current" != "$latest" ]]; then
    echo -e "  Current: ${YELLOW}${current}${RESET}"
    echo -e "  Latest:  ${GREEN}${latest}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating ${display_name}...${RESET}"
    brew upgrade --cask "$cask_name" 2>&1 || true
    # Verify the update actually applied
    local new_ver
    new_ver=$(eval "$version_cmd" 2>/dev/null || true)
    if [[ -n "$new_ver" && "$new_ver" != "$current" ]]; then
      echo -e "${GREEN}  Updated to ${new_ver}.${RESET}"
      add_summary "$display_name" "$current" "$new_ver" "Updated" "Via Homebrew cask"
    else
      echo -e "  ${RED}Update may have failed — still on ${current}.${RESET}"
      add_summary "$display_name" "$current" "$latest" "Update failed" "brew upgrade did not change version"
    fi
  else
    echo -e "  Version: ${current}"
    echo -e "${GREEN}  ${display_name} is up to date.${RESET}"
    add_summary "$display_name" "$current" "" "Up to date" ""
  fi
}

# Counters
brew_formula_count=0
brew_cask_count=0
pip_count=0

# Version tracking for summary table
declare -a summary_names=()
declare -a summary_old_versions=()
declare -a summary_new_versions=()
declare -a summary_statuses=()
declare -a summary_notes=()

add_summary() {
  summary_names+=("$1")
  summary_old_versions+=("$2")
  summary_new_versions+=("$3")
  summary_statuses+=("$4")
  summary_notes+=("${5:-}")
}

header() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  $1${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ── Homebrew ──────────────────────────────────────

if command -v brew &>/dev/null; then
  header "Homebrew"
  brew_version=$(brew --version 2>/dev/null | head -1 | awk '{print $2}')
  echo -e "${YELLOW}Fetching latest package info...${RESET}"
  brew update --quiet

  echo ""
  echo -e "${BOLD}Outdated Formulae:${RESET}"
  brew_formula_output=$(brew outdated --formula 2>/dev/null || true)
  if [[ -n "$brew_formula_output" ]]; then
    echo "$brew_formula_output"
    brew_formula_count=$(echo "$brew_formula_output" | wc -l | tr -d ' ')
    echo ""
    echo -e "${YELLOW}Upgrading formulae...${RESET}"
    brew upgrade --formula 2>&1 || true
    echo -e "${GREEN}  Formulae upgraded.${RESET}"
  else
    echo -e "${GREEN}  All formulae are up to date.${RESET}"
  fi

  echo ""
  echo -e "${BOLD}Outdated Casks:${RESET}"
  brew_cask_output=$(brew outdated --cask 2>/dev/null || true)
  if [[ -n "$brew_cask_output" ]]; then
    echo "$brew_cask_output"
    brew_cask_count=$(echo "$brew_cask_output" | wc -l | tr -d ' ')
    echo ""
    echo -e "${YELLOW}Upgrading casks...${RESET}"
    brew upgrade --cask 2>&1 || true
    echo -e "${GREEN}  Casks upgraded.${RESET}"
  else
    echo -e "${GREEN}  All casks are up to date.${RESET}"
  fi
  total_brew=$((brew_formula_count + brew_cask_count))
  if [[ $total_brew -gt 0 ]]; then
    add_summary "Homebrew" "$brew_version" "$brew_version" "Updated" "${brew_formula_count} formula(e), ${brew_cask_count} cask(s) upgraded"
  else
    add_summary "Homebrew" "$brew_version" "" "Up to date" ""
  fi
fi

# ── pip3 ──────────────────────────────────────────

if command -v pip3 &>/dev/null; then
  header "pip3 (Python)"
  pip_version=$(pip3 --version 2>/dev/null | awk '{print $2}')
  pip_output=$(pip3 list --outdated --format=columns 2>/dev/null || true)
  if [[ -n "$pip_output" ]] && [[ $(echo "$pip_output" | wc -l | tr -d ' ') -gt 2 ]]; then
    echo "$pip_output"
    pip_count=$(( $(echo "$pip_output" | wc -l | tr -d ' ') - 2 ))
    echo ""
    echo -e "  ${YELLOW}pip packages are managed by Homebrew — upgrade via brew upgrade python.${RESET}"
  else
    echo -e "${GREEN}  All Python packages are up to date.${RESET}"
  fi
  if [[ $pip_count -gt 0 ]]; then
    add_summary "pip3" "$pip_version" "" "Outdated" "${pip_count} package(s) — managed by Homebrew"
  else
    add_summary "pip3" "$pip_version" "" "Up to date" ""
  fi
fi

# ── Python ────────────────────────────────────────

if command -v python3 &>/dev/null; then
  header "Python"
  py_current=$(python3 --version 2>&1 | awk '{print $2}')
  py_latest=""
  # Check all installed python formulae via Homebrew
  while IFS= read -r formula; do
    [[ -z "$formula" ]] && continue
    py_brew_json=$(brew info --json=v2 "$formula" 2>/dev/null || true)
    py_installed=$(echo "$py_brew_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['formulae'][0]['installed'][0]['version'])" 2>/dev/null || true)
    py_brew_latest=$(echo "$py_brew_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['formulae'][0]['versions']['stable'])" 2>/dev/null || true)
    if [[ -n "$py_installed" && -n "$py_brew_latest" && "$py_installed" != "${py_brew_latest}"* ]]; then
      echo -e "  ${formula}: ${YELLOW}${py_installed}${RESET} → ${GREEN}${py_brew_latest}${RESET}"
      echo -e "  ${YELLOW}Upgrading ${formula}...${RESET}"
      brew upgrade "$formula" 2>&1 || true
      echo -e "  ${GREEN}${formula} upgraded.${RESET}"
      py_latest="outdated"
    else
      echo -e "  ${formula}: ${py_installed:-unknown} — up to date"
    fi
  done < <(brew list --formula 2>/dev/null | grep "^python@")
  if [[ "$py_latest" == "outdated" ]]; then
    python_status="update available"
  else
    echo -e "${GREEN}  All Python installations are up to date.${RESET}"
    python_status="up to date"
  fi

  # Remove legacy Python versions that nothing depends on
  py_active=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
  while IFS= read -r formula; do
    [[ -z "$formula" ]] && continue
    formula_ver=$(echo "$formula" | sed 's/python@//')
    if [[ "$formula_ver" != "$py_active" ]]; then
      dependents=$(brew uses --installed "$formula" 2>/dev/null || true)
      if [[ -z "$dependents" ]]; then
        echo ""
        echo -e "  ${YELLOW}Legacy ${formula} found with no dependents — removing...${RESET}"
        brew uninstall "$formula" 2>&1 || true
        echo -e "  ${GREEN}${formula} removed.${RESET}"
      else
        echo -e "  ${formula} is a dependency of: ${dependents} — keeping."
      fi
    fi
  done < <(brew list --formula 2>/dev/null | grep "^python@")
  if [[ "$python_status" == "up to date" ]]; then
    add_summary "Python" "$py_current" "" "Up to date" ""
  else
    add_summary "Python" "$py_current" "" "Updated" "Upgraded via Homebrew"
  fi
fi

# ── Salesforce CLI ────────────────────────────────

if command -v sf &>/dev/null; then
  header "Salesforce CLI (sf)"
  sf_current_ver=$(sf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo -e "${YELLOW}Checking for updates...${RESET}"
  sf update 2>&1 || true
  sf_new_ver=$(sf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [[ -n "$sf_current_ver" && -n "$sf_new_ver" && "$sf_current_ver" != "$sf_new_ver" ]]; then
    echo -e "  Previous: ${YELLOW}${sf_current_ver}${RESET}"
    echo -e "  Updated:  ${GREEN}${sf_new_ver}${RESET}"
    add_summary "Salesforce CLI" "$sf_current_ver" "$sf_new_ver" "Updated" ""
  else
    echo -e "  Version: ${sf_current_ver:-unknown}"
    echo -e "${GREEN}  Salesforce CLI is up to date.${RESET}"
    add_summary "Salesforce CLI" "${sf_current_ver:-unknown}" "" "Up to date" ""
  fi

  echo ""
  echo -e "${YELLOW}Updating SF plugins...${RESET}"
  sf_plugins_output=$(sf plugins update 2>&1 || true)
  if echo "$sf_plugins_output" | grep -qi "updated\|installing"; then
    echo -e "${GREEN}  SF plugins updated.${RESET}"
  else
    echo -e "${GREEN}  All SF plugins are up to date.${RESET}"
  fi
fi

# ── Claude Code CLI ───────────────────────────────

if command -v claude &>/dev/null; then
  header "Claude Code CLI"
  claude_current=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo -e "  Version: ${claude_current:-unknown}"
  echo -e "${YELLOW}Checking for updates...${RESET}"
  claude_output=$(claude update 2>&1 || true)
  if echo "$claude_output" | grep -qi "up to date"; then
    echo -e "${GREEN}  Claude Code is up to date.${RESET}"
    add_summary "Claude Code" "$claude_current" "" "Up to date" ""
  else
    claude_new=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo -e "  Previous: ${YELLOW}${claude_current}${RESET}"
    echo -e "  Updated:  ${GREEN}${claude_new:-check manually}${RESET}"
    add_summary "Claude Code" "$claude_current" "${claude_new:-?}" "Updated" ""
  fi
fi

# ── Codex CLI (OpenAI) ───────────────────────────

if command -v codex &>/dev/null; then
  check_npm_tool "Codex CLI (OpenAI)" "codex" "@openai/codex"
fi

# ── Gemini CLI (Google) ──────────────────────────

if command -v gemini &>/dev/null; then
  check_npm_tool "Gemini CLI (Google)" "gemini" "@google/gemini-cli"
fi

# ── GitHub CLI ────────────────────────────────────

if command -v gh &>/dev/null; then
  header "GitHub CLI (gh)"
  gh_current=$(gh --version | head -1 | awk '{print $3}')
  gh_latest=$(gh api repos/cli/cli/releases/latest --jq '.tag_name' 2>/dev/null | sed 's/^v//' || true)
  if [[ -z "$gh_latest" ]]; then
    echo -e "  Version: ${gh_current}"
    echo -e "  ${RED}Could not reach GitHub API — skipping update check.${RESET}"
    add_summary "GitHub CLI" "$gh_current" "" "Check failed" "GitHub API unreachable"
  elif [[ "$gh_current" != "$gh_latest" ]]; then
    echo -e "  Current: ${YELLOW}${gh_current}${RESET}"
    echo -e "  Latest:  ${GREEN}${gh_latest}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating GitHub CLI...${RESET}"
    brew upgrade gh 2>&1 || true
    gh_new=$(gh --version 2>/dev/null | head -1 | awk '{print $3}')
    if [[ -n "$gh_new" && "$gh_new" != "$gh_current" ]]; then
      echo -e "${GREEN}  Updated to ${gh_new}.${RESET}"
      add_summary "GitHub CLI" "$gh_current" "$gh_new" "Updated" "Via Homebrew"
    else
      echo -e "  ${RED}Update may have failed — still on ${gh_current}.${RESET}"
      add_summary "GitHub CLI" "$gh_current" "$gh_latest" "Update failed" "brew upgrade did not change version"
    fi
  else
    echo -e "  Version: ${gh_current}"
    echo -e "${GREEN}  GitHub CLI is up to date.${RESET}"
    add_summary "GitHub CLI" "$gh_current" "" "Up to date" ""
  fi
fi

# ── 1Password CLI ─────────────────────────────────

check_brew_cask_tool "1Password CLI" "op" "1password-cli" "op --version"

# ── Warp Terminal ─────────────────────────────────

if brew list --cask 2>/dev/null | grep -q "^warp$"; then
  header "Warp Terminal"
  warp_json=$(brew info --json=v2 --cask warp 2>/dev/null || true)
  warp_installed=$(brew_json_field "$warp_json" "installed")
  warp_latest=$(brew_json_field "$warp_json" "version")
  [[ -z "$warp_installed" ]] && warp_installed="unknown"
  [[ -z "$warp_latest" ]] && warp_latest="unknown"
  warp_outdated=$(brew outdated --cask --greedy 2>/dev/null | grep "^warp" || true)
  if [[ -n "$warp_outdated" ]]; then
    echo -e "  Current: ${YELLOW}${warp_installed}${RESET}"
    echo -e "  Latest:  ${GREEN}${warp_latest:-check manually}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating Warp...${RESET}"
    brew upgrade --cask warp 2>&1 || true
    warp_short_old=$(shorten_warp_ver "$warp_installed")
    warp_short_new=$(shorten_warp_ver "${warp_latest:-?}")
    add_summary "Warp" "${warp_short_old:-$warp_installed}" "${warp_short_new:-${warp_latest:-?}}" "Updated" "Via Homebrew cask"
  else
    echo -e "  Version: ${warp_installed}"
    echo -e "${GREEN}  Warp is up to date.${RESET}"
    warp_short=$(shorten_warp_ver "$warp_installed")
    add_summary "Warp" "${warp_short:-$warp_installed}" "" "Up to date" ""
  fi
fi

# ── Java (Azul Zulu) ─────────────────────────────

if command -v java &>/dev/null; then
  header "Java (Azul Zulu)"
  java_current=$(java -version 2>&1 | head -1 | grep -oE '"[^"]+"' | tr -d '"')
  java_vendor=$(java -version 2>&1 | grep -i "runtime" || true)
  echo -e "  Version: ${java_current}"
  echo -e "  ${java_vendor}"

  # Report legacy OpenJDK installations (no longer auto-deletes)
  legacy_jdk_paths=()
  while IFS= read -r jdk_path; do
    [[ -n "$jdk_path" ]] && legacy_jdk_paths+=("$jdk_path")
  done < <(find /Library/Java/JavaVirtualMachines -maxdepth 1 -name "jdk-*.jdk" 2>/dev/null | grep -v "zulu" || true)

  java_legacy_note=""
  if [[ ${#legacy_jdk_paths[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}Legacy OpenJDK installations found:${RESET}"
    for jdk_path in "${legacy_jdk_paths[@]}"; do
      echo -e "    $(basename "$jdk_path")"
    done
    echo ""
    echo -e "  ${YELLOW}To remove legacy OpenJDKs, run manually:${RESET}"
    for jdk_path in "${legacy_jdk_paths[@]}"; do
      echo -e "    sudo rm -rf \"${jdk_path}\""
    done
    java_legacy_note="Legacy OpenJDKs detected — manual removal suggested"
  fi

  # Check for Zulu casks installed via Homebrew
  zulu_cask_list=()
  while IFS= read -r cask; do
    [[ -n "$cask" ]] && zulu_cask_list+=("$cask")
  done < <(brew list --cask 2>/dev/null | grep "^zulu" || true)

  if [[ ${#zulu_cask_list[@]} -gt 0 ]]; then
    zulu_outdated=""
    for cask in "${zulu_cask_list[@]}"; do
      cask_json=$(brew info --json=v2 --cask "$cask" 2>/dev/null || true)
      cask_installed=$(brew_json_field "$cask_json" "installed")
      cask_latest=$(brew_json_field "$cask_json" "version")
      if [[ -n "$cask_installed" && -n "$cask_latest" && "$cask_installed" != "$cask_latest" ]]; then
        echo -e "  ${cask}: ${YELLOW}${cask_installed}${RESET} → ${GREEN}${cask_latest}${RESET}"
        echo -e "  ${YELLOW}Updating ${cask}...${RESET}"
        brew upgrade --cask "$cask" 2>&1 || true
        zulu_outdated="yes"
      fi
    done
    if [[ -n "$zulu_outdated" ]]; then
      java_note="Via Homebrew cask"
      [[ -n "$java_legacy_note" ]] && java_note="${java_legacy_note}"
      add_summary "Java (Zulu)" "$java_current" "updated" "Updated" "$java_note"
    else
      echo -e "${GREEN}  Java is up to date.${RESET}"
      add_summary "Java (Zulu)" "$java_current" "" "Up to date" "$java_legacy_note"
    fi
  else
    # Detect the latest available Zulu major version from Homebrew
    zulu_latest_cask=$(brew search --cask "zulu@" 2>/dev/null | grep -oE 'zulu@[0-9]+' | sort -t@ -k2 -n | tail -1)
    zulu_install_cmd="${zulu_latest_cask:-zulu}"
    # Check for existing non-Homebrew JDK installations
    manual_jdk_paths=()
    while IFS= read -r jdk_path; do
      [[ -n "$jdk_path" ]] && manual_jdk_paths+=("$jdk_path")
    done < <(find /Library/Java/JavaVirtualMachines -maxdepth 1 -name "*.jdk" 2>/dev/null || true)

    if [[ ${#manual_jdk_paths[@]} -gt 0 ]]; then
      echo -e "  ${YELLOW}Existing JDK installation(s) found:${RESET}"
      for jdk_path in "${manual_jdk_paths[@]}"; do
        echo -e "    $(basename "$jdk_path")"
      done
      echo ""
      echo -e "  ${YELLOW}To switch to Homebrew-managed Zulu, run:${RESET}"
      echo -e "    sudo rm -rf /Library/Java/JavaVirtualMachines/*.jdk"
      echo -e "    brew install --cask ${zulu_install_cmd}"
      add_summary "Java (Zulu)" "$java_current" "" "Not managed" "Remove old JDK, then: brew install --cask ${zulu_install_cmd}"
    else
      echo -e "  ${YELLOW}Not installed via Homebrew — install with: brew install --cask ${zulu_install_cmd}${RESET}"
      add_summary "Java (Zulu)" "$java_current" "" "Not managed" "Run: brew install --cask ${zulu_install_cmd}"
    fi
  fi
fi

# ── Slack CLI ─────────────────────────────────────

check_brew_cask_tool "Slack CLI" "slack" "slack-cli" "slack version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1"

# ── Google Cloud CLI ──────────────────────────────

if command -v gcloud &>/dev/null; then
  header "Google Cloud CLI (gcloud)"
  gcloud_current=$(gcloud version 2>/dev/null | head -1 | awk '{print $NF}')
  echo -e "  Version: ${gcloud_current}"
  echo -e "${YELLOW}Checking for updates...${RESET}"
  gcloud components update --quiet 2>&1 || true
  gcloud_new=$(gcloud version 2>/dev/null | head -1 | awk '{print $NF}')
  if [[ -n "$gcloud_current" && -n "$gcloud_new" && "$gcloud_current" != "$gcloud_new" ]]; then
    echo -e "  Previous: ${YELLOW}${gcloud_current}${RESET}"
    echo -e "  Updated:  ${GREEN}${gcloud_new}${RESET}"
    add_summary "Google Cloud" "$gcloud_current" "$gcloud_new" "Updated" "Via gcloud components"
  else
    echo -e "${GREEN}  Google Cloud CLI is up to date.${RESET}"
    add_summary "Google Cloud" "$gcloud_current" "" "Up to date" ""
  fi
fi

# ── Playwright CLI ───────────────────────────────

if command -v npx &>/dev/null && npx playwright --version &>/dev/null 2>&1; then
  check_npm_tool "Playwright" "npx playwright" "@playwright/test" "npx playwright install"
fi

# ── Homebrew Cleanup ─────────────────────────────────

if command -v brew &>/dev/null; then
  header "Cleanup"
  echo -e "${YELLOW}Removing old versions and cache...${RESET}"
  brew cleanup --prune=7 2>&1 | tail -1 || true
  echo -e "${GREEN}  Cleanup complete.${RESET}"
fi

# ── Summary Table ─────────────────────────────────

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Summary${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
# pad_col: right-pads text to a given width, then wraps with optional colour
pad_col() {
  local text="$1" width="$2" colour="${3:-}"
  local padded
  padded=$(printf "%-${width}s" "$text")
  if [[ -n "$colour" ]]; then
    echo -ne "${colour}${padded}${RESET}"
  else
    echo -ne "$padded"
  fi
}

printf "  "
pad_col "CLI" 18 "$BOLD"; pad_col "Previous Ver" 16 "$BOLD"; pad_col "Updated Ver" 16 "$BOLD"; pad_col "Status" 14 "$BOLD"; pad_col "Notes" 35 "$BOLD"
echo -e "${RESET}"
printf "  %-18s %-16s %-16s %-14s %-35s\n" "──────────────────" "────────────────" "────────────────" "──────────────" "───────────────────────────────────"

for i in "${!summary_names[@]}"; do
  name="${summary_names[$i]}"
  old_ver="${summary_old_versions[$i]}"
  new_ver="${summary_new_versions[$i]}"
  status="${summary_statuses[$i]}"
  notes="${summary_notes[$i]}"

  [[ -z "$new_ver" ]] && new_ver="—"
  [[ "$status" == "skipped" ]] && continue

  printf "  "
  if [[ "$status" == "Updated" ]]; then
    pad_col "$name" 18; pad_col "$old_ver" 16 "$YELLOW"; pad_col "$new_ver" 16 "$GREEN"; pad_col "$status" 14 "$GREEN"; pad_col "$notes" 35
  elif [[ "$status" == "Up to date" ]]; then
    pad_col "$name" 18; pad_col "$old_ver" 16; pad_col "—" 16; pad_col "$status" 14 "$GREEN"; pad_col "$notes" 35
  elif [[ "$status" == "Check failed" || "$status" == "Update failed" ]]; then
    pad_col "$name" 18; pad_col "$old_ver" 16; pad_col "$new_ver" 16; pad_col "$status" 14 "$RED"; pad_col "$notes" 35
  else
    pad_col "$name" 18; pad_col "$old_ver" 16; pad_col "$new_ver" 16; pad_col "$status" 14 "$YELLOW"; pad_col "$notes" 35
  fi
  echo ""
done
echo ""
