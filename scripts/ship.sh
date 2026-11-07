#!/usr/bin/env bash
# Checks whether anything has changed since the last release and, if so, ships it: version, build,
# signing, notarization, GitHub release, Homebrew tap and website. Without --publish it only prints
# the plan and changes nothing.
#
#   scripts/ship.sh                      plan: commits since the last tag, the next version, what is missing
#   scripts/ship.sh --publish            run every step, asking once before anything leaves this Mac
#   scripts/ship.sh --publish --yes      the same without the question
#   --bump patch|minor|major             how far to raise the version (default patch)
#   --version X.Y.Z                      release exactly this version
#
# The release notes are written by hand: when CHANGELOG.md has none for the new version the script
# lists the commits to write them from and stops. Commit the notes ("docs: changelog for X.Y.Z")
# and run it again.
#
# Signing comes from the environment or from ~/.config/sysbar/release.env:
#   SIGN_IDENTITY     Developer ID Application certificate (its SHA-1 if the name has non-ASCII letters)
#   NOTARY_PROFILE    profile saved by `xcrun notarytool store-credentials` (default: sysbar)
#   EXPECTED_TEAM_ID  optional; the build must be signed by this team
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="$HOME/.config/sysbar/release.env"
# shellcheck disable=SC1090
[[ -f "$CONFIG" ]] && source "$CONFIG"
NOTARY_PROFILE="${NOTARY_PROFILE:-sysbar}"
TAP_REPO="homebrew-sysbar"
USER_FACING='^(feat|fix|perf)(\(.+\))?!?: '

PUBLISH=0
ASSUME_YES=0
BUMP="patch"
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --yes) ASSUME_YES=1 ;;
    --bump) BUMP="${2:-}"; shift ;;
    --version) VERSION="${2:-}"; shift ;;
    *) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
  shift
done
[[ "$BUMP" =~ ^(patch|minor|major)$ ]] || { echo "--bump takes patch, minor or major" >&2; exit 2; }
[[ -z "$VERSION" || "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "--version takes major.minor.patch" >&2; exit 2; }

PROBLEMS=()
problem() { PROBLEMS+=("$1"); }

CURRENT_STEP="checking the repository"
on_error() {
  echo >&2
  echo "Stopped while: $CURRENT_STEP." >&2
  echo "Steps before it are done and stay done; fix the cause and finish the rest by hand (see the end of scripts/release.sh)." >&2
}
trap on_error ERR

# --- what changed since the last release ---------------------------------------------------------
git fetch origin main --tags --quiet
LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"
SUBJECTS="$(git log --format=%s "$RANGE")"
COUNT="$(printf '%s' "$SUBJECTS" | grep -c . || true)"
if [[ "$COUNT" -eq 0 ]]; then
  echo "Nothing to release: no commits since ${LAST_TAG:-the start}."
  exit 0
fi
FACING="$(printf '%s\n' "$SUBJECTS" | grep -E "$USER_FACING" || true)"
OTHER="$(printf '%s\n' "$SUBJECTS" | grep -vE "$USER_FACING" | grep . || true)"

if [[ -z "$VERSION" ]]; then
  if [[ -z "$FACING" ]]; then
    echo "$COUNT commit(s) since ${LAST_TAG:-the start}, none of them feat, fix or perf; nothing users would notice."
    printf '%s\n' "$SUBJECTS" | sed 's/^/  /'
    echo "Release anyway with --version X.Y.Z."
    exit 0
  fi
  IFS=. read -r MAJOR MINOR PATCH <<<"${LAST_TAG#v}"
  case "$BUMP" in
    major) VERSION="$((MAJOR + 1)).0.0" ;;
    minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    patch) VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  esac
fi

echo "Last release  ${LAST_TAG:-none}   ($COUNT commits since)"
echo "Next version  $VERSION   (--bump $BUMP)"
echo
echo "For the changelog (feat, fix, perf):"
if [[ -n "$FACING" ]]; then printf '%s\n' "$FACING" | sed 's/^/  /'; else echo "  none"; fi
if [[ -n "$OTHER" ]]; then
  echo "Not in the changelog:"
  printf '%s\n' "$OTHER" | sed 's/^/  /'
fi
echo

# --- what is missing -----------------------------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] || problem "on branch '$BRANCH'; releases are cut from main"
[[ -z "$(git status --porcelain)" ]] || problem "uncommitted changes (commit or stash them; the changelog entry must be committed too)"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || problem "HEAD is not origin/main (pull, or push what you have first)"
git rev-parse "v$VERSION" >/dev/null 2>&1 && problem "tag v$VERSION already exists"
./scripts/changelog.py check "$VERSION" >/dev/null 2>&1 || problem "CHANGELOG.md has no notes for $VERSION (write them from the list above, then commit)"
[[ -n "${SIGN_IDENTITY:-}" ]] || problem "SIGN_IDENTITY is not set (environment or $CONFIG); an ad-hoc build is rejected by the in-app updater"
command -v gh >/dev/null || problem "gh is not installed"
gh auth status >/dev/null 2>&1 || problem "gh is not logged in"

if [[ ${#PROBLEMS[@]} -gt 0 ]]; then
  echo "Not ready:"
  printf '  - %s\n' "${PROBLEMS[@]}"
  exit 1
fi
if [[ $PUBLISH -eq 0 ]]; then
  echo "Ready. Run with --publish to: test, build, sign and notarize, tag and push, create the GitHub"
  echo "release, update the Homebrew tap and deploy the website."
  exit 0
fi

# --- ship ----------------------------------------------------------------------------------------
CURRENT_STEP="running the tests"
swift test
./scripts/strings.py check

if [[ $ASSUME_YES -eq 0 ]]; then
  echo
  read -r -p "Build $VERSION, then push, tag, publish the release, update the tap and deploy the site? [y/N] " ANSWER
  [[ "$ANSWER" =~ ^[Yy]$ ]] || { echo "Cancelled; nothing was published."; exit 1; }
fi

CURRENT_STEP="building, signing and notarizing"
SIGN_IDENTITY="$SIGN_IDENTITY" NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/release.sh "$VERSION"

CURRENT_STEP="verifying the signature"
APP="build/Sysbar.app"
TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ -z "$TEAM" || "$TEAM" == "not set" ]]; then
  echo "The build is not signed with a Developer ID; not publishing." >&2
  exit 1
fi
if [[ -n "${EXPECTED_TEAM_ID:-}" && "$TEAM" != "$EXPECTED_TEAM_ID" ]]; then
  echo "The build is signed by team $TEAM, expected $EXPECTED_TEAM_ID; not publishing." >&2
  exit 1
fi
xcrun stapler validate "$APP"

ZIP="build/Sysbar-$VERSION.zip"
NOTES="build/notes-$VERSION.md"

CURRENT_STEP="committing and pushing v$VERSION"
git commit -m "chore: release $VERSION" Resources/Info.plist packaging/homebrew/Casks/sysbar.rb docs/index.html
git tag -a "v$VERSION" -m "Sysbar $VERSION"
git push --follow-tags

CURRENT_STEP="creating the GitHub release"
gh release create "v$VERSION" "$ZIP" --title "Sysbar $VERSION" --notes-file "$NOTES"

CURRENT_STEP="updating the Homebrew tap"
OWNER="$(gh api user -q .login)"
TAP_DIR="$(mktemp -d)"
gh repo clone "$OWNER/$TAP_REPO" "$TAP_DIR" -- --quiet
mkdir -p "$TAP_DIR/Casks"
cp packaging/homebrew/Casks/sysbar.rb "$TAP_DIR/Casks/sysbar.rb"
git -C "$TAP_DIR" add Casks/sysbar.rb
if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "Tap already has this cask."
else
  git -C "$TAP_DIR" commit --quiet -m "sysbar $VERSION"
  git -C "$TAP_DIR" push --quiet
fi
rm -rf "$TAP_DIR"

CURRENT_STEP="deploying the website"
npx --yes wrangler deploy

trap - ERR
echo
echo "Sysbar $VERSION is out: https://github.com/$OWNER/sysbar/releases/tag/v$VERSION"
