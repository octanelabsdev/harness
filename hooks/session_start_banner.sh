#!/usr/bin/env bash
# SessionStart hook — deterministic harness-status banner (environment-verified).
# Reports the ACTIVE config home's global CLAUDE.md, the harness config state, and the
# project's BYO agents. Honors CLAUDE_CONFIG_DIR so work/personal configs never cross-read.
set -uo pipefail
shopt -s nullglob
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"

# Informational; shown unless explicitly disabled in the config.
[ "$(hcfg '.components."session_banner"' 'true')" = "false" ] && exit 0

repo="$(harness_repo)"; cd "$repo" 2>/dev/null || true

global="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"
if [ -f "$global" ]; then g="present ($(wc -l < "$global" | tr -d ' ') lines)"; else g="MISSING"; fi

# Agents are BYO — count the project's own .claude/agents/*.md, of any kind.
if [ -d .claude/agents ]; then
  links=(.claude/agents/*.md); n=${#links[@]}; broken=0
  for l in "${links[@]}"; do [ -e "$l" ] || broken=$((broken + 1)); done
  agents="$n agent(s)"; [ "$broken" -gt 0 ] && agents="$agents, $broken BROKEN"
  [ "$n" -eq 0 ] && agents="none (BYO — none present)"
else
  agents="none (BYO — no .claude/agents/)"
fi

cfg="$(harness_cfg)"
if [ -n "$cfg" ]; then
  stack="$(hcfg '.stack.name' 'unknown')"
  comps="$(jq -r '.components | to_entries | map(select(.value==true)) | map(.key) | join(", ")' "$cfg" 2>/dev/null)"
  cfgline="configured (stack: $stack; active: ${comps:-none})"
elif [ -n "$(harness_implicit_profile)" ]; then
  cfgline="no .claude/harness.json — using the detected '$(hcfg '.stack.name' 'generic')' preset in memory (commit gate enforcing, verification gate warn-only)"
else
  cfgline="NOT configured (run the harness installer)"
fi

read -r -d '' banner <<EOF || true
HARNESS CHECK (SessionStart hook — environment-verified, not model memory):
  global CLAUDE.md : $g
  harness          : $cfgline
  agents (BYO)     : $agents
EOF

# One JSON object: systemMessage is what the operator sees, additionalContext is what the model gets.
# Any other text on stdout makes Claude Code treat the whole thing as raw model-only context.
jq -nc --arg b "$banner" \
  '{systemMessage: $b, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $b}}'
