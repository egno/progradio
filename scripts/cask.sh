#!/bin/bash
# Writes Casks/progradio.rb in the Homebrew tap (github.com/egno/homebrew-tap) for the version in project.yml and
# the DMG built by `make release`. Publish the GitHub release first, then commit and push the tap.
#   make cask TAP=~/proj/homebrew-tap
set -euo pipefail
cd "$(dirname "$0")/.."

tap="${TAP:-../homebrew-tap}"
tap="${tap/#\~/$HOME}"  # make passes ~ unexpanded
version=$(sed -nE 's/^ *MARKETING_VERSION: "(.*)"/\1/p' project.yml)
dmg=build/ProgRadio-$version.dmg
[ -f "$dmg" ] || { echo "no $dmg: run make release" >&2; exit 1; }
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)

mkdir -p "$tap/Casks"
cat >"$tap/Casks/progradio.rb" <<CASK
cask "progradio" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/egno/progradio/releases/download/v#{version}/ProgRadio-#{version}.dmg"
  name "Prog Radio"
  desc "Menu bar player for Prog Radio with widgets and a Control Center control"
  homepage "https://github.com/egno/progradio"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "ProgRadio.app"

  # Not notarized: clear the quarantine flag so macOS opens it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/ProgRadio.app"]
  end

  uninstall quit: "io.github.egno.ProgRadio"

  zap trash: [
    "~/Library/Containers/io.github.egno.ProgRadio",
    "~/Library/Containers/io.github.egno.ProgRadio.Widgets",
  ]
end
CASK
echo "wrote $tap/Casks/progradio.rb ($version, $sha)"
