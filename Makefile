CONFIG ?= Release
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/$(CONFIG)/ProgRadio.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: project build test install run log clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project ProgRadio.xcodeproj -scheme ProgRadio -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination "platform=macOS,arch=arm64" -quiet build

test: project
	xcodebuild -project ProgRadio.xcodeproj -scheme ProgRadio -derivedDataPath $(DERIVED) -destination "platform=macOS,arch=arm64" -quiet test

# Widgets are only discovered for apps in an Applications folder.
install: build
	-pkill -x ProgRadio; sleep 0.5
	mkdir -p $(INSTALL_DIR)
	rm -rf "$(INSTALL_DIR)/ProgRadio.app"
	cp -R "$(APP)" "$(INSTALL_DIR)/ProgRadio.app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALL_DIR)/ProgRadio.app"
	open "$(INSTALL_DIR)/ProgRadio.app"

run: install

log:
	log stream --level info --predicate 'subsystem == "local.progradio"'

clean:
	rm -rf build ProgRadio.xcodeproj
