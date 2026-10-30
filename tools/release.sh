#!/usr/bin/env bash
# release.sh — cut a harness release from main, after the version-bump PR has merged.
#
#   tools/release.sh <vX.Y.Z> [notes-file]
#
# Checks first: HEAD is origin/main with a clean tree, plugin.json and the README pin both name the
# version, and tools/ci.sh is green. Then, each step skipped when it's already done, so a failed run
# can be re-run:
#   1. tag HEAD (annotated) and push the tag; ls-remote must show it on HEAD
#   2. create the GitHub Release, marked Latest; notes from the file, else GitHub's generated notes
#   3. deploy the docs from a detached worktree of HEAD (uvx mkdocs gh-deploy)
#   4. confirm GitHub's latest release is the tag; the docs header shows that version
# Needs git, jq, gh (authenticated) and uv. Exit 1 on the first failed step.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.." || exit 1

CI_CMD="${CI_CMD:-bash tools/ci.sh}"

[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
TAG="$1"; NOTES="${2:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "release: '$TAG' isn't vX.Y.Z" >&2; exit 2; }
[ -z "$NOTES" ] || [ -f "$NOTES" ] || { echo "release: no notes file at $NOTES" >&2; exit 2; }

die() { echo "  ✘ $*" >&2; exit 1; }
step() { echo "── $* ──"; }

step "preflight"
git fetch -q origin main gh-pages || die "could not fetch origin"
HEAD="$(git rev-parse HEAD)"
[ "$HEAD" = "$(git rev-parse origin/main)" ] || die "HEAD isn't origin/main; merge the bump PR and pull first"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes"
version="$(jq -r .version .claude-plugin/plugin.json)"
[ "v$version" = "$TAG" ] || die "plugin.json says $version, not ${TAG#v}"
grep -qF "\"ref\": \"$TAG\"" README.md || die "README pin isn't $TAG"
$CI_CMD > /dev/null 2>&1 || die "CI is red ($CI_CMD)"
echo "  ✔ ${HEAD:0:7} on origin/main, version $TAG, CI green"

step "tag"
remote_sha="$(git ls-remote origin "refs/tags/$TAG^{}" | cut -f1)"
if [ "$remote_sha" = "$HEAD" ]; then
  echo "  – $TAG already on origin at ${HEAD:0:7}"
elif [ -n "$remote_sha" ]; then
  die "$TAG is on origin at ${remote_sha:0:7}, not ${HEAD:0:7}; refusing to move a release tag"
else
  local_sha="$(git rev-parse -q --verify "refs/tags/$TAG^{commit}")"
  if [ -z "$local_sha" ]; then git tag -a "$TAG" -m "$TAG" || die "could not tag"
  elif [ "$local_sha" != "$HEAD" ]; then die "local $TAG points at ${local_sha:0:7}, not ${HEAD:0:7}"
  fi
  git push -q origin "refs/tags/$TAG" || die "could not push $TAG"
  [ "$(git ls-remote origin "refs/tags/$TAG^{}" | cut -f1)" = "$HEAD" ] || die "origin doesn't show $TAG on ${HEAD:0:7} after the push"
  echo "  ✔ pushed $TAG"
fi

step "GitHub release"
if gh release view "$TAG" > /dev/null 2>&1; then
  echo "  – release $TAG exists"
else
  if [ -n "$NOTES" ]; then notes=(--notes-file "$NOTES"); else notes=(--generate-notes); fi
  gh release create "$TAG" --verify-tag --latest --title "$TAG" "${notes[@]}" > /dev/null || die "gh release create failed"
  echo "  ✔ created release $TAG"
fi

step "docs"
if git log -1 --format=%s origin/gh-pages | grep -qF "Deploy docs ${HEAD:0:7}"; then
  echo "  – docs for ${HEAD:0:7} already deployed"
else
  tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"
  WORK="$(mktemp -d "${tmp:-/tmp}/harness-release.XXXXXX")"
  trap 'git worktree remove --force "$WORK/site" 2>/dev/null; rm -rf "$WORK"' EXIT
  git worktree add -q --detach "$WORK/site" "$HEAD" || die "could not create a docs worktree"
  (cd "$WORK/site" &&
    UV_CACHE_DIR="$WORK/uvc" UV_TOOL_DIR="$WORK/uvt" XDG_DATA_HOME="$WORK/xdg" \
    uvx --with-requirements requirements-docs.txt mkdocs gh-deploy --strict -m "Deploy docs {sha} for $TAG") \
    || die "mkdocs gh-deploy failed"
  git fetch -q origin gh-pages
  git log -1 --format=%s origin/gh-pages | grep -qF "Deploy docs ${HEAD:0:7}" || die "origin/gh-pages doesn't show the ${HEAD:0:7} deploy"
  echo "  ✔ deployed docs"
fi

step "verify"
latest="$(gh api 'repos/{owner}/{repo}/releases/latest' -q .tag_name)"
[ "$latest" = "$TAG" ] || die "GitHub's latest release is '$latest', not $TAG"
echo "  ✔ latest release is $TAG"
echo "Released $TAG."
