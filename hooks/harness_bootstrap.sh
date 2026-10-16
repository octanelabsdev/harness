#!/usr/bin/env bash
# SessionStart hook — auto-bootstrap .claude/harness.json when a project has none.
#
# The harness is a plugin, and a plugin has no install-time hook (verified against Claude Code docs):
# SessionStart is the earliest point plugin code runs inside a project. Without .claude/harness.json
# every gate is inert and the banner says NOT configured — the exact "installed but does nothing"
# trap. This closes it: on first session we detect the stack and write a sensible config so the
# harness works the moment the plugin is installed. It NEVER clobbers an existing config, only runs
# inside a git repo, writes harness.json alone (never committed settings), and can be opted out with
# HARNESS_NO_AUTOBOOTSTRAP=1.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"
. "$HERE/../lib/harness_detect.sh"

[ "${HARNESS_NO_AUTOBOOTSTRAP:-}" = "1" ] && exit 0

repo="$(harness_repo)"
git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0   # non-repo -> leave inert
[ -f "$repo/.claude/harness.json" ] && exit 0                        # already configured -> never clobber

stack="$(harness_detect_stack "$repo")"
preset="$HERE/../stacks/$stack.json"
[ -f "$preset" ] || { stack="generic"; preset="$HERE/../stacks/generic.json"; }
[ -f "$preset" ] || exit 0                                           # presets missing -> do nothing

# All components on, warn-first: the pipeline gate warns until .claude/.pipeline-block, and a
# .claude/.verification-warn marker (written below) keeps the verification gate in warn mode until the
# adopter opts into blocking by removing it.
comps='{"session_banner":true,"skill_nudge":true,"context_warning":true,"verification_gate":true,"pipeline_gate":true}'

mkdir -p "$repo/.claude"
if ! jq -n --argjson c "$comps" --slurpfile s "$preset" \
      '{components:$c, stack:$s[0]}' > "$repo/.claude/harness.json" 2>/dev/null; then
  rm -f "$repo/.claude/harness.json"   # don't leave a truncated/partial config behind
  exit 0
fi

# Warn-first for auto-configured repos: the verification gate blocks on a failing test_command by
# default, but a repo that never explicitly opted in shouldn't start blocking. Drop the warn marker.
: > "$repo/.claude/.verification-warn" 2>/dev/null || true

msg="HARNESS AUTO-BOOTSTRAP: no .claude/harness.json found — detected stack '$stack' and wrote one (all components on; gates in WARN mode). Customize it with /harness:init, add your agents with /harness:agents, or set HARNESS_NO_AUTOBOOTSTRAP=1 to opt out."
printf '%s\n' "$msg"
esc=$(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
[ -n "$esc" ] && printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
exit 0
