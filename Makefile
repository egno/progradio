CONFIG ?= Release
DERIVED := build/DerivedData
APP_NAME := Prog Radio Mini
APP := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications

.PHONY: project build test install run log release cask clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project ProgRadio.xcodeproj -scheme ProgRadio -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination "platform=macOS,arch=arm64" -quiet build

test: project
	xcodebuild -project ProgRadio.xcodeproj -scheme ProgRadio -derivedDataPath $(DERIVED) -destination "platform=macOS,arch=arm64" -quiet test

# Widgets are only discovered for apps in an Applications folder.
install: build
	-pkill -x "$(APP_NAME)"; pkill -x ProgRadio; sleep 0.5
	mkdir -p $(INSTALL_DIR)
	rm -rf "$(INSTALL_DIR)/ProgRadio.app" "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_DIR)/$(APP_NAME).app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

run: install

log:
	log stream --level info --predicate 'subsystem == "io.github.egno.ProgRadio"'

# build/ProgRadioMini-<version>.dmg and .zip for a GitHub release, see scripts/release.sh.
release:
	scripts/release.sh

# Casks/progradio.rb in the Homebrew tap for this version's DMG: make cask TAP=~/proj/homebrew-tap
cask:
	scripts/cask.sh

clean:
	rm -rf build ProgRadio.xcodeproj
