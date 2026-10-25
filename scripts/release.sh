#!/bin/bash
# Builds a Shellhand release for direct download: a notarized, stapled DMG holding Shellhand.app,
# plus the dSYMs. The version and team come from project.yml. The DMG goes into the updates
# folder, whose appcast generate_appcast rewrites and signs for Sparkle, and the DMG's version and
# SHA-256 are written into the Homebrew cask, Casks/shellhand.rb, to commit and copy into the tap.
#
# Nothing is published. The script builds, signs, notarizes and packages, then prints the two
# commands that put it out — a tag and a GitHub release — because pushing is the user's call.
#
# **The feed and the downloads are GitHub, not a domain.** There is no shellhand.app host, and the
# SUFeedURL compiled into a build is the address that build asks for ever after, so a shipped build
# must not depend on a registrar. appcast.xml is served from this repository's main branch, and
# each DMG from the GitHub release tagged for its version. That is why the enclosure URLs are
# rewritten below: generate_appcast takes one --download-url-prefix for the whole folder, and
# GitHub puts every version behind a prefix of its own.
#
# Notarization reads a notarytool keychain profile, stored once with
#   xcrun notarytool store-credentials Shellhand --apple-id <Apple ID> --team-id MN66F68NBY
# which asks for an app-specific password (appleid.apple.com), or with --key, --key-id and
# --issuer for an App Store Connect API key.
#
# Sparkle signs with the EdDSA key in the login keychain under the account shellhand, made once
# with generate_keys --account shellhand. **Back it up** with
#   generate_keys --account shellhand -x <file>
# and keep that file somewhere safe and off this disk: without it, every app already out there
# takes no further update, for ever. There is no recovery and no way to re-key a shipped build.
#
# usage: scripts/release.sh [--skip-notarize] [--allow-dirty]
#   --skip-notarize      build, sign and package only, to try the script without credentials
#   --allow-dirty        build even though the working tree has uncommitted changes
#   NOTARY_PROFILE       the keychain profile to notarize with (default Shellhand)
#   UPDATES_DIR          the DMGs this and every past release serve, their release notes and
#                        appcast.xml (default build/updates). Past DMGs are fetched from the
#                        GitHub releases, because generate_appcast writes the appcast from what
#                        is in the folder: a folder holding only the new DMG produces an appcast
#                        that has forgotten every earlier version.
#   RELEASE_NOTES        a Markdown file of what's new, shown in the update window
#                        (default docs/release-notes/<version>.md, if it's there)

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
profile=${NOTARY_PROFILE:-Shellhand}
updates=${UPDATES_DIR:-build/updates}
repo=cuonggt/shellhand
sparkle_account=shellhand
cask=Casks/shellhand.rb
sparkle_bin=build/SourcePackages/artifacts/sparkle/Sparkle/bin
# The prefix handed to generate_appcast, rewritten per version straight after. It is a stand-in,
# never a real address, so it is spelled so that a leak into a shipped appcast is obvious.
tag_sentinel=TAG-PER-VERSION
notarize=1
allow_dirty=0
for argument in "$@"; do
    case $argument in
        --skip-notarize) notarize=0 ;;
        --allow-dirty) allow_dirty=1 ;;
        *) echo "usage: $0 [--skip-notarize] [--allow-dirty]" >&2; exit 2 ;;
    esac
done

step() { printf '\n== %s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

setting() { awk -v key="$1:" '$1 == key { gsub(/"/, "", $2); print $2; exit }' project.yml; }
version=$(setting MARKETING_VERSION)
build=$(setting CURRENT_PROJECT_VERSION)
team=$(setting DEVELOPMENT_TEAM)
bundle_id=$(setting PRODUCT_BUNDLE_IDENTIFIER)
commit=$(git rev-parse --short HEAD)
# The release tags the commit the DMG was built from, not whatever HEAD has reached by the time it
# is published. GitHub's API refuses an abbreviated SHA for target_commitish with a bare "invalid",
# so the full one is what gets passed.
full_commit=$(git rev-parse HEAD)
[[ -n $version && -n $build && -n $team && -n $bundle_id ]] || fail "can't read the version, build, team or bundle ID from project.yml"
if [[ -n $(git status --porcelain) && $allow_dirty == 0 ]]; then
    fail "the working tree has uncommitted changes; commit them, or pass --allow-dirty"
fi
identity=$(security find-identity -v -p codesigning | awk -v team="($team)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
[[ -n $identity ]] || fail "no Developer ID Application certificate for team $team in the keychain"

out=build/release/$version
derived=build/release/DerivedData
products=$derived/Build/Products/Release
app=$products/Shellhand.app
dmg=$out/Shellhand-$version.dmg
rm -rf "$out"
mkdir -p "$out"

# Submits a file to the notary service and waits; on a rejection, saves the service's log.
notarize_file() {
    local file=$1 result="$out/notary-$(basename "$1").json"
    xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --output-format json > "$result" \
        || fail "notarytool couldn't submit $file; is the keychain profile \"$profile\" stored? (see the top of this script)"
    local status id
    status=$(plutil -extract status raw "$result")
    id=$(plutil -extract id raw "$result")
    if [[ $status != Accepted ]]; then
        xcrun notarytool log "$id" --keychain-profile "$profile" "$out/notary-log-$id.json" || true
        fail "notarization of $(basename "$file") ended $status; the reasons are in $out/notary-log-$id.json"
    fi
    echo "notarized $(basename "$file") ($id)"
}

step "Building Shellhand $version ($build) at $commit"
# --timestamp: notarization takes only signatures with a secure timestamp, which Xcode leaves out
# of ordinary builds.
# -skipPackagePluginValidation: SwiftTerm carries a build plugin Xcode otherwise asks a human to
# trust, which a script cannot answer.
xcodebuild build -project Shellhand.xcodeproj -scheme Shellhand -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$derived" \
    -clonedSourcePackagesDirPath build/SourcePackages -skipPackagePluginValidation \
    OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet

step "Signing Sparkle's helpers"
# Xcode signs Sparkle.framework as it embeds it but leaves the helpers inside as Sparkle shipped
# them, and notarization needs them signed with ours, the hardened runtime and a secure timestamp.
# It happens here rather than in a build phase: Xcode embeds package frameworks outside the build
# phases, so a phase couldn't be ordered after that signing and raced it. The XPC services are only
# for sandboxed apps — this one isn't, which is also why Info.plist has no
# SUEnableInstallerLauncherService — so they go; the app is signed again over the changed framework.
sparkle=$app/Contents/Frameworks/Sparkle.framework
[[ -d $sparkle ]] || fail "Sparkle.framework isn't in the app; did the package dependency survive?"
rm -rf "$sparkle/Versions/B/XPCServices" "$sparkle/XPCServices"
for code in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
    codesign --force --sign "$identity" --options runtime --timestamp "$code"
done
codesign --force --sign "$identity" --options runtime --timestamp --preserve-metadata=identifier,entitlements,requirements,flags "$app"

step "Checking the app"
for code in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle" "$app"; do
    codesign --verify --strict --deep "$code" || fail "$code doesn't verify"
    details=$(codesign -dvv "$code" 2>&1)
    grep -q "^Timestamp=" <<< "$details" || fail "$code has no secure timestamp"
    grep -q "flags=.*runtime" <<< "$details" || fail "$code isn't signed with the hardened runtime"
    grep -q "Authority=Developer ID Application" <<< "$details" || fail "$code isn't signed with a Developer ID"
    if codesign -d --entitlements - --xml "$code" 2>/dev/null | grep -q get-task-allow; then
        fail "$code carries get-task-allow, which notarization rejects"
    fi
done
archs=$(lipo -archs "$app/Contents/MacOS/Shellhand")
[[ $archs == *arm64* ]] || fail "the app has no arm64 slice (it is $archs)"
plist=$app/Contents/Info.plist
[[ $(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist") == "$version" ]] || fail "the app's version isn't $version"
[[ $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist") == "$build" ]] || fail "the app's build isn't $build"
feed=$(/usr/libexec/PlistBuddy -c "Print SUFeedURL" "$plist")
# A build whose feed is wrong can never be corrected in the field: it asks that address for ever.
[[ $feed == "https://raw.githubusercontent.com/$repo/main/appcast.xml" ]] \
    || fail "the app's SUFeedURL is $feed, not this repository's appcast"
echo "signed, timestamped, $archs, version $version ($build)"

if (( notarize )); then
    step "Notarizing the app"
    # Stapled, the app opens offline on first launch too, wherever it's copied from the DMG.
    ditto -c -k --keepParent "$app" "$out/Shellhand.zip"
    notarize_file "$out/Shellhand.zip"
    rm "$out/Shellhand.zip"
    xcrun stapler staple -q "$app"
fi

step "Making the DMG"
staging=$out/dmg
mkdir -p "$staging"
ditto "$app" "$staging/Shellhand.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Shellhand $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov -quiet "$dmg"
rm -rf "$staging"
codesign --sign "$identity" --timestamp --identifier "$bundle_id.dmg" "$dmg"

if (( notarize )); then
    step "Notarizing the DMG"
    notarize_file "$dmg"
    xcrun stapler staple -q "$dmg"
fi

step "Checking what Gatekeeper sees"
if (( notarize )); then
    spctl --assess --type execute -vv "$app"
    spctl --assess --type open --context context:primary-signature -vv "$dmg"
    xcrun stapler validate -q "$dmg"
else
    echo "skipped: without notarization Gatekeeper would refuse both the app and the DMG"
fi

step "Packaging the dSYMs"
(cd "$products" && ditto -c -k --keepParent Shellhand.app.dSYM "$OLDPWD/$out/Shellhand-$version-dSYMs.zip")

sha=$(shasum -a 256 "$dmg" | awk '{ print $1 }')
echo "$sha  $(basename "$dmg")" > "$dmg.sha256"

step "Adding the update to the appcast"
if (( notarize )); then
    app_key=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" "$plist")
    [[ $("$sparkle_bin/generate_keys" --account "$sparkle_account" -p | tail -1) == "$app_key" ]] \
        || fail "the keychain's Sparkle key ($sparkle_account) isn't the one the app checks updates with"
    mkdir -p "$updates"

    # The appcast is written from what is in the folder, so every DMG still being offered has to be
    # in it. They live in the GitHub releases, so fetch any that aren't here yet; a first release
    # finds none, which is fine.
    if command -v gh > /dev/null; then
        for tag in $(gh release list --repo "$repo" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null || true); do
            past=Shellhand-${tag#v}.dmg
            [[ -f $updates/$past ]] && continue
            gh release download "$tag" --repo "$repo" --pattern '*.dmg' --dir "$updates" 2>/dev/null \
                && echo "fetched $past from $tag" || true
        done
    else
        echo "  gh isn't installed: past DMGs can't be fetched, so check $updates holds every"
        echo "  version still being offered before trusting the appcast"
    fi

    cp "$dmg" "$updates/"
    notes=${RELEASE_NOTES:-docs/release-notes/$version.md}
    if [[ -f $notes ]]; then
        cp "$notes" "$updates/$(basename "$dmg" .dmg).md"
    else
        echo "  no release notes at $notes: the update window will be blank"
    fi
    # The release notes go inside the appcast, signed with it, rather than beside it as a file of
    # their own to host.
    # --maximum-deltas 0: no binary deltas. Sparkle will happily generate them once the folder
    # holds two versions, and they are a trap here rather than a saving. A delta is named for the
    # BUILD numbers it spans — Shellhand2-1.delta — not the marketing version, so there is nothing
    # in the filename to map it to the GitHub release that would serve it, and the rewrite below
    # cannot place it. The saving is a fraction of a 14 MB download, while a delta URL pointing at
    # the wrong release breaks updating for exactly the people who are updating. If download size
    # ever matters enough to want them back, they need uploading to the new version's release and
    # a build-to-version map built from the DMGs in the folder.
    "$sparkle_bin/generate_appcast" --account "$sparkle_account" --maximum-deltas 0 \
        --download-url-prefix "https://github.com/$repo/releases/download/$tag_sentinel/" \
        --embed-release-notes "$updates"

    # Each version's DMG lives in the release tagged for it, so the one prefix above becomes one
    # per version here: Shellhand-1.2.3.dmg is served from the release tagged v1.2.3. The version
    # is in the filename, so this needs nothing from outside the appcast.
    /usr/bin/sed -i '' -E \
        "s|/releases/download/$tag_sentinel/Shellhand-([^\"/]+)\.dmg|/releases/download/v\1/Shellhand-\1.dmg|g" \
        "$updates/appcast.xml"
    if grep -q "$tag_sentinel" "$updates/appcast.xml"; then
        # This caught the delta case above, on the first release that had a predecessor. If it
        # fires again, something other than Shellhand-<version>.dmg is being enclosed; look at
        # what the URL names before widening the rewrite.
        grep -o 'url="[^"]*'"$tag_sentinel"'[^"]*"' "$updates/appcast.xml" >&2 || true
        fail "an enclosure URL in $updates/appcast.xml still holds $tag_sentinel; it would point nowhere"
    fi
    grep -q "/releases/download/v$version/$(basename "$dmg")" "$updates/appcast.xml" \
        || fail "$updates/appcast.xml doesn't offer $(basename "$dmg") from the v$version release"

    # Served from main, which is what every shipped build asks for.
    cp "$updates/appcast.xml" appcast.xml
    echo "appcast.xml now offers $version; it is served from main, so it has to be committed"
else
    echo "skipped: only a notarized DMG goes in the appcast"
fi

step "Updating the Homebrew cask"
if (( notarize )); then
    grep -q "url \"https://github.com/$repo/releases/download/" "$cask" \
        || fail "$cask doesn't download from this repository's releases"
    # The only two lines that change from release to release, so a release leaves a reviewable diff
    # and the repository's history records which DMG each cask was signed over.
    /usr/bin/sed -i '' -E "s|^  version \".*\"\$|  version \"$version\"|; s|^  sha256 \".*\"\$|  sha256 \"$sha\"|" "$cask"
    grep -q "  version \"$version\"" "$cask" && grep -q "  sha256 \"$sha\"" "$cask" \
        || fail "couldn't write the version and the SHA-256 into $cask"
    echo "$cask now names $(basename "$dmg")"
else
    echo "skipped: the cask would name a DMG nobody can install"
fi

step "Done"
notes_flag=""
[[ -f docs/release-notes/$version.md ]] && notes_flag=" --notes-file docs/release-notes/$version.md"
echo "$dmg"
echo "sha256 $sha"
if (( notarize )); then
    cat <<DONE

Nothing has been published. The order below is the only one that works: the release has to exist
before the appcast naming it is committed, and the commit the release tags has to be on the remote
before the release can tag it.

  git push origin main

  gh release create v$version --repo $repo --target $full_commit \\
      --title "Shellhand $version"${notes_flag} \\
      "$dmg" "$out/Shellhand-$version-dSYMs.zip"

  git add appcast.xml $cask && git commit -m "Release $version" && git push

Then copy $cask into the Casks/ directory of the homebrew-tap repository.

Worth checking afterwards, because it is the one link nothing here can test: that the URL in
appcast.xml really serves the DMG.

  curl -sIL "$(grep -o 'url="[^"]*"' appcast.xml | sed 's/url="//; s/"//')" | grep -iE '^HTTP/|content-length'
DONE
else
    echo "not notarized: for trying the script only"
fi
