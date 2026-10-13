#!/usr/bin/env bash
# cycle.sh — the deterministic half of the cycle workflow (the cycle skill is the other half).
#
#   cycle.sh start <slug> [--tier summary-only|standard|client] [--from <file>]
#   cycle.sh phase <slug> [<cycle>]  start the next phase (refused until the previous one is approved)
#   cycle.sh active                print the active cycle's path (newest not closed)
#   cycle.sh status [<cycle>]      tier, status and each phase's state
#   cycle.sh close [<cycle>]       mark closed (every phase approved, unless summary-only) and sync
#   cycle.sh sync [<cycle>]        one-way mirror meta repo -> vault (cycles.mirror)
#   cycle.sh evidence [<cycle>]    check the current phase's evidence against its brief and the diff
#   cycle.sh evidence stamp [<cycle>]  record the current diff in the evidence manifest
#   cycle.sh report [<cycle>] [<phase>]  write the internal + client report for an approved phase
#   cycle.sh path [<cycle>]        print a cycle's folder (the open one by default)
#   cycle.sh base [<cycle>]        print the commit the current phase started from (its review's base)
#   cycle.sh evidence-items <cycle> <phase>  a phase's evidence statuses, without the diff check
#
# The human's decision on a phase is recorded by tools/cycle_approve.sh, never by this script.
#
# Cycles live in cycles.dir from .claude/harness.json — usually a sibling meta repo such as
# ../acme-meta/cycles — or .claude/cycles in the code repo. Run from inside the code repo. A cycle covers
# one code repo: the one it was started in (recorded in cycle.json).
# Exit: 0 ok · 1 refused (a rule says not yet) · 2 usage/setup error.
set -uo pipefail
unset CLAUDE_PROJECT_DIR   # the repo is the one this runs in, even when called from a hook's process
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../hooks/_harness_lib.sh"

die()    { echo "cycle: $*" >&2; exit 2; }
refuse() { echo "cycle: $*" >&2; exit 1; }

# shellcheck disable=SC2088  # the patterns match a literal "~" from the config
expand_home() { case "$1" in "~"|"~/"*) printf '%s' "$HOME${1#\~}" ;; *) printf '%s' "$1" ;; esac; }
repo="$(harness_repo)"
[ -n "$(harness_cfg)" ] || die "no .claude/harness.json in $repo — run this from the code repo"
resolve_dir() { # relative paths are relative to the code repo root, not the cwd
  local d; d="$(expand_home "$1")"
  case "$d" in /*) ;; *) d="$repo/$d" ;; esac
  # resolve the part that exists, so ../x/y compares correctly before it is created
  local rest=""
  while [ ! -d "$d" ]; do rest="/$(basename "$d")$rest"; d="$(dirname "$d")"; done
  printf '%s%s' "$(cd "$d" && pwd -P)" "$rest"
}
cycles_dir="$(resolve_dir "$(hcfg '.cycles.dir' '.claude/cycles')")"
# Inside the code repo, cycle files would count as code changes in every review and evidence hash.
case "$cycles_dir/" in
  "$repo/.claude/"*) ;;
  "$repo/"*) die "cycles.dir ($cycles_dir) is inside the code repo — use a sibling meta repo (e.g. ../acme-meta/cycles) or .claude/cycles" ;;
esac
mirror_cfg="$(hcfg '.cycles.mirror' '')"

# Front matter of summary.md is the cycle's only machine state: tier and status.
fm_get() {
  awk -v k="$2" '{sub(/\r$/, "")} NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit}
    f && index($0, k": ")==1 {v=substr($0, length(k)+3); sub(/[ \t]+$/, "", v); gsub(/^["\047]|["\047]$/, "", v); print v; exit}' "$1"
}
fm_set() {
  local tmp; tmp="$(mktemp "$1.XXXXXX")" || die "cannot write next to $1"
  if awk -v k="$2" -v v="$3" '{sub(/\r$/, "")} NR==1 && $0=="---" {f=1; print; next} f && $0=="---" {f=0} f && index($0, k": ")==1 {print k": "v; done=1; next} {print} END {exit !done}' "$1" > "$tmp"; then
    cat "$tmp" > "$1" || { rm -f "$tmp"; die "could not update $1"; }
    rm -f "$tmp"
  else
    rm -f "$tmp"; die "$1 has no '$2:' line in its front matter — restore it between the --- lines at the top"
  fi
}

# as_cycle <path>: its physical path, if it is a real cycle folder directly inside cycles.dir.
# Every command resolves cycles through this, so a symlinked folder can never stand in for a cycle.
as_cycle() {
  local p
  [ -d "$1" ] && [ ! -L "${1%/}" ] || return 1
  p="$(cd "$1" && pwd -P)" || return 1
  [ "$(dirname "$p")" = "$cycles_dir" ] && [ -f "$p/summary.md" ] && printf '%s' "$p"
}

cycle_path() { # cycle_path [<name-or-path>] — default: the one open cycle
  local c open="" n=0 found=""
  if [ -n "${1:-}" ]; then
    if [ -d "$1" ]; then c="$1"; else c="$cycles_dir/$1"; fi
    as_cycle "$c" || die "'$1' is not a cycle folder in $cycles_dir"
    return
  fi
  [ -d "$cycles_dir" ] || die "no cycles yet ($cycles_dir does not exist) — run: cycle.sh start <slug>"
  for c in "$cycles_dir"/*/; do
    c="$(as_cycle "$c")" || continue
    [ "$(fm_get "$c/summary.md" status)" = closed ] && continue
    n=$((n+1)); found="$c"; open="$open $(basename "$c")"
  done
  [ "$n" = 0 ] && die "no open cycle in $cycles_dir — run: cycle.sh start <slug>"
  [ "$n" = 1 ] || die "$n cycles are open:$open — name the one you mean"
  printf '%s' "$found"
}

phases_of() { # phase dirs in order (numeric prefix), one per line
  local p
  for p in "$1"/phases/[0-9]*-*/; do [ -d "$p" ] && basename "$p"; done | LC_ALL=C sort -t- -k1,1n
}
sha_file() { [ -f "$1" ] || return 0; { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1"; } | awk '{print $1}'; }

# decision_of <cycle> <phase>: approve | approve-unverified | revise | reject | (empty). An approval
# counts only if it matches what was approved: this cycle and phase, a named approver and time, a passing
# review, hashes equal to the phase's current brief, review.json and evidence manifest, and evidence files
# unchanged since they were stamped. A hand-written or copied approval.json doesn't; one forged with
# the right hashes would.
decision_of() {
  local f="$1/phases/$2/approval.json" d r e b
  [ -f "$f" ] || return 0
  d="$(jq -r '.decision // empty' "$f" 2>/dev/null)"
  if [ "$d" = approve ]; then
    r="$(sha_file "$1/phases/$2/review.json")"; e="$(sha_file "$1/phases/$2/evidence/manifest.json")"
    b="$(sha_file "$1/phases/$2/brief.md")"
    jq -e --arg c "$(basename "$1")" --arg p "$2" --arg r "$r" --arg e "$e" --arg b "$b" --arg base "$(phase_base "$1" "$2")" \
      '.cycle == $c and .phase == $p and (.approver // "") != "" and (.at // "") != "" and .review == "pass"
       and $r != "" and .review_sha256 == $r and $e != "" and .evidence_sha256 == $e
       and $b != "" and .brief_sha256 == $b and $base != "" and .base == $base' "$f" >/dev/null 2>&1 \
      && proofs_unchanged "$1/phases/$2" \
      || d=approve-unverified
  fi
  printf '%s' "$d"
}

current_phase() { phases_of "$1" | tail -1; }
phase_base() { [ -f "$1/phases/$2/phase.json" ] && jq -r '.base // empty' "$1/phases/$2/phase.json" 2>/dev/null; }
# A repo's identity is its root commit: the same on every clone, unlike its path.
repo_id() { git -C "$repo" rev-list --max-parents=0 HEAD 2>/dev/null | LC_ALL=C sort | head -1; }
# require_repo <cycle>: refuse to act on a cycle from a different code repo than the one it covers.
require_repo() {
  local want name
  want="$(jq -r '.repo_root // empty' "$1/cycle.json" 2>/dev/null)"
  [ -n "$want" ] || die "$(basename "$1") has no cycle.json — it wasn't started with cycle.sh start"
  name="$(jq -r '.repo_name // "?"' "$1/cycle.json")"
  [ "$(repo_id)" = "$want" ] || die "$(basename "$1") covers the code repo '$name', not this one — run cycle.sh from '$name' (a cycle covers one code repo)"
}
# reviewed_code_unchanged <cycle> <phase>: the code still matches what that phase's review covered.
reviewed_code_unchanged() { (cd "$repo" && bash "$HERE/review_verify.sh" "$1/phases/$2/review.json" >/dev/null 2>&1); }

# proofs_unchanged <phase-dir>: every evidence/ proof still has the hash recorded when it was stamped.
proofs_unchanged() {
  local m="$1/evidence/manifest.json" proof want
  [ -f "$m" ] || return 1
  while IFS=$'\t' read -r proof want; do
    [ -n "$proof" ] || continue
    [ -n "$want" ] && [ "$(sha_file "$1/$proof")" = "$want" ] || return 1
  done < <(jq -r '.items[]? | select((.proof // "") | startswith("evidence/")) | [.proof, (.proof_sha256 // "")] | @tsv' "$m" 2>/dev/null)
  return 0
}
section() { awk -v h="## $2" '{sub(/\r$/, "")} $0==h {f=1; next} /^## / {f=0} f' "$1"; }
done_when_items() { section "$1" "Done when" | sed -n 's/^- \{1,\}//p' | sed 's/[[:space:]]*$//' | grep -v '^$'; }

# fresh <diff_sha> <base>: does the code repo's diff still match? It hands review_verify a minimal
# artifact, so evidence and review agree on exactly what "the diff" is.
fresh() {
  local tmp rc
  [ -n "$1" ] || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/cycle-fresh.XXXXXX")" || return 1
  jq -n --arg s "$1" --arg b "$2" '{diff_sha:$s, base:$b, verdict:"pass", findings:[]}' > "$tmp"
  (cd "$repo" && bash "$HERE/review_verify.sh" "$tmp" >/dev/null 2>&1); rc=$?
  rm -f "$tmp"
  return "$rc"
}

# evidence_report <cycle> <phase> [items]: one line per done-when item; 0 only if complete, current, none
# failing. "items" checks statuses and files only, for an earlier phase whose diff is history.
evidence_report() {
  local c="$1" p="$2" only="${3:-}" m items item st proof want open rc=0
  m="$c/phases/$p/evidence/manifest.json"
  [ -f "$m" ] || { echo "no evidence yet (phases/$p/evidence/manifest.json)"; return 1; }
  jq -e '.items | type == "array"' "$m" >/dev/null 2>&1 || { echo "phases/$p/evidence/manifest.json is not valid (needs an items array)"; return 1; }
  if [ -n "$only" ]; then
    :
  elif fresh "$(jq -r '.diff_sha // empty' "$m")" "$(jq -r '.base // empty' "$m")"; then
    echo "matches the current diff"
  else
    echo "STALE: gathered for a different diff, or never stamped — re-check, then: cycle.sh evidence stamp"; rc=1
  fi
  items="$(done_when_items "$c/phases/$p/brief.md")"
  [ -n "$items" ] || { echo "the brief has no Done when items"; return 1; }
  while IFS= read -r item; do
    st="$(jq -r --arg d "$item" '[.items[] | select(.done_when == $d)][0].status // "missing"' "$m")"
    proof="$(jq -r --arg d "$item" '[.items[] | select(.done_when == $d)][0].proof // ""' "$m")"
    case "$st" in
      verified)         echo "  ✔ verified          $item${proof:+  — $proof}" ;;
      could-not-verify) echo "  ? could-not-verify  $item${proof:+  — $proof}" ;;
      failing)          echo "  ✘ failing           $item${proof:+  — $proof}"; rc=1 ;;
      missing)          echo "  — no evidence       $item"; rc=1 ;;
      *)                echo "  ✘ bad status '$st'  $item"; rc=1 ;;
    esac
    case "$proof" in evidence/*)
      want="$(jq -r --arg d "$item" '[.items[] | select(.done_when == $d)][0].proof_sha256 // ""' "$m")"
      if [ ! -f "$c/phases/$p/$proof" ]; then echo "    missing file: $proof"; rc=1
      elif [ -z "$only" ] && [ "$(sha_file "$c/phases/$p/$proof")" != "$want" ]; then echo "    changed since it was stamped: $proof"; rc=1
      fi ;;
    esac
  done <<< "$items"
  open="$(jq -r '.open_app // empty' "$m")"
  if [ -n "$open" ]; then echo "open the app: $open"; else echo "missing: open_app (how to run or open what was built)"; rc=1; fi
  return "$rc"
}

cmd_evidence() { # evidence [stamp] [<cycle>]
  local stamp="" c p m sha base tmp proof hashes
  [ "${1:-}" = stamp ] && { stamp=1; shift; }
  c="$(cycle_path "${1:-}")" || exit $?
  require_repo "$c"
  p="$(current_phase "$c")"; [ -n "$p" ] || refuse "$(basename "$c") has no phases"
  m="$c/phases/$p/evidence/manifest.json"
  if [ -z "$stamp" ]; then evidence_report "$c" "$p"; return; fi
  if [ "$(decision_of "$c" "$p")" = approve ]; then
    reviewed_code_unchanged "$c" "$p" \
      || refuse "phase $p is approved but its code has changed since — re-review it first (copy the new review into phases/$p/review.json), then stamp the evidence"
    refuse "phase $p is approved — its evidence is frozen; start the next phase with cycle.sh phase <slug>"
  fi
  [ -f "$m" ] || die "write $m first: {\"open_app\": \"...\", \"items\": [{\"done_when\": \"...\", \"status\": \"verified|could-not-verify|failing\", \"proof\": \"...\"}]}"
  jq -e '.items | type == "array"' "$m" >/dev/null 2>&1 || die "$m needs an items array"
  hashes='{}'
  while IFS= read -r proof; do
    case "$proof" in */../*|../*|*/..) die "proof '$proof' must stay inside the phase's evidence/ folder" ;; esac
    [ -f "$c/phases/$p/$proof" ] || die "proof file missing: phases/$p/$proof"
    hashes="$(jq -c --arg k "$proof" --arg v "$(sha_file "$c/phases/$p/$proof")" '. + {($k): $v}' <<< "$hashes")"
  done < <(jq -r '.items[]? | .proof // "" | select(startswith("evidence/"))' "$m")
  base="$(phase_base "$c" "$p")"; [ -n "$base" ] || die "phases/$p has no phase.json base — it wasn't started with cycle.sh phase"
  sha="$(cd "$repo" && bash "$HERE/review_verify.sh" --emit-sha "$base")" || die "cannot hash the code repo's diff since $base"
  tmp="$(mktemp "$m.XXXXXX")" || die "cannot write next to $m"
  if jq --arg s "$sha" --arg b "$base" --argjson h "$hashes" \
       '.diff_sha=$s | .base=$b | .items |= map(if (.proof // "") | startswith("evidence/") then .proof_sha256 = $h[.proof] else del(.proof_sha256) end)' \
       "$m" > "$tmp"; then
    cat "$tmp" > "$m" || { rm -f "$tmp"; die "could not stamp $m"; }
    rm -f "$tmp"
  else
    rm -f "$tmp"; die "could not stamp $m"
  fi
  echo "stamped phases/$p evidence against the current diff"
}

# report [<cycle>] [<phase>]: internal and client markdown for an approved phase. The client copy
# leaves out review findings, comments, the approver and evidence paths, redacts every cycles.deny
# string (case-insensitive), and is refused if any of them survive.
cmd_report() {
  local c p pd a title deny leaks d st item
  c="$(cycle_path "${1:-}")" || exit $?
  p="${2:-$(current_phase "$c")}"; pd="$c/phases/$p"
  [ -n "$p" ] && [ -d "$pd" ] || die "no phase '${p}' in $(basename "$c")"
  a="$pd/approval.json"
  [ "$(decision_of "$c" "$p")" = approve ] || refuse "phase $p isn't approved — reports are written after approval"
  title="$(sed -n '1s/^# //p' "$pd/brief.md")"; title="${title:-$p}"
  {
    echo "# $title — internal report"
    echo
    echo "Cycle \`$(basename "$c")\` · approved $(jq -r '.at // "?"' "$a") by $(jq -r '.approver // "?"' "$a") · used it: $(jq -r '.used_it // "?"' "$a")"
    echo
    echo "## What was built"; section "$pd/brief.md" Builds
    echo "## Evidence"; evidence_report "$c" "$p" || true
    echo
    echo "## Review"
    echo "Verdict at approval: $(jq -r '.review // "?"' "$a")."
    [ -f "$pd/review.json" ] && jq -r '.findings[]? | "- **\(.severity)** `\(.file):\(.line)` \(.summary)"' "$pd/review.json"
    echo
    echo "## Approver's comment"
    jq -r 'if (.comment // "") == "" then "(none)" else .comment end' "$a"
  } > "$pd/report-internal.md" || die "could not write the internal report"
  jq -e '(.cycles.deny // []) | type == "array" and all(.[]; type == "string")' "$(harness_cfg)" >/dev/null 2>&1 \
    || die "cycles.deny must be a list of strings, e.g. [\"AcmeCorp\"] — no client report written"
  deny="$(jq -c '[.cycles.deny[]? | select(length > 0)]' "$(harness_cfg)")"
  {
    echo "# $title"
    echo
    echo "Accepted $(jq -r '.at // empty | fromdateiso8601 | localtime | strftime("%Y-%m-%d")' "$a" 2>/dev/null || echo "on an unknown date")."
    echo
    echo "## What was delivered"; section "$pd/brief.md" Builds
    echo "## How it was checked"
    while IFS= read -r item; do
      st="$(jq -r --arg d "$item" '[.items[]? | select(.done_when == $d)][0].status // "not recorded"' "$pd/evidence/manifest.json" 2>/dev/null)"
      echo "- $item — ${st:-not recorded}"
    done < <(done_when_items "$pd/brief.md")
  } | jq -Rrs --argjson deny "$deny" '
        # The whole text at once, any whitespace between words: a name wrapped across lines still matches.
        def pat: [splits("[\\s_-]+")] | map(select(length > 0) | gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/])"; "\\\(.c)")) | join("[\\s_-]+");
        reduce $deny[] as $d (.; gsub(($d | pat); "▇▇▇"; "i"))' > "$pd/report-client.md" \
    || die "could not write the client report"
  # An independent check: whitespace-normalised, lower-cased text must contain no deny string.
  leaks="$(jq -Rrs --argjson deny "$deny" '
      def norm: gsub("[\\s_-]+"; " ") | ascii_downcase;
      (. | norm) as $text | [$deny[] | (norm | select(length > 0)) as $k | select($text | contains($k))] | join(", ")' \
      "$pd/report-client.md")" || leaks="(the leak check could not run)"
  if [ -n "$leaks" ]; then rm -f "$pd/report-client.md"; die "client report removed: it still contained $leaks"; fi
  jq -n --arg a "$(sha_file "$a")" --arg r "$(sha_file "$pd/report-client.md")" --arg i "$(sha_file "$pd/report-internal.md")" \
    '{approval_sha256:$a, client_sha256:$r, internal_sha256:$i}' > "$pd/report.json" || die "could not record the report"
  echo "wrote phases/$p/report-internal.md"
  echo "wrote phases/$p/report-client.md"
}

cmd_start() {
  local slug="" tier=standard from=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier) [ $# -ge 2 ] || die "--tier needs a value"; tier="$2"; shift 2 ;;
      --from) [ $# -ge 2 ] || die "--from needs a file"; from="$2"; shift 2 ;;
      -*) die "unknown option $1" ;;
      *) [ -z "$slug" ] || die "one slug only"; slug="$1"; shift ;;
    esac
  done
  case "$slug" in ''|*[!a-z0-9-]*|-*) die "slug must be lowercase letters, digits and dashes (got '$slug')" ;; esac
  case "$tier" in summary-only|standard|client) ;; *) die "tier must be summary-only, standard or client" ;; esac
  [ -z "$from" ] || [ -f "$from" ] || die "--from file not found: $from"
  local dir start_base rid; dir="$cycles_dir/$(date +%F)-$slug"
  start_base="$(git -C "$repo" rev-parse --verify HEAD 2>/dev/null)" || die "the code repo has no commits yet — commit once, then start the cycle"
  rid="$(repo_id)"
  [ -e "$dir" ] && refuse "$dir already exists"
  mkdir -p "$dir" || die "cannot create $dir"
  dir="$(cd "$dir" && pwd -P)" || die "cannot resolve $dir"
  cleanup="$dir"
  trap 'rm -rf "$cleanup"' EXIT
  cat > "$dir/summary.md" <<EOF || die "cannot write $dir/summary.md"
---
tier: $tier
status: shaping
---
# $slug

## Status
Shaping. Nothing decided yet.

## Next action
Shape the scope: run the cycle skill's \`shape\` interview.

## Learnings

## Gotchas

## Could not decide
EOF
  printf '# Decisions\n\nOne line per locked decision: date — decision. Why: reason. A later change supersedes, it never silently contradicts.\n\n' > "$dir/decisions.md" \
    || die "cannot write $dir/decisions.md"
  if [ -n "$from" ]; then cp "$from" "$dir/scope.md" || die "cannot copy $from into the cycle"; fi
  jq -n --arg r "$rid" --arg n "$(basename "$repo")" --arg b "$start_base" '{repo_root:$r, repo_name:$n, start_base:$b}' \
    > "$dir/cycle.json" || die "cannot write $dir/cycle.json"
  trap - EXIT
  echo "$dir"
}

cmd_phase() { # phase <slug> [<cycle>]
  local slug="${1:-}" c n last prev
  case "$slug" in ''|*[!a-z0-9-]*|-*) die "phase slug must be lowercase letters, digits and dashes" ;; esac
  c="$(cycle_path "${2:-}")" || exit $?
  require_repo "$c"
  [ "$(fm_get "$c/summary.md" status)" = closed ] && refuse "$(basename "$c") is closed — start a new cycle"
  [ "$(fm_get "$c/summary.md" tier)" = summary-only ] && refuse "a summary-only cycle has no phases — raise its tier in summary.md first"
  last="$(phases_of "$c" | tail -1)"
  if [ -n "$last" ]; then
    prev="$(decision_of "$c" "$last")"
    case "$prev" in
      approve) ;;
      approve-unverified) refuse "phase $last's approval.json doesn't match the review and evidence it approved — the human re-runs cycle_approve.sh" ;;
      *) refuse "phase $last isn't approved yet (${prev:-no decision}) — only the human can approve it" ;;
    esac
    case "${last%%-*}" in *[!0-9]*) die "phases/$last: a phase folder must start with a number and a dash (1-slug)" ;; esac
    reviewed_code_unchanged "$c" "$last" \
      || refuse "the code changed after phase $last was approved — those changes aren't reviewed; revert them, or re-review phase $last and have the human approve it again"
    n=$(( 10#${last%%-*} + 1 ))
  else
    n=1
  fi
  [ -e "$c/phases/$n-$slug" ] && die "phases/$n-$slug already exists"
  if [ "$n" != 1 ] && [ -n "$(git -C "$repo" status --porcelain -- . ':(exclude).claude' 2>/dev/null)" ]; then
    refuse "commit phase $last's reviewed work first — the next phase starts from the latest commit, so anything uncommitted (or untracked) would fall outside every review"
  fi
  local base
  if [ "$n" = 1 ]; then
    base="$(jq -r '.start_base // empty' "$c/cycle.json")"   # work since the cycle started, shaping included
  else
    base="$(git -C "$repo" rev-parse --verify HEAD 2>/dev/null)"
  fi
  [ -n "$base" ] || die "cannot tell which commit this phase starts from"
  mkdir -p "$c/phases/$n-$slug/evidence" || die "cannot create phase dir"
  cleanup="$c/phases/$n-$slug"
  trap 'rm -rf "$cleanup"' EXIT
  cat > "$c/phases/$n-$slug/brief.md" <<EOF || die "cannot write the brief"
# Phase $n: $slug

## Builds

## Done when
-

## Evidence required

## Not in this phase
EOF
  jq -n --arg b "$base" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{base:$b, started_at:$t}' > "$c/phases/$n-$slug/phase.json" \
    || die "cannot record the phase's base"
  fm_set "$c/summary.md" status building
  trap - EXIT
  echo "$c/phases/$n-$slug"
}

cmd_status() {
  local c p d tier
  c="$(cycle_path "${1:-}")" || exit $?
  tier="$(fm_get "$c/summary.md" tier)"
  echo "cycle:  $(basename "$c")  ($c)"
  echo "tier:   ${tier:-?}    status: $(fm_get "$c/summary.md" status)"
  [ -n "$(phases_of "$c")" ] || { echo "phases: none"; return 0; }
  echo "phases:"
  while IFS= read -r p; do
    d="$(decision_of "$c" "$p")"
    printf '  %-28s %s\n' "$p" "${d:-open}"
    case "$d" in revise|reject)
      jq -r '"    comment: " + (.comment // "")' "$c/phases/$p/approval.json" 2>/dev/null ;;
    esac
  done < <(phases_of "$c")
}

cmd_sync() {
  local c dest mroot name sha rel stage
  [ -n "$mirror_cfg" ] || { echo "cycle: no cycles.mirror configured — nothing to sync"; return 0; }
  c="$(cycle_path "${1:-}")" || exit $?
  name="$(basename "$c")"
  mroot="$(resolve_dir "$mirror_cfg")"
  case "$mroot/" in "$repo/"*) die "refusing to sync: the mirror ($mroot) is inside the code repo — point cycles.mirror at your vault" ;; esac
  mkdir -p "$mroot" || die "cannot create mirror root $mroot"
  mroot="$(cd "$mroot" && pwd -P)" || die "cannot resolve mirror root"
  dest="$mroot/$name"
  [ -L "$dest" ] && die "refusing to sync: $dest is a symlink — the mirror must be a real copy"
  [ -e "$dest" ] && [ ! -d "$dest" ] && die "refusing to sync: $dest exists and is not a folder"
  case "$mroot/" in "$c/"*) die "refusing to sync: the mirror ($mroot) is inside the cycle — cycles.mirror must differ from cycles.dir" ;; esac
  case "$c/" in "$mroot/"*) die "refusing to sync: the cycle is inside the mirror ($mroot) — cycles.mirror must differ from cycles.dir" ;; esac
  sha="$(git -C "$c" rev-parse --short HEAD 2>/dev/null || echo uncommitted)"
  [ -z "$(git -C "$c" status --porcelain -- . 2>/dev/null)" ] || sha="$sha+uncommitted"
  stage="$(mktemp -d "$mroot/.sync-$name.XXXXXX")" || die "cannot stage in $mroot"
  while IFS= read -r rel; do
    rel="${rel#./}"
    mkdir -p "$stage/$(dirname "$rel")" || { rm -rf "$stage"; die "sync failed creating $(dirname "$rel")"; }
    case "$rel" in
      *.md) { printf '> Mirrored from `%s` @ %s. Edit it there; this copy is overwritten on every sync.\n\n' "$c" "$sha"; cat "$c/$rel"; } > "$stage/$rel" ;;
      *)    cp "$c/$rel" "$stage/$rel" ;;
    esac || { rm -rf "$stage"; die "sync failed copying $rel"; }
  done < <(cd "$c" && find . -type f)
  # One-way: the previous copy is replaced whole, so an edit made in the vault does not survive.
  if [ -d "$dest" ]; then rm -rf "$dest" || { rm -rf "$stage"; die "cannot replace $dest"; }; fi
  mv "$stage" "$dest" || die "cannot move the new copy into $dest (staged at $stage)"
  echo "synced $name -> $dest"
}

cmd_close() {
  local c p d open=""
  c="$(cycle_path "${1:-}")" || exit $?
  local was
  if [ "$(fm_get "$c/summary.md" tier)" = summary-only ] && [ -n "$(phases_of "$c")" ]; then
    refuse "$(basename "$c") has phases, so it can't close as summary-only — restore its tier and approve the phases"
  fi
  if [ "$(fm_get "$c/summary.md" tier)" != summary-only ]; then
    [ -n "$(phases_of "$c")" ] || refuse "no phases yet — a $(fm_get "$c/summary.md" tier) cycle closes after its phases are approved (changing the tier is the human's call)"
    require_repo "$c"
    while IFS= read -r p; do
      d="$(decision_of "$c" "$p")"; [ "$d" = approve ] || open="$open $p(${d:-open})"
    done < <(phases_of "$c")
    [ -z "$open" ] || refuse "not every phase is approved:$open"
    p="$(phases_of "$c" | tail -1)"
    reviewed_code_unchanged "$c" "$p" \
      || refuse "the code changed after phase $p was approved — those changes aren't reviewed; revert them, or re-review phase $p and have the human approve it again"
  fi
  if [ "$(fm_get "$c/summary.md" tier)" = client ] \
     || grep -q '"client"' <<< "$(for p in $(phases_of "$c"); do jq -c '.tier // empty' "$c/phases/$p/approval.json" 2>/dev/null; done)"; then
    open=""
    while IFS= read -r p; do
      jq -e --arg a "$(sha_file "$c/phases/$p/approval.json")" --arg r "$(sha_file "$c/phases/$p/report-client.md")" \
        --arg i "$(sha_file "$c/phases/$p/report-internal.md")" \
        '$r != "" and $i != "" and .approval_sha256 == $a and .client_sha256 == $r and .internal_sha256 == $i' \
        "$c/phases/$p/report.json" >/dev/null 2>&1 \
        || open="$open $p"
    done < <(phases_of "$c")
    [ -z "$open" ] || refuse "a client cycle closes with current internal and client reports for every phase (written by cycle.sh report for its approval); missing or out of date:$open — run: cycle.sh report <cycle> <phase>"
  fi
  was="$(fm_get "$c/summary.md" status)"
  fm_set "$c/summary.md" status closed
  if ! (cmd_sync "$c"); then
    fm_set "$c/summary.md" status "${was:-building}"
    die "the vault sync failed, so the cycle was left open — fix the error above and close again"
  fi
  echo "closed $(basename "$c")"
}

sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  start)  cmd_start "$@" ;;
  phase)  cmd_phase "$@" ;;
  active) cycle_path; echo ;;
  path)   cycle_path "${1:-}"; echo ;;
  base)
    bc="$(cycle_path "${1:-}")" || exit $?
    require_repo "$bc"
    bp="$(current_phase "$bc")"; [ -n "$bp" ] || refuse "$(basename "$bc") has no phases"
    bb="$(phase_base "$bc" "$bp")"; [ -n "$bb" ] || die "phases/$bp has no recorded base"
    echo "$bb" ;;
  evidence-items)
    [ $# -eq 2 ] || die "usage: evidence-items <cycle> <phase>"
    ec="$(cycle_path "$1")" || exit $?
    [ -d "$ec/phases/$2" ] || die "no phase '$2'"
    evidence_report "$ec" "$2" items ;;
  evidence) cmd_evidence "$@" ;;
  report) cmd_report "$@" ;;
  status) cmd_status "$@" ;;
  sync)   cmd_sync "$@" ;;
  close)  cmd_close "$@" ;;
  *) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2 ;;
esac
