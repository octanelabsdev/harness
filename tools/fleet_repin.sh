#!/usr/bin/env bash
# fleet_repin.sh — move every repo in a fleet list to a harness release tag, one PR per repo.
#
#   tools/fleet_repin.sh <tag> <fleet-file>
#
# The fleet file lists one repo per line: `<checkout path> <base branch>` (# comments, ~ allowed).
# The base branch is explicit on purpose; guessing it once sent a PR to the wrong branch.
#
# Per repo, in a detached temp worktree off origin/<base> (the checkout's files, branches and current
# branch are left alone):
#   1. pin .claude/settings.json to <tag> plus the tag's commit sha, resolved with ls-remote
#   2. commit and push under the repo's Ruby (.ruby-version or .tool-versions, via mise), so Ruby
#      git hooks run against the right gems
#   3. open the PR only after ls-remote shows the pushed sha on origin
#   4. read the pin back from the PR head on GitHub
# A repo that fails is reported and skipped; the rest still run. Exit 1 if any repo failed.
# CI and merging are separate steps.
set -uo pipefail

HARNESS_REPO_URL="${HARNESS_REPO_URL:-https://github.com/octanelabsdev/harness}"
MKT_NAME="harness"

[ $# -eq 2 ] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
TAG="$1"; FLEET="$2"
[ -f "$FLEET" ] || { echo "fleet_repin: no fleet file at $FLEET" >&2; exit 2; }

SHA="$(git ls-remote "$HARNESS_REPO_URL" "$TAG" "$TAG^{}" 2>/dev/null \
  | awk '$2 ~ /\^\{\}$/ {peeled=$1} $2 !~ /\^\{\}$/ {plain=$1} END {print (peeled != "" ? peeled : plain)}')"
[ -n "$SHA" ] || { echo "fleet_repin: $TAG not found on $HARNESS_REPO_URL (pushed yet? offline?)" >&2; exit 2; }
BRANCH="chore/harness-$TAG-${SHA:0:7}"
echo "Pinning to $TAG @ $SHA (branch $BRANCH)"

tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"
WORK="$(mktemp -d "${tmp:-/tmp}/fleet-repin.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failed=0
fail() { echo "  ✘ $name: $*"; failed=1; }

repo_ruby() { # repo_ruby <dir> -> the Ruby version the repo pins, or nothing
  if [ -f "$1/.ruby-version" ]; then sed 's/^ruby-//' "$1/.ruby-version" | tr -d '[:space:]'
  elif [ -f "$1/.tool-versions" ]; then awk '$1 == "ruby" {print $2; exit}' "$1/.tool-versions"
  fi
}

pin_of() { jq -r --arg m "$MKT_NAME" '.extraKnownMarketplaces[$m].source | "\(.ref) \(.sha)"' "$@"; }

drop() { git -C "$1" worktree remove --force "$2" 2>/dev/null; } # drop <checkout> <worktree>

repin() { # repin <checkout> <base>
  local repo="$1" base="$2" wt="$WORK/$name" settings ruby head pr oid pinned
  local run=(env) # never empty: bash 3.2 treats "${run[@]}" of an empty array as unbound under set -u

  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { fail "not a git checkout: $repo"; return; }
  git -C "$repo" fetch -q origin "$base" || { fail "could not fetch origin/$base"; return; }
  if [ -n "$(git -C "$repo" ls-remote --heads origin "$BRANCH")" ]; then
    fail "$BRANCH already exists on origin"; return
  fi
  # detached, so the checkout never gains a local branch; the push names the remote branch
  git -C "$repo" worktree add -q --detach "$wt" "origin/$base" || { fail "could not create a worktree"; return; }

  settings="$wt/.claude/settings.json"
  if ! jq -e --arg m "$MKT_NAME" '.extraKnownMarketplaces[$m].source' "$settings" >/dev/null 2>&1; then
    fail "origin/$base has no $MKT_NAME marketplace in .claude/settings.json"; drop "$repo" "$wt"; return
  fi
  if [ "$(pin_of "$settings")" = "$TAG $SHA" ]; then
    echo "  – $name: origin/$base already pins $TAG @ ${SHA:0:7}"; drop "$repo" "$wt"; return
  fi

  ruby="$(repo_ruby "$wt")"
  if [ -n "$ruby" ]; then
    mise where "ruby@$ruby" >/dev/null 2>&1 || { fail "Ruby $ruby isn't installed (mise install ruby@$ruby)"; drop "$repo" "$wt"; return; }
    run=(mise exec "ruby@$ruby" --)
  fi

  jq --arg m "$MKT_NAME" --arg ref "$TAG" --arg sha "$SHA" \
    '.extraKnownMarketplaces[$m].source.ref = $ref | .extraKnownMarketplaces[$m].source.sha = $sha' \
    "$settings" > "$settings.new" && mv "$settings.new" "$settings"

  (cd "$wt" && "${run[@]}" git commit -q -m "Re-pin harness plugin to $TAG" -- .claude/settings.json) \
    || { fail "commit failed (hook output above)"; drop "$repo" "$wt"; return; }
  (cd "$wt" && "${run[@]}" git push -q origin "HEAD:refs/heads/$BRANCH") \
    || { fail "push failed (hook output above); no PR opened"; drop "$repo" "$wt"; return; }

  head="$(git -C "$wt" rev-parse HEAD)"
  if [ "$(git -C "$wt" ls-remote origin "refs/heads/$BRANCH" | cut -f1)" != "$head" ]; then
    fail "origin/$BRANCH doesn't show ${head:0:7} after the push; no PR opened"; drop "$repo" "$wt"; return
  fi

  pr="$(cd "$wt" && gh pr create --base "$base" --head "$BRANCH" --title "Re-pin harness plugin to $TAG" \
    --body "Pins the harness marketplace to \`$TAG\` (\`$SHA\`).")" \
    || { fail "pushed $BRANCH but gh pr create failed"; drop "$repo" "$wt"; return; }

  oid="$(cd "$wt" && gh pr view "$pr" --json headRefOid -q .headRefOid)"
  pinned="$(cd "$wt" && gh api "repos/{owner}/{repo}/contents/.claude/settings.json?ref=$oid" \
    -H 'Accept: application/vnd.github.raw' | pin_of)"
  if [ "$oid" != "$head" ] || [ "$pinned" != "$TAG $SHA" ]; then
    fail "$pr head ${oid:0:7} pins '$pinned', expected ${head:0:7} pinning '$TAG $SHA'"; drop "$repo" "$wt"; return
  fi

  echo "  ✔ $name: $pr"
  drop "$repo" "$wt"
}

# fd 3, so git/gh/hooks reading stdin can't swallow the rest of the list
while read -r -u 3 path base _; do
  case "$path" in ''|'#'*) continue;; esac
  path="${path/#\~/$HOME}"
  name="$(basename "$path")"
  if [ -z "$base" ]; then fail "no base branch in $FLEET"; continue; fi
  repin "$path" "$base"
done 3< "$FLEET"

exit "$failed"
