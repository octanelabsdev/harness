#!/usr/bin/env bash
# test_update.sh — behavior tests for tools/harness_update.sh --apply: it bumps the project's pin, finds
# the main checkout's settings from a worktree, and never rewrites user settings. (A ref written into the
# user-scope marketplace entry makes Claude Code ignore the marketplace in every repo.)
#
# The harness remote is a local bare repo (HARNESS_REPO_URL); HOME is a throwaway. Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$HERE/harness_update.sh"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }

tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"; ROOT="$(mktemp -d "${tmp:-/tmp}/harness-updatetest.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

export GIT_CONFIG_GLOBAL="$ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global init.defaultBranch main

git init -q "$ROOT/harness-src"
git -C "$ROOT/harness-src" commit -q --allow-empty -m release
git -C "$ROOT/harness-src" tag -a v9.9.9 -m v9.9.9
git clone -q --bare "$ROOT/harness-src" "$ROOT/harness.git"
export HARNESS_REPO_URL="$ROOT/harness.git"

export HOME="$ROOT/home"; mkdir -p "$HOME/.claude"
USER_SETTINGS='{"extraKnownMarketplaces":{"harness":{"source":{"source":"github","repo":"octanelabsdev/harness"}}}}'
printf '%s\n' "$USER_SETTINGS" > "$HOME/.claude/settings.json"
PINNED='{"extraKnownMarketplaces":{"harness":{"source":{"source":"github","repo":"octanelabsdev/harness","ref":"v0.0.1"}}}}'
ref_in() { jq -r '.extraKnownMarketplaces.harness.source.ref // "none"' "$1"; }
user_untouched() { [ "$(jq -c . "$HOME/.claude/settings.json")" = "$(jq -c . <<< "$USER_SETTINGS")" ]; }
apply_in() { (cd "$1" && env -u CLAUDE_PROJECT_DIR bash "$UPDATE" --apply 2>&1); }

echo "harness_update --apply:"

# A repo that pins in its own settings.json.
git init -q "$ROOT/app"; mkdir -p "$ROOT/app/.claude"; printf '%s\n' "$PINNED" > "$ROOT/app/.claude/settings.json"
git -C "$ROOT/app" add -A; git -C "$ROOT/app" commit -q -m init
OUT="$(apply_in "$ROOT/app")"
[ "$(ref_in "$ROOT/app/.claude/settings.json")" = v9.9.9 ] && ok "bumps the project's own pin" || no "project pin not bumped: $OUT"
user_untouched && ok "leaves user settings alone" || no "user settings changed"

# A repo whose settings.json is untracked (excluded), run from a worktree that therefore lacks it.
git init -q "$ROOT/local"; git -C "$ROOT/local" commit -q --allow-empty -m init
mkdir -p "$ROOT/local/.claude"; printf '%s\n' "$PINNED" > "$ROOT/local/.claude/settings.json"
printf '/.claude/\n' >> "$ROOT/local/.git/info/exclude"
git -C "$ROOT/local" worktree add -q "$ROOT/local/.claude/worktrees/wt" -b wt
OUT="$(apply_in "$ROOT/local/.claude/worktrees/wt")"
[ "$(ref_in "$ROOT/local/.claude/settings.json")" = v9.9.9 ] && ok "from a worktree, bumps the main checkout's untracked pin" || no "main checkout pin not bumped: $OUT"
user_untouched && ok "from a worktree, leaves user settings alone" || no "worktree run changed user settings"

# Only user settings declare the marketplace: refuse, and say why.
git init -q "$ROOT/bare-app"; git -C "$ROOT/bare-app" commit -q --allow-empty -m init
OUT="$(apply_in "$ROOT/bare-app")"; RC=$?
[ "$RC" != 0 ] && ok "no project pin: refuses (exit $RC)" || no "no project pin: expected non-zero exit"
grep -q "user settings" <<< "$OUT" && ok "the refusal names user settings" || no "refusal doesn't explain: $OUT"
user_untouched && ok "no project pin: user settings untouched" || no "user settings were rewritten"

echo
if [ "$fail" = 0 ]; then echo "OK: update tests passed ($pass)."; exit 0; else echo "FAIL: $fail update test(s), $pass passed." >&2; exit 1; fi
