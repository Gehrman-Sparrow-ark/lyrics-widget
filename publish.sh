#!/usr/bin/env bash
# Publish a package staged by release.sh to GitHub. Run it only when you mean to publish.
#   1. creates an immutable versioned release (vX-REL) with the package and checksums
#   2. uploads the package to the "repo" pacman-feed release and checks the download
#   3. only then replaces the feed database, and checks that download too
#   4. keeps the newest two packages on the feed so machines with a stale database still work
set -euo pipefail

die() { echo "publish.sh: $*" >&2; exit 1; }

case "${1:-}" in
    -h|--help)
        printf 'Usage: bash publish.sh [stage-directory]\nPublishes the newest dist/*-stage made by release.sh.\n'
        exit 0 ;;
esac
(( $# <= 1 )) || { echo 'Usage: bash publish.sh [stage-directory]' >&2; exit 2; }

for tool in gh git sha256sum curl; do
    command -v "$tool" >/dev/null || die "$tool is required."
done
gh auth status >/dev/null 2>&1 || die "Run 'gh auth login' first."

src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "$src"

if (( $# == 1 )); then
    stage="$1"
else
    stage="$(ls -dt "$src"/dist/lyrics-widget-*-stage 2>/dev/null | head -n 1 || true)"
fi
[[ -n "${stage:-}" && -d "$stage" ]] || die "No staged release found. Run: bash release.sh"
stage="$(cd -- "$stage" && pwd -P)"

for f in SHA256SUMS SOURCE-SHA256SUMS PROVENANCE.txt lyrics-widget.db lyrics-widget.files; do
    [[ -f "$stage/$f" ]] || die "$stage/$f is missing."
done
( cd -- "$stage" && sha256sum --check --strict SHA256SUMS >/dev/null ) || die "Checksum check failed. Rebuild with release.sh."

prov() { sed -n "s/^$1=//p" "$stage/PROVENANCE.txt" | head -n 1; }
package="$(prov package)"
[[ -f "$stage/$package" ]] || die "Package $package is missing from $stage."
[[ "$(prov source_tree)" == clean ]] || die "The package was built from uncommitted changes. Commit, push, then run release.sh again."
base="$(prov base_commit)"
head="$(git rev-parse HEAD)"
[[ "$base" == "$head" ]] || die "The package was built from ${base:0:7} but you are on ${head:0:7}. Run release.sh again."
git fetch -q origin
git merge-base --is-ancestor "$head" origin/main || die "Push your commit to origin/main first (git push)."

if [[ ! "$package" =~ ^lyrics-widget-(.+)-([^-]+)-([^-]+)\.pkg\.tar\.[a-z]+$ ]]; then
    die "Cannot read the version from $package."
fi
tag="v${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
slug="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
[[ -n "$slug" ]] || die "Could not determine the GitHub repository."

if gh release view "$tag" >/dev/null 2>&1; then
    die "Release $tag already exists. Versioned releases are immutable: raise pkgver or pkgrel and rebuild."
fi

echo "Publishing $package to $slug"
gh release create "$tag" --target "$head" --title "lyrics-widget ${tag#v}" \
    --notes "Arch package ${package}. Verify with SHA256SUMS." \
    "$stage/$package" "$stage/SHA256SUMS" "$stage/SOURCE-SHA256SUMS" "$stage/PROVENANCE.txt"

if ! gh release view repo >/dev/null 2>&1; then
    gh release create repo --title "pacman repo" \
        --notes "Pacman feed for lyrics-widget. Files here change with each release; use the vX-Y releases for fixed copies."
fi

verify_download() {
    local name="$1" want got tries=0 tmp
    want="$(sha256sum < "$stage/$name" | cut -d' ' -f1)"
    tmp="$(mktemp)"
    while :; do
        if curl -fsSL --retry 2 -o "$tmp" "https://github.com/$slug/releases/download/repo/$name" 2>/dev/null; then
            got="$(sha256sum < "$tmp" | cut -d' ' -f1)"
            [[ "$got" == "$want" ]] && { rm -f "$tmp"; return 0; }
        fi
        tries=$(( tries + 1 ))
        if (( tries >= 6 )); then
            rm -f "$tmp"
            die "$name downloaded from the feed does not match the staged file. The feed was not fully updated."
        fi
        sleep "${PUBLISH_RETRY_SLEEP:-5}"
    done
}

gh release upload repo "$stage/$package" --clobber
verify_download "$package"
gh release upload repo "$stage/lyrics-widget.db" "$stage/lyrics-widget.files" --clobber
verify_download lyrics-widget.db
verify_download lyrics-widget.files

mapfile -t pkgs < <(gh release view repo --json assets -q '.assets[].name' | grep -E '^lyrics-widget-.*\.pkg\.tar\.zst$' | sort -V || true)
if (( ${#pkgs[@]} > 2 )); then
    for old in "${pkgs[@]:0:${#pkgs[@]}-2}"; do
        gh release delete-asset repo "$old" -y
        echo "Removed old feed package $old"
    done
fi

echo
echo "Published $tag. Machines update with:  sudo pacman -Syu  then  lyrics-widget-setup"
