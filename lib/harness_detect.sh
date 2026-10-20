#!/usr/bin/env bash
# Stack detection shared by the installer and the auto-bootstrap hook.
#
# Echoes exactly one stack name that matches a stacks/<name>.json preset:
#   rails | go | python | node | generic
# Detection is by on-disk markers, most specific first. A Rails app also carries a package.json,
# so Rails is checked before node; plain Ruby (no Rails) falls through to generic (no ruby preset).

harness_detect_stack() { # <dir> -> echoes stack name
  local d="${1:-$PWD}"

  if { [ -f "$d/Gemfile" ] && grep -qE "gem ['\"]rails['\"]" "$d/Gemfile" 2>/dev/null; } \
     || [ -f "$d/bin/rails" ] || [ -f "$d/config/application.rb" ]; then
    printf '%s' rails; return
  fi

  [ -f "$d/go.mod" ] && { printf '%s' go; return; }

  if [ -f "$d/pyproject.toml" ] || [ -f "$d/requirements.txt" ] \
     || [ -f "$d/setup.py" ] || [ -f "$d/Pipfile" ]; then
    printf '%s' python; return
  fi

  [ -f "$d/package.json" ] && { printf '%s' node; return; }

  printf '%s' generic
}

# Rails suites come in two shapes; read which one this repo has instead of assuming Minitest.
harness_rails_test_command() { # <dir> -> echoes the suite command
  local d="${1:-$PWD}"
  if [ -d "$d/spec" ] && { grep -qE '^ +rspec-rails( |$)' "$d/Gemfile.lock" 2>/dev/null \
       || grep -qE "gem ['\"]rspec-rails['\"]" "$d/Gemfile" 2>/dev/null; }; then
    printf '%s' 'bundle exec rspec'
  else
    printf '%s' 'bin/rails test'
  fi
}

# stack.test_command as the gate should run it: "auto" is resolved for the configured stack.name on every
# call, any other value is used as written. "auto" on a stack with no resolver resolves to "".
harness_resolve_test_command() { # <dir> <configured> <stack name> -> echoes the command
  local d="$1" tc="$2" stack="$3"
  [ "$tc" = auto ] || { printf '%s' "$tc"; return; }
  case "$stack" in
    rails) harness_rails_test_command "$d" ;;
  esac
}

# Hooks inherit Claude Code's environment, whose Ruby may not be the one .ruby-version pins, so run
# under the pinned version when mise already has it installed. `mise where` never installs, so a machine
# whose Ruby comes from rbenv/chruby/asdf keeps running the command unchanged.
harness_wrap_ruby() { # <dir> <command> -> echoes the command to run
  local d="$1" cmd="$2" v=""
  [ -f "$d/.ruby-version" ] && v="$(tr -d '[:space:]' < "$d/.ruby-version")"
  v="${v#ruby-}"
  if [ -n "$v" ] && command -v mise >/dev/null 2>&1 && mise where "ruby@$v" >/dev/null 2>&1; then
    printf 'mise exec ruby@%s -- bash -c %q' "$v" "$cmd"
  else
    printf '%s' "$cmd"
  fi
}

# A runner that reports only zero-test summaries verified nothing. Reads Minitest ("N runs,") and RSpec
# ("N examples,") summary lines; output with no summary line, or any summary above zero, is not zero.
harness_ran_zero_tests() { # <test output> -> exit 0 when every summary line reports 0 tests
  local counts
  counts="$(printf '%s\n' "$1" | grep -oE '(^|[^0-9])[0-9]+ (runs|examples?), ' | grep -oE '[0-9]+' || true)"
  [ -n "$counts" ] && ! grep -qv '^0$' <<< "$counts"
}
