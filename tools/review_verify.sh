#!/usr/bin/env bash
# review_verify.sh — deterministically verify a blind-review findings artifact against the CURRENT diff.
#
# A Stop hook cannot spawn the reviewer (hooks can't call the Agent tool), so the gate cannot RUN the
# review — it verifies the artifact the review wrote. This checker ties the artifact to the exact
# current tree and refuses a review that doesn't engage with the real changed lines.
#
# Modes:
#   review_verify.sh --emit-sha          print sha256 of the reviewed diff (the tree vs HEAD). The review
#                                        stamps it into the artifact as diff_sha.
#   review_verify.sh --emit-base         print the full sha of HEAD. The review stamps it as base.
#   review_verify.sh [artifact-path]     verify the artifact (default .claude/.review/current.json):
#     exit 0 = valid artifact AND verdict:pass                              -> allow the stop
#     exit 1 = valid artifact AND verdict:changes-requested (critical)      -> block, surface findings
#     exit 2 = missing / malformed / stale / a finding cites a non-diff line -> block
#
# Committing reviewed work: with a base stamped, the gate re-renders the current tree against base, so
# the reviewed changes can be committed (in any number of commits) and the artifact stays fresh. Any
# edit after the review, committed or not, changes the rendering and makes it stale. The rendering is
# independent of where a change sits in history: tracked changes since base (renames split into
# delete + add), then every file added since base — committed, staged or untracked — as an add-diff in
# path order. An artifact without a full-sha base (legacy) is checked against the uncommitted diff only,
# exactly as before, so it goes stale once committed.
#
# jq is the only dependency (already required by the hooks). No ruby. Run from the repo root.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "review: jq is required but not on PATH" >&2; exit 2; }

# .claude/ is excluded from every rendering — it holds config + markers, including this review artifact
# itself; including it would make writing the review change the very diff the review records.

# Legacy rendering: tracked changes vs HEAD, then untracked files as add-diffs (no index mutation).
uncommitted_diff() {
  git diff HEAD -- . ':(exclude).claude'
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && git diff --no-index -- /dev/null "$f" 2>/dev/null
  done < <(git ls-files --others --exclude-standard -- . ':(exclude).claude')
}

# base_diff <commit> — the tree vs base, rendered the same whether the changes are committed or not.
base_diff() {
  git diff --no-renames --diff-filter=a "$1" -- . ':(exclude).claude'
  local f
  while IFS= read -r -d '' f; do
    git diff --no-index -- /dev/null "$f" 2>/dev/null
  done < <({ git diff -z --name-only --no-renames --diff-filter=A "$1" -- . ':(exclude).claude'
             git ls-files -z --others --exclude-standard -- . ':(exclude).claude'; } | LC_ALL=C sort -zu)
}

reviewed_diff() { if [ -n "${BASE:-}" ]; then base_diff "$BASE"; else uncommitted_diff; fi; }
sha_cmd()  { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; }
diff_sha() { reviewed_diff | sha_cmd | awk '{print $1}'; }

case "${1:-}" in
  --emit-sha)  BASE="$(git rev-parse --verify HEAD)" || exit 2; diff_sha; exit 0 ;;
  --emit-base) git rev-parse --verify HEAD; exit $? ;;
esac

ART="${1:-.claude/.review/current.json}"
[ -f "$ART" ] || { echo "review: no review artifact at $ART — run the code-review skill on this diff" >&2; exit 2; }
jq -e . "$ART" >/dev/null 2>&1 || { echo "review: $ART is not valid JSON" >&2; exit 2; }
jq -e '(.diff_sha|type=="string") and (.verdict|type=="string") and (.findings|type=="array")' "$ART" >/dev/null 2>&1 \
  || { echo "review: artifact missing required diff_sha/verdict/findings" >&2; exit 2; }
verdict="$(jq -r '.verdict' "$ART")"
case "$verdict" in pass|changes-requested) ;; *) echo "review: invalid verdict '$verdict'" >&2; exit 2 ;; esac

# Only a full commit sha pins a review; a symbolic ref like HEAD or main moves, so it is treated as legacy.
BASE="$(jq -r '.base // empty | strings' "$ART")"
if [[ "$BASE" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
  git rev-parse -q --verify "$BASE^{commit}" >/dev/null \
    || { echo "review: artifact base $BASE is not a commit in this repo" >&2; exit 2; }
else
  BASE=""
fi

if [ "$(diff_sha)" != "$(jq -r '.diff_sha' "$ART")" ]; then
  echo "review: artifact is stale — it reviewed a different diff than the current tree (edit-after-review). Re-run the review." >&2
  exit 2
fi

# Set of file:new-line inside a changed hunk (added + context lines are citable; removed lines aren't).
changed_lines="$(reviewed_diff | awk '
  /^\+\+\+ / { f=$2; sub(/^b\//,"",f); next }
  /^@@ /     { hunk=$3; sub(/^\+/,"",hunk); split(hunk,a,","); ln=a[1]; next }
  /^-/       { next }
  /^\+/      { print f":"ln; ln++; next }
  /^ /       { print f":"ln; ln++; next }
')"
bad=0
while IFS= read -r fl; do
  [ -n "$fl" ] || continue
  # A here-string, not a pipe: grep -q exits on the first match, and under pipefail the producer's
  # SIGPIPE would fail the check and reject a valid citation on a large diff.
  grep -qxF -- "$fl" <<<"$changed_lines" \
    || { echo "review: finding cites $fl, which is not a changed line in the current diff" >&2; bad=1; }
done < <(jq -r '.findings[]? | "\(.file):\(.line)"' "$ART")
[ "$bad" = 0 ] || exit 2

if [ "$verdict" = pass ]; then exit 0; else
  echo "review: verdict=changes-requested — $(jq -r '[.findings[]?|select(.severity=="critical")]|length' "$ART") critical finding(s):" >&2
  jq -r '.findings[]? | select(.severity=="critical") | "  - \(.file):\(.line) \(.summary)"' "$ART" >&2
  exit 1
fi
