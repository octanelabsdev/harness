#!/usr/bin/env bash
# install.sh — wire the harness into a project. Interactive by default; flag-driven for scripts/CI.
#
# The harness is a Claude Code PLUGIN; this installer sets up the parts a plugin can't:
#   - .claude/harness.json  (which components are active + your stack profile)
#   - plugin enablement in .claude/settings.json (safe: references the versioned plugin, not $HOME scripts)
#   - optionally, a generic global ruleset in your active config home
# It does NOT install agents — agents are Bring-Your-Own (.claude/agents/).
#
# Usage:
#   ./install.sh [TARGET]                                   # interactive
#   ./install.sh --stack rails --yes [TARGET]              # non-interactive, all gates on (warn)
#   ./install.sh --stack node --components session_banner,verification_gate --local --yes .
#
# Flags:
#   --stack NAME        one of: $(ls stacks | sed 's/.json//' | tr '\n' ' ') — or a path to a custom stack JSON
#   --components LIST    comma list of: session_banner,skill_nudge,verification_gate,pipeline_gate,review_gate  (default: the first four; review_gate is opt-in)
#   --local             enablement/config in .claude/settings.local.json (just you) instead of committed settings.json
#   --no-plugin         don't touch settings — only write .claude/harness.json
#   --ref REF           pin the marketplace to this git tag/branch (default: v<plugin.json version>)
#   --sha SHA           also record this commit sha (note: only the ref is enforced via settings→startup)
#   --no-sha            don't auto-resolve a commit sha for a version-tag ref (ref only)
#   --no-mcp            don't write .mcp.json even if the stack declares MCP servers
#   --mcp-download      download any missing MCP guide resources (default: just nudge)
#   --tomes-dir PATH    set env.TOMES_DIR (EPUB bookshelf) in your config home
#   --global            also install the generic global-CLAUDE.md into your config home
#   --migrate           first clean a legacy (pre-plugin) install: committed hooks/settings, symlinked
#                       agents, committed shelf/guardrail copies. Dry-run unless --apply is also passed.
#   --apply             with --migrate, actually perform the cleanup (backs up what it removes)
#   --yes               accept defaults, no prompts
set -euo pipefail

BUNDLE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MKT_NAME="harness"; MKT_REPO="octanelabsdev/harness"   # this repo, self-referencing marketplace
ALL_COMPONENTS=(session_banner skill_nudge verification_gate pipeline_gate)
. "$BUNDLE/lib/harness_detect.sh"   # harness_detect_stack — shared with the auto-bootstrap hook

# --- args ---
TARGET=""; STACK=""; COMPONENTS=""; SCOPE="project"; DO_PLUGIN=1; DO_GLOBAL=""; ASSUME_YES=""; PIN_REF=""; PIN_SHA=""; DO_SHA=1; DO_MCP=1; DO_MCP_DOWNLOAD=0; TOMES_VAL=""; DO_MIGRATE=0; MIG_APPLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --migrate) DO_MIGRATE=1; shift;;
    --apply) MIG_APPLY=1; shift;;
    --stack) STACK="$2"; shift 2;;
    --components) COMPONENTS="$2"; shift 2;;
    --local) SCOPE="local"; shift;;
    --no-plugin) DO_PLUGIN=0; shift;;
    --ref) PIN_REF="$2"; shift 2;;
    --sha) PIN_SHA="$2"; shift 2;;
    --no-sha) DO_SHA=0; shift;;
    --no-mcp) DO_MCP=0; shift;;
    --mcp-download) DO_MCP_DOWNLOAD=1; shift;;
    --tomes-dir) TOMES_VAL="$2"; shift 2;;
    --global) DO_GLOBAL=1; shift;;
    --yes|-y) ASSUME_YES=1; shift;;
    -h|--help) sed -n '2,28p' "$0"; exit 0;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *) TARGET="$1"; shift;;
  esac
done
TARGET="${TARGET:-$PWD}"
[ -d "$TARGET" ] || { echo "error: target is not a directory: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || echo "note: $TARGET is not a git repo — the hooks use git and will stay inert until it is." >&2

# Pin the marketplace to a release tag (default: v<plugin.json version>) rather than a moving branch. A
# ref-pinned marketplace does NOT auto-update (verified 2026-09-25: pinning a ref drops the autoUpdate
# flag), so a later force-push of a branch can't flow arbitrary hook code to everyone on their next
# session. Moving to a newer release is then a deliberate step — see /harness:update.
if [ -z "$PIN_REF" ]; then
  _ver="$(jq -r '.version // empty' "$BUNDLE/.claude-plugin/plugin.json" 2>/dev/null)"
  [ -n "$_ver" ] && PIN_REF="v$_ver"
fi

# We also record the tag's commit sha in the source. HONESTY NOTE (verified 2026-09-25, CLI 2.1.283):
# only the `ref` is observably enforced through the settings→startup reconcile — the sha did NOT propagate
# to the machine cache, so the effective guarantee is TAG-LEVEL, not commit-level. A force-re-cut tag
# upstream could still be pulled on the next reload; the real mitigation is protecting your release tags +
# account 2FA. We still write the sha (harmless; may be honored at the initial `marketplace add` checkout).
# Auto-resolve it for a version tag (vN.N.N); leave a branch/channel ref (main, stable, …) at ref-only so
# it can still move. An explicit --sha always wins; --no-sha opts out. Offline -> ref only (never hard-fail).
if [ "$DO_PLUGIN" = 1 ] && [ -n "$PIN_REF" ] && [ -z "$PIN_SHA" ] && [ "$DO_SHA" = 1 ] \
   && printf '%s' "$PIN_REF" | grep -qE '^v[0-9]'; then
  PIN_SHA="$(git ls-remote "https://github.com/$MKT_REPO" "$PIN_REF" "$PIN_REF^{}" 2>/dev/null \
    | awk '$2 ~ /\^\{\}$/ {peeled=$1} $2 !~ /\^\{\}$/ {plain=$1} END {print (peeled != "" ? peeled : plain)}')"
  [ -n "$PIN_SHA" ] || echo "  note: could not resolve a commit sha for $PIN_REF (offline, or tag not pushed yet) — pinning ref only" >&2
fi

ask() { # ask <prompt> <default>  -> echoes answer
  local a; if [ -n "$ASSUME_YES" ]; then printf '%s' "$2"; return; fi
  read -r -p "$1" a </dev/tty || true; printf '%s' "${a:-$2}"
}
yesno() { local a; a="$(ask "$1 [$2] " "$2")"; case "$a" in [Yy]*) return 0;; *) return 1;; esac; }

echo "── harness installer ──  target: $TARGET"

# --- 0. (optional) migrate off a legacy, pre-plugin install ---
if [ "$DO_MIGRATE" = 1 ]; then
  . "$BUNDLE/lib/harness_migrate.sh"
  echo "  scanning for a legacy harness install…"
  harness_migrate_scan "$TARGET"
  if harness_migrate_report; then
    if [ "$MIG_APPLY" = 1 ]; then
      harness_migrate_apply "$TARGET"
    else
      echo "  (dry-run — re-run with --migrate --apply to clean, then install continues)"
      [ -n "$ASSUME_YES" ] || yesno "  continue with install anyway?" "y" || exit 0
    fi
  fi
fi

# --- 1. stack (auto-detected from the target's on-disk markers; overridable) ---
DETECTED="$(harness_detect_stack "$TARGET")"
if [ -z "$STACK" ] && [ -z "$ASSUME_YES" ]; then
  echo "Stack presets: $(ls "$BUNDLE"/stacks | sed 's/.json//' | tr '\n' ' ')  (or 'custom')"
  STACK="$(ask "Choose a stack [$DETECTED]: " "$DETECTED")"
fi
STACK="${STACK:-$DETECTED}"
if [ "$STACK" = "custom" ]; then
  impl="$(ask 'implementation dirs (comma) [src,lib]: ' 'src,lib')"
  ui="$(ask 'UI dirs (comma, blank ok): ' '')"
  td="$(ask 'test dir [test]: ' 'test')"
  otd="$(ask 'operator/e2e test dir (blank ok): ' '')"
  tc="$(ask 'test command (blank ok): ' '')"
  to_arr() { printf '%s' "$1" | tr ',' '\n' | sed '/^$/d' | jq -R . | jq -s .; }
  STACK_JSON="$(jq -n --arg n custom --argjson impl "$(to_arr "$impl")" --argjson uid "$(to_arr "$ui")" \
    --arg td "$td" --arg otd "$otd" --arg tc "$tc" \
    '{name:$n, impl_dirs:$impl, ui_dirs:$uid, test_dir:$td, operator_test_dir:$otd, test_command:$tc}')"
else
  sfile="$BUNDLE/stacks/$STACK.json"; [ -f "$STACK" ] && sfile="$STACK"
  [ -f "$sfile" ] || { echo "error: no stack preset '$STACK' (have: $(ls "$BUNDLE"/stacks | sed 's/.json//' | tr '\n' ' '))" >&2; exit 1; }
  STACK_JSON="$(cat "$sfile")"
fi
echo "  stack: $(printf '%s' "$STACK_JSON" | jq -r '.name')  impl=$(printf '%s' "$STACK_JSON" | jq -c '.impl_dirs')"

# --- 2. components (the enforceable hooks) ---
declare -A ON
# review_gate is opt-in (needs a configured reviewer + the blind-review skill) — off unless explicitly picked.
if [ -n "$COMPONENTS" ]; then
  for c in "${ALL_COMPONENTS[@]}" review_gate; do ON[$c]=false; done
  IFS=',' read -r -a picked <<< "$COMPONENTS"; for c in "${picked[@]}"; do ON[$c]=true; done
else
  for c in "${ALL_COMPONENTS[@]}"; do
    if yesno "Activate $c?" y; then ON[$c]=true; else ON[$c]=false; fi
  done
  if yesno "Activate review_gate? (needs a reviewer + the blind-review skill; advanced)" n; then ON[review_gate]=true; else ON[review_gate]=false; fi
fi
COMPS_JSON="$(jq -n --argjson sb "${ON[session_banner]}" --argjson sn "${ON[skill_nudge]}" --argjson vg "${ON[verification_gate]}" --argjson pg "${ON[pipeline_gate]}" --argjson rg "${ON[review_gate]}" \
  '{session_banner:$sb, skill_nudge:$sn, verification_gate:$vg, pipeline_gate:$pg, review_gate:$rg}')"

# --- 3. write .claude/harness.json ---
cdir="$TARGET/.claude"; mkdir -p "$cdir"
jq -n --argjson c "$COMPS_JSON" --argjson s "$STACK_JSON" '{components:$c, stack:$s}' > "$cdir/harness.json"
echo "  wrote .claude/harness.json"

# --- 4. enable the plugin (safe committed reference, or --local) ---
if [ "$DO_PLUGIN" = 1 ]; then
  settings="$cdir/settings.json"; [ "$SCOPE" = "local" ] && settings="$cdir/settings.local.json"
  python3 - "$settings" "$MKT_NAME" "$MKT_REPO" "$PIN_REF" "$PIN_SHA" <<'PY'
import json, os, sys
p, mkt, repo, ref, sha = (sys.argv + ["", ""])[1:6]
s = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) > 0 else {}
src = {"source": "github", "repo": repo}
if ref:
    src["ref"] = ref
if sha:
    src["sha"] = sha   # recorded for completeness; effective pin is tag-level (sha not enforced via settings→startup — protect your tags)
# assign (not setdefault) so re-running re-pins an existing/older/unpinned entry
s.setdefault("extraKnownMarketplaces", {})[mkt] = {"source": src}
s.setdefault("enabledPlugins", {})[f"{mkt}@{mkt}"] = True
with open(p, "w") as f:
    json.dump(s, f, indent=2); f.write("\n")
where = (f"pinned {ref}" + (f"@{sha[:12]}" if sha else "")) if ref else "UNPINNED — tracks default branch!"
print(f"  enabled plugin {mkt}@{mkt} in {os.path.basename(p)} ({where})")
PY
else
  echo "  (skipped plugin enablement — run /plugin marketplace add $MKT_REPO && /plugin install $MKT_NAME@$MKT_NAME yourself)"
fi

# --- 4b. per-stack MCP servers (committed .mcp.json), if the stack declares any ---
mcp="$(printf '%s' "$STACK_JSON" | jq -c '.mcp // empty')"
if [ -n "$mcp" ] && [ "$DO_MCP" = 1 ]; then
  # A project entry shadows a same-named user-scope server, so a working global install must win.
  skip=()
  for name in $(printf '%s' "$mcp" | jq -r 'keys[]'); do
    if command -v claude >/dev/null 2>&1 && (cd "$TARGET" && claude mcp get "$name" 2>/dev/null) | grep -q 'Scope: User'; then
      echo "  mcp: '$name' already configured at user scope — not writing it to .mcp.json"
      skip+=("$name")
    elif printf '%s' "$mcp" | jq -e --arg n "$name" '.[$n].args // [] | index("rails-mcp-server")' >/dev/null \
         && [ -f "$TARGET/Gemfile" ] && ! grep -q 'rails-mcp-server' "$TARGET/Gemfile"; then
      echo "  mcp: '$name' needs the gem before 'bundle exec rails-mcp-server' can start — add to your Gemfile:  gem \"rails-mcp-server\", group: :development (not written)"
      skip+=("$name")
    fi
  done
  mcp="$(printf '%s' "$mcp" | jq -c --args 'with_entries(select(.key | IN($ARGS.positional[]) | not))' ${skip[@]+"${skip[@]}"})"
  if [ "$mcp" != "{}" ]; then
    python3 - "$TARGET/.mcp.json" "$mcp" <<'PY'
import json, os, sys
p, mcp = sys.argv[1], json.loads(sys.argv[2])
s = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) > 0 else {}
srv = s.setdefault("mcpServers", {})
for k, v in mcp.items():
    srv[k] = v
with open(p, "w") as f:
    json.dump(s, f, indent=2); f.write("\n")
print("  wrote .mcp.json ground-truth server(s):", ", ".join(mcp.keys()))
PY
  fi
elif [ -n "$mcp" ]; then
  echo "  (skipped MCP wiring per --no-mcp; stack declares: $(printf '%s' "$mcp" | jq -r 'keys|join(", ")'))"
fi

# --- 4c. MCP guide resources (machine-level, shared across repos): check + nudge, or download ---
guides="$(printf '%s' "$STACK_JSON" | jq -c '.mcp_guides // empty')"
if [ -n "$guides" ] && [ "$DO_MCP" = 1 ]; then
  rdir="$HOME/$(printf '%s' "$guides" | jq -r '.resources_dir')"
  dl="$(printf '%s' "$guides" | jq -r '.download_cmd')"
  missing=()
  while IFS= read -r lib; do
    [ -n "$lib" ] || continue
    [ -d "$rdir/$lib" ] || missing+=("$lib")
  done < <(printf '%s' "$guides" | jq -r '.libs[]?')
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "  mcp guides: all present in $rdir"
  elif [ "$DO_MCP_DOWNLOAD" = 1 ]; then
    if command -v "$dl" >/dev/null 2>&1; then
      for lib in "${missing[@]}"; do echo "  downloading guide resource: $lib"; "$dl" "$lib" >/dev/null 2>&1 || echo "    (failed: $lib)"; done
    else
      echo "  mcp guides: '$dl' not on PATH — install the MCP server, then: $dl ${missing[*]}"
    fi
  else
    echo "  mcp guides MISSING (${missing[*]}) — one-time per machine, run:  $dl ${missing[*]}   (or re-run install with --mcp-download)"
  fi
fi

# --- 5. optional generic global ruleset ---
if [ -z "$DO_GLOBAL" ] && [ -z "$ASSUME_YES" ]; then yesno "Install the generic global-CLAUDE.md into your config home?" n && DO_GLOBAL=1; fi
if [ -n "$DO_GLOBAL" ]; then
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; mkdir -p "$cfg"
  dest="$cfg/CLAUDE.md"
  if [ -f "$dest" ]; then
    echo "  NOTE: $dest already exists — not overwriting. Template is at $BUNDLE/templates/global-CLAUDE.md"
  else
    cp "$BUNDLE/templates/global-CLAUDE.md" "$dest"; echo "  installed global ruleset -> $dest"
  fi
fi

# --- 6. TOMES_DIR for the bookshelf skill (per-machine/profile; written to the config home's env) ---
if [ -z "$TOMES_VAL" ] && [ -z "$ASSUME_YES" ]; then
  TOMES_VAL="$(ask 'Path(s) to your EPUB reference shelf for the bookshelf skill (colon-separated, blank to skip): ' '')"
fi
if [ -n "$TOMES_VAL" ]; then
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; mkdir -p "$cfg"
  python3 - "$cfg/settings.json" "$TOMES_VAL" <<'PY'
import json, os, sys
p, val = sys.argv[1], sys.argv[2]
s = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) > 0 else {}
s.setdefault("env", {})["TOMES_DIR"] = val
with open(p, "w") as f:
    json.dump(s, f, indent=2); f.write("\n")
print(f"  set env.TOMES_DIR in {p}")
PY
fi

# --- summary ---
active="$(printf '%s' "$COMPS_JSON" | jq -r 'to_entries|map(select(.value))|map(.key)|join(", ")')"
cat <<EOF

✔ harness wired into $TARGET
  stack       : $(printf '%s' "$STACK_JSON" | jq -r '.name')
  gates active: ${active:-none (all off)}
  plugin      : $([ "$DO_PLUGIN" = 1 ] && echo "enabled ($SCOPE scope, marketplace pinned ${PIN_REF:-UNPINNED}${PIN_SHA:+@${PIN_SHA:0:12}})" || echo "not enabled")
  mcp         : $( [ -n "$(printf '%s' "$STACK_JSON" | jq -c '.mcp // empty')" ] && { [ "$DO_MCP" = 1 ] && { [ "$mcp" != "{}" ] && echo ".mcp.json written ($(printf '%s' "$mcp" | jq -r 'keys|join(", ")'))" || echo "not written (user-scope server or missing gem)"; } || echo "skipped (--no-mcp)"; } || echo "none for this stack")
  agents      : Bring-Your-Own — put your agents in .claude/agents/ (none shipped)
  skills      : guardrails, story-writer, product-manager, bookshelf, blind-review come with the plugin
  commands    : /harness:init, /harness:agents, /harness:status, /harness:doctor
  bookshelf   : $( [ -n "${TOMES_VAL:-}" ] && echo "TOMES_DIR set in config home" || echo "set TOMES_DIR (env) to use the EPUB bookshelf — see docs/agents.md" )

Next: restart Claude Code (or /config) so it picks up the plugin, then open a session —
the SessionStart banner reports the harness state. Gates run in WARN mode; promote with
'touch .claude/.pipeline-block' (pipeline) or edit the verification gate's tail.
EOF
