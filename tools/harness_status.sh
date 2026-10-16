#!/usr/bin/env bash
# harness_status.sh — inventory of what Cleetus is providing in THIS project. Read-only; always exit 0.
# The SessionStart banner is a one-line summary; this is the full "what's loaded/configured" view.
set -uo pipefail
shopt -s nullglob
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../hooks/_harness_lib.sh"
repo="$(harness_repo)"; cd "$repo" 2>/dev/null || true
cfg="$(harness_cfg)"

echo "── Cleetus status ──  $repo"

if [ -n "$cfg" ]; then
  echo "config:            .claude/harness.json  (stack: $(hcfg '.stack.name' 'unknown'))"
else
  echo "config:            NOT configured — run /harness:init"
fi

echo "components:"
for c in session_banner skill_nudge verification_gate pipeline_gate review_gate; do
  def=false; case "$c" in session_banner|skill_nudge) def=true;; esac
  printf '  %-18s %s\n' "$c" "$(hcfg ".components.\"$c\"" "$def")"
done

if [ -n "$cfg" ]; then
  echo "stack profile:"
  printf '  %-18s %s\n' impl_dirs      "$(jq -rc '.stack.impl_dirs // []' "$cfg")"
  printf '  %-18s %s\n' ui_dirs        "$(jq -rc '.stack.ui_dirs // []' "$cfg")"
  printf '  %-18s %s\n' test_command   "$(hcfg '.stack.test_command' '(none)')"
  printf '  %-18s %s\n' operator_test  "$(hcfg '.stack.operator_test_dir' '(none)')"
fi

if [ -d .claude/agents ]; then
  a=(.claude/agents/*.md); n=${#a[@]}; broken=0
  for l in "${a[@]}"; do [ -e "$l" ] || broken=$((broken+1)); done
  line="$n present"; [ "$broken" -gt 0 ] && line="$line ($broken BROKEN symlink(s))"
  echo "agents:            $line  (.claude/agents/)"
else
  echo "agents:            none (BYO — no .claude/agents/)"
fi
[ -n "$cfg" ] && { b="$(jq -rc '.stack.agents_bundle.repo // empty' "$cfg" 2>/dev/null)"; [ -n "$b" ] && echo "  default bundle:  $b"; }

sv="$(hcfg '.stack.mcp_user.name' '')"
preset="$HERE/../stacks/$(hcfg '.stack.name' '').json"
[ -z "$sv" ] && [ -n "$cfg" ] && [ -f "$preset" ] && sv="$(jq -r '.mcp_user.name // empty' "$preset" 2>/dev/null)"
if [ -f .mcp.json ]; then
  echo "MCP servers:       $(jq -rc '(.mcpServers // {}) | keys | join(", ") | if .=="" then "(.mcp.json has none)" else . end' .mcp.json 2>/dev/null)  (.mcp.json)"
elif [ -n "$cfg" ] && [ "$(jq -r '(.stack.mcp // {}) | length' "$cfg" 2>/dev/null)" != "0" ]; then
  echo "MCP servers:       $(jq -rc '.stack.mcp | keys | join(", ")' "$cfg")  (declared by stack; no .mcp.json yet — run /harness:init)"
elif [ -z "$sv" ]; then
  echo "MCP servers:       none configured"
fi
if [ -n "$sv" ]; then
  ucfg="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"; ucfg="${ucfg:-$HOME/.claude.json}"
  if [ -f "$ucfg" ] && jq -e --arg n "$sv" '.mcpServers // {} | has($n)' "$ucfg" >/dev/null 2>&1; then
    echo "MCP (user scope):  $sv  (configured)"
  else
    echo "MCP (user scope):  $sv  NOT configured — /harness:doctor"
  fi
fi

if [ -n "$cfg" ]; then
  rd="$(hcfg '.stack.mcp_guides.resources_dir' '')"
  if [ -n "$rd" ]; then
    full="$HOME/$rd"
    if [ -d "$full" ]; then
      echo "MCP guides:        $full ($(ls "$full" 2>/dev/null | wc -l | tr -d ' ') present); libs: $(jq -rc '.stack.mcp_guides.libs // [] | join(", ")' "$cfg")"
    else
      echo "MCP guides:        none downloaded ($full missing) — $(hcfg '.stack.mcp_guides.download_cmd' 'download cmd') <lib>"
    fi
  fi
fi

if [ -n "${TOMES_DIR:-}" ] && [ -d "${TOMES_DIR:-}" ]; then
  echo "bookshelf:         TOMES_DIR=$TOMES_DIR ($(find "$TOMES_DIR" -maxdepth 3 -iname '*.epub' 2>/dev/null | wc -l | tr -d ' ') epub(s))"
elif [ -n "${TOMES_DIR:-}" ]; then
  echo "bookshelf:         TOMES_DIR set but missing ($TOMES_DIR)"
else
  echo "bookshelf:         TOMES_DIR unset (bookshelf skill falls back / labels unverified)"
fi

echo "session markers:"
found=0
for m in "current-story.yaml|DoR story" ".small-fix|pipeline bypass" ".pipeline-block|pipeline block" ".verification-warn|verify warn-only" ".review/current.json|review artifact"; do
  p=".claude/${m%%|*}"; d="${m##*|}"
  [ -e "$p" ] && { printf '  %-28s present (%s)\n' "$p" "$d"; found=1; }
done
[ "$found" = 0 ] && echo "  (none)"
exit 0
