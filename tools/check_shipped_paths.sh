#!/usr/bin/env bash
# check_shipped_paths.sh — fail the build if shipped content carries author-local absolute paths.
#
# The harness installs onto other people's machines. A reference to a personal vault, a real
# /Users/<name> home, or the author's ~/Development bundle is dead on every adopter's box. This
# guard makes that whole class of bug build-failing instead of relying on someone remembering to grep.
# Run it before tagging a release (and optionally as a pre-push hook — see docs/troubleshooting.md).
#
#   bash tools/check_shipped_paths.sh   # exits 0 clean, 1 on any real hit
#
# Allowed: the documented placeholder /Users/you (e.g. in a TOMES_DIR example), and any line
# carrying the inline sentinel `shipped-path-ok` — for docs that must name the patterns themselves.

set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || { echo "not a git repo" >&2; exit 2; }

self="tools/check_shipped_paths.sh"
# Forbidden in any tracked (shipped) file. ERE.
pat='Obsidian Vault|Development/rails-agents|/Users/[a-z]'
# A line is exempt if it uses the documented /Users/you placeholder or carries the inline sentinel.
allow='/Users/you|shipped-path-ok'

hits=0
while IFS= read -r f; do
  [ "$f" = "$self" ] && continue          # the checker defines the patterns; don't scan it
  case "$f" in *.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf) continue;; esac
  while IFS= read -r line; do
    grep -Eq "$allow" <<< "$line" && continue
    echo "  $f:$line"
    hits=$((hits + 1))
  done < <(grep -nE "$pat" "$f" 2>/dev/null)
done < <(git ls-files)

if [ "$hits" -gt 0 ]; then
  echo "FAIL: $hits author-local path reference(s) in shipped content (above)." >&2
  echo "Fix: use \${CLAUDE_PLUGIN_ROOT}, \$HOME, or the documented /Users/you placeholder." >&2
  exit 1
fi
echo "OK: no author-local paths in shipped content ($(git ls-files | wc -l | tr -d ' ') files scanned)."
