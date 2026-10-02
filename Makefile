.PHONY: generate build test install dmg clean forget-extra-apps helper

XCODEBUILD = xcodebuild \
	-project CheckpointVPNOneClick.xcodeproj \
	-scheme CheckpointVPNOneClick \
	-configuration Debug \
	-derivedDataPath build/DerivedData \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_ALLOWED=NO \
	REGISTER_APP_IN_LAUNCH_SERVICES=NO

generate:
	xcodegen generate

helper:
	./Scripts/build-tunnel-helper.sh

build: generate
	mkdir -p build && touch build/.metadata_never_index
	$(XCODEBUILD) build
	./Scripts/remove-extra-apps.sh

test: generate
	$(XCODEBUILD) test
	./Scripts/remove-extra-apps.sh

forget-extra-apps:
	./Scripts/remove-extra-apps.sh

install: helper
	./Scripts/install.sh

dmg: generate helper
	./Scripts/package-dmg.sh

clean:
	rm -rf build TunnelHelper/dist
	rm -rf Vendor/snx-rs/target
