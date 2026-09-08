#!/bin/bash
# Whisky Claude — cut + publish a release that Sparkle can auto-update to.
# Usage: ./scripts/release.sh <version>     e.g. ./scripts/release.sh 1.3.0
#
# Builds Release, codesigns (stable cert if present), zips, EdDSA-signs the zip,
# creates a GitHub Release with the zip asset, prepends an <item> to appcast.xml,
# then commits + pushes + tags. The EdDSA private key lives in the login Keychain
# (see docs/RELEASING.md) — never in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> (e.g. 1.3.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ version must be semver (x.y.z)"; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "✗ tracked changes present — commit/stash first"; exit 1; }
command -v gh >/dev/null || { echo "✗ gh CLI not found"; exit 1; }

PROJ="WhiskyClaude.xcodeproj"
SCHEME="WhiskyClaude"
APPNAME="Whisky Claude"
REPO="Whisky-11/whisky-claude"
REL="build/Build/Products/Release"
ZIP="WhiskyClaude-${VERSION}.zip"
SIGN_ID="Ahmad Sharaf Code Signing"

# Locate Sparkle's sign_update (resolved by SPM into build/SourcePackages).
# NOTE: `find` exits 1 when a search root is missing (build/SourcePackages does not
# exist on a clean checkout). With `set -euo pipefail` that killed the script HERE,
# silently — stderr was /dev/null'd, so it exited 1 printing nothing at all, and the
# guard below never got the chance to explain why. `|| true` keeps the guard reachable.
SIGN_UPDATE=$({ find build/SourcePackages ~/Library/Developer/Xcode/DerivedData \
  -path "*Sparkle*/bin/sign_update" 2>/dev/null || true; } | head -1)
[ -n "$SIGN_UPDATE" ] || { echo "✗ sign_update not found — run a build first to resolve Sparkle"; exit 1; }

# 1. version bump (monotonic build number)
CUR_BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);/\1/p' "$PROJ/project.pbxproj" | head -1)
BUILD=$(( CUR_BUILD + 1 ))
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = ${VERSION};/g" "$PROJ/project.pbxproj"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD};/g" "$PROJ/project.pbxproj"
echo "→ version ${VERSION} (build ${BUILD})"

# 2. build Release + codesign
echo "→ building Release"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build | tail -3
APP="$REL/${APPNAME}.app"
rm -rf "$APP"; cp -R "$REL/WhiskyClaude.app" "$APP"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  echo "→ codesign with '$SIGN_ID'"; codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "→ codesign ad-hoc (stable cert '$SIGN_ID' not found)"; codesign --force --deep --sign - "$APP"
fi

# 3. zip (ditto preserves the bundle)
rm -f "$ZIP"
( cd "$REL" && ditto -c -k --keepParent "${APPNAME}.app" "${OLDPWD}/${ZIP}" )

# 4. EdDSA-sign the zip. sign_update prints BOTH attributes, e.g.
#    sparkle:edSignature="…" length="…"  — use it verbatim (do NOT add length again).
SIGINFO=$("$SIGN_UPDATE" "$ZIP")
echo "→ signed: $SIGINFO"

# 5. prepend appcast item (URL is deterministic — release created below).
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP}"
PUBDATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
python3 - "$VERSION" "$BUILD" "$PUBDATE" "$URL" "$SIGINFO" <<'PY'
import sys, re
version, build, pubdate, url, siginfo = sys.argv[1:6]
item = (f"    <item>\n"
        f"        <title>{version}</title>\n"
        f"        <pubDate>{pubdate}</pubDate>\n"
        f"        <sparkle:version>{build}</sparkle:version>\n"
        f"        <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"        <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\n"
        f'        <enclosure url="{url}" type="application/octet-stream" {siginfo} />\n'
        f"    </item>\n")
p = "appcast.xml"; s = open(p).read()
s = re.sub(r"(<language>en</language>\n)", r"\1" + item, s, count=1)
open(p, "w").write(s)
PY
xmllint --noout appcast.xml && echo "→ appcast.xml updated"

# 6. commit + push the release commit FIRST (so the tag/release point at it)
git add "$PROJ/project.pbxproj" appcast.xml
git commit -m "release: v${VERSION}"
git push origin HEAD

# 7. GitHub Release at this commit (creates the tag + uploads the asset)
echo "→ creating GitHub release v${VERSION}"
gh release create "v${VERSION}" "$ZIP" --repo "$REPO" --target "$(git rev-parse HEAD)" \
   --title "v${VERSION}" --notes "Whisky Claude ${VERSION}"
rm -f "$ZIP"

# 8. Remove the build products. Both of them are Spotlight-indexed as applications,
# so leaving them behind makes "Whisky Claude" resolve to three .app bundles and the
# user cannot tell which one is installed. install.sh already cleans up after itself;
# release.sh did not, and a release on 2026-08-17 left both copies on disk until
# 2026-09-08. /Applications/Whisky Claude.app is the only copy that should exist.
rm -rf "$REL/WhiskyClaude.app" "$APP" "$REL/WhiskyClaude.app.dSYM"
echo "✓ released v${VERSION} — appcast live on master, Sparkle clients will pick it up"
