#!/bin/zsh
# Usage: ./release.sh 1.1.0 "릴리스 노트"
set -euo pipefail
cd "$(dirname "$0")"
V="${1:-}"
NOTES="${2:-버그 수정 및 개선}"
[[ -n "$V" ]] || { echo "usage: ./release.sh <version> [notes]"; exit 1; }
REPO=dong3789/TypePet
GIT=/opt/homebrew/bin/git
printf '%s\n' "$V" > VERSION
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist

STAGE="$(mktemp -d)/TypePet.app"
TYPEPET_INSTALL=0 TYPEPET_STAGE="$STAGE" ./build.sh
ZIP="$(mktemp -d)/TypePet.zip"
ditto -c -k --keepParent "$STAGE" "$ZIP"

export GH_TOKEN
GH_TOKEN="$(gh auth token --user dong3789)"
$GIT add -A
$GIT commit -qm "v$V" || true
$GIT tag "v$V"
$GIT -c credential.helper= -c credential.helper='!gh auth git-credential' push origin HEAD:main
$GIT -c credential.helper= -c credential.helper='!gh auth git-credential' push origin "v$V"
gh release create "v$V" "$ZIP" --repo "$REPO" --title "타입펫 $V" --notes "$NOTES"

rm -rf /Applications/TypePet.app
cp -R "$STAGE" /Applications/TypePet.app
xattr -cr /Applications/TypePet.app || true
echo "released v$V → https://github.com/$REPO/releases/tag/v$V"
