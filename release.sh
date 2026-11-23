#!/usr/bin/env bash
# release.sh - build the package and publish it to the GitHub "repo" release
set -e
cd "$(dirname "$0")"
srcdir="$(pwd)"
repo=Gehrman-Sparrow-ark/lyrics-widget
out="$HOME/lyrics-repo"

makepkg -sf --noconfirm
pkg=$(ls -t lyrics-widget-*-any.pkg.tar.zst | head -1)

mkdir -p "$out/upload"
rm -f "$out"/upload/*
cp "$pkg" "$out/"
cd "$out"
repo-add lyrics-widget.db.tar.gz "$pkg"
cp -L lyrics-widget.db lyrics-widget.files upload/
cp "$pkg" upload/

for old in $(gh release view repo --repo "$repo" --json assets --jq '.assets[].name' | grep '\.pkg\.tar\.zst$' | grep -vx "$pkg"); do
    gh release delete-asset repo "$old" --repo "$repo" -y
done
gh release upload repo upload/* --clobber --repo "$repo"
git -C "$srcdir" tag -f repo HEAD
git -C "$srcdir" push -f origin refs/tags/repo
echo "Published $pkg"
