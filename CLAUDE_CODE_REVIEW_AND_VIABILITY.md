# Claude Code Review And Viability

## Review Scope

- Repository: `guy2c9/Autocheck-cli-updates`
- Ref reviewed: `origin/main`
- Commit reviewed: `d58f302`
- Refresh date: `2026-04-06`

This review was produced after refreshing the local checkout from GitHub. It supersedes the earlier recommendations-only document.

## Findings

### [P1] README still executes a mutable script directly from `main`

Files:

- `README.md:28`
- `README.md:63`

Why it matters:

- The one-off command and the daily wrapper both download and execute `check-cli-updates.sh` from the moving `main` branch.
- This repo has already used force-pushes on `main`, so the trust model is not theoretical.
- For an unattended updater, mutable-branch remote execution is the largest project-level risk.

Recommendation:

- Replace the `main` download URLs with either:
  - a release tag
  - a pinned commit SHA
  - a local-first install flow where the script is installed once and updated intentionally

### [P1] Helper-based tool checks still misreport "Up to date" when version parsing fails

Files:

- `check-cli-updates.sh:37-64`
- `check-cli-updates.sh:83-107`

Why it matters:

- `check_npm_tool` and `check_brew_cask_tool` now handle lookup failures better, but they still fall through to `Up to date` when:
  - the package registry lookup succeeds
  - the command exists
  - the current version cannot be parsed
- In that state, the script silently reports green status instead of surfacing that local version detection is broken.

Concrete example:

- If a CLI changes its `--version` output format and `grep -oE '[0-9]+\.[0-9]+\.[0-9]+'` no longer matches, `current` becomes empty and the helper lands in the `else` branch.

Recommendation:

- Add an explicit branch for `[[ -z "$current" ]]` that records `Check failed` with a note like `installed version unreadable`.

### [P1] Several major update paths still report success without post-update verification

Files:

- `check-cli-updates.sh:147-177`
- `check-cli-updates.sh:255-279`
- `check-cli-updates.sh:284-298`
- `check-cli-updates.sh:350-372`
- `check-cli-updates.sh:411-427`
- `check-cli-updates.sh:465-479`

Why it matters:

- The helper-based npm, cask, and `gh` paths now re-check the installed version after updating.
- The remaining core sections still do not.
- They continue to use `|| true` and optimistic success output, so a failed upgrade can still show up as successful or effectively green in the run.

Highest-risk areas:

- Homebrew formulae
- Homebrew casks
- Salesforce CLI core update
- Claude Code update
- Warp update
- Zulu update
- gcloud update

Recommendation:

- Move all updateable tools onto a consistent helper pattern:
  - detect latest
  - run update
  - re-check installed version
  - record `Updated` only if the version changed

### [P2] Playwright remains cwd-dependent and is not a reliable global-tool target

Files:

- `check-cli-updates.sh:484-485`

Why it matters:

- `npx playwright --version` can resolve a project-local dependency from the current working directory.
- The script then updates a global npm package and installs browsers, which may not affect the version that was just detected.
- That creates mismatched behavior and makes the updater less predictable.

Recommendation:

- Remove Playwright from this global updater unless a clearly global install can be detected reliably.
- If retained, document that it only manages a global Playwright toolchain and should not run inside arbitrary project directories.

### [P2] Python "legacy" guidance is still based on whichever `python3` wins on `PATH`

Files:

- `check-cli-updates.sh:231-245`

Why it matters:

- The script no longer auto-uninstalls legacy Python versions, which is the right safety move.
- But it still treats the active `python3` as the reference point for deciding which Homebrew Python formulae are legacy.
- On machines using `pyenv`, `asdf`, Conda, or another non-Homebrew interpreter, the resulting recommendation can still be misleading.

Recommendation:

- Base "legacy" only on installed Homebrew Python formulae relative to each other, not relative to the active shell interpreter.
- At minimum, soften the wording so it is informational rather than prescriptive.

### [P3] CI is still too narrow for an unattended updater

Files:

- `.github/workflows/lint.yml:13-16`

Why it matters:

- The repo has ShellCheck CI, which is useful.
- But there are no behavioral tests for the state machine that now distinguishes `Up to date`, `Check failed`, `Updated`, and `Update failed`.
- The workflow also uses a floating GitHub Action ref instead of an immutable SHA.

Recommendation:

- Pin GitHub Actions to commit SHAs.
- Add mocked shell tests for:
  - unreadable version output
  - unreachable registry/API
  - failed update command
  - unchanged version after update
  - wrapper retry behavior

## Viability Assessment

### Current viability

- Personal or internal use: `viable`
- Public unattended distribution: `not yet strong enough`

### Strengths

- Small codebase with a clear single-purpose design
- Recent maintenance and visible iteration history
- Documentation is understandable and practical
- Safety has improved compared with earlier revisions
- Basic CI exists

### Weaknesses

- Mutable `main` is still the default execution target
- Update result accuracy is inconsistent across tool sections
- Tool detection is still environment-sensitive in a few places
- No behavior-level tests
- Single-script approach will become harder to evolve as more tools are added

### Score

- Personal-use viability: `7/10`
- Public-use viability: `4/10`

## Recommended Next Steps

1. Eliminate remote execution from mutable `main`.
2. Fix the remaining false-success and false-green paths.
3. Remove or redesign Playwright handling.
4. Make Python cleanup guidance independent of `PATH` interpreter choice.
5. Add mocked behavior tests and pin CI actions.

## Questions For Claude

1. Do you agree that mutable-`main` execution is the top project risk?
2. Did I miss any remaining false-success branches outside the ones listed above?
3. Should Playwright be removed entirely from this script?
4. What is the smallest safe testing harness for this repo?
