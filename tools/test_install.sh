#!/usr/bin/env bash
# test_install.sh — behavior tests for the installer's rails MCP wiring: the app is registered in
# projects.yml, the user-scope server is used (never a project .mcp.json entry), and a missing
# server gets a `claude mcp add --scope user` line with an absolute path, never a version-manager shim.
#
# Each case runs install.sh against a throwaway HOME and a PATH holding only fakes plus jq/python3,
# so nothing on this machine is read or written. Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$HERE/../install.sh"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }
has()   { grep -qF -- "$2" <<< "$1" && ok "$3" || no "$3 — output lacked: $2"; }
lacks() { grep -qF -- "$2" <<< "$1" && no "$3 — output had: $2" || ok "$3"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-installtest.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# fresh <case> -> sets H (fake HOME), APP (target project), BIN (fake PATH dir)
fresh() {
  H="$ROOT/$1/home"; APP="$ROOT/$1/app"; BIN="$ROOT/$1/bin"
  mkdir -p "$H" "$APP" "$BIN"
  for t in jq python3; do ln -s "$(command -v "$t")" "$BIN/$t"; done
  printf '#!/bin/sh\nexit 1\n' > "$BIN/mise"; chmod +x "$BIN/mise"
}
user_rails() { printf '{"mcpServers":{"rails":{"command":"/opt/rails-mcp-server","args":["--mode","stdio"]}}}\n' > "$H/.claude.json"; }
install() { env -u CLAUDE_CONFIG_DIR HOME="$H" PATH="$BIN:/usr/bin:/bin" "$BASH" "$INSTALL" --stack rails --no-plugin --yes "$@" "$APP" 2>&1; }
PFILE() { printf '%s' "$H/.config/rails-mcp/projects.yml"; }

echo "rails MCP wiring:"

fresh user-scope; user_rails
out="$(install)"
has "$out" "using your user-scope 'rails' server" "user-scope server present -> used"
[ ! -e "$APP/.mcp.json" ] && ok "no project .mcp.json written" || no "project .mcp.json was written"
lacks "$out" 'gem "rails-mcp-server"' "no add-the-gem suggestion"
grep -qxF "\"app\": \"$APP\"" "$(PFILE)" && ok "app registered in projects.yml" || no "app missing from projects.yml: $(cat "$(PFILE)" 2>/dev/null)"
has "$out" "mcp         : user-scope 'rails' server" "summary reports the user-scope server"
out="$(install)"
has "$out" "already registered" "re-run -> reports existing registration"
[ "$(grep -c "$APP" "$(PFILE)")" = 1 ] && ok "re-run -> no duplicate projects.yml entry" || no "duplicate projects.yml entries"

fresh standalone
printf '#!/bin/sh\n' > "$BIN/rails-mcp-server"; chmod +x "$BIN/rails-mcp-server"
out="$(install)"
has "$out" "claude mcp add --scope user rails -- $BIN/rails-mcp-server --mode stdio" "no user-scope server -> prints add line with the absolute path"
has "$out" "NOT configured" "summary flags the missing server"

fresh shim
mkdir -p "$ROOT/shim/shims" "$ROOT/shim/real"
printf '#!/bin/sh\n' > "$ROOT/shim/shims/rails-mcp-server"; printf '#!/bin/sh\n' > "$ROOT/shim/real/rails-mcp-server"
chmod +x "$ROOT/shim/shims/rails-mcp-server" "$ROOT/shim/real/rails-mcp-server"
out="$(env -u CLAUDE_CONFIG_DIR HOME="$H" PATH="$BIN:$ROOT/shim/shims:/usr/bin:/bin" "$BASH" "$INSTALL" --stack rails --no-plugin --yes "$APP" 2>&1)"
lacks "$out" "/shims/rails-mcp-server --mode" "a shim on PATH is never offered"
has "$out" "no standalone 'rails-mcp-server' found" "shim only, no mise -> install hint"
printf '#!/bin/sh\necho %s\n' "$ROOT/shim/real/rails-mcp-server" > "$BIN/mise"
out="$(env -u CLAUDE_CONFIG_DIR HOME="$H" PATH="$BIN:$ROOT/shim/shims:/usr/bin:/bin" "$BASH" "$INSTALL" --stack rails --no-plugin --yes "$APP" 2>&1)"
has "$out" "-- $ROOT/shim/real/rails-mcp-server --mode stdio" "shim on PATH -> resolved through mise to the real install"

fresh shadow; user_rails
printf '{"mcpServers":{"rails":{"command":"bundle","args":["exec","rails-mcp-server"]}}}\n' > "$APP/.mcp.json"
out="$(install)"
has "$out" "WARN: .mcp.json has a 'rails' entry" "existing project entry -> override warning"

fresh collision; user_rails
mkdir -p "$H/.config/rails-mcp"; printf 'app: "/somewhere/else"' > "$(PFILE)"
out="$(install)"
has "$out" "WARN: 'app' in" "name taken by another path -> warning"
[ "$(wc -l < "$(PFILE)" | tr -d ' ')" = 0 ] && ok "name taken -> projects.yml untouched" || no "projects.yml changed on a name collision"

fresh newline; user_rails
mkdir -p "$H/.config/rails-mcp"; printf 'other: "/x"' > "$(PFILE)"
install >/dev/null
[ "$(sed -n 2p "$(PFILE)")" = "\"app\": \"$APP\"" ] && ok "file without a trailing newline -> entry on its own line" || no "bad append: $(cat "$(PFILE)")"

fresh nomcp; user_rails
out="$(install --no-mcp)"
[ ! -e "$(PFILE)" ] && ok "--no-mcp -> projects.yml not touched" || no "--no-mcp wrote projects.yml"
has "$out" "mcp         : skipped (--no-mcp)" "--no-mcp -> summary says skipped"

echo
if [ "$fail" = 0 ]; then echo "OK: install tests passed ($pass)."; else echo "FAIL: $fail install test(s) failed ($pass passed)." >&2; exit 1; fi
