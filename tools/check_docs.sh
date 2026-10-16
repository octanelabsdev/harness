#!/usr/bin/env bash
# check_docs.sh — a branch that changes harness behavior must change its docs in the same branch.
#
# Behavior: install.sh, hooks/, lib/, tools/ (tests excluded), skills/, stacks/, commands/.
# Docs: docs/ and README.md. A branch with nothing to document says why in a commit message line:
#   Docs-Not-Needed: <reason>
# Compares the branch (plus uncommitted work) with its merge base on origin/main (override with
# DOCS_BASE). On main itself, or with no base to compare against, there is nothing to check.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

base_ref="${DOCS_BASE:-origin/main}"
base="$(git merge-base HEAD "$base_ref" 2>/dev/null)" || { echo "OK: no $base_ref to compare against — docs check skipped"; exit 0; }
changed="$( { git diff --name-only "$base" HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)"

code="$(grep -E '^(install\.sh|hooks/|lib/|tools/|skills/|stacks/|commands/)' <<< "$changed" | grep -vE '^tools/test_[^/]*\.sh$')"
if [ -z "$code" ]; then echo "OK: no behavior changes on this branch"; exit 0; fi
if grep -qE '^(docs/|README\.md$)' <<< "$changed"; then echo "OK: behavior changes come with doc changes"; exit 0; fi
msgs="$(git log --format=%B "$base..HEAD")"
if grep -qE '^Docs-Not-Needed: .+' <<< "$msgs"; then echo "OK: Docs-Not-Needed: $(grep -m1 -E '^Docs-Not-Needed: ' <<< "$msgs" | cut -d' ' -f2-)"; exit 0; fi

echo "FAIL: behavior changed but no docs did:" >&2
sed 's/^/  /' <<< "$code" >&2
echo "Update docs/ or README.md, or add 'Docs-Not-Needed: <reason>' to a commit message." >&2
exit 1
