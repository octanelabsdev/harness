#!/usr/bin/env bash
# test_release.sh — behavior tests for tools/release.sh: a release pushes the tag on HEAD, creates the
# GitHub Release marked Latest, deploys the docs, and checks GitHub's latest is the tag. A re-run skips
# what's done; a wrong version, red CI, or a moved tag stops it before anything is published.
#
# origin is a local bare repo; gh and uvx are fakes on PATH that log their calls, and the fake uvx
# pushes a gh-pages commit the way mkdocs gh-deploy does. Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/release.sh"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }
has()   { grep -qF -- "$2" <<< "$1" && ok "$3" || no "$3 — output lacked: $2"; }
lacks() { grep -qF -- "$2" <<< "$1" && no "$3 — output had: $2" || ok "$3"; }

tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"; ROOT="$(mktemp -d "${tmp:-/tmp}/harness-releasetest.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

export GIT_CONFIG_GLOBAL="$ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

BIN="$ROOT/bin"; LOG="$ROOT/calls.log"; STATE="$ROOT/gh-state"; mkdir -p "$BIN" "$STATE"
# gh: a release exists once created; `api .../releases/latest` reports the last one created --latest.
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$LOG"
case "\$1 \$2" in
  "release view")   [ -f "$STATE/\$3" ];;
  "release create") touch "$STATE/\$3"; [[ " \$* " == *" --latest "* ]] && echo "\$3" > "$STATE/latest"; true;;
  "api "*)          cat "$STATE/latest" 2>/dev/null;;
esac
EOF
# uvx: stands in for mkdocs gh-deploy, pushing an empty-tree commit with the -m message to gh-pages.
cat > "$BIN/uvx" <<EOF
#!/usr/bin/env bash
echo "uvx \$*" >> "$LOG"
while [ \$# -gt 0 ]; do [ "\$1" = -m ] && msg="\$2"; shift; done
msg="\${msg//\{sha\}/\$(git rev-parse --short HEAD)}"
git fetch -q origin gh-pages
c="\$(git commit-tree "\$(git hash-object -t tree /dev/null)" -p FETCH_HEAD -m "\$msg")"
git push -q origin "\$c:refs/heads/gh-pages"
EOF
chmod +x "$BIN/gh" "$BIN/uvx"
export PATH="$BIN:$PATH"

# repo <name> <version> <readme-ref> -> a checkout at $ROOT/<name> holding release.sh, with a bare origin
repo() {
  local d="$ROOT/$1"
  git init -q "$d"
  mkdir -p "$d/tools" "$d/.claude-plugin"
  cp "$SRC" "$d/tools/release.sh"
  printf '{"name":"harness","version":"%s"}\n' "$2" > "$d/.claude-plugin/plugin.json"
  printf '"harness": { "source": { "source": "github", "repo": "octanelabsdev/harness", "ref": "%s" } }\n' "$3" > "$d/README.md"
  : > "$d/requirements-docs.txt"
  git -C "$d" add -A && git -C "$d" commit -q -m "Bump harness"
  git clone -q --bare "$d" "$ROOT/$1.git"
  git -C "$d" remote add origin "$ROOT/$1.git"
  git -C "$d" fetch -q origin
  git -C "$d" push -q origin "$(git -C "$d" commit-tree "$(git -C "$d" hash-object -t tree /dev/null)" -m init):refs/heads/gh-pages"
}
release() { (cd "$ROOT/$1" && shift && CI_CMD="${CI:-true}" bash tools/release.sh "$@" 2>&1); }
remote_tag() { git -C "$ROOT/$1.git" rev-parse -q --verify "refs/tags/$2^{commit}"; }
reset_gh() { rm -f "$STATE"/*; : > "$LOG"; }

echo "── release from a merged bump ──"
repo good 1.2.3 v1.2.3
echo "Notes body" > "$ROOT/notes.md"
out="$(release good v1.2.3 "$ROOT/notes.md")"; rc=$?
[ "$rc" = 0 ] && ok "exits 0" || no "exited $rc: $out"
head="$(git -C "$ROOT/good" rev-parse HEAD)"
[ "$(remote_tag good v1.2.3)" = "$head" ] && ok "tag on origin points at HEAD" || no "tag on origin isn't HEAD"
[ "$(git -C "$ROOT/good.git" cat-file -t refs/tags/v1.2.3)" = tag ] && ok "tag is annotated" || no "tag isn't annotated"
has "$(cat "$LOG")" "gh release create v1.2.3 --verify-tag --latest --title v1.2.3 --notes-file $ROOT/notes.md" "release created Latest from the notes file"
has "$(git -C "$ROOT/good.git" log -1 --format=%s gh-pages)" "Deploy docs ${head:0:7} for v1.2.3" "docs deployed from HEAD"
has "$out" "latest release is v1.2.3" "confirms GitHub's latest"
[ -z "$(git -C "$ROOT/good" worktree list | sed 1d)" ] && ok "docs worktree removed" || no "docs worktree left behind"

echo "── re-run skips what's done ──"
: > "$LOG"
out="$(release good v1.2.3)"; rc=$?
[ "$rc" = 0 ] && ok "exits 0" || no "exited $rc: $out"
lacks "$(cat "$LOG")" "release create" "no second release"
lacks "$(cat "$LOG")" "uvx" "no second docs deploy"
has "$out" "already on origin" "reports the tag as done"

echo "── no notes file: GitHub generates them ──"
reset_gh
repo gen 2.0.0 v2.0.0
out="$(release gen v2.0.0)"; rc=$?
[ "$rc" = 0 ] && ok "exits 0" || no "exited $rc: $out"
has "$(cat "$LOG")" "--generate-notes" "uses --generate-notes"

echo "── version mismatch stops before publishing ──"
reset_gh
repo stale 1.0.0 v1.0.1
out="$(release stale v1.0.1)"; rc=$?
[ "$rc" = 1 ] && ok "exits 1" || no "exited $rc"
has "$out" "plugin.json says 1.0.0" "names the plugin.json version"
[ -z "$(remote_tag stale v1.0.1)" ] && ok "no tag pushed" || no "tag pushed anyway"
lacks "$(cat "$LOG")" "release create" "no release created"

echo "── README pin mismatch stops before publishing ──"
repo pin 1.0.1 v1.0.0
out="$(release pin v1.0.1)"; rc=$?
[ "$rc" = 1 ] && ok "exits 1" || no "exited $rc"
has "$out" "README pin isn't v1.0.1" "names the README pin"

echo "── red CI stops before publishing ──"
repo red 3.0.0 v3.0.0
out="$(CI=false release red v3.0.0)"; rc=$?
[ "$rc" = 1 ] && ok "exits 1" || no "exited $rc"
has "$out" "CI is red" "says CI is red"
[ -z "$(remote_tag red v3.0.0)" ] && ok "no tag pushed" || no "tag pushed anyway"

echo "── HEAD ahead of origin/main is refused ──"
repo ahead 4.0.0 v4.0.0
git -C "$ROOT/ahead" commit -q --allow-empty -m local
out="$(release ahead v4.0.0)"; rc=$?
[ "$rc" = 1 ] && ok "exits 1" || no "exited $rc"
has "$out" "HEAD isn't origin/main" "says HEAD isn't origin/main"

echo "── a tag already on another commit is never moved ──"
repo moved 5.0.0 v5.0.0
old="$(git -C "$ROOT/moved" rev-parse HEAD)"
git -C "$ROOT/moved" tag -a v5.0.0 -m v5.0.0 && git -C "$ROOT/moved" push -q origin v5.0.0
git -C "$ROOT/moved" commit -q --allow-empty -m later && git -C "$ROOT/moved" push -q origin HEAD:main
out="$(release moved v5.0.0)"; rc=$?
[ "$rc" = 1 ] && ok "exits 1" || no "exited $rc"
has "$out" "refusing to move a release tag" "refuses to move it"
[ "$(remote_tag moved v5.0.0)" = "$old" ] && ok "tag still on the old commit" || no "tag moved"

echo "── a latest release that isn't the tag fails the run ──"
reset_gh
repo notlatest 6.0.0 v6.0.0
touch "$STATE/v6.0.0"; echo v5.9.9 > "$STATE/latest"
out="$(release notlatest v6.0.0)"; rc=$?
[ "$rc" = 1 ] && ok "exits 1" || no "exited $rc"
has "$out" "latest release is 'v5.9.9', not v6.0.0" "names the stale latest"

echo "── bad arguments ──"
out="$(release good 1.2.3)"; rc=$?
[ "$rc" = 2 ] && ok "a tag without v exits 2" || no "exited $rc"

echo
echo "release: $pass passed, $fail failed"
[ "$fail" = 0 ]
