.PHONY: generate build test install clean

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
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

install:
	./Scripts/install.sh

clean:
	rm -rf build
