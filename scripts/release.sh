#!/usr/bin/env bash
# Prepares a release: sets the version, builds Sysbar.app, zips it and writes the Homebrew cask.
# Nothing is uploaded or pushed; the steps to publish are printed at the end.
#
#   scripts/release.sh 0.1.0
#
# Optional, for a build that opens without Gatekeeper warnings:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"   sign with your Developer ID
#   NOTARY_PROFILE="sysbar"   notarize with a profile saved by `xcrun notarytool store-credentials`
# Optional: GITHUB_OWNER (defaults to the account `gh` is logged in to).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <major.minor.patch>" >&2
  exit 2
fi
OWNER="${GITHUB_OWNER:-$(gh api user -q .login 2>/dev/null || true)}"
if [[ -z "$OWNER" ]]; then
  echo "Set GITHUB_OWNER or log in with 'gh auth login'." >&2
  exit 2
fi
OWNER="$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')"

# The build number only has to grow; the number of commits does that without bookkeeping.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
plutil -replace CFBundleShortVersionString -string "$VERSION" Resources/Info.plist
plutil -replace CFBundleVersion -string "$BUILD" Resources/Info.plist

./scripts/bundle.sh
APP="build/Sysbar.app"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

ZIP="build/Sysbar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
fi

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
mkdir -p packaging/homebrew/Casks
sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{SHA256}}/$SHA256/g" -e "s/{{OWNER}}/$OWNER/g" \
  packaging/homebrew/sysbar.rb.template > packaging/homebrew/Casks/sysbar.rb

cat <<EOF

Release $VERSION is ready (nothing has been published):
  $ZIP
  sha256 $SHA256
  packaging/homebrew/Casks/sysbar.rb

To publish:
  1. Commit the version bump and tag it:
       git commit -m "chore: release $VERSION" Resources/Info.plist packaging/homebrew/Casks/sysbar.rb && git tag v$VERSION && git push --follow-tags
  2. Create the GitHub release with the zip:
       gh release create v$VERSION "$ZIP" --title "Sysbar $VERSION" --generate-notes
  3. Copy the cask into your tap (github.com/$OWNER/homebrew-tap, folder Casks/) and push it.
  4. Users install with:
       brew install --cask $OWNER/tap/sysbar
EOF
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo
  echo "Note: this build is ad-hoc signed. macOS will block it on first open until it is signed"
  echo "with a Developer ID and notarized; set SIGN_IDENTITY and NOTARY_PROFILE for that."
fi
