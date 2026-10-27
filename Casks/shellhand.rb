# The Homebrew cask, kept here and copied into the Casks/ directory of the
# cuonggt/homebrew-tap repository on release, so this repository's history
# records which DMG each cask was signed over.
#
# `scripts/release.sh` rewrites the version and sha256 lines and nothing else,
# which is why they are formatted exactly as they are: one per line, two
# spaces in, the value in double quotes.
cask "shellhand" do
  version "0.0.7"
  # Rewritten by scripts/release.sh with the new DMG's digest; between releases
  # it holds the previous one's, which is real. That is what keeps a slip safe:
  # were the version ever moved on without the digest — by hand, or by a run
  # that half finished — Homebrew would fetch the new DMG, find it does not
  # match, and refuse loudly instead of installing something unverified.
  sha256 "24ca015ca35b7f9d801e26a47e70de7ee86922224f7da8ba90640774bb8cf2b2"

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
