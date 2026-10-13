#!/usr/bin/env bash
# cycle_approve.sh — the human's decision on a cycle phase. Run it yourself, in your own terminal, from
# the code repo:
#
#   bash <harness>/tools/cycle_approve.sh [<cycle>]
#
# It acts on the earliest phase that isn't approved. For the newest phase it shows the brief, the
# blind-review verdict and the evidence, asks whether you used the result, and records approve /
# revise / reject in the phase's approval.json. Approve needs a passing review of the current diff and
# complete, current evidence with nothing failing.
#
# An earlier phase only comes back here if its approval stopped matching its files (its brief, review,
# evidence manifest or an evidence file changed after you approved). Its code is history, so it can't be re-reviewed against today's
# diff; you are shown what changed and can re-confirm the approval as the files now stand.
#
# It refuses to run from Claude's tools (no terminal there, and CLAUDE_CODE_CHILD_SESSION is set), and
# the cycle_guard hook denies agent commands that invoke it or write approval.json. That stops an agent
# approving its own work by shortcut; it is not a defense against an agent deliberately evading it.
set -uo pipefail
unset CLAUDE_PROJECT_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "approve: $*" >&2; exit 2; }
[ "${CLAUDE_CODE_CHILD_SESSION:-}" = 1 ] && die "this is the human's decision — run it in your own terminal, not through Claude"
{ exec 3<>/dev/tty; } 2>/dev/null || die "needs a terminal — run it in your own terminal, not through Claude"
say() { printf '%s\n' "$*" >&3; }
# ask runs inside $(...), so a closed terminal is reported by its status; callers die on it.
ask() { local a; printf '%s' "$1" >&3; IFS= read -r a <&3 || return 1; printf '%s' "$a"; }
closed() { die "the terminal closed — nothing recorded"; }
sha_file() { [ -f "$1" ] || return 0; { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1"; } | awk '{print $1}'; }

c="$(bash "$HERE/cycle.sh" path ${1:+"$1"})" || exit 2
status_out="$(bash "$HERE/cycle.sh" status "$c")" || exit 2
newest="$(awk '$1 ~ /^[0-9]+-/ {p = $1} END {print p}' <<< "$status_out")"
[ -n "$newest" ] || die "$(basename "$c") has no phases yet"
phase="$(awk '$1 ~ /^[0-9]+-/ && $2 != "approve" {print $1; exit}' <<< "$status_out")"
if [ -z "$phase" ]; then
  # Every phase is approved — unless the code moved after the newest one was, which needs a fresh decision.
  if (cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && bash "$HERE/review_verify.sh" "$c/phases/$newest/review.json" >/dev/null 2>&1); then
    die "every phase is approved — the next phase starts with: cycle.sh phase <slug>"
  fi
  die "$newest is approved, but the code has changed since — have it re-reviewed (and the evidence re-stamped), then run this again"
fi
prior="$(awk -v p="$phase" '$1 == p {print $2}' <<< "$status_out")"
pd="$c/phases/$phase"
tier="$(sed -n 's/^tier: *\([^ ]*\).*/\1/p' <<< "$status_out")"
phase_base="$(jq -r '.base // empty' "$pd/phase.json" 2>/dev/null)"
[ -n "$phase_base" ] || die "$phase has no phase.json base — it wasn't started with cycle.sh phase"
bash "$HERE/cycle.sh" base "$c" >/dev/null || exit 2   # refuses unless run from the cycle's code repo
approver="$(git config user.name 2>/dev/null || echo "${USER:-unknown}")"
at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# write_approval <jq-filter> [jq args...]: replace approval.json, keeping earlier decisions as history.
write_approval() {
  local filter="$1" history='[]' tmp; shift
  [ -f "$pd/approval.json" ] && history="$(jq -c '[.history[]?] + [del(.history)]' "$pd/approval.json" 2>/dev/null || echo '[]')"
  tmp="$(mktemp "$pd/.approval.XXXXXX")" || die "cannot write in $pd"
  if jq -n --argjson history "$history" --arg cycle "$(basename "$c")" --arg phase "$phase" --arg approver "$approver" --arg at "$at" \
        --arg review_sha "${shown_review:-$(sha_file "$pd/review.json")}" \
        --arg evidence_sha "${shown_evidence:-$(sha_file "$pd/evidence/manifest.json")}" \
        --arg brief_sha "${shown_brief:-$(sha_file "$pd/brief.md")}" \
        --arg tier "$tier" \
        "$@" "({cycle:\$cycle, tier:\$tier, brief_sha256:\$brief_sha} + ($filter))
              | if .decision == \"approve\" then . else
                  {cycle, tier, phase, decision, comment, used_it, approver, at, history,
                   seen: del(.cycle, .tier, .phase, .decision, .comment, .used_it, .approver, .at, .history)} end" > "$tmp"; then
    mv "$tmp" "$pd/approval.json" || { rm -f "$tmp"; die "could not write approval.json"; }
  else
    rm -f "$tmp"; die "could not build approval.json"
  fi
  chmod 644 "$pd/approval.json" 2>/dev/null
}

if [ "$phase" != "$newest" ]; then
  # Re-confirming an earlier phase is an approval, so it meets every condition approve does except one:
  # its review can't match today's diff, because later phases have changed the code since.
  a="$pd/approval.json"; m="$pd/evidence/manifest.json"
  restore="restore it from the meta repo's git history (or copy it back from the vault mirror)"
  [ -f "$a" ] || die "$phase has no approval.json but later phases exist — if you approved it, $restore; if you didn't, the later phase folders were created out of order and should be removed"
  [ "$(jq -r '.decision // ""' "$a" 2>/dev/null)" = approve ] \
    || die "$phase was never approved (its decision is '$(jq -r '.decision // "none"' "$a" 2>/dev/null)') but later phases exist — they were created out of order and should be removed"
  for f in brief.md review.json evidence/manifest.json; do [ -f "$pd/$f" ] || die "$phase's $f is missing — $restore"; done
  [ "$(jq -r '.verdict // ""' "$pd/review.json" 2>/dev/null)" = pass ] \
    || die "$phase's review.json no longer says pass — it was replaced after you approved; $restore"
  jq -e --slurpfile r "$pd/review.json" '(.diff_sha // "") != "" and .diff_sha == $r[0].diff_sha and .base == $r[0].base' "$a" >/dev/null 2>&1 \
    || die "$phase's review.json isn't the review you approved (it covers different code) — $restore"
  shown_brief="$(sha_file "$pd/brief.md")"; shown_review="$(sha_file "$pd/review.json")"; shown_manifest="$(sha_file "$m")"
  shown_proofs="$(jq -r '.items[]? | .proof // "" | select(startswith("evidence/"))' "$m" | while IFS= read -r x; do printf '%s %s\n' "$x" "$(sha_file "$pd/$x")"; done)"
  items_out="$(bash "$HERE/cycle.sh" evidence-items "$c" "$phase" 2>&1)" \
    || die "$phase's evidence is incomplete or failing — $restore:
$items_out"

  say ""
  say "━━ $(basename "$c") · $phase (approved $(jq -r '.at // "?"' "$a") by $(jq -r '.approver // "?"' "$a"))"
  say ""
  say "Its approval no longer matches its files:"
  [ "$(jq -r '.brief_sha256 // ""' "$a")" = "$shown_brief" ] || say "  - brief.md changed"
  [ "$(jq -r '.review_sha256 // ""' "$a")" = "$shown_review" ] || say "  - review.json changed"
  [ "$(jq -r '.evidence_sha256 // ""' "$a")" = "$shown_manifest" ] || say "  - evidence/manifest.json changed"
  while IFS=$'\t' read -r proof want; do
    [ -n "$proof" ] && [ "$(sha_file "$pd/$proof")" != "$want" ] && say "  - $proof changed"
  done < <(jq -r '.items[]? | select((.proof // "") | startswith("evidence/")) | [.proof, (.proof_sha256 // "")] | @tsv' "$m" 2>/dev/null)
  [ "$(jq -r '.phase // ""' "$a")" = "$phase" ] || say "  - approval.json names a different phase"
  [ "$(jq -r '.cycle // ""' "$a")" = "$(basename "$c")" ] || say "  - approval.json names a different cycle (copied from another cycle?)"
  say ""
  say "As it stands now:"
  say "Builds:"; awk '$0=="## Builds" {f=1; next} /^## / {f=0} f && NF' "$pd/brief.md" | sed 's/^/  /' >&3
  say "Done when:"; awk '$0=="## Done when" {f=1; next} /^## / {f=0} f && NF' "$pd/brief.md" | sed 's/^/  /' >&3
  say "Review: pass — the same review you approved, of the code as it was then"
  say "Evidence:"; printf '%s\n' "$items_out" | sed 's/^/  /' >&3
  say ""
  say "If any of this is wrong, don't re-confirm: $restore."
  used="$(ask 'Did you check it yourself (open the files / the app)? [y/N] ')" || closed
  case "$used" in y|Y|yes|YES) used=true ;; *) used=false ;; esac
  answer="$(ask "Re-confirm the approval of $phase as shown above? Type yes: ")" || closed
  [ "$answer" = yes ] || die "not re-confirmed — nothing recorded"
  comment="$(ask 'Why (required): ')" || closed
  [ -n "$comment" ] || die "a reason is required — nothing recorded"
  [ "$(sha_file "$pd/brief.md")" = "$shown_brief" ] && [ "$(sha_file "$pd/review.json")" = "$shown_review" ] \
    && [ "$(sha_file "$m")" = "$shown_manifest" ] \
    && [ "$(jq -r '.items[]? | .proof // "" | select(startswith("evidence/"))' "$m" | while IFS= read -r x; do printf '%s %s\n' "$x" "$(sha_file "$pd/$x")"; done)" = "$shown_proofs" ] \
    || die "the brief, review or evidence changed while you were deciding — nothing recorded; run it again"
  # Re-record each evidence file's hash as it was shown, in a new manifest beside the old one. The
  # approval is written against the new manifest's hash before it replaces the old one, so a failure
  # part-way leaves the old manifest and no new approval.
  newm="$(mktemp "$m.XXXXXX")" || die "cannot write next to $m"
  trap 'rm -f "$newm"' EXIT
  hashes='{}'
  while IFS= read -r proof; do
    hashes="$(jq -c --arg k "$proof" --arg v "$(sha_file "$pd/$proof")" '. + {($k): $v}' <<< "$hashes")"
  done < <(jq -r '.items[]? | .proof // "" | select(startswith("evidence/"))' "$m")
  jq --argjson h "$hashes" '.items |= map(if (.proof // "") | startswith("evidence/") then .proof_sha256 = $h[.proof] else . end)' "$m" > "$newm" \
    || { rm -f "$newm"; die "could not build the updated manifest"; }
  shown_evidence="$(sha_file "$newm")"
  write_approval '{phase:$phase, decision:"approve", reconfirmed:true, comment:$comment, used_it:$used, approver:$approver,
                   at:$at, review:"pass", diff_sha:$diff_sha, base:$base, review_sha256:$review_sha,
                   evidence_sha256:$evidence_sha, history:$history}' \
    --arg comment "$comment" --argjson used "$used" \
    --arg diff_sha "$(jq -r '.diff_sha' "$pd/review.json")" --arg base "$(jq -r '.base' "$pd/review.json")"
  cat "$newm" > "$m" || die "the approval was written but $m couldn't be updated — re-run this to fix it"
  [ "$(bash "$HERE/cycle.sh" status "$c" 2>/dev/null | awk -v p="$phase" '$1 == p {print $2}')" = approve ] \
    || die "re-confirmed, but $phase still doesn't verify — check its folder against the meta repo's git history"
  say "Re-confirmed: $phase → approve"
  bash "$HERE/cycle.sh" sync "$c" >&3 2>&1 || say "(the vault sync failed — run: cycle.sh sync)"
  exit 0
fi

check_review() {
  review_state=missing; review_out=""
  [ -f "$pd/review.json" ] || return 0
  review_out="$(cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && bash "$HERE/review_verify.sh" "$pd/review.json" 2>&1)"
  case $? in 0) review_state=pass ;; 1) review_state=changes-requested ;; *) review_state=stale-or-invalid ;; esac
  if [ "$review_state" = pass ] && [ "$(jq -r '.base // ""' "$pd/review.json")" != "$phase_base" ]; then
    review_state=wrong-base
    review_out="the review was measured from $(jq -r '.base // "?"' "$pd/review.json" | cut -c1-12), not from the commit this phase started at ($(cut -c1-12 <<< "$phase_base")) — so it may not cover all of the phase's code; review again from the phase's base (cycle.sh base)"
  fi
}
# What you are shown is exactly what gets approved: these hashes are recorded, and approve is refused
# if any of the files changes before you decide.
shown_brief="$(sha_file "$pd/brief.md")"; shown_review="$(sha_file "$pd/review.json")"
shown_evidence="$(sha_file "$pd/evidence/manifest.json")"
check_review
ev_out="$(bash "$HERE/cycle.sh" evidence "$c" 2>&1)"; ev_rc=$?

say ""
say "━━ $(basename "$c") · $phase · tier: ${tier:-?}"
say ""
[ "$prior" = approve-unverified ] && say "Note: the earlier approval no longer matches its review and evidence; record a new decision." && say ""
say "Builds:"
awk '$0=="## Builds" {f=1; next} /^## / {f=0} f && NF' "$pd/brief.md" | sed 's/^/  /' >&3
say ""
repo_top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
changed="$(git -C "$repo_top" diff --stat "$phase_base" -- . ':(exclude).claude' 2>/dev/null | tail -1)"
untracked="$(git -C "$repo_top" ls-files --others --exclude-standard -- . ':(exclude).claude' | grep -c . || true)"
extra=""; [ "${untracked:-0}" != 0 ] && extra=", $untracked untracked file(s)"
say "Code changed since the phase began at $(git -C "$repo_top" log -1 --format='%h "%s" (%cr)' "$phase_base" 2>/dev/null || cut -c1-12 <<< "$phase_base"):"
say "  ${changed:-no tracked changes}$extra"
commits="$(git -C "$repo_top" log --oneline "$phase_base"..HEAD 2>/dev/null)"
if [ -n "$commits" ]; then
  say "  commits since then:"; head -15 <<< "$commits" | sed 's/^/    /' >&3
  [ "$(wc -l <<< "$commits")" -gt 15 ] && say "    … and $(( $(wc -l <<< "$commits") - 15 )) more"
fi
[ -z "$changed" ] && [ "${untracked:-0}" = 0 ] && say "  ! nothing changed since the phase began — the review covered no code"
say "Review: $review_state"
[ "$review_state" = pass ] || printf '%s\n' "$review_out" | sed 's/^/  /' >&3
say ""
say "Evidence:"
printf '%s\n' "$ev_out" | sed 's/^/  /' >&3
say ""

blockers=""
[ "$review_state" = pass ] || blockers="$blockers the review is $review_state;"
[ "$ev_rc" = 0 ] || blockers="$blockers the evidence is incomplete, out of date or failing;"
[ -n "$blockers" ] && say "Approve is not available:$blockers you can revise or reject." && say ""

used="$(ask 'Did you use it yourself (open the app / run it)? [y/N] ')" || closed
case "$used" in y|Y|yes|YES) used=true ;; *) used=false ;; esac
while :; do
  decision="$(ask 'approve / revise / reject? ')" || closed
  case "$decision" in
    approve) [ -z "$blockers" ] && break; say "Approve is not available:$blockers" ;;
    revise|reject) break ;;
    *) say "Type approve, revise or reject." ;;
  esac
done
if [ "$decision" = approve ]; then
  comment="$(ask 'Comment (optional): ')" || closed
  if [ "$used" = false ]; then
    answer="$(ask 'You have not used it. Approve anyway? Type yes: ')" || closed
    [ "$answer" = yes ] || die "not approved — nothing recorded"
  fi
  # The code may have moved while you were reading; approve only what is still true now.
  [ "$(sha_file "$pd/brief.md")" = "$shown_brief" ] && [ "$(sha_file "$pd/review.json")" = "$shown_review" ] \
    && [ "$(sha_file "$pd/evidence/manifest.json")" = "$shown_evidence" ] \
    || die "the brief, review or evidence changed while you were deciding — nothing recorded; run it again to see the new version"
  check_review; bash "$HERE/cycle.sh" evidence "$c" >/dev/null 2>&1; ev_rc=$?
  [ "$review_state" = pass ] && [ "$ev_rc" = 0 ] \
    || die "the code changed while you were deciding (review: $review_state, evidence: $([ "$ev_rc" = 0 ] && echo current || echo not current)) — nothing recorded; run it again"
else
  comment="$(ask 'What needs to change? (required) ')" || closed
  [ -n "$comment" ] || die "a comment is required to $decision — nothing recorded"
fi

diff_sha=""; base=""
[ -f "$pd/review.json" ] && { diff_sha="$(jq -r '.diff_sha // empty' "$pd/review.json")"; base="$(jq -r '.base // empty' "$pd/review.json")"; }
write_approval '{phase:$phase, decision:$decision, comment:$comment, used_it:$used, approver:$approver, at:$at,
                 review:$review, diff_sha:$diff_sha, base:$base, review_sha256:$review_sha, evidence_sha256:$evidence_sha,
                 history:$history}' \
  --arg decision "$decision" --arg comment "$comment" --argjson used "$used" --arg review "$review_state" \
  --arg diff_sha "$diff_sha" --arg base "$base"

say "Recorded: $phase → $decision"
if [ "$decision" = approve ] && [ "$tier" = client ]; then
  bash "$HERE/cycle.sh" report "$c" "$phase" >&3 2>&1 || say "(the client report failed — fix it, then run: cycle.sh report)"
fi
bash "$HERE/cycle.sh" sync "$c" >&3 2>&1 || say "(the vault sync failed — run: cycle.sh sync)"
exit 0
