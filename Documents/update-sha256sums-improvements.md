# update-sha256sums.sh — Improvements Tracker

Purpose
- Track and prioritize improvements for `update-sha256sums.sh`.
- Focus first on reliability and UX improvements with minimal disruption.
- Keep a single source of truth for outstanding work and status.

Status Legend
- [ ] TODO
- [x] Done
- [~] In progress / partial

Notes
- Some UX changes are already implemented in another copy of the script and should be synchronized across all copies to avoid drift.
- High-priority items are grouped into Phase 1.

---

## Phase 1 — High-impact, low-risk (prioritized)

Reliability and correctness
- [ ] Skip edits if checksums are unchanged:
  - Read existing hashes, compare to new ones, and no-op with a clear message if nothing changed.
- [ ] Better repo inference:
  - Also inspect `source=()` lines for GitHub URLs (including `git+https` and tag fragments) when `url=` is missing.
- [ ] Add download retries/backoff:
  - Wrap `curl` with a small retry loop and exponential backoff for transient failures.

User experience
- [ ] Confirmation before writing:
  - Print a clear summary (PKGFILE, repo, tag, asset, URLs, new hashes) and prompt “Proceed? [Y/n]”.
  - Add `--yes` to skip confirmation in non-interactive/CI runs.
- [ ] Optional .SRCINFO update:
  - `--update-srcinfo` to run `makepkg --printsrcinfo > .SRCINFO` on success.
- [ ] Non-interactive safeguards:
  - Detect lack of TTY and require `-p/--pkgbuild` (or `--package NAME`); exit with a clear message instead of prompting.
- [ ] Add `--package NAME`:
  - Shortcut to select `$AUR_BASE/NAME-bin/PKGBUILD` without opening the interactive menu.

Hygiene and maintainability
- [ ] Remove unused variables and dead code (e.g., `console_output` references where present).
- [ ] Consistent exit codes:
  - Use distinct non-zero exit codes for common failure modes (no PKGBUILD, invalid version, downloads, etc.).

Sync work
- [ ] Sync all implemented UX improvements across both script locations so behavior is identical.

Acceptance criteria for Phase 1
- Robust array update works with one-line and multi-line `sha256sums`, preserves formatting, and updates the first two entries.
- No-op commit when sums are unchanged.
- Confirmation step with `--yes` flag.
- Improved repo inference from `source=`.
- Resilient downloads with retry.
- Optional `.SRCINFO` update flag.
- CLI-only (non-interactive) mode supported for automation.
- `--package` resolves packages without interactive prompts.

---

## Phase 2 — Medium complexity, strong UX improvements

Selection and discovery
- [ ] Fuzzy finder support:
  - If `fzf` is installed, use it for package selection; otherwise fall back to numbered list.

Asset naming and templating
- [ ] Asset templates:
  - Add `--asset-template '{name}-{version}-{arch}'` with placeholders:
    - `{name}` = derived dir name, stripped of `-bin`
    - `{version}` = resolved version
    - `{tag}` = resolved tag
    - `{arch}` = normalized `uname -m` (e.g., `x86_64`, `arm64`/`aarch64` mapping)

Hash algorithm flexibility
- [ ] Support `--algo sha256|sha512`:
  - Switch hash command and target array (`sha256sums` vs `sha512sums`) accordingly.

Tag discovery
- [ ] Latest release discovery:
  - `--latest` to fetch the latest release tag (GitHub API or `gh` if available) and set `TAG` accordingly.

Provider abstraction
- [ ] Multi-provider support:
  - `--provider github|gitlab|custom` and corresponding URL builders.

Configuration
- [ ] Config file:
  - Optional `~/.config/update-sha256sums/config` for defaults like `AUR_BASE`, `TAG_PREFIX`, provider, etc. CLI flags override config.

---

## Phase 3 — Advanced maintainability and quality

Refactoring
- [ ] Extract into functions (e.g., `select_pkgbuild`, `derive_asset_name`, `resolve_version_and_tag`, `infer_repo`, `build_urls`, `download_artifacts`, `compute_hashes`, `update_pkgbuild`, `maybe_update_srcinfo`, `confirm`, `print_summary`).

Testing and linting
- [ ] Test harness:
  - Fixtures for:
    - Multi-line arrays
    - Arrays with comments
    - Different AUR folder names
    - Missing `url=` but GitHub in `source=`
    - Dry-run assertions
- [ ] Shellcheck cleanup and CI:
  - Add shellcheck and minimal CI to prevent regressions.

Logging and UX polish
- [ ] Verbosity flags:
  - `--quiet`, `--verbose` logging levels.
- [ ] Machine-readable output:
  - `--print-json` to dump a summary (pkgfile, repo, version, tag, asset, URLs, hashes) for tooling.
- [ ] Colorized output:
  - Toggle via `--no-color` and auto-detect TTY.

---

## Implemented UX improvements (Done)

Interactive and defaults
- [x] Prefer `./PKGBUILD` in current directory; if missing, interactively select from `$AUR_BASE` (default `$HOME/aur-packages`).
- [x] Only list packages whose directory names end with `-bin`.
- [x] Allow override of base directory via `AUR_BASE` environment variable.

Asset name
- [x] Derive default asset name from directory name (strip trailing `-bin`).
- [x] When using `./PKGBUILD`, derive asset name from the current working directory.

Version/Tag interaction
- [x] If neither `--version` nor `--tag` is provided:
  - Show current `pkgver`.
  - Prompt for new version with “Enter to keep current”.
  - Validate `x.x.x` when entered.
- [x] Derive `TAG` from `VERSION` using `TAG_PREFIX`.
- [x] Derive `VERSION` from `TAG` by stripping `TAG_PREFIX`.

Overrides
- [x] `-a/--asset` continues to override the derived asset name.

Note: The items above are implemented in the updated script; ensure they are synchronized across all copies of the script to avoid divergence.

---

## Open Questions / Design Decisions

- Should the script also update `pkgver` in PKGBUILD when a new version is chosen, or remain checksum-only?
- How should we handle packages with more than two sources or custom source ordering?
- Should binary vs source checksum order be configurable (e.g., source-first packages)?
- What is the preferred failure behavior in non-interactive contexts when selection is required?
- For provider support, do we require CLI tools (like `gh`) or rely only on `curl` + API tokens?

---

## Changelog (for this tracker)

- 2025-10-28: Initial tracker created. Marked already-implemented UX items as Done. Prioritized Phase 1 tasks.
