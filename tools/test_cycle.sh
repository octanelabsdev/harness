#!/usr/bin/env bash
# test_cycle.sh — behavior tests for the cycle workflow tools, in throwaway repos. Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYCLE="$HERE/cycle.sh"
# Run from a scratch folder: a test that mistakes an error message for a path then writes there, never
# into the repo.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/harness-cyclecwd.XXXXXX")" || exit 1
cd "$SCRATCH" || exit 1
trap 'rm -rf "$SCRATCH"' EXIT
APPROVE="$HERE/cycle_approve.sh"
GUARD="$HERE/../hooks/cycle_guard.sh"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }

# mkcode <harness.json body> -> physical path of a temp dir holding code/ (a git repo) and vault/
mkcode() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/harness-cycletest.XXXXXX")" || exit 1
  d="$(cd "$d" && pwd -P)" || exit 1
  case "$d" in *harness-cycletest.*) ;; *) echo "mkcode: unexpected temp path '$d'" >&2; exit 1 ;; esac
  mkdir -p "$d/code/.claude" "$d/vault" "$d/decoy/.claude"
  git -C "$d/code" init -q
  git -C "$d/code" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
  git -C "$d/decoy" init -q; printf '{}' > "$d/decoy/.claude/harness.json"
  printf '%s' "$1" > "$d/code/.claude/harness.json"
  printf '%s' "$d"
}
# A hook's CLAUDE_PROJECT_DIR points somewhere else; cycle.sh must still act on the repo it runs in.
cy() { (cd "$T/code" && CLAUDE_PROJECT_DIR="$T/decoy" bash "$CYCLE" "$@"); }
decoy_clean() { [ ! -e "$T/decoy/cycles" ]; }
sha() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1"; } | awk '{print $1}'; }
approve() {
  case "$1" in "$T"/*) ;; *) no "approve(): '$1' is not a phase folder under the test dir"; return 1 ;; esac
  local cyc; cyc="$(basename "$(dirname "$(dirname "$1")")")"
  [ -f "$1/brief.md" ] || printf '# Phase\n\n## Done when\n- done\n' > "$1/brief.md"
  [ -f "$1/phase.json" ] || jq -n --arg b "$(git -C "$T/code" rev-parse HEAD)" '{base:$b}' > "$1/phase.json"
  # a real review artifact: the code since the phase's base, as it is now
  [ -f "$1/review.json" ] || jq -n --arg s "$(cd "$T/code" && bash "$HERE/review_verify.sh" --emit-sha "$(jq -r .base "$1/phase.json")")" \
    --arg b "$(jq -r .base "$1/phase.json")" '{diff_sha:$s, base:$b, verdict:"pass", findings:[]}' > "$1/review.json"
  mkdir -p "$1/evidence"; [ -f "$1/evidence/manifest.json" ] || printf '{"items":[]}' > "$1/evidence/manifest.json"
  jq -n --arg c "$cyc" --arg p "$(basename "$1")" --arg d "$2" --arg r "$(sha "$1/review.json")" --arg e "$(sha "$1/evidence/manifest.json")" \
    --arg b "$(sha "$1/brief.md")" --arg base "$(jq -r .base "$1/phase.json")" \
    '{cycle:$c, phase:$p, brief_sha256:$b, base:$base, decision:$d, comment:"", approver:"Pat", at:"2026-10-14T10:00:00Z", review:"pass", review_sha256:$r, evidence_sha256:$e}' \
    > "$1/approval.json"
}

echo "cycle.sh:"
T="$(mkcode '{"cycles":{"dir":"../meta/cycles","mirror":"../vault"}}')"

out="$(cy start acme-invoicing --tier client 2>&1)"; rc=$?
C="$out"
[ "$rc" = 0 ] && [ -f "$C/summary.md" ] && [ -f "$C/decisions.md" ] && ok "start: creates summary.md + decisions.md in the meta repo dir" || no "start: rc=$rc out=$out"
case "$C" in "$T/meta/cycles/"*-acme-invoicing) ok "start: path is dated, under cycles.dir, normalized" ;; *) no "start: unexpected path '$C'" ;; esac
grep -qx 'tier: client' "$C/summary.md" && grep -qx 'status: shaping' "$C/summary.md" && ok "start: front matter records tier + status" || no "start: front matter missing"

cy start acme-invoicing >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "start: refuses an existing cycle (exit 1)" || no "start twice: expected 1, got $rc"
cy start Bad_Slug >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "start: rejects a bad slug (exit 2)" || no "bad slug: expected 2, got $rc"
cy start x --tier huge >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "start: rejects an unknown tier (exit 2)" || no "bad tier: expected 2, got $rc"

[ "$(cy active)" = "$C" ] && ok "active: the open cycle" || no "active: got '$(cy active)'"

P1="$(cy phase invoice-model 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$P1/brief.md" ] && [ -d "$P1/evidence" ] && ok "phase: first phase gets a brief + evidence dir" || no "phase 1: rc=$rc out=$P1"
[ "$(jq -r .base "$P1/phase.json")" = "$(git -C "$T/code" rev-parse HEAD)" ] && [ "$(cy base)" = "$(git -C "$T/code" rev-parse HEAD)" ] \
  && ok "phase: records the commit it starts from (cycle.sh base)" || no "phase base: $(cat "$P1/phase.json" 2>/dev/null)"
grep -qx 'status: building' "$C/summary.md" && ok "phase: cycle status moves to building" || no "phase: status not updated"

cy phase send-pdf >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "phase: next phase refused until the previous is approved" || no "phase 2 early: expected 1, got $rc"
printf '{"decision":"revise","comment":"Totals are off by a cent"}' > "$P1/approval.json"
out="$(cy status)"
grep -q 'comment: Totals are off by a cent' <<< "$out" && ok "status: shows the comment on a revise decision" || no "status: revise comment missing"
cy phase send-pdf >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "phase: a 'revise' decision does not unlock the next phase" || no "phase 2 after revise: expected 1, got $rc"
approve "$P1" approve
P2="$(cy phase send-pdf 2>&1)"; rc=$?
case "$P2" in */phases/2-send-pdf) [ "$rc" = 0 ] && ok "phase: approved phase unlocks phase 2" || no "phase 2: rc=$rc" ;; *) no "phase 2: '$P2'" ;; esac

out="$(cy status)"
grep -q '1-invoice-model *approve$' <<< "$out" && grep -q '2-send-pdf *open$' <<< "$out" && ok "status: shows each phase's decision" || no "status: $out"

cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && grep -qx 'status: building' "$C/summary.md" && ok "close: refused while a phase is unapproved" || no "close early: expected 1, got $rc"

approve "$P2" approve; cp "$P2/approval.json" "$T/good.json"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && grep -qx 'status: building' "$C/summary.md" && ok "close: a client cycle needs a client report for every phase" || no "client close without reports: rc=$rc"
for x in "$P1" "$P2"; do
  echo "# hand-written" > "$x/report-client.md"
  printf '{"approval_sha256":"%s","client_sha256":"%s"}' "$(sha "$x/approval.json")" "0000" > "$x/report.json"
done
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "close: a hand-written client report doesn't count" || no "hand-written report accepted at close: rc=$rc"
cy report "$C" 1-invoice-model >/dev/null 2>&1 && cy report "$C" 2-send-pdf >/dev/null 2>&1 || no "reports for close: failed"
mv "$P2/report-internal.md" "$T/internal.keep"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "close: a client cycle needs the internal report too" || no "close without internal report: rc=$rc"
mv "$T/internal.keep" "$P2/report-internal.md"
printf '{"decision":"approve"}' > "$P2/approval.json"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "a bare {\"decision\":\"approve\"} doesn't count as approval" || no "bare approval accepted: rc=$rc"
cp "$P1/approval.json" "$P2/approval.json"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "an approval copied from another phase doesn't count" || no "copied approval accepted: rc=$rc"
cp "$T/good.json" "$P2/approval.json"
cp -R "$C" "$T/meta/cycles/2026-01-09-copy"
out="$(cy status 2026-01-09-copy)"
grep -q '1-invoice-model *approve-unverified' <<< "$out" && ok "a cycle copied wholesale doesn't inherit its approvals" || no "copied cycle kept approvals: $out"
rm -rf "$T/meta/cycles/2026-01-09-copy"
jq '.base = "0000000000000000000000000000000000000000"' "$T/good.json" > "$P2/approval.json"
out="$(cy status)"
grep -q '2-send-pdf *approve-unverified' <<< "$out" && ok "an approval recorded for a different base doesn't count" || no "wrong-base approval accepted: $out"
cp "$T/good.json" "$P2/approval.json"
cp "$P2/review.json" "$T/review.orig"
printf '{"verdict":"pass","findings":[],"edited":true}' > "$P2/review.json"
out="$(cy status)"
grep -q '2-send-pdf *approve-unverified' <<< "$out" && ok "editing the review after approval un-verifies it" || no "tampered review still approved: $out"
cp "$T/review.orig" "$P2/review.json"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && grep -qx 'status: closed' "$C/summary.md" && ok "close: marks closed once every phase is approved" || no "close: rc=$rc"

M="$T/vault/$(basename "$C")"
[ -f "$M/summary.md" ] && [ -f "$M/phases/2-send-pdf/approval.json" ] && ok "close: mirrors the cycle to the vault" || no "close: mirror missing"
grep -q 'Mirrored from' <<< "$(head -1 "$M/summary.md")" && ok "sync: markdown copies say where they came from" || no "sync: no provenance header"
cmp -s "$C/phases/2-send-pdf/approval.json" "$M/phases/2-send-pdf/approval.json" && ok "sync: non-markdown files copied verbatim" || no "sync: json differs"
echo stray > "$M/vault-edit.md"
cy sync "$C" >/dev/null 2>&1
[ ! -e "$M/vault-edit.md" ] && ok "sync: one-way — files only in the vault are removed" || no "sync: vault-only file survived"

cy active >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "active: none once the only cycle is closed (exit 2)" || no "active after close: expected 2, got $rc"

mkdir -p "$T/vault/keep-me"; echo keep > "$T/vault/keep-me/notes.md"
cy sync >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ -f "$T/vault/keep-me/notes.md" ] && [ -f "$M/summary.md" ] && ok "sync with no open cycle: exit 2, the vault is untouched" || no "sync no-open: rc=$rc, vault damaged?"
cy sync no-such-cycle >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ -f "$T/vault/keep-me/notes.md" ] && ok "sync of an unknown cycle: exit 2, the vault is untouched" || no "sync unknown: rc=$rc"
cy sync / >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ -f "$T/vault/keep-me/notes.md" ] && ok "sync of '/': refused" || no "sync /: rc=$rc"
cy status no-such-cycle >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "status of an unknown cycle: exit 2" || no "status unknown: expected 2, got $rc"
decoy_clean && ok "nothing was written to CLAUDE_PROJECT_DIR's repo" || no "cycle.sh wrote into CLAUDE_PROJECT_DIR: $(ls -A "$T/decoy")"
rm -rf "$T"

# cycles.mirror == cycles.dir must never delete the source
T="$(mkcode '{"cycles":{"dir":"../notes/cycles","mirror":"../notes/cycles"}}')"
C="$(cy start same-place --tier summary-only)"
echo '- 2026-10-12 — keep this. Why: test.' >> "$C/decisions.md"
cy sync >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q 'keep this' "$C/decisions.md" && [ -f "$C/summary.md" ] && ok "mirror == cycles dir: refused, source intact" || no "mirror==dir: rc=$rc, source damaged?"
rm -rf "$T"

# front matter edge cases and phase numbering
T="$(mkcode '{}')"
C="$(cy start edges --tier summary-only)"
sed -i.bak '/^status:/d' "$C/summary.md" && rm -f "$C/summary.md.bak"
out="$(cy close 2>&1)"; rc=$?
[ "$rc" = 2 ] && ! grep -q '^closed' <<< "$out" && ok "close with no status line: exit 2, not a false 'closed'" || no "fm missing key: rc=$rc out=$out"
C2="$(cy start crlf --tier summary-only)"
printf -- '---\r\ntier: summary-only\r\nstatus: closed\r\n---\r\n# crlf\r\n' > "$C2/summary.md"
out="$(cy status "$C2" 2>&1)"
grep -q 'status: closed$' <<< "$out" && ok "CRLF front matter: a closed cycle reads as closed" || no "CRLF: status not parsed: $out"
C3="$(cy start octal)"
mkdir -p "$C3/phases/08-eight"; approve "$C3/phases/08-eight" approve
out="$(cy phase nine "$C3" 2>&1)"; rc=$?
case "$out" in */phases/9-nine) [ "$rc" = 0 ] && ok "phase numbers like 08 aren't read as octal" || no "octal: rc=$rc" ;; *) no "octal: $out" ;; esac
rm -rf "$T"

# summary-only: no phases, closes without approvals; in-repo default dir; no mirror configured
T="$(mkcode '{}')"
C="$(cy start typo-fix --tier summary-only)"
case "$C" in "$T/code/.claude/cycles/"*) ok "default cycles.dir is .claude/cycles in the code repo" ;; *) no "default dir: '$C'" ;; esac
cy phase anything >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "summary-only: refuses phases" || no "summary-only phase: expected 1, got $rc"
out="$(cy close 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q 'no cycles.mirror' <<< "$out" && ok "summary-only: closes without approvals; sync is a no-op without a mirror" || no "summary-only close: rc=$rc $out"
rm -rf "$T"

# --from imports outside scope
T="$(mkcode '{}')"
printf 'scope shaped elsewhere\n' > "$T/scope-in.md"
C="$(cy start imported --from "$T/scope-in.md")"
cmp -s "$T/scope-in.md" "$C/scope.md" && ok "start --from: imports the file as scope.md" || no "start --from: scope.md missing or different"
cy start other --from "$T/nope.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "start --from: missing file is a usage error" || no "start --from missing: expected 2, got $rc"
rm -rf "$T"

# the vault copy must never write back into the cycle, even through a symlink
T="$(mkcode '{"cycles":{"dir":"../meta/cycles","mirror":"../vault"}}')"
C="$(cy start linked --tier summary-only)"
cp "$C/summary.md" "$T/summary.orig"
ln -s "$C" "$T/vault/$(basename "$C")"
cy sync >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && cmp -s "$C/summary.md" "$T/summary.orig" && ok "sync: a symlinked vault copy is refused; the cycle is untouched" || no "sync symlink: rc=$rc, summary changed?"
rm -f "$T/vault/$(basename "$C")"

# an explicit cycle argument must be a cycle folder, not any folder with a summary.md
mkdir -p "$T/code/docs" "$T/vault/docs"; echo notes > "$T/code/docs/summary.md"; echo mine > "$T/vault/docs/important.md"
cy sync docs >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ -f "$T/vault/docs/important.md" ] && ok "sync: a folder outside cycles.dir is not a cycle (vault untouched)" || no "sync docs: rc=$rc"

# summary.md keeps its permissions through status updates
chmod 644 "$C/summary.md"; cy close >/dev/null 2>&1
case "$(ls -l "$C/summary.md")" in -rw-r--r--*) ok "summary.md keeps its mode after an update" ;; *) no "mode changed: $(ls -l "$C/summary.md")" ;; esac

# a failed copy is an error, and the previous vault copy survives
M="$T/vault/$(basename "$C")"
[ -f "$M/summary.md" ] && cp "$M/summary.md" "$T/mirror.before"
chmod 000 "$C/decisions.md"
cy sync "$C" >/dev/null 2>&1; rc=$?
chmod 644 "$C/decisions.md"
[ "$rc" = 2 ] && cmp -s "$M/summary.md" "$T/mirror.before" && ok "sync: a copy failure exits 2 and keeps the previous vault copy" || no "sync failure: rc=$rc"
staged=""; for x in "$T/vault"/.sync-*; do [ -e "$x" ] && staged="$staged $x"; done
[ -z "$staged" ] && ok "sync: no staging folders left behind" || no "sync: staging left:$staged"
rm -rf "$T"

# with two open cycles, phase can name the older one
T="$(mkcode '{}')"
OLD="$T/code/.claude/cycles/2026-01-01-old"; mkdir -p "$OLD"
printf -- '---\ntier: standard\nstatus: building\n---\n## Status\nx\n' > "$OLD/summary.md"
jq -n --arg r "$(git -C "$T/code" rev-list --max-parents=0 HEAD)" --arg b "$(git -C "$T/code" rev-parse HEAD)" \
  '{repo_root:$r, repo_name:"code", start_base:$b}' > "$OLD/cycle.json"
cy start newer --tier summary-only >/dev/null
out="$(cy phase p1 2026-01-01-old 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$OLD/phases/1-p1/brief.md" ] && ok "phase <slug> <cycle>: adds a phase to a named, older open cycle" || no "phase named cycle: rc=$rc $out"

# setup problems are exit 2, not a refusal
mkdir -p "$OLD/phases/2a-spike"; approve "$OLD/phases/2a-spike" approve
approve "$OLD/phases/1-p1" approve
cy phase p3 2026-01-01-old >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "a phase folder like 2a-spike is a setup error (exit 2)" || no "2a-spike: expected 2, got $rc"
rm -rf "$OLD/phases/2a-spike"

# trailing space and quotes in front matter
printf -- '---\ntier: "summary-only" \nstatus: closed \n---\n## Status\nx\n' > "$OLD/summary.md"
out="$(cy status 2026-01-01-old 2>&1)"
grep -q 'tier:   summary-only    status: closed$' <<< "$out" && ok "front matter: trailing space and quotes are ignored" || no "fm trim: $out"
rm -rf "$T"

# no harness config: refuse rather than guess the repo
T="$(mkcode '{}')"; rm -f "$T/code/.claude/harness.json"
cy start nocfg >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -d "$T/code/.claude/cycles" ] && ok "no .claude/harness.json: exit 2, nothing created" || no "no config: rc=$rc"
rm -rf "$T"

# a cycle folder that is a symlink into the vault is not a cycle
T="$(mkcode '{"cycles":{"dir":"../meta/cycles","mirror":"../vault"}}')"
mkdir -p "$T/meta/cycles" "$T/vault/2026-01-02-x"
printf -- '---\ntier: summary-only\nstatus: building\n---\n## Status\nx\n' > "$T/vault/2026-01-02-x/summary.md"
cp "$T/vault/2026-01-02-x/summary.md" "$T/x.orig"
ln -s "$T/vault/2026-01-02-x" "$T/meta/cycles/2026-01-02-x"
cy sync 2026-01-02-x >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && cmp -s "$T/vault/2026-01-02-x/summary.md" "$T/x.orig" && ok "a symlinked cycle folder is refused by name; its target is untouched" || no "symlinked cycle by name: rc=$rc"
cy sync >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && cmp -s "$T/vault/2026-01-02-x/summary.md" "$T/x.orig" && ok "a symlinked cycle folder is never the active cycle" || no "symlinked cycle as active: rc=$rc"
rm -rf "$T"

# two open cycles: commands that would guess refuse instead
T="$(mkcode '{}')"
cy start alpha >/dev/null; cy start zeta >/dev/null
out="$(cy phase p1 2>&1)"; rc=$?
[ "$rc" = 2 ] && grep -q 'name the one you mean' <<< "$out" && [ ! -d "$T/code/.claude/cycles/$(date +%F)-alpha/phases" ] && [ ! -d "$T/code/.claude/cycles/$(date +%F)-zeta/phases" ] \
  && ok "two open cycles: an unnamed phase is refused, nothing created" || no "ambiguous phase: rc=$rc $out"
rm -rf "$T"

# a failed --from leaves no half-made cycle
T="$(mkcode '{}')"
printf 'scope\n' > "$T/locked.md"; chmod 000 "$T/locked.md"
cy start locked --from "$T/locked.md" >/dev/null 2>&1; rc=$?
chmod 644 "$T/locked.md"
[ "$rc" = 2 ] && [ ! -e "$T/code/.claude/cycles/$(date +%F)-locked" ] && ok "start --from an unreadable file: exit 2, no folder left" || no "start --from unreadable: rc=$rc"
cy start locked --from "$T/locked.md" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "start: the same slug works once the problem is fixed" || no "start retry: rc=$rc"
rm -rf "$T"

# a standard cycle can't close with no phases, and a closed cycle takes no new phases
T="$(mkcode '{}')"
C="$(cy start nophase)"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && grep -qx 'status: shaping' "$C/summary.md" && ok "close: a standard cycle with no phases is refused" || no "close zero phases: rc=$rc"
sed -i.bak 's/^status: shaping$/status: closed/' "$C/summary.md" && rm -f "$C/summary.md.bak"
cy phase extra "$C" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -d "$C/phases" ] && grep -qx 'status: closed' "$C/summary.md" && ok "phase: refused on a closed cycle; it stays closed" || no "phase on closed: rc=$rc"
rm -rf "$T"

# a failed sync during close leaves the cycle open, so close can be retried
T="$(mkcode '{"cycles":{"mirror":"../vault"}}')"
C="$(cy start retry --tier summary-only)"
chmod 000 "$C/decisions.md"
cy close >/dev/null 2>&1; rc=$?
chmod 644 "$C/decisions.md"
[ "$rc" = 2 ] && grep -qx 'status: shaping' "$C/summary.md" && ok "close: a failed vault sync leaves the cycle open" || no "close sync failure: rc=$rc, status=$(grep '^status' "$C/summary.md")"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && grep -qx 'status: closed' "$T/vault/$(basename "$C")/summary.md" && ok "close: retry succeeds and the vault copy says closed" || no "close retry: rc=$rc"
rm -rf "$T"

# a failed start in a repo whose path has apostrophes and spaces removes only its own folder
T="$(mkcode '{}')"
R="$T/Bob's and Alice's/repo"
mkdir -p "$R/.claude" "$R/and" "$R/Bobs"; echo precious > "$R/and/keep.txt"; echo precious > "$R/Bobs/keep.txt"
git -C "$R" init -q; git -C "$R" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init; printf '{}' > "$R/.claude/harness.json"
printf 'scope\n' > "$T/locked.md"; chmod 000 "$T/locked.md"
(cd "$R" && CLAUDE_PROJECT_DIR="$T/decoy" bash "$CYCLE" start demo --from "$T/locked.md") >/dev/null 2>&1; rc=$?
chmod 644 "$T/locked.md"
[ "$rc" = 2 ] && [ -f "$R/and/keep.txt" ] && [ -f "$R/Bobs/keep.txt" ] && [ ! -e "$R/.claude/cycles/$(date +%F)-demo" ] \
  && ok "failed start under a path with apostrophes: removes its own folder and nothing else" || no "apostrophe path cleanup: rc=$rc"

# a failed phase leaves no folder and no status change
C="$(cd "$R" && CLAUDE_PROJECT_DIR="$T/decoy" bash "$CYCLE" start ro)"
mkdir -p "$C/phases"; chmod 555 "$C/phases"
(cd "$R" && CLAUDE_PROJECT_DIR="$T/decoy" bash "$CYCLE" phase p1 "$C") >/dev/null 2>&1; rc=$?
chmod 755 "$C/phases"
[ "$rc" = 2 ] && [ -z "$(ls -A "$C/phases")" ] && grep -qx 'status: shaping' "$C/summary.md" && ok "a failed phase leaves no folder and the status unchanged" || no "failed phase: rc=$rc status=$(grep '^status' "$C/summary.md")"
rm -rf "$T"

# cycle files inside the code repo (outside .claude) would count as code changes: refused
T="$(mkcode '{"cycles":{"dir":"cycles"}}')"
cy start inrepo >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -e "$T/code/cycles" ] && ok "cycles.dir inside the code repo (outside .claude): exit 2, nothing created" || no "in-repo cycles.dir: rc=$rc"
rm -rf "$T"

# a phased cycle can't close by relabelling itself summary-only
T="$(mkcode '{}')"
C="$(cy start relabel)"; P="$(cy phase one)"
sed -i.bak 's/^tier: standard$/tier: summary-only/' "$C/summary.md" && rm -f "$C/summary.md.bak"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ! grep -qx 'status: closed' "$C/summary.md" && ok "close: a cycle with phases can't close as summary-only" || no "summary-only dodge: rc=$rc"
rm -rf "$T"

# the vault mirror never lands inside the code repo
T="$(mkcode '{"cycles":{"mirror":"docs/cycles"}}')"
cy start mirrored --tier summary-only >/dev/null
cy sync >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -e "$T/code/docs/cycles" ] && ok "sync: a mirror inside the code repo is refused" || no "mirror in repo: rc=$rc"
rm -rf "$T"

# review_verify --emit-sha accepts a base, and refuses one that isn't a commit
T="$(mkcode '{}')"
(cd "$T/code" && bash "$HERE/review_verify.sh" --emit-sha "$(git rev-parse HEAD)" >/dev/null); rc=$?
(cd "$T/code" && bash "$HERE/review_verify.sh" --emit-sha nope >/dev/null 2>&1); rc2=$?
[ "$rc" = 0 ] && [ "$rc2" = 2 ] && ok "review_verify --emit-sha <base>: works, and rejects a non-commit" || no "emit-sha base: rc=$rc rc2=$rc2"

# a phase approved under the client tier still needs its client report after the tier is lowered
C="$(cy start relabel-client --tier client)"; P="$(cy phase one)"; approve "$P" approve
jq '.tier = "client"' "$P/approval.json" > "$T/a" && cat "$T/a" > "$P/approval.json"
sed -i.bak 's/^tier: client$/tier: standard/' "$C/summary.md" && rm -f "$C/summary.md.bak"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ! grep -qx 'status: closed' "$C/summary.md" && ok "close: lowering a client cycle's tier doesn't skip its client reports" || no "tier relabel: rc=$rc"
rm -rf "$T"

# code changed after an approval blocks the next phase and close until it's reviewed
T="$(mkcode '{}')"
C="$(cy start drift)"; P="$(cy phase one)"; echo reviewed > "$T/code/a.txt"
approve "$P" approve
echo "unreviewed change" >> "$T/code/a.txt"
cy phase two >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -d "$C/phases/2-two" ] && ok "phase: refused when the code changed after the previous phase was approved" || no "drift phase: rc=$rc"
cy close >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ! grep -qx 'status: closed' "$C/summary.md" && ok "close: refused when the code changed after the last approval" || no "drift close: rc=$rc"
mkdir -p "$P/evidence"; printf '{"items":[]}' > "$P/evidence/manifest.json"
out="$(cy evidence stamp 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 're-review it first' <<< "$out" && ok "evidence stamp on an approved phase whose code changed: says to re-review first" || no "stamp drift message: rc=$rc $out"
echo reviewed > "$T/code/a.txt"
cy phase two >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -d "$C/phases/2-two" ] && ok "phase: refused while phase 1's reviewed work is uncommitted" || no "uncommitted reviewed work: rc=$rc"
git -C "$T/code" add -A && git -C "$T/code" -c user.email=t@e -c user.name=t commit -q -m "phase one"
cy phase two >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "phase: committing exactly the reviewed code is fine" || no "commit reviewed then phase: rc=$rc"
rm -rf "$T"

# a cycle covers one code repo; phase 1 starts where the cycle started
T="$(mkcode '{"cycles":{"dir":"../meta/cycles"}}')"
C="$(cy start onerepo)"
[ "$(jq -r .start_base "$C/cycle.json")" = "$(git -C "$T/code" rev-parse HEAD)" ] && ok "start: records the code repo and the commit it starts from" || no "cycle.json: $(cat "$C/cycle.json" 2>/dev/null)"
echo spike > "$T/code/spike.txt"; git -C "$T/code" add -A; git -C "$T/code" -c user.email=t@e -c user.name=t commit -q -m spike
P="$(cy phase one)"
[ "$(jq -r .base "$P/phase.json")" = "$(jq -r .start_base "$C/cycle.json")" ] && ok "phase 1: starts where the cycle started, so commits made while shaping are reviewed" || no "phase 1 base: $(cat "$P/phase.json")"
mkdir -p "$T/other/.claude"; git -C "$T/other" init -q; git -C "$T/other" -c user.email=t@e -c user.name=t commit -q --allow-empty -m other
printf '{"cycles":{"dir":"../meta/cycles"}}' > "$T/other/.claude/harness.json"
out="$( (cd "$T/other" && CLAUDE_PROJECT_DIR="$T/decoy" bash "$CYCLE" evidence stamp "$C") 2>&1)"; rc=$?
[ "$rc" = 2 ] && grep -q 'covers the code repo' <<< "$out" && ok "a cycle refuses to be worked from a different code repo" || no "cross-repo: rc=$rc $out"
out="$(cy close "$C" 2>&1)"
! grep -q 'set tier' <<< "$out" && ok "close: the refusal doesn't suggest relabelling the tier" || no "close hint: $out"
rm -rf "$T"

echo "cycle_guard (PreToolUse):"
T="$(mkcode '{}')"
guard() { CLAUDE_PROJECT_DIR="$T/code" bash "$GUARD"; }
denied() { [ "$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)" = deny ]; }
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"bash ~/h/tools/cycle_approve.sh"}}' | guard)"
denied "$out" && ok "denies running the approval tool" || no "approve command not denied: $out"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"printf x > ../meta/cycles/c/phases/1-a/approval.json"}}' | guard)"
denied "$out" && ok "denies a shell command touching approval.json" || no "approval.json shell write not denied: $out"
out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"/x/meta/cycles/c/phases/1-a/approval.json","content":"{}"}}' | guard)"
denied "$out" && ok "denies Write to a phase's approval.json" || no "Write approval.json not denied: $out"
for c in 'env -u CLAUDE_CODE_CHILD_SESSION bash tools/cycle_approve.sh' 'cd x && ./tools/cycle_approve.sh' \
         'env -u X tools/cycle_approve.sh' 'x=1; . ./cycle_approve.sh' 'jq . a | tee phases/1-a/approval.json' \
         'bash "tools/cycle_approve.sh"' 'rm phases/1-a/approval.json' "$(printf 'cd x\n./tools/cycle_approve.sh')" \
         'jq -n "{}" > "$pd/approval.json"' 'bash "$HARNESS/tools/cycle_approve.sh"' 'x="$(tools/cycle_approve.sh)"' \
         'printf x | tee phases/1/approval.json >/dev/null' 'jq . a >| phases/1-x/approval.json' \
         "echo it\\'s > x; echo {} > phases/1-a/approval.json" 'sudo bash tools/cycle_approve.sh' \
         'if true; then tools/cycle_approve.sh; fi' 'perl -pi -e s/revise/approve/ phases/1-a/approval.json' \
         'printf x > phases/1-a/approval.json 2>/dev/null' 'mv phases/1-a/approval.json /tmp/x' 'rm -f phases/1-a/approval.json /tmp/y' \
         "$(printf 'cat > "$P/approval.json" <<EOF\n{}\nEOF')" \
         'cp /tmp/a.json phases/1-a/approval.json' "sed -i '' s/revise/approve/ phases/1-a/approval.json"; do
  out="$(jq -n --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' | guard)"
  denied "$out" && ok "denies: $c" || no "not denied: $c"
done
for c in 'git add tools/cycle_approve.sh' 'shellcheck tools/cycle_approve.sh' 'grep -rn approval.json docs' 'cat phases/1-a/approval.json' \
         'git add ../acme-meta/cycles/c/phases/1-a/approval.json' 'find . -name cycle_approve.sh' \
         'git ls-files | xargs grep -l cycle_approve' 'git diff -- . tools/cycle_approve.sh' \
         'bash -n tools/cycle_approve.sh' 'cp phases/1-a/approval.json /tmp/x' 'echo hi >approval.json.bak' \
         'git commit -m "Harden the gate (cycle_approve.sh refuses child sessions)"' 'cp "$P/approval.json" /tmp/x' \
         'curl -s api/approvals/1 > spec/fixtures/approval.json' 'cp tmp.json config/approval.json' 'grep x <<< y; echo ok' \
         'git commit -m "Ready! cycle_approve.sh now asks for a reason"' 'echo "{bash cycle_approve.sh}"' \
         'time shellcheck tools/cycle_approve.sh' 'env LC_ALL=C grep -n tty tools/cycle_approve.sh' \
         'grep -n else tools/cycle_approve.sh' \
         "$(printf 'git commit -m "Add approval\n\ntools/cycle_approve.sh records the decision"')" \
         "$(printf 'git commit -F - <<EOF\nFix\n\ntools/cycle_approve.sh records it\nEOF')"; do
  out="$(jq -n --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' | guard)"
  [ -z "$out" ] && ok "allows: $c" || no "falsely denied: $c"
done
out="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"/x/meta/cycles/c/phases/1-a/brief.md"}}' | guard)"
[ -z "$out" ] && ok "allows editing the brief" || no "brief edit was decided: $out"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"bash tools/cycle.sh status"}}' | guard)"
[ -z "$out" ] && ok "allows reading status" || no "status was decided: $out"
printf '{"components":{"cycle_guard":false}}' > "$T/code/.claude/harness.json"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"bash cycle_approve.sh"}}' | guard)"
[ -z "$out" ] && ok "components.cycle_guard: false turns it off" || no "guard ignored its toggle: $out"
rm -f "$T/code/.claude/harness.json"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"bash cycle_approve.sh"}}' | guard)"
[ -z "$out" ] && ok "inert without a harness config" || no "guard acted without config: $out"
rm -rf "$T"

echo "cycle_approve.sh:"
T="$(mkcode '{}')"
git -C "$T/code" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
C="$(cy start gate)"; P="$(cy phase one)"
out="$( (cd "$T/code" && CLAUDE_CODE_CHILD_SESSION=1 bash "$APPROVE") 2>&1 </dev/null)"; rc=$?
[ "$rc" = 2 ] && [ ! -e "$P/approval.json" ] && grep -q 'own terminal' <<< "$out" && ok "refuses inside Claude's tools; records nothing" || no "approve in child session: rc=$rc $out"
if ( exec 3<>/dev/tty ) 2>/dev/null; then
  printf '  - skipped: no-terminal refusal (this shell has a terminal; CI and the Stop hook run it)\n'
else
  out="$( (cd "$T/code" && env -u CLAUDE_CODE_CHILD_SESSION bash "$APPROVE") 2>&1 </dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ ! -e "$P/approval.json" ] && ok "refuses without a terminal; records nothing" || no "approve without tty: rc=$rc $out"
fi
rm -rf "$T"

echo "cycle_approve.sh (interactive):"
pty_ok() { expect -c 'spawn bash -c "exit 7"; expect eof; catch wait r; exit [lindex $r 3]' >/dev/null 2>&1; [ $? = 7 ]; }
if ! command -v expect >/dev/null 2>&1 || ! pty_ok; then
  printf '  - skipped: no pseudo-terminal here (expect missing or openpty denied)\n'
else
  T="$(mkcode '{"cycles":{"dir":"../meta/cycles"}}')"
  git -C "$T/code" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
  git -C "$T/code" config user.name "Pat Human"
  cat > "$T/drive.exp" <<'EXP'
set timeout 20
set approve [lindex $argv 0]
set answers [lrange $argv 1 end]
spawn env -u CLAUDE_CODE_CHILD_SESSION bash $approve
foreach {pattern reply} $answers {
  if {$pattern eq "@swap"} { exec sh $reply; continue }
  expect {
    $pattern { send "$reply\r" }
    eof { break }
    timeout { puts "\nTIMEOUT waiting for: $pattern"; exit 9 }
  }
}
expect eof
catch wait result
exit [lindex $result 3]
EXP
  drive() { (cd "$T/code" && perl -e 'alarm 60; exec @ARGV' expect "$T/drive.exp" "$APPROVE" "$@" 2>&1 | tr -d '\r'); }
  ready() { # ready <phase-dir>: a passing review and stamped evidence for the current diff
    jq -n --arg s "$(cd "$T/code" && bash "$HERE/review_verify.sh" --emit-sha "$(cy base)")" --arg b "$(cy base)" \
      '{diff_sha:$s, base:$b, verdict:"pass", findings:[]}' > "$1/review.json"
    printf '{"open_app":"cat app.txt","items":[{"done_when":"It works","status":"verified","proof":"evidence/s.png"}]}' > "$1/evidence/manifest.json"
    cy evidence stamp >/dev/null
  }
  C="$(cy start live)"; P1="$(cy phase one)"
  printf '# Phase 1: one\n\n## Builds\nThe thing.\n\n## Done when\n- It works\n' > "$P1/brief.md"
  echo v1 > "$T/code/app.txt"; echo shot > "$P1/evidence/s.png"; ready "$P1"

  # a review and evidence that are valid for the new code, just not the ones the human was shown
  cat > "$T/swap.sh" <<SWAP
cd "$T/code" && echo v2 >> app.txt || exit 1
jq -n --arg s "\$(bash "$HERE/review_verify.sh" --emit-sha "\$(CLAUDE_PROJECT_DIR=/x bash "$CYCLE" base)")" --arg b "\$(CLAUDE_PROJECT_DIR=/x bash "$CYCLE" base)" \
  '{diff_sha:\$s, base:\$b, verdict:"pass", findings:[]}' > "$P1/review.json"
CLAUDE_PROJECT_DIR=/nonexistent bash "$CYCLE" evidence stamp >/dev/null
SWAP
  # the agent swaps in a different review after the screen is shown and before the human decides
  out="$(drive "Did you use it" y "@swap" "$T/swap.sh" "approve / revise" approve "Comment" ok)"
  [ ! -e "$P1/approval.json" ] && grep -q 'changed while you were deciding' <<< "$out" && ok "approve: refused when the review changes while you decide" || no "swap mid-decision: $out"
  echo v1 > "$T/code/app.txt"; ready "$P1"

  out="$(drive "Did you use it" y "approve / revise" revise "What needs to change" "")"
  [ ! -e "$P1/approval.json" ] && grep -q 'a comment is required' <<< "$out" && ok "revise without a comment: refused, nothing recorded" || no "empty revise: $out"
  out="$(drive "Did you use it" y "approve / revise" revise "What needs to change" "the link is broken")"
  sed -i.bak 's/"revise"/"approve"/' "$P1/approval.json" && rm -f "$P1/approval.json.bak"
  [ "$(cy status | awk '$1 == "1-one" {print $2}')" = approve-unverified ] && ok "a recorded revise edited to say approve doesn't count" || no "revise flip: $(cy status)"
  out="$(drive "Did you use it" y "approve / revise" approve "Comment" "Looks right")"
  [ "$(cy status | awk '$1 == "1-one" {print $2}')" = approve ] && grep -q 'Recorded: 1-one → approve' <<< "$out" && ok "approve: recorded, and cycle.sh verifies it" || no "approve: $out"
  [ "$(jq -r '.approver' "$P1/approval.json")" = "Pat Human" ] && [ "$(jq -r '.used_it' "$P1/approval.json")" = true ] && ok "approval records the approver and that they used it" || no "approval fields: $(cat "$P1/approval.json")"

  echo "tweak after approval" >> "$T/code/app.txt"
  out="$(drive "Did you use it" y)"
  grep -q 'code has changed since' <<< "$out" && ok "approve tool: an approved phase whose code changed asks for a re-review" || no "drift tool: $out"
  echo v1 > "$T/code/app.txt"
  git -C "$T/code" add -A; git -C "$T/code" -c user.email=t@e -c user.name=t commit -q -m p1
  P2="$(cy phase two)"; printf '# Phase 2: two\n\n## Builds\nMore.\n\n## Done when\n- It works\n' > "$P2/brief.md"
  echo shot > "$P2/evidence/s.png"
  # the agent commits the phase's work, then reviews from the new HEAD: the review covers nothing
  echo v3 >> "$T/code/app.txt"; git -C "$T/code" add -A; git -C "$T/code" -c user.email=t@e -c user.name=t commit -q -m p2
  jq -n --arg s "$(cd "$T/code" && bash "$HERE/review_verify.sh" --emit-sha)" --arg b "$(git -C "$T/code" rev-parse HEAD)" \
    '{diff_sha:$s, base:$b, verdict:"pass", findings:[]}' > "$P2/review.json"
  printf '{"open_app":"x","items":[{"done_when":"It works","status":"verified","proof":"evidence/s.png"}]}' > "$P2/evidence/manifest.json"
  cy evidence stamp >/dev/null
  out="$(drive "Did you use it" y "approve / revise" approve "approve / revise" revise "What needs" "review again")"
  grep -q 'Review: wrong-base' <<< "$out" && grep -q 'Approve is not available' <<< "$out" && ok "approve: a review measured from a later commit than the phase's start isn't accepted" || no "wrong-base review: $out"
  grep -q 'Code changed since the phase began' <<< "$out" && ok "approve screen: shows what changed since the phase began" || no "diffstat missing: $out"
  ready "$P2"

  printf '\nAlso exports CSV.\n' >> "$P1/brief.md"
  out="$(drive "Did you check it yourself" y "Type yes" yes "Why" "Agreed to add CSV")"
  grep -q 'brief.md changed' <<< "$out" && grep -q 'Also exports CSV' <<< "$out" && ok "re-confirm: shows that the brief changed, and the brief itself" || no "re-confirm display: $out"
  [ "$(cy status | awk '$1 == "1-one" {print $2}')" = approve ] && ok "re-confirm: the earlier phase verifies again" || no "re-confirm result: $(cy status)"
  cp "$P1/review.json" "$T/r1.keep"; cp "$P2/review.json" "$P1/review.json"
  out="$(drive "Type yes" yes "Why" x)"
  grep -q "isn't the review you approved" <<< "$out" && ok "re-confirm: refused when the review is of different code" || no "re-confirm wrong review: $out"
  cp "$T/r1.keep" "$P1/review.json"
  jq '.items[0].status = "failing"' "$P1/evidence/manifest.json" > "$T/m" && cat "$T/m" > "$P1/evidence/manifest.json"
  out="$(drive "Type yes" yes "Why" x)"
  grep -q 'incomplete or failing' <<< "$out" && [ "$(cy status | awk '$1 == "1-one" {print $2}')" = approve-unverified ] \
    && ok "re-confirm: refused when the earlier phase's evidence is failing" || no "re-confirm failing evidence: $out"
  rm -rf "$T"
fi

echo "evidence + report:"
T="$(mkcode '{"cycles":{"deny":["AcmeCorp","Project Falcon"]}}')"
git -C "$T/code" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
echo 'v1' > "$T/code/app.txt"
C="$(cy start ev)"; P="$(cy phase totals)"
cat > "$P/brief.md" <<'MD'
# Phase 1: Totals for AcmeCorp

## Builds
Invoice totals for acmecorp (Project Falcon).

## Done when
- Totals round to the cent
- The PDF matches the screen

## Evidence required
MD
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 'no evidence yet' <<< "$out" && ok "evidence: none yet is incomplete (exit 1)" || no "evidence none: rc=$rc $out"
cy evidence stamp >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "evidence stamp: needs a manifest first (exit 2)" || no "stamp without manifest: rc=$rc"
mkdir -p "$P/evidence"; echo png > "$P/evidence/pdf.png"
cat > "$P/evidence/manifest.json" <<'JSON'
{"open_app":"bin/dev, then /invoices/1","items":[
 {"done_when":"Totals round to the cent","status":"verified","proof":"test/invoice_test.rb:12"},
 {"done_when":"The PDF matches the screen","status":"could-not-verify","proof":"evidence/pdf.png"}]}
JSON
cy evidence stamp >/dev/null 2>&1
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q 'matches the current diff' <<< "$out" && grep -q '? could-not-verify' <<< "$out" && ok "evidence: complete and current (could-not-verify is reported, not passed off)" || no "evidence complete: rc=$rc $out"
git -C "$T/code" add -A && git -C "$T/code" -c user.email=t@e -c user.name=t commit -q -m "phase work"
cy evidence stamp >/dev/null 2>&1
[ "$(jq -r .base "$P/evidence/manifest.json")" = "$(jq -r .base "$P/phase.json")" ] && ok "evidence stamped after a commit still measures from the phase's start" || no "evidence base: $(jq -r .base "$P/evidence/manifest.json")"
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "evidence: committing the phase's work keeps it current (measured from the phase's base)" || no "evidence after commit: rc=$rc $out"
echo 'v2' > "$T/code/app.txt"
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 'STALE' <<< "$out" && ok "evidence: an edit after stamping makes it stale" || no "evidence stale: rc=$rc $out"
cy evidence stamp >/dev/null 2>&1
rm "$P/evidence/pdf.png"
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 'missing file: evidence/pdf.png' <<< "$out" && ok "evidence: a missing proof file is incomplete" || no "evidence missing file: rc=$rc $out"
echo png > "$P/evidence/pdf.png"
jq '.items[0].status="failing"' "$P/evidence/manifest.json" > "$T/m" && cat "$T/m" > "$P/evidence/manifest.json"
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 'failing' <<< "$out" && ok "evidence: a failing item blocks" || no "evidence failing: rc=$rc"
jq '.items |= [.[0]] | .items[0].status="verified"' "$P/evidence/manifest.json" > "$T/m" && cat "$T/m" > "$P/evidence/manifest.json"
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 'no evidence *The PDF matches the screen' <<< "$out" && ok "evidence: a done-when item with no entry blocks" || no "evidence missing item: rc=$rc $out"

echo png > "$P/evidence/pdf.png"
cat > "$P/evidence/manifest.json" <<'JSON'
{"open_app":"bin/dev, then /invoices/1","items":[
 {"done_when":"Totals round to the cent","status":"verified","proof":"test/invoice_test.rb:12"},
 {"done_when":"The PDF matches the screen","status":"verified","proof":"evidence/pdf.png"}]}
JSON
cy evidence stamp >/dev/null 2>&1
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "evidence: complete again after re-stamping" || no "re-stamp: rc=$rc $out"
echo different > "$P/evidence/pdf.png"
out="$(cy evidence 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q 'changed since it was stamped: evidence/pdf.png' <<< "$out" && ok "evidence: a proof file replaced after stamping is caught" || no "replaced proof: rc=$rc $out"
echo png > "$P/evidence/pdf.png"
cy report >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -e "$P/report-client.md" ] && ok "report: refused before approval" || no "report early: rc=$rc"
printf '{"findings":[{"severity":"critical","file":"app.rb","line":3,"summary":"rounding bug"}]}' > "$P/review.json"
approve "$P" approve
jq '.comment = "Internal: AcmeCorp asked for this" | .approver = "pat"' "$P/approval.json" > "$T/a" && cat "$T/a" > "$P/approval.json"
out="$(cy report 2>&1)"; rc=$?
CR="$P/report-client.md"; IR="$P/report-internal.md"
[ "$rc" = 0 ] && [ -f "$CR" ] && [ -f "$IR" ] && ok "report: writes internal and client reports after approval" || no "report: rc=$rc $out"
! grep -qi 'acmecorp\|project falcon' "$CR" && grep -q '▇▇▇' "$CR" && ok "client report: deny strings redacted, case-insensitively" || no "client leak: $(cat "$CR")"
! grep -q 'rounding bug\|pat\|Internal:' "$CR" && ok "client report: no findings, approver or comment" || no "client has internal detail: $(cat "$CR")"
grep -q 'rounding bug' "$IR" && grep -q 'Internal: AcmeCorp asked' "$IR" && ok "internal report: keeps findings and the comment" || no "internal missing detail"
cy evidence stamp >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "evidence stamp: refused on an approved phase (its evidence is frozen)" || no "stamp on approved: rc=$rc"
[ "$(cy status | awk '$1 == "1-totals" {print $2}')" = approve ] && ok "an approved phase stays approved after a refused re-stamp" || no "approval lost after stamp attempt"
cp "$P/evidence/pdf.png" "$T/pdf.keep"; echo swapped > "$P/evidence/pdf.png"
[ "$(cy status | awk '$1 == "1-totals" {print $2}')" = approve-unverified ] && ok "replacing a proof file after approval un-verifies the approval" || no "swapped proof still approved"
cp "$T/pdf.keep" "$P/evidence/pdf.png"
# a deny phrase hard-wrapped across lines is still redacted
printf '{"cycles":{"deny":["Project Falcon","Red"]}}' > "$T/code/.claude/harness.json"
cp "$P/brief.md" "$T/brief.keep"
printf '# Phase 1: Totals\n\n## Builds\nThe invoice screen for Project\nFalcon, rebuilt for Red and RED.\n\n## Done when\n- Totals round to the cent\n- The PDF matches the screen\n' > "$P/brief.md"
cy report >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "report: refused once the approved brief has changed" || no "report after brief edit: rc=$rc"
cp "$P/approval.json" "$T/approval.keep"; approve "$P" approve
out="$(cy report 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! grep -qi 'falcon' "$CR" && ! grep -qiw 'red' "$CR" && ok "client report: a name wrapped across lines and a short deny word are both redacted" || no "wrapped/short deny: rc=$rc $(cat "$CR" 2>/dev/null) $out"
cp "$T/brief.keep" "$P/brief.md"; cp "$T/approval.keep" "$P/approval.json"
# a deny name in slug form (dashes) is redacted too
printf '{"cycles":{"deny":["Project Falcon"]}}' > "$T/code/.claude/harness.json"
cp "$P/brief.md" "$T/brief.keep2"; cp "$P/approval.json" "$T/approval.keep2"
sed -i.bak '1s/.*/# Phase 1: project-falcon-export/' "$P/brief.md" && rm -f "$P/brief.md.bak"; approve "$P" approve
out="$(cy report 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! grep -qi 'falcon' "$CR" && ok "client report: a deny name in slug form is redacted" || no "slug deny: rc=$rc $(head -1 "$CR" 2>/dev/null)"
cp "$T/brief.keep2" "$P/brief.md"; cp "$T/approval.keep2" "$P/approval.json"

out="$(cy evidence-items "$C" "$(basename "$P")" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! grep -q 'matches the current diff' <<< "$out" && grep -q 'verified' <<< "$out" && ok "evidence-items: statuses without the diff check" || no "evidence-items: rc=$rc $out"
printf '{"cycles":{"deny":"AcmeCorp"}}' > "$T/code/.claude/harness.json"; rm -f "$CR"
cy report >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -e "$CR" ] && ok "report: a deny that isn't a list is refused (no unredacted client report)" || no "deny string: rc=$rc"
rm -rf "$T"

echo
if [ "$fail" = 0 ]; then echo "OK: cycle tests passed ($pass)."; exit 0; else echo "FAIL: $fail cycle test(s), $pass passed." >&2; exit 1; fi
