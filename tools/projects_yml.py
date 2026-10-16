#!/usr/bin/env python3
"""Read and append rails-mcp-server's projects.yml (flat `name: "path"` lines) without PyYAML.

  projects_yml.py has FILE PATH              exit 0 and print the name if PATH is registered, else 1
  projects_yml.py register FILE NAME PATH    add PATH as NAME unless it's already there; always exit 0

The file is shared by every app on the machine, so a line this can't parse is left alone, and
paths are compared by realpath so a symlinked checkout matches its registration.
"""
import json, os, sys


def scalar(raw):
    raw = raw.strip()
    if raw.startswith('"'):
        try:
            return json.JSONDecoder().raw_decode(raw)[0]
        except ValueError:
            return raw.strip('"')
    if raw.startswith("'"):
        end = raw.find("'", 1)
        return raw[1:end] if end > 0 else raw[1:]
    return raw.split(" #", 1)[0].strip()


def split(line):
    s = line.strip()
    if s[:1] == '"':
        try:
            key, end = json.JSONDecoder().raw_decode(s)
        except ValueError:
            return None
    elif s[:1] == "'":
        end = s.find("'", 1) + 1
        if end == 0:
            return None
        key = s[1:end - 1]
    else:
        key, sep, value = s.partition(":")
        return (key.strip(), value) if sep else None
    rest = s[end:].lstrip()
    return (key, rest[1:]) if rest.startswith(":") else None


def entries(p):
    out = {}
    if not os.path.exists(p):
        return out
    with open(p, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.lstrip().startswith("#"):
                continue
            kv = split(line)
            if kv:
                out[kv[0]] = scalar(kv[1])
    return out


def same(a, b):
    return a == b or os.path.realpath(a) == os.path.realpath(b)


def find(p, path):
    return next((k for k, v in entries(p).items() if v and same(v, path)), None)


def main(argv):
    if len(argv) == 3 and argv[0] == "has":
        name = find(argv[1], argv[2])
        if name is None:
            return 1
        print(name)
        return 0
    if len(argv) == 4 and argv[0] == "register":
        p, key, path = argv[1:]
        known = find(p, path)
        current = entries(p)
        if known is not None:
            print(f"  mcp: project already registered in {p} as '{known}'")
        elif key in current:
            print(f"  WARN: '{key}' in {p} points at {current[key]} — add this project under another name: <name>: {json.dumps(path, ensure_ascii=False)}")
        else:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            tail = open(p, "rb").read()[-1:] if os.path.exists(p) else b""
            with open(p, "a", encoding="utf-8") as f:
                f.write(("\n" if tail not in (b"", b"\n") else "")
                        + f"{json.dumps(key, ensure_ascii=False)}: {json.dumps(path, ensure_ascii=False)}\n")
            print(f"  mcp: registered this project in {p} as '{key}'")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
