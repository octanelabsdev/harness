#!/usr/bin/env bash
# Shared helpers for the harness hooks.
#
# The harness is CONFIG-DRIVEN and STACK-AGNOSTIC. Each project carries
# .claude/harness.json (written by the interactive installer) that declares which
# components are active and the stack's conventions:
#
#   { "components": { "session_banner": true, "verification_gate": true, "pipeline_gate": true },
#     "stack": { "name": "rails",
#                "impl_dirs": ["app","lib","db/migrate"],
#                "ui_dirs": ["app/views","app/controllers"],
#                "test_dir": "test", "operator_test_dir": "test/system",
#                "test_command": "bin/rails test" } }
#
# With no config in a git repo, the detected stack's preset is used in memory (see
# harness_implicit_profile); outside a git repo the enforcing gates stay inert. Nothing is
# hardcoded to any one stack — the gates read impl_dirs / ui_dirs / operator_test_dir
# / test_command from the profile.

# Repo root of the project the hook is acting on.
harness_repo() {
  git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null \
    || printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}"
}

# Path to the project's harness config, or empty if none.
harness_cfg() {
  local repo; repo="$(harness_repo)"
  [ -f "$repo/.claude/harness.json" ] && printf '%s' "$repo/.claude/harness.json"
}

# With no harness.json in a git repo, the detected stack's preset stands in, held in memory so nothing
# is written to the repo. The commit gate enforces and the verification gate only warns, so a repo
# nobody configured still can't ship an untested tree.
harness_implicit_profile() {
  local repo stack preset root
  repo="$(harness_repo)"
  git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  declare -F harness_detect_stack >/dev/null || . "$root/lib/harness_detect.sh"
  stack="$(harness_detect_stack "$repo")"
  preset="$root/stacks/$stack.json"; [ -f "$preset" ] || preset="$root/stacks/generic.json"
  [ -f "$preset" ] || return 0
  jq -c '{implicit: true, components: {verification_gate: true, commit_gate: true}, stack: .}' "$preset" 2>/dev/null
}

# The config the hooks act on: harness.json if present, else the implicit profile, else nothing.
harness_cfg_json() {
  if [ -n "${_harness_cfg_dir:-}" ] && [ "$_harness_cfg_dir" = "${CLAUDE_PROJECT_DIR:-$PWD}" ]; then
    printf '%s' "$_harness_cfg_json"; return
  fi
  local cfg; cfg="$(harness_cfg)"
  if [ -n "$cfg" ]; then cat "$cfg" 2>/dev/null; else harness_implicit_profile; fi
}

# A hook on a hot path (every Bash call) reads the config once instead of once per hcfg.
harness_load_cfg() {
  _harness_cfg_json="$(harness_cfg_json)"; _harness_cfg_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
}

# The verification gate warns instead of blocking: opted down with the marker, or running implicitly.
harness_verification_warn() {
  [ -f "$(harness_repo)/.claude/.verification-warn" ] && return 0
  [ -z "$(harness_cfg)" ] && [ -n "$(harness_implicit_profile)" ]
}

# jq read with a default. Usage: hcfg '.stack.test_command' 'bin/rails test'
# Note: we do NOT use jq's `//` operator — it treats a literal `false` as empty, which would make a
# `components.<x>: false` toggle silently fall back to its default. Read the value raw and treat only
# jq's `null` (missing key) and the empty string as "absent → use default"; `false` is preserved.
hcfg() {
  local json; json="$(harness_cfg_json)"
  if [ -z "$json" ]; then printf '%s' "${2:-}"; return; fi
  local v; v="$(printf '%s' "$json" | jq -r "${1}" 2>/dev/null)"
  if [ -n "$v" ] && [ "$v" != "null" ]; then printf '%s' "$v"; else printf '%s' "${2:-}"; fi
}

# Component toggle. Enforcing gates default OFF when unconfigured (safe/inert).
# Usage: component_on verification_gate   (pass a default as $2 to override)
component_on() {
  [ "$(hcfg ".components.\"$1\"" "${2:-false}")" = "true" ]
}

# Newline list of dirs for a stack key (impl_dirs, ui_dirs).
stack_dirs() {
  local json; json="$(harness_cfg_json)"; [ -n "$json" ] || return 0
  printf '%s' "$json" | jq -r ".stack.$1[]? // empty" 2>/dev/null
}

# Is a repo-relative path under any dir listed for <key>?
path_under() {  # path_under <rel-path> <key>
  local rel="$1" key="$2" d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$rel" in "$d"/*|"$d") return 0 ;; esac
  done < <(stack_dirs "$key")
  return 1
}

# Green test runs, recorded per working-tree hash so a gate can tell a tested tree from an untested
# one. The record lives in the git common dir, shared by every worktree and never committed.
harness_pass_file() { # harness_pass_file <repo>
  local common; common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s' "$common/harness-test-passes"
}

# The working tree as it stands, untracked files in and ignored files out; a throwaway index keeps the
# real one untouched. .claude/ is left out, as review_verify.sh does: it holds config, markers and the
# review artifact, and writing a review must not make a tested tree look untested.
harness_worktree_tree() { # harness_worktree_tree <repo>
  local idx rc=0 tree
  idx="$(mktemp "${TMPDIR:-/tmp}/harness-index.XXXXXX")" || return 1
  # No real index yet (nothing ever staged): an empty file isn't a valid index, so let git start one.
  cp "$(git -C "$1" rev-parse --path-format=absolute --git-path index)" "$idx" 2>/dev/null || rm -f "$idx"
  tree="$(GIT_INDEX_FILE="$idx" git -C "$1" add -A 2>/dev/null &&
          GIT_INDEX_FILE="$idx" git -C "$1" rm -r -q --cached --ignore-unmatch -- .claude >/dev/null 2>&1 &&
          GIT_INDEX_FILE="$idx" git -C "$1" write-tree 2>/dev/null)" || rc=1
  rm -f "$idx"
  [ "$rc" = 0 ] && [ -n "$tree" ] && printf '%s' "$tree"
}

# HEAD's committed tree, keyed the same way (.claude/ left out) so it matches a recorded pass.
harness_head_tree() { # harness_head_tree <repo>
  local idx rc=0 tree
  idx="$(mktemp "${TMPDIR:-/tmp}/harness-index.XXXXXX")" || return 1
  rm -f "$idx"
  tree="$(GIT_INDEX_FILE="$idx" git -C "$1" read-tree HEAD 2>/dev/null &&
          GIT_INDEX_FILE="$idx" git -C "$1" rm -r -q --cached --ignore-unmatch -- .claude >/dev/null 2>&1 &&
          GIT_INDEX_FILE="$idx" git -C "$1" write-tree 2>/dev/null)" || rc=1
  rm -f "$idx"
  [ "$rc" = 0 ] && [ -n "$tree" ] && printf '%s' "$tree"
}

harness_has_pass() { # harness_has_pass <repo> <tree> <test_command>
  local f; f="$(harness_pass_file "$1")" || return 1
  [ -f "$f" ] && grep -qxF "$2"$'\t'"$3" "$f"
}

harness_record_pass() { # harness_record_pass <repo> <tree> <test_command>
  local f; f="$(harness_pass_file "$1")" || return 0
  [ -n "$2" ] && printf '%s\t%s\n' "$2" "$3" >> "$f" 2>/dev/null
  return 0
}
