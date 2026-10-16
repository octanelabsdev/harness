#!/usr/bin/env bash
# SessionStart hook — make the harness skills auto-ENGAGE, not just auto-list.
#
# Skills are invocation-gated: at session start Claude Code only REGISTERS them (availability), it
# does not APPLY them (activation). Without a nudge the operator has to type /harness:<name> before a
# skill shapes the response. This hook injects a directive so the model invokes the right skill on its
# own the moment a trigger fires. It changes model behavior only — it cannot call a skill itself.
#
# Fires once per session at SessionStart with the full directive. (It previously ALSO fired a terse
# reminder on every UserPromptSubmit; that was dropped — the per-prompt injection added up over a long
# session, and the SessionStart directive plus the auto-listed skills carry the reminder.)
#
# Informational/behavioral, so it defaults ON (like session_banner) — set components.skill_nudge
# to false in .claude/harness.json to silence it for a project.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"

[ "$(hcfg '.components."skill_nudge"' 'true')" = "false" ] && exit 0

cat >/dev/null 2>&1 || true   # drain stdin; this hook fires only at SessionStart and takes no input

read -r -d '' msg <<'EOF' || true
HARNESS SKILLS — invoke proactively; availability ≠ activation. These plugin skills are listed but do
NOT auto-apply. Invoke the matching one yourself via the Skill tool the moment its trigger fires — do
not wait to be asked and do not require a /command:
  • guardrails      → before your first file edit, on a failed command/test, before claiming
                      done/passing/complete or committing, when touching a language trap, when
                      calling a code path live or sizing its cost, when concluding code is
                      wrong/dead or planning on how an external system behaves, when following
                      existing code as the pattern, or when planning/delegating or adding
                      anything beyond the ask
  • product-manager → when deciding what to work on next, triaging a backlog/board, or routing
                      ready work to an engineer
  • story-writer    → when creating or refining a work item / ticket / story before implementation
EOF

printf '%s\n' "$msg"
esc="$(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)"
[ -n "$esc" ] && printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
exit 0
