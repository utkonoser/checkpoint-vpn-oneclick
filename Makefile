.PHONY: generate build test install dmg clean

XCODEBUILD = xcodebuild \
	-project CheckpointVPNOneClick.xcodeproj \
	-scheme CheckpointVPNOneClick \
	-configuration Debug \
	-derivedDataPath build/DerivedData \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_ALLOWED=NO

generate:
	xcodegen generate

build: generate
	mkdir -p build && touch build/.metadata_never_index
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

install:
	./Scripts/install.sh

dmg: generate
	./Scripts/package-dmg.sh

clean:
	rm -rf build
