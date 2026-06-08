# Homebrew formula for the claude-spotlight Stage-1 collector (`cspot`).
#
# This is READY but requires the repo to be on GitHub first (Homebrew installs
# from a source URL / git repo, not a local folder). Two ways to use it:
#
#   A) Build from main (no release needed):
#        # (owner already set to Moon-1C)
#        brew install --HEAD --formula ./Formula/cspot.rb
#      or via a tap:
#        brew tap Moon-1C/claude-spotlight https://github.com/Moon-1C/claude-spotlight
#        brew install --HEAD Moon-1C/claude-spotlight/cspot
#
#   B) Tagged release: create a GitHub release tag (e.g. v0.1.0), then fill in
#      `url` + `sha256` below (get sha with:  brew fetch --build-from-source ...)
#      and `brew install Moon-1C/claude-spotlight/cspot`.
#
# TODO (only for option B / tagged release): confirm `license`, fill url+sha256.

class Cspot < Formula
  desc "Natural-language Spotlight-style search over local files and calendar"
  homepage "https://github.com/Moon-1C/claude-spotlight"
  license "MIT"

  head "https://github.com/Moon-1C/claude-spotlight.git", branch: "dev"

  # Uncomment for a tagged release:
  # url "https://github.com/Moon-1C/claude-spotlight/archive/refs/tags/v0.1.0.tar.gz"
  # sha256 "REPLACE_WITH_TARBALL_SHA256"

  # Builds with the Swift toolchain from Xcode Command Line Tools — full Xcode not required,
  # so we intentionally do NOT `depends_on xcode`. (`swift build` uses /usr/bin/swift.)
  depends_on :macos

  def install
    # --disable-sandbox: SwiftPM manages its own build cache; avoids Homebrew sandbox conflicts.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/cspot"
  end

  test do
    assert_match "shouldEscalate", shell_output("#{bin}/cspot report")
  end
end
