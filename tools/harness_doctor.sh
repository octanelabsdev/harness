#!/usr/bin/env bash
# harness_doctor.sh — health check: is every needed piece present and wired so Cleetus gives a full
# experience? Deterministic (no live network/process probing). Exit 0 = healthy (warnings allowed),
# exit 2 = a hard gap. Usable in CI / pre-push.
set -uo pipefail
shopt -s nullglob
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../hooks/_harness_lib.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
repo="$(harness_repo)"; cd "$repo" 2>/dev/null || true
fail=0; warn=0
ok()   { printf '  ✔ %s\n' "$1"; }
bad()  { printf '  ✘ %s\n' "$1" >&2; fail=1; }
note() { printf '  ! %s\n' "$1"; warn=1; }

echo "── Cleetus doctor ──  repo: $repo"
echo "                     plugin: $PLUGIN"

# 1. plugin hook wiring + every referenced hook script exists
HF="$PLUGIN/hooks/hooks.json"
if [ -f "$HF" ] && jq -e '.hooks | objects | keys | length > 0' "$HF" >/dev/null 2>&1; then
  ok "hooks.json valid, events: $(jq -r '.hooks|keys|join(", ")' "$HF")"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    f="$(printf '%s' "$ref" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN#g")"
    [ -f "$f" ] && ok "hook script present: ${f#"$PLUGIN"/}" || bad "hook script MISSING: $ref"
  done < <(jq -r '.hooks[][].hooks[].command' "$HF" 2>/dev/null | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}[^"]*\.sh')
else
  bad "hooks.json missing or has no events"
fi

# 2. tool scripts exist (+ executable for *.sh)
echo "tools:"
for t in tools/review_verify.sh tools/dor_lint.rb tools/ci.sh tools/test_hooks.sh tools/tome.sh \
         tools/check_shipped_paths.sh tools/smoke_load.sh tools/harness_status.sh tools/harness_doctor.sh \
         tools/harness_update.sh; do
  if [ -f "$PLUGIN/$t" ]; then
    case "$t" in
      *.sh) [ -x "$PLUGIN/$t" ] && ok "$t" || note "$t present but not executable (chmod +x)";;
      *)    ok "$t";;
    esac
  else
    bad "$t MISSING"
  fi
done

# 3. review-gate assets (needed only if enabled anywhere; check presence regardless)
[ -f "$PLUGIN/skills/blind-review/SKILL.md" ] && ok "blind-review skill present" || bad "blind-review skill MISSING"
[ -f "$PLUGIN/tools/review-findings.schema.json" ] && ok "review-findings schema present" || bad "review-findings schema MISSING"

# 4. this project's config
echo "project:"
cfg="$(harness_cfg)"
if [ -z "$cfg" ]; then
  note "no .claude/harness.json — harness is inert here; run /harness:init"
else
  jq -e . "$cfg" >/dev/null 2>&1 && ok "harness.json valid JSON" || bad "harness.json invalid JSON"
  missing=""; while IFS= read -r d; do [ -n "$d" ] && [ ! -d "$d" ] && missing="$missing $d"; done < <(stack_dirs impl_dirs)
  [ -z "$missing" ] && ok "impl_dirs all exist" || note "impl_dirs declared but not present:$missing"
  if component_on verification_gate; then
    tc="$(hcfg '.stack.test_command' '')"
    [ -n "$tc" ] && ok "verification_gate on + test_command set" || note "verification_gate on but test_command is empty (nothing to run)"
  fi
  if [ "$(hcfg '.components."review_gate"' 'false')" = "true" ]; then
    if [ -d .claude/agents ] && ls .claude/agents/*.md >/dev/null 2>&1; then ok "review_gate on + a reviewer agent is present"; else bad "review_gate on but no reviewer in .claude/agents (BYO a reviewer)"; fi
  fi
  # A user-scope MCP server (rails-mcp-server). Fall back to the stack preset so installs from before
  # the stack declared it are checked too.
  srv="$(jq -c '.stack.mcp_user // empty' "$cfg" 2>/dev/null)"
  sname="$(hcfg '.stack.name' '')"
  [ -z "$srv" ] && [ -n "$sname" ] && [ -f "$PLUGIN/stacks/$sname.json" ] && srv="$(jq -c '.mcp_user // empty' "$PLUGIN/stacks/$sname.json" 2>/dev/null)"
  if [ -n "$srv" ]; then
    sv_name="$(jq -r '.name' <<< "$srv")"; sv_bin="$(jq -r '.bin' <<< "$srv")"
    pfile="$HOME/$(jq -r '.projects_file' <<< "$srv")"
    user_cfg="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"; user_cfg="${user_cfg:-$HOME/.claude.json}"
    if [ -f "$user_cfg" ] && jq -e --arg n "$sv_name" '.mcpServers // {} | has($n)' "$user_cfg" >/dev/null 2>&1; then
      ok "user-scope '$sv_name' MCP server configured"
    else
      note "no user-scope '$sv_name' MCP server — re-run the installer for the 'claude mcp add --scope user' line"
    fi
    registered=0; phys="$(pwd -P)"
    if [ -f "$pfile" ]; then
      while IFS= read -r line; do
        v="${line#*:}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; v="${v#[\"\']}"; v="${v%[\"\']}"
        [ "$v" = "$repo" ] || [ "$v" = "$phys" ] && { registered=1; break; }
      done < <(grep -v '^[[:space:]]*#' "$pfile")
    fi
    [ "$registered" = 1 ] && ok "project registered in $pfile" || note "project not in $pfile — the '$sv_name' server can't see it; re-run the installer"
    if [ -f .mcp.json ] && jq -e --arg b "$sv_bin" '[.mcpServers // {} | .[] | select(.command == "bundle" and ((.args // []) | index($b)))] | length > 0' .mcp.json >/dev/null 2>&1; then
      note ".mcp.json runs $sv_bin through bundle exec, which overrides the user-scope server — remove that entry and the gem (docs/troubleshooting.md)"
    fi
  fi
fi

echo "releases:"
note_ver="$(jq -r '.version // "?"' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null)"
echo "  → loaded v$note_ver — run /harness:update --check for a newer release (network check; not run here)"

echo
if [ "$fail" != 0 ]; then
  echo "FAIL: Cleetus has gaps — see the ✘ lines above." >&2; exit 2
elif [ "$warn" != 0 ]; then
  echo "OK (with warnings): Cleetus is functional; the ! lines are worth addressing."; exit 0
else
  echo "OK: Cleetus is healthy — all hooks, scripts, schema, and config in place."; exit 0
fi
