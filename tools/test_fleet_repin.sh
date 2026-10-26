#!/usr/bin/env bash
# test_fleet_repin.sh — behavior tests for tools/fleet_repin.sh: each repo in the fleet list gets a
# PR on its own base branch pinning the tag's real commit sha, hooks run under the repo's Ruby, and no
# PR is opened unless the push landed.
#
# Remotes are local bare repos (the harness remote too, via HARNESS_REPO_URL); gh and mise are fakes
# on PATH that log their calls. Git config is a throwaway, so no real config, remote, or PR is touched.
# Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPIN="$HERE/fleet_repin.sh"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }
has()   { grep -qF -- "$2" <<< "$1" && ok "$3" || no "$3 — output lacked: $2"; }
lacks() { grep -qF -- "$2" <<< "$1" && no "$3 — output had: $2" || ok "$3"; }

tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"; ROOT="$(mktemp -d "${tmp:-/tmp}/harness-repintest.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

export GIT_CONFIG_GLOBAL="$ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# The harness remote: an annotated tag, so the pinned sha must be the peeled commit, not the tag object.
git init -q "$ROOT/harness-src"
git -C "$ROOT/harness-src" commit -q --allow-empty -m release
git -C "$ROOT/harness-src" tag -a v9.9.9 -m v9.9.9
git clone -q --bare "$ROOT/harness-src" "$ROOT/harness.git"
export HARNESS_REPO_URL="$ROOT/harness.git"
SHA="$(git -C "$ROOT/harness.git" rev-parse 'v9.9.9^{commit}')"
BRANCH="chore/harness-v9.9.9-${SHA:0:7}"

BIN="$ROOT/bin"; LOG="$ROOT/calls.log"; mkdir -p "$BIN"; : > "$LOG"
# gh: reads stdin (as real tools may) so a loop fed from the fleet file would lose lines.
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
cat > /dev/null
echo "gh \$* (in \$(basename "\$PWD"))" >> "$LOG"
case "\$1 \$2" in
  "pr create") echo "https://github.com/o/\$(basename "\$PWD")/pull/1";;
  "pr view")   git ls-remote origin "refs/heads/$BRANCH" | cut -f1;;
  "api "*)     git show "\${2##*ref=}:.claude/settings.json";;
esac
EOF
cat > "$BIN/mise" <<EOF
#!/usr/bin/env bash
case "\$1" in
  where) grep -qxF "\${2#ruby@}" "$ROOT/installed-rubies";;
  exec)  echo "mise \$2 (in \$(basename "\$PWD"))" >> "$LOG"; shift 3; exec "\$@";;
esac
EOF
chmod +x "$BIN/gh" "$BIN/mise"
printf '%s\n' 3.4.4 3.4.3 > "$ROOT/installed-rubies"
export PATH="$BIN:$PATH"

# app <name> <base> <ruby-file> <ref> <sha> -> a checkout at $ROOT/<name> with a bare origin
app() {
  local d="$ROOT/$1"
  git init -q -b "$2" "$d"
  mkdir -p "$d/.claude"
  printf '{"extraKnownMarketplaces":{"harness":{"source":{"source":"github","repo":"octanelabsdev/harness","ref":"%s","sha":"%s"}}},"enabledPlugins":{"harness@harness":true}}\n' "$4" "$5" > "$d/.claude/settings.json"
  case "$3" in
    .ruby-version)  echo ruby-3.4.4 > "$d/.ruby-version";;
    .tool-versions) printf 'nodejs 22\nruby 3.4.3\n' > "$d/.tool-versions";;
    .ruby-missing)  echo 3.1.0 > "$d/.ruby-version";;
  esac
  git -C "$d" add -A && git -C "$d" commit -q -m init
  git clone -q --bare "$d" "$ROOT/$1.git"
  git -C "$d" remote add origin "$ROOT/$1.git" && git -C "$d" fetch -q origin
  git -C "$d" switch -q -c feature/in-progress
}
pin_on_origin() { git -C "$ROOT/$1.git" show "$BRANCH:.claude/settings.json" 2>/dev/null \
  | jq -r '.extraKnownMarketplaces.harness.source | "\(.ref) \(.sha)"'; }
branch_on_origin() { git -C "$ROOT/$1.git" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; }
repin() { bash "$REPIN" "$@" < /dev/null 2>&1; }

OLD=0a3817e674d9d2e8ba81b66fe76997b4bfcb1cbb
app rubyapp main .ruby-version v9.9.8 "$OLD"
app toolapp develop .tool-versions v9.9.8 "$OLD"
app current main none v9.9.9 "$SHA"
app oldruby main .ruby-missing v9.9.8 "$OLD"
app noruby main none v9.9.9 "$OLD"
cat > "$ROOT/fleet" <<EOF
# the fleet
$ROOT/rubyapp main
$ROOT/toolapp develop

$ROOT/current main
$ROOT/oldruby main
$ROOT/noruby main
EOF

echo "fleet re-pin:"
out="$(repin v9.9.9 "$ROOT/fleet")"; rc=$?
[ "$rc" = 1 ] && ok "one repo failed -> exit 1" || no "expected exit 1, got $rc"$'\n'"$out"
has "$out" "✔ rubyapp: https://github.com/o/rubyapp/pull/1" "operator sees the PR link for a repo that moved"
[ "$(pin_on_origin rubyapp)" = "v9.9.9 $SHA" ] && ok "pushed pin is the tag's peeled commit sha" || no "rubyapp pin on origin: $(pin_on_origin rubyapp)"
grep -qF "gh pr create --base develop --head $BRANCH" "$LOG" && ok "PR targets the repo's listed base branch (develop)" || no "no develop PR: $(cat "$LOG")"
[ "$(pin_on_origin toolapp)" = "v9.9.9 $SHA" ] && ok "repo after the first one in the list was still re-pinned" || no "toolapp pin on origin: $(pin_on_origin toolapp)"
grep -qF "mise ruby@3.4.4 (in rubyapp)" "$LOG" && ok "commit/push ran under .ruby-version's Ruby" || no "no mise ruby@3.4.4 call: $(cat "$LOG")"
grep -qF "mise ruby@3.4.3 (in toolapp)" "$LOG" && ok "commit/push ran under .tool-versions' Ruby" || no "no mise ruby@3.4.3 call: $(cat "$LOG")"
has "$out" "– current: origin/main already pins v9.9.9" "already-pinned repo -> reported, skipped"
branch_on_origin current && no "already-pinned repo got a branch pushed" || ok "already-pinned repo -> nothing pushed"
has "$out" "✘ oldruby: Ruby 3.1.0 isn't installed" "missing Ruby -> named, with the install command"
branch_on_origin oldruby && no "missing-Ruby repo was pushed anyway" || ok "missing Ruby -> nothing pushed"
has "$out" "✔ noruby:" "repo with no Ruby pin -> plain git, still re-pinned (fixes a sha-only drift)"
[ "$(git -C "$ROOT/rubyapp" branch --show-current)" = feature/in-progress ] && ok "checkout stays on its own branch" || no "checkout branch changed"
[ -z "$(git -C "$ROOT/rubyapp" worktree list | sed 1d)" ] && ok "temp worktree removed" || no "leftover worktree: $(git -C "$ROOT/rubyapp" worktree list)"
git -C "$ROOT/rubyapp" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null && no "checkout gained a local $BRANCH" || ok "checkout gains no local PR branch"

if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]; then
  app bash32 main none v9.9.8 "$OLD"
  echo "$ROOT/bash32 main" > "$ROOT/fleet-bash32"
  out="$(/bin/bash "$REPIN" v9.9.9 "$ROOT/fleet-bash32" < /dev/null 2>&1)"
  has "$out" "✔ bash32:" "macOS /bin/bash 3.2, repo with no Ruby pin -> still re-pinned"
fi

echo "safety:"
out="$(repin v9.9.9 "$ROOT/fleet")"
has "$out" "✘ rubyapp: $BRANCH already exists on origin" "re-run -> refuses to reuse a pushed branch"

app hooked main none v9.9.8 "$OLD"
printf '#!/bin/sh\necho "pre-push: RuboCop issues found" >&2\nexit 1\n' > "$ROOT/hooked/.git/hooks/pre-push"; chmod +x "$ROOT/hooked/.git/hooks/pre-push"
echo "$ROOT/hooked main" > "$ROOT/fleet-hooked"; : > "$LOG"
out="$(repin v9.9.9 "$ROOT/fleet-hooked")"
has "$out" "✘ hooked: push failed" "rejected push -> reported"
has "$out" "RuboCop issues found" "rejected push -> hook output shown"
grep -qF "pr create" "$LOG" && no "a PR was opened after a failed push" || ok "rejected push -> no PR opened"

app nobase main none v9.9.8 "$OLD"
echo "$ROOT/nobase" > "$ROOT/fleet-nobase"
out="$(repin v9.9.9 "$ROOT/fleet-nobase")"
has "$out" "✘ nobase: no base branch" "line without a base branch -> refused, not guessed"

out="$(repin v0.0.1 "$ROOT/fleet")"; rc=$?
[ "$rc" = 2 ] && ok "unknown tag -> exit 2" || no "unknown tag exit $rc"
has "$out" "v0.0.1 not found" "unknown tag -> says so before touching any repo"
lacks "$out" "✘" "unknown tag -> no repo attempted"

echo
echo "fleet_repin: $pass passed, $fail failed"
[ "$fail" = 0 ]
