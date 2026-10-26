#!/usr/bin/env bash
# fleet_ci.sh — run bin/ci on one branch across a fleet list, one suite at a time on this machine.
#
#   tools/fleet_ci.sh <branch> <fleet-file>
#
# Fleet file lines: `<checkout path> <base branch> [setup command...]` (the same file fleet_repin.sh
# reads; it ignores the setup part). Repos without <branch> on origin are skipped.
#
# Per repo:
#   1. wait until no other test suite (bin/ci, rspec, rails test) is running anywhere on the machine;
#      parallel suites fail each other through shared test DBs and browsers
#   2. check out <branch> tracking origin in a temp worktree (gh signoff needs a tracked branch)
#   3. run the setup command there, if any, with $CHECKOUT set to the real checkout, e.g.
#        ln -s "$CHECKOUT/config/master.key" config/ && bundle install --quiet
#   4. run bin/ci under the repo's Ruby through run_tests.sh (which also takes the repo's test lock)
#   5. report green/red and the PR's signoff status; full logs are kept and their path printed
# Merging is left to you. Exit 1 if any repo failed.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUSY_PATTERN="(bin/ci|bin/rspec|/rspec|rails test|rake test)([: ]|$)"   # rails test:system too
BUSY_WAIT="${FLEET_CI_BUSY_WAIT:-1800}"   # seconds to wait for another machine-wide suite
CI_TIMEOUT="${FLEET_CI_TIMEOUT:-3600}"

[ $# -eq 2 ] || { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
BRANCH="$1"; FLEET="$2"
[ -f "$FLEET" ] || { echo "fleet_ci: no fleet file at $FLEET" >&2; exit 2; }

tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"
WORK="$(mktemp -d "${tmp:-/tmp}/fleet-ci.XXXXXX")"
LOGS="$WORK/logs"; mkdir -p "$LOGS"
echo "Running bin/ci on $BRANCH (logs: $LOGS)"

failed=0
fail() { echo "  ✘ $name: $*"; failed=1; }

repo_ruby() { # repo_ruby <dir> -> the Ruby version the repo pins, or nothing
  if [ -f "$1/.ruby-version" ]; then sed 's/^ruby-//' "$1/.ruby-version" | tr -d '[:space:]'
  elif [ -f "$1/.tool-versions" ]; then awk '$1 == "ruby" {print $2; exit}' "$1/.tool-versions"
  fi
}

wait_for_quiet() { # 0 once no other suite runs; 1 if one outlasts BUSY_WAIT; 2 if processes can't be listed
  local waited=0 others rc
  while :; do
    others="$(pgrep -fl -- "$BUSY_PATTERN" 2>&1)"; rc=$?
    [ "$rc" = 1 ] && return 0
    [ "$rc" = 0 ] || { echo "      pgrep: $others"; return 2; }   # fail closed: unknown is not quiet
    [ "$waited" -ge "$BUSY_WAIT" ] && { echo "$others" | head -3 | sed 's/^/      /'; return 1; }
    [ "$waited" = 0 ] && echo "  … $name: another test suite is running; waiting (up to ${BUSY_WAIT}s)"
    sleep 15; waited=$((waited + 15))
  done
}

CUR_REPO=""; CUR_WT=""
drop() { # drop <checkout> <worktree>: the worktree and the local branch made for it
  git -C "$1" worktree remove --force "$2" 2>/dev/null
  git -C "$1" branch -q -D "$BRANCH" 2>/dev/null
  CUR_REPO=""; CUR_WT=""
}
# Ctrl-C mid-suite must not leave a worktree holding the branch in the real checkout
trap '[ -n "$CUR_WT" ] && drop "$CUR_REPO" "$CUR_WT"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP

ci() { # ci <checkout> <setup>
  local repo="$1" setup="$2" wt="$WORK/$name" ruby rc signoff heads
  local run=(env) # never empty: bash 3.2 treats "${run[@]}" of an empty array as unbound under set -u

  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { fail "not a git checkout: $repo"; return; }
  # ask origin, not refs/remotes: a merged-and-deleted branch survives there until a prune.
  # Only an answer from origin can skip a repo; an unreachable origin is a failure.
  heads="$(git -C "$repo" ls-remote --heads origin "refs/heads/$BRANCH")" \
    || { fail "could not reach origin"; return; }
  [ -n "$heads" ] || { echo "  – $name: no $BRANCH on origin"; return; }
  git -C "$repo" fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" \
    || { fail "could not fetch $BRANCH"; return; }
  if git -C "$repo" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then
    fail "a local $BRANCH already exists in $repo; delete it or run from elsewhere"; return
  fi

  wait_for_quiet
  case $? in
    1) fail "another test suite kept running for ${BUSY_WAIT}s; not run"; return;;
    2) fail "couldn't list processes to check for other suites; not run"; return;;
  esac

  git -C "$repo" worktree add -q --track -b "$BRANCH" "$wt" "origin/$BRANCH" \
    || { fail "could not create a worktree"; return; }
  CUR_REPO="$repo"; CUR_WT="$wt"

  ruby="$(repo_ruby "$wt")"
  if [ -n "$ruby" ]; then
    mise where "ruby@$ruby" >/dev/null 2>&1 || { fail "Ruby $ruby isn't installed (mise install ruby@$ruby)"; drop "$repo" "$wt"; return; }
    run=(mise exec "ruby@$ruby" --)
  fi

  if [ -n "$setup" ]; then
    (cd "$wt" && CHECKOUT="$repo" "${run[@]}" bash -c "$setup") > "$LOGS/$name.setup.log" 2>&1 < /dev/null \
      || { fail "setup failed — see $LOGS/$name.setup.log"; tail -5 "$LOGS/$name.setup.log" | sed 's/^/      /'; drop "$repo" "$wt"; return; }
  fi

  # stdin from /dev/null: run_tests then logs to a file and copies it, instead of streaming to a terminal
  (cd "$wt" && "${run[@]}" "$HERE/run_tests.sh" --timeout "$CI_TIMEOUT" --wait 600 \
    --log-copy "$LOGS/$name.log" -- bin/ci) > "$LOGS/$name.tail" 2>&1 < /dev/null
  rc=$?

  signoff="$(cd "$wt" && gh pr view "$BRANCH" --json statusCheckRollup \
    -q '[.statusCheckRollup[] | select((.context // .name) == "signoff") | (.state // .conclusion)] | first // "none"' 2>/dev/null)"
  # run_tests.sh exits 0 green, 1 red, 2 setup error, 3 lock busy, 4 timeout; it copies the full log
  # only when the suite finishes, so a timeout leaves just the tail (its last 200 lines)
  case "$rc" in
    0) echo "  ✔ $name: bin/ci green, signoff=${signoff:-unknown}";;
    1) fail "bin/ci red, signoff=${signoff:-unknown} — see $LOGS/$name.log"; tail -5 "$LOGS/$name.tail" | sed 's/^/      /';;
    3) fail "the repo's test lock stayed busy; not run";;
    4) fail "bin/ci timed out after ${CI_TIMEOUT}s — last 200 lines in $LOGS/$name.tail"; tail -5 "$LOGS/$name.tail" | sed 's/^/      /';;
    *) fail "run_tests.sh couldn't start bin/ci (exit $rc); not run"; tail -5 "$LOGS/$name.tail" | sed 's/^/      /';;
  esac
  drop "$repo" "$wt"
}

# fd 3, so suites and tools reading stdin can't swallow the rest of the list
while read -r -u 3 path _base setup; do
  case "$path" in ''|'#'*) continue;; esac
  path="${path/#\~/$HOME}"
  name="$(basename "$path")"
  ci "$path" "$setup"
done 3< "$FLEET"

exit "$failed"
