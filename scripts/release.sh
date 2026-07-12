#!/usr/bin/env bash
# scripts/release.sh — drop_observability release automation
#
# Usage:
#   ./scripts/release.sh [--dry-run|-n] [--pr] [VERSION]
#   ./scripts/release.sh --tag-only VERSION
#   make release [VERSION=x.y.z] [DRY_RUN=1] [PR=1]
#
# Flags:
#   --dry-run / -n   Run all checks and show what would happen; write nothing.
#   --pr             Open a release PR for review instead of committing
#                     straight to main. Stops after opening the PR — once it's
#                     merged, finish with:
#                       ./scripts/release.sh --tag-only VERSION
#   --tag-only       Skip changelog/version-bump/commit (assumes a release
#                     commit already landed on main, e.g. via --pr) and just
#                     run the CI gate + create/push the tag.
#
# What it does (default, no flags):
#   1. Validates tooling and git state (must be on main, clean, up to date)
#   2. Resolves the release version (arg or prompted, semver-validated)
#   3. Runs the CI gate locally: analyze, format, test, facade-contract.
#      This is the concrete stand-in for "all phases are complete" — the
#      script refuses to release if the working tree isn't green.
#   4. Drafts a CHANGELOG.md entry from conventional commits since the last tag
#   5. Bumps the version in pubspec.yaml
#   6. Commits directly to main and pushes
#   7. Creates and pushes the vX.Y.Z tag (after an explicit confirmation) —
#      this tag is the actual release artifact: consuming apps
#      (drop-mobile, drop-rider, drop-admin-mobile) pin their git dependency
#      `ref` to it deliberately, per OTEL_LIBRARY_PLAN.md.

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
PUBSPEC="$REPO_ROOT/pubspec.yaml"

GITHUB_REPO="kennankole/drop-flutter-otel-sdk"
GITHUB_REPO_URL="https://github.com/$GITHUB_REPO"

# ── Output helpers ───────────────────────────────────────────────────────────
BOLD='\033[1m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()   { printf "${BLUE}▶${NC}  %s\n" "$*"; }
ok()     { printf "${GREEN}✓${NC}  %s\n" "$*"; }
warn()   { printf "${YELLOW}⚠${NC}  %s\n" "$*"; }
die()    { printf "${RED}✗${NC}  %s\n" "$*" >&2; exit 1; }
header() { printf "\n${BOLD}%s${NC}\n" "$*"; }

# ── Dry-run helpers ───────────────────────────────────────────────────────────
DRY_RUN=false
USE_PR=false
TAG_ONLY=false

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf "${YELLOW}[dry-run]${NC}  %s\n" "$*"
  else
    "$@"
  fi
}
would() { printf "${YELLOW}[dry-run]${NC}  %s\n" "$*"; }

# ── 1. Preflight ──────────────────────────────────────────────────────────────
check_deps() {
  header "Checking dependencies"
  local missing=()
  for cmd in git flutter dart; do
    if command -v "$cmd" &>/dev/null; then
      ok "$cmd"
    else
      missing+=("$cmd")
    fi
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Install missing tools before continuing: ${missing[*]}"

  if command -v gh &>/dev/null; then
    ok "gh"
    GH_AVAILABLE=true
  else
    warn "gh not found — PR creation (--pr) will fall back to printed instructions."
    warn "Install from: https://cli.github.com/"
    GH_AVAILABLE=false
  fi
}

check_git_state() {
  header "Checking git state"
  local branch
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

  [[ "$branch" == "main" ]] || die "Current branch is '$branch'. Releases are cut from 'main' — switch and try again."
  ok "On branch main"

  if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
    die "Working tree has uncommitted changes. Commit or stash them first."
  fi
  ok "Working tree clean"

  info "Fetching from origin..."
  git -C "$REPO_ROOT" fetch --quiet origin

  local local_head remote_head
  local_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  remote_head="$(git -C "$REPO_ROOT" rev-parse origin/main 2>/dev/null || echo "")"
  if [[ -n "$remote_head" && "$local_head" != "$remote_head" ]]; then
    die "Local main is not up to date with origin/main. Pull first."
  fi
  ok "Up to date with origin/main"
}

# ── 2. Version ────────────────────────────────────────────────────────────────
resolve_version() {
  header "Resolving version"
  CURRENT_VERSION="$(grep '^version:' "$PUBSPEC" | sed 's/version: *//' | tr -d '[:space:]')"

  if [[ -n "${1:-}" ]]; then
    TARGET_VERSION="$1"
  else
    local suggested
    suggested="$(echo "$CURRENT_VERSION" | awk -F. '{print $1"."$2"."$3+1}')"
    printf "Current version: ${BOLD}%s${NC}\n" "$CURRENT_VERSION"
    printf "New version [%s]: " "$suggested"
    read -r input
    TARGET_VERSION="${input:-$suggested}"
  fi

  [[ "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "Invalid version '$TARGET_VERSION'. Use semver: X.Y.Z"

  TAG_NAME="v$TARGET_VERSION"

  if [[ "$TAG_ONLY" == true ]]; then
    [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]] \
      || die "--tag-only expects pubspec.yaml to already be at $TARGET_VERSION (it's $CURRENT_VERSION). Did the release commit land on main?"
  fi

  if [[ "$DRY_RUN" == false ]]; then
    if git -C "$REPO_ROOT" show-ref --tags --quiet "refs/tags/$TAG_NAME"; then
      die "Tag $TAG_NAME already exists locally."
    fi
    if git -C "$REPO_ROOT" ls-remote --tags origin "refs/tags/$TAG_NAME" 2>/dev/null | grep -q .; then
      die "Tag $TAG_NAME already exists on origin."
    fi
  fi

  ok "Releasing $CURRENT_VERSION → $TARGET_VERSION (tag $TAG_NAME)"
}

# ── 3. CI gate ──────────────────────────────────────────────────────────────
run_ci_gate() {
  header "Running CI checks locally (the 'all phases complete' gate)"
  ( cd "$REPO_ROOT" && flutter pub get ) \
    || die "flutter pub get failed."
  ( cd "$REPO_ROOT" && flutter analyze ) \
    || die "flutter analyze failed. Fix issues before releasing."
  ( cd "$REPO_ROOT" && dart format --output=none --set-exit-if-changed lib test ) \
    || die "dart format check failed. Run 'dart format lib test' and commit."
  ( cd "$REPO_ROOT" && flutter test ) \
    || die "flutter test failed. Fix failing tests before releasing."
  ( cd "$REPO_ROOT" && ./scripts/check_facade_imports.sh ) \
    || die "Facade import-graph contract violated."
  ok "All CI checks passed."
}

# ── 4. Changelog ──────────────────────────────────────────────────────────────
draft_changelog() {
  header "Drafting changelog"

  local log_range last_tag
  last_tag="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "")"
  if [[ -n "$last_tag" ]]; then
    log_range="${last_tag}..HEAD"
    info "Commits since tag $last_tag"
  else
    log_range="HEAD"
    info "No previous tags — using full history"
  fi

  local today all_commits
  today="$(date +%Y-%m-%d)"
  all_commits="$(git -C "$REPO_ROOT" log "$log_range" --pretty=format:"%s" 2>/dev/null || true)"

  local features fixes chores
  features="$(printf '%s\n' "$all_commits" | grep '^feat:'                | sed 's/^feat: \{0,1\}//'  | sort -u || true)"
  fixes="$(   printf '%s\n' "$all_commits" | grep '^fix:'                 | sed 's/^fix: \{0,1\}//'   | sort -u || true)"
  chores="$(  printf '%s\n' "$all_commits" | grep -E '^(chore|ci|build):' | sed 's/^[^:]*: \{0,1\}//' | sort -u || true)"

  local tmpfile
  tmpfile="$(mktemp /tmp/drop-observability-changelog-XXXX.md)"

  {
    printf "## [%s] — %s\n\n" "$TARGET_VERSION" "$today"
    if [[ -n "$features" ]]; then
      printf "### Features\n\n"
      while IFS= read -r line; do [[ -z "$line" ]] || printf -- '- %s\n' "$line"; done <<< "$features"
      printf "\n"
    fi
    if [[ -n "$fixes" ]]; then
      printf "### Fixes\n\n"
      while IFS= read -r line; do [[ -z "$line" ]] || printf -- '- %s\n' "$line"; done <<< "$fixes"
      printf "\n"
    fi
    if [[ -n "$chores" ]]; then
      printf "### Chores\n\n"
      while IFS= read -r line; do [[ -z "$line" ]] || printf -- '- %s\n' "$line"; done <<< "$chores"
      printf "\n"
    fi
    if [[ -z "$features" && -z "$fixes" && -z "$chores" ]]; then
      printf "### Changes\n\n- (no conventional commits found — edit this section manually)\n\n"
    fi
  } > "$tmpfile"

  printf "\n${BOLD}Draft:${NC}\n"
  cat "$tmpfile"

  if [[ "$DRY_RUN" == true ]]; then
    would "write entry above to CHANGELOG.md"
    rm "$tmpfile"
    return
  fi

  printf "\nOpen in editor to edit? [Y/n]: "
  read -r open_editor
  if [[ "${open_editor:-Y}" =~ ^[Yy]$ ]]; then
    ${EDITOR:-nano} "$tmpfile"
  fi

  local entry
  entry="$(cat "$tmpfile")"
  rm "$tmpfile"

  if grep -q "^## \[" "$CHANGELOG"; then
    awk -v entry="$entry" '
      /^## \[/ && !inserted { printf "%s\n", entry; inserted=1 }
      { print }
    ' "$CHANGELOG" > "${CHANGELOG}.tmp" && mv "${CHANGELOG}.tmp" "$CHANGELOG"
  else
    # First-ever release entry: no prior "## [" anchor to insert above.
    printf "\n%s" "$entry" >> "$CHANGELOG"
  fi

  ok "CHANGELOG.md updated."
}

# ── 5. Version bump ───────────────────────────────────────────────────────────
bump_version() {
  header "Bumping version"
  if [[ "$DRY_RUN" == true ]]; then
    would "sed pubspec.yaml: version $CURRENT_VERSION → $TARGET_VERSION"
    return
  fi
  sed -i "s/^version: .*/version: $TARGET_VERSION/" "$PUBSPEC"
  ok "pubspec.yaml: $CURRENT_VERSION → $TARGET_VERSION"
}

# ── 6. Commit + land (direct to main, or via PR) ──────────────────────────────
commit_and_land() {
  header "Committing release"

  if [[ "$USE_PR" == true ]]; then
    local branch_name="release/$TARGET_VERSION"
    run git -C "$REPO_ROOT" checkout -b "$branch_name"
    run git -C "$REPO_ROOT" add "$CHANGELOG" "$PUBSPEC"
    run git -C "$REPO_ROOT" commit -m "chore: release $TARGET_VERSION"
    run git -C "$REPO_ROOT" push -u origin "$branch_name"

    if [[ "$GH_AVAILABLE" == true ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        would "gh pr create --base main --head $branch_name --title 'Release $TARGET_VERSION'"
      else
        gh pr create --base main --head "$branch_name" --title "Release $TARGET_VERSION" \
          --body "Automated release PR for $TARGET_VERSION.

After merging, finish the release with:
\`\`\`
git checkout main && git pull
./scripts/release.sh --tag-only $TARGET_VERSION
\`\`\`" \
          || die "Failed to open PR."
        ok "PR opened."
      fi
    else
      warn "Open a PR manually: $branch_name → main"
      printf "  %s/compare/main...%s\n" "$GITHUB_REPO_URL" "$branch_name"
    fi

    printf "\n${YELLOW}${BOLD}Stopping here — PR flow.${NC} Once merged, run:\n"
    printf "  git checkout main && git pull\n"
    printf "  ./scripts/release.sh --tag-only %s\n" "$TARGET_VERSION"
    exit 0
  fi

  run git -C "$REPO_ROOT" add "$CHANGELOG" "$PUBSPEC"
  run git -C "$REPO_ROOT" commit -m "chore: release $TARGET_VERSION"
  run git -C "$REPO_ROOT" push origin main
  ok "Pushed release commit to main."
}

# ── 7. Tag (the actual release artifact) ───────────────────────────────────────
create_and_push_tag() {
  header "Tagging release"

  printf "About to create and push tag ${BOLD}%s${NC} — this is what consuming apps pin to. Continue? [y/N]: " "$TAG_NAME"
  if [[ "$DRY_RUN" == false ]]; then
    read -r confirm
    [[ "${confirm:-N}" =~ ^[Yy]$ ]] || die "Aborted before tagging. Any release commit already on main is unaffected."
  else
    would "prompt for tag confirmation"
  fi

  run git -C "$REPO_ROOT" tag -a "$TAG_NAME" -m "Release $TAG_NAME"
  run git -C "$REPO_ROOT" push origin "$TAG_NAME"
  ok "Tag $TAG_NAME pushed."
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  local version_arg=""
  for arg in "$@"; do
    case "$arg" in
      --dry-run|-n) DRY_RUN=true ;;
      --pr)         USE_PR=true ;;
      --tag-only)   TAG_ONLY=true ;;
      *)            version_arg="$arg" ;;
    esac
  done

  printf "${BOLD}drop_observability — Release Script${NC}"
  [[ "$DRY_RUN" == true ]] && printf "  ${YELLOW}(dry run — nothing will be written)${NC}"
  printf "\n"

  check_deps
  check_git_state
  resolve_version "$version_arg"
  run_ci_gate

  if [[ "$TAG_ONLY" == false ]]; then
    draft_changelog
    bump_version
    commit_and_land # exits early if --pr
  fi

  create_and_push_tag

  if [[ "$DRY_RUN" == true ]]; then
    printf "\n${YELLOW}${BOLD}Dry run complete.${NC} No files written, no commits, no tags.\n"
    printf "Run without --dry-run to execute for real.\n"
  else
    printf "\n${GREEN}${BOLD}Done.${NC} Released %s.\n" "$TARGET_VERSION"
    printf "Tag: %s\n" "$TAG_NAME"
    printf "Consuming apps pin: drop_observability: {git: {url: %s.git, ref: %s}}\n" "$GITHUB_REPO_URL" "$TAG_NAME"
  fi
}

main "$@"
