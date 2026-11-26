#!/usr/bin/env bash
# Build and stage the Arch package. This script never publishes; run publish.sh for that.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        printf 'Usage: bash release.sh [output-directory]\nBuilds and stages the Arch package, feed files and hashes; never publishes (see publish.sh).\n'
        exit 0 ;;
esac
if (( $# > 1 )); then
    echo 'Usage: bash release.sh [output-directory]' >&2
    exit 2
fi

src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
out="${1:-$src/dist}"
inputs=(PKGBUILD lyrics-widget.install lyrics-widget-setup shell.qml lyrsearch lyrsave LICENSE release.sh)

for tool in makepkg repo-add sha256sum; do
    command -v "$tool" >/dev/null || { echo "$tool is required on Arch Linux." >&2; exit 1; }
done
# Report the actual source, including uncommitted edits to the packaged files.
source_commit="$(git -C "$src" rev-parse --verify HEAD 2>/dev/null || printf 'source-archive')"
source_state=source-archive
if [[ "$source_commit" != source-archive ]]; then
    source_state=clean
    if [[ -n "$(git -C "$src" status --porcelain --untracked-files=normal)" ]]; then
        source_state=modified
    fi
fi

mkdir -p -- "$out"
out="$(cd -- "$out" && pwd -P)"
work="$(mktemp -d "$out/.lyrics-widget-stage.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p -- "$work/source" "$work/packages" "$work/final"
for name in "${inputs[@]}"; do
    cp -p -- "$src/$name" "$work/source/$name"
done

(
    cd -- "$work/source"
    sha256sum -- "${inputs[@]}" > "$work/final/SOURCE-SHA256SUMS"
    export PKGDEST="$work/packages"
    # Clean sources are staged above. Missing dependencies must be installed separately.
    makepkg --cleanbuild
    # makepkg --packagelist can also list a -debug package that is never built; keep real files only.
    mapfile -t packages < <(makepkg --packagelist | while IFS= read -r listed; do
        [[ -f "$listed" ]] && printf '%s\n' "$listed"
    done)
    (( ${#packages[@]} == 1 )) || { echo 'Expected exactly one package.' >&2; exit 1; }
    package_path="${packages[0]}"
    [[ "$package_path" == "$work/packages/"* && -f "$package_path" ]] ||
        { echo "Expected a package staged under $work/packages, not '$package_path'." >&2; exit 1; }
    cp -p -- "$package_path" "$work/final/"
)
cd -- "$work/final"
mapfile -t packages < <(printf '%s\n' lyrics-widget-*.pkg.tar.* | grep -v '\.sig$')
(( ${#packages[@]} == 1 )) && [[ -f "${packages[0]}" ]] ||
    { echo 'Could not identify the staged package.' >&2; exit 1; }
package="${packages[0]}"
repo-add lyrics-widget.db.tar.gz "$package"
# Release hosts need regular files, not the repo-add symlinks.
cp -L -- lyrics-widget.db lyrics-widget.db.asset
cp -L -- lyrics-widget.files lyrics-widget.files.asset
mv -fT -- lyrics-widget.db.asset lyrics-widget.db
mv -fT -- lyrics-widget.files.asset lyrics-widget.files
printf 'base_commit=%s\nsource_tree=%s\npackage=%s\n' "$source_commit" "$source_state" "$package" > PROVENANCE.txt
sha256sum -- "$package" lyrics-widget.db lyrics-widget.files SOURCE-SHA256SUMS PROVENANCE.txt > SHA256SUMS
sha256sum --check --strict SHA256SUMS

dist="$out/${package%%.pkg.tar.*}-stage"
mv -nT -- "$work/final" "$dist"
if [[ -d "$work/final" ]]; then
    echo "Destination already exists: $dist (left unchanged)." >&2
    exit 1
fi
printf 'Artifacts staged at %s; nothing published. Run: bash publish.sh\n' "$dist"
