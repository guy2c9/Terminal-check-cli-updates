#!/bin/bash
# check-cli-updates.sh — Check for and install updates across all CLI applications

set -uo pipefail

# Colours
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# Helper: shorten Warp version (e.g. 0.2025.04.01.08.02.stable_02 → 2025.04.01)
shorten_warp_ver() {
  echo "$1" | sed -E 's/^0\.//; s/\.[0-9]{2}\.[0-9]{2}\.stable.*//'
}

# Counters
brew_formula_count=0
brew_cask_count=0
pip_count=0
python_status="skipped"
sf_status="skipped"
claude_status="skipped"
gh_status="skipped"
op_status="skipped"
warp_status="skipped"
gcloud_status="skipped"
java_status="skipped"
slack_status="skipped"

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
  for formula in $(brew list --formula 2>/dev/null | grep "^python@"); do
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
  done
  if [[ "$py_latest" == "outdated" ]]; then
    python_status="update available"
  else
    echo -e "${GREEN}  All Python installations are up to date.${RESET}"
    python_status="up to date"
  fi

  # Remove legacy Python versions that nothing depends on
  py_active=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
  for formula in $(brew list --formula 2>/dev/null | grep "^python@"); do
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
  done
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
  sf_update_output=$(sf update 2>&1 || true)
  sf_new_ver=$(sf version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [[ -n "$sf_current_ver" && -n "$sf_new_ver" && "$sf_current_ver" != "$sf_new_ver" ]]; then
    echo -e "  Previous: ${YELLOW}${sf_current_ver}${RESET}"
    echo -e "  Updated:  ${GREEN}${sf_new_ver}${RESET}"
    sf_status="updated (${sf_current_ver} → ${sf_new_ver})"
    add_summary "Salesforce CLI" "$sf_current_ver" "$sf_new_ver" "Updated" ""
  else
    echo -e "  Version: ${sf_current_ver:-unknown}"
    echo -e "${GREEN}  Salesforce CLI is up to date.${RESET}"
    sf_status="up to date"
    add_summary "Salesforce CLI" "$sf_current_ver" "" "Up to date" ""
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
    claude_status="up to date"
    add_summary "Claude Code" "$claude_current" "" "Up to date" ""
  else
    claude_new=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo -e "  Previous: ${YELLOW}${claude_current}${RESET}"
    echo -e "  Updated:  ${GREEN}${claude_new:-check manually}${RESET}"
    claude_status="updated (${claude_current} → ${claude_new:-?})"
    add_summary "Claude Code" "$claude_current" "${claude_new:-?}" "Updated" ""
  fi
fi

# ── GitHub CLI ────────────────────────────────────

if command -v gh &>/dev/null; then
  header "GitHub CLI (gh)"
  gh_current=$(gh --version | head -1 | awk '{print $3}')
  gh_latest=$(gh api repos/cli/cli/releases/latest --jq '.tag_name' 2>/dev/null | sed 's/^v//' || true)
  if [[ -n "$gh_latest" && "$gh_current" != "$gh_latest" ]]; then
    echo -e "  Current: ${YELLOW}${gh_current}${RESET}"
    echo -e "  Latest:  ${GREEN}${gh_latest}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating GitHub CLI...${RESET}"
    brew upgrade gh 2>&1 || true
    gh_status="updated (${gh_current} → ${gh_latest})"
    add_summary "GitHub CLI" "$gh_current" "$gh_latest" "Updated" "Via Homebrew"
  else
    echo -e "  Version: ${gh_current}"
    echo -e "${GREEN}  GitHub CLI is up to date.${RESET}"
    gh_status="up to date"
    add_summary "GitHub CLI" "$gh_current" "" "Up to date" ""
  fi
fi

# ── 1Password CLI ─────────────────────────────────

if command -v op &>/dev/null; then
  header "1Password CLI (op)"
  op_current=$(op --version 2>/dev/null)
  op_latest=$(brew info --json=v2 1password-cli 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  if [[ -n "$op_latest" && "$op_current" != "$op_latest" ]]; then
    echo -e "  Current: ${YELLOW}${op_current}${RESET}"
    echo -e "  Latest:  ${GREEN}${op_latest}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating 1Password CLI...${RESET}"
    brew upgrade --cask 1password-cli 2>&1 || true
    op_status="updated (${op_current} → ${op_latest})"
    add_summary "1Password CLI" "$op_current" "$op_latest" "Updated" "Via Homebrew cask"
  else
    echo -e "  Version: ${op_current}"
    echo -e "${GREEN}  1Password CLI is up to date.${RESET}"
    op_status="up to date"
    add_summary "1Password CLI" "$op_current" "" "Up to date" ""
  fi
fi

# ── Warp Terminal ─────────────────────────────────

if brew list --cask 2>/dev/null | grep -q "^warp$"; then
  header "Warp Terminal"
  warp_json=$(brew info --json=v2 --cask warp 2>/dev/null || true)
  warp_installed=$(echo "$warp_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['casks'][0]['installed'])" 2>/dev/null || echo "unknown")
  warp_latest=$(echo "$warp_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['casks'][0]['version'])" 2>/dev/null || echo "unknown")
  warp_outdated=$(brew outdated --cask --greedy 2>/dev/null | grep "^warp" || true)
  if [[ -n "$warp_outdated" ]]; then
    echo -e "  Current: ${YELLOW}${warp_installed}${RESET}"
    echo -e "  Latest:  ${GREEN}${warp_latest:-check manually}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating Warp...${RESET}"
    brew upgrade --cask warp 2>&1 || true
    warp_status="updated (${warp_installed} → ${warp_latest:-?})"
    warp_short_old=$(shorten_warp_ver "$warp_installed")
    warp_short_new=$(shorten_warp_ver "${warp_latest:-?}")
    add_summary "Warp" "${warp_short_old:-$warp_installed}" "${warp_short_new:-${warp_latest:-?}}" "Updated" "Via Homebrew cask"
  else
    echo -e "  Version: ${warp_installed}"
    echo -e "${GREEN}  Warp is up to date.${RESET}"
    warp_status="up to date"
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
  # Remove legacy OpenJDK installations if Zulu is present or being installed
  legacy_jdks=$(ls -d /Library/Java/JavaVirtualMachines/jdk-*.jdk 2>/dev/null | grep -v "zulu" || true)
  java_legacy_note=""
  if [[ -n "$legacy_jdks" ]]; then
    legacy_names=""
    echo ""
    echo -e "  ${YELLOW}Legacy OpenJDK installations found:${RESET}"
    for jdk_path in $legacy_jdks; do
      jdk_name=$(basename "$jdk_path")
      echo -e "    ${jdk_name}"
      legacy_names="${legacy_names}${jdk_name}, "
    done
    echo -e "  ${YELLOW}Removing legacy OpenJDKs...${RESET}"
    for jdk_path in $legacy_jdks; do
      sudo rm -rf "$jdk_path" 2>/dev/null || true
    done
    # Check if any legacy JDKs still remain
    remaining_jdks=$(ls -d /Library/Java/JavaVirtualMachines/jdk-*.jdk 2>/dev/null | grep -v "zulu" || true)
    if [[ -n "$remaining_jdks" ]]; then
      java_legacy_note="Sudo required to remove legacy JDKs"
    fi
    if [[ -n "$java_legacy_note" ]]; then
      echo -e "  ${RED}Could not remove — run with sudo manually.${RESET}"
    else
      java_legacy_note="Legacy OpenJDKs removed"
      echo -e "  ${GREEN}Legacy OpenJDKs removed.${RESET}"
    fi
  fi

  # Check for Zulu casks installed via Homebrew
  zulu_casks=$(brew list --cask 2>/dev/null | grep "^zulu" || true)
  if [[ -n "$zulu_casks" ]]; then
    zulu_outdated=""
    for cask in $zulu_casks; do
      cask_json=$(brew info --json=v2 --cask "$cask" 2>/dev/null || true)
      cask_installed=$(echo "$cask_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['casks'][0]['installed'])" 2>/dev/null || true)
      cask_latest=$(echo "$cask_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['casks'][0]['version'])" 2>/dev/null || true)
      if [[ -n "$cask_installed" && -n "$cask_latest" && "$cask_installed" != "$cask_latest" ]]; then
        echo -e "  ${cask}: ${YELLOW}${cask_installed}${RESET} → ${GREEN}${cask_latest}${RESET}"
        echo -e "  ${YELLOW}Updating ${cask}...${RESET}"
        brew upgrade --cask "$cask" 2>&1 || true
        zulu_outdated="yes"
      fi
    done
    if [[ -n "$zulu_outdated" ]]; then
      java_status="updated"
      java_note="Via Homebrew cask"
      [[ -n "$java_legacy_note" ]] && java_note="${java_legacy_note}"
      add_summary "Java (Zulu)" "$java_current" "updated" "Updated" "$java_note"
    else
      echo -e "${GREEN}  Java is up to date.${RESET}"
      java_status="up to date"
      add_summary "Java (Zulu)" "$java_current" "" "Up to date" "$java_legacy_note"
    fi
  else
    # Detect the latest available Zulu major version from Homebrew
    zulu_latest_cask=$(brew search --cask "zulu@" 2>/dev/null | grep -oE 'zulu@[0-9]+' | sort -t@ -k2 -n | tail -1)
    zulu_install_cmd="${zulu_latest_cask:-zulu}"
    # Check for existing non-Homebrew JDK installations
    manual_jdks=$(ls -d /Library/Java/JavaVirtualMachines/*.jdk 2>/dev/null || true)
    if [[ -n "$manual_jdks" ]]; then
      echo -e "  ${YELLOW}Existing JDK installation(s) found:${RESET}"
      for jdk_path in $manual_jdks; do
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
    java_status="not managed by Homebrew"
  fi
fi

# ── Slack CLI ─────────────────────────────────────

if command -v slack &>/dev/null; then
  header "Slack CLI"
  slack_current=$(slack version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  slack_latest=$(brew info --json=v2 --cask slack-cli 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['casks'][0]['version'])" 2>/dev/null || true)
  if [[ -n "$slack_latest" && -n "$slack_current" && "$slack_current" != "$slack_latest" ]]; then
    echo -e "  Current: ${YELLOW}${slack_current}${RESET}"
    echo -e "  Latest:  ${GREEN}${slack_latest}${RESET}"
    echo ""
    echo -e "${YELLOW}Updating Slack CLI...${RESET}"
    brew upgrade --cask slack-cli 2>&1 || true
    slack_status="updated (${slack_current} → ${slack_latest})"
    add_summary "Slack CLI" "$slack_current" "$slack_latest" "Updated" "Via Homebrew cask"
  else
    echo -e "  Version: ${slack_current}"
    echo -e "${GREEN}  Slack CLI is up to date.${RESET}"
    slack_status="up to date"
    add_summary "Slack CLI" "$slack_current" "" "Up to date" ""
  fi
fi

# ── Google Cloud CLI ──────────────────────────────

if command -v gcloud &>/dev/null; then
  header "Google Cloud CLI (gcloud)"
  gcloud_current=$(gcloud version 2>/dev/null | head -1 | awk '{print $NF}')
  echo -e "  Version: ${gcloud_current}"
  echo -e "${YELLOW}Checking for updates...${RESET}"
  gcloud_update_output=$(gcloud components update --quiet 2>&1 || true)
  gcloud_new=$(gcloud version 2>/dev/null | head -1 | awk '{print $NF}')
  if [[ -n "$gcloud_current" && -n "$gcloud_new" && "$gcloud_current" != "$gcloud_new" ]]; then
    echo -e "  Previous: ${YELLOW}${gcloud_current}${RESET}"
    echo -e "  Updated:  ${GREEN}${gcloud_new}${RESET}"
    gcloud_status="updated (${gcloud_current} → ${gcloud_new})"
    add_summary "Google Cloud" "$gcloud_current" "$gcloud_new" "Updated" "Via gcloud components"
  else
    echo -e "${GREEN}  Google Cloud CLI is up to date.${RESET}"
    gcloud_status="up to date"
    add_summary "Google Cloud" "$gcloud_current" "" "Up to date" ""
  fi
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
  else
    pad_col "$name" 18; pad_col "$old_ver" 16; pad_col "$new_ver" 16; pad_col "$status" 14 "$YELLOW"; pad_col "$notes" 35
  fi
  echo ""
done
echo ""
