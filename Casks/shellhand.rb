# The Homebrew cask, kept here and copied into the Casks/ directory of the
# cuonggt/homebrew-tap repository on release, so this repository's history
# records which DMG each cask was signed over.
#
# `scripts/release.sh` rewrites the version and sha256 lines and nothing else,
# which is why they are formatted exactly as they are: one per line, two
# spaces in, the value in double quotes.
cask "shellhand" do
  version "0.0.2"
  # Replaced by scripts/release.sh with the real digest. Left as a string that
  # is not a valid SHA-256 on purpose: if it ever reaches the tap unreplaced,
  # Homebrew refuses it loudly instead of installing something unverified.
  sha256 "dad51299bd2c5fc8ce8638b07774cebd26b711949c00a7d6af8761fff5bd175a"

  url "https://github.com/cuonggt/shellhand/releases/download/v#{version}/Shellhand-#{version}.dmg"
  name "Shellhand"
  desc "Native macOS SSH client: the host list, tabs on real ssh, and files over SFTP"
  homepage "https://github.com/cuonggt/shellhand"

  # The app updates itself through Sparkle, so brew leaves the version it
  # finds installed alone rather than reporting it as outdated.
  auto_updates true
  depends_on macos: :tahoe

  app "Shellhand.app"

  # Everything the app writes outside its own bundle. The host list is the one
  # that matters — it is the user's own data, so it goes only on `brew zap`,
  # never on uninstall.
  zap trash: [
    "~/Library/Application Support/Shellhand",
    "~/Library/Caches/com.shellhand.Shellhand",
    "~/Library/Preferences/com.shellhand.Shellhand.plist",
    "~/Library/Saved Application State/com.shellhand.Shellhand.savedState",
  ]
end
