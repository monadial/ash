.PHONY: all build-ios build-core test clean generate-swift

# Default target
all: build-ios

# Build core library
build-core:
	cd core && cargo build --release

# Build bindings and iOS framework
build-ios: build-core
	./scripts/build-ios.sh

# Run all tests
test:
	cd core && cargo test
	cd bindings && cargo test

# Generate Swift bindings (requires library to be built first)
generate-swift:
	cd bindings && cargo build --lib
	cd bindings && cargo run --features bindgen --bin uniffi-bindgen -- \
		generate --library target/debug/libash_bindings.dylib \
		--language swift --out-dir ../apps/ios/AshCore

# Clean build artifacts
clean:
	cd core && cargo clean
	cd bindings && cargo clean
	rm -rf apps/ios/AshCore/lib
	rm -rf apps/ios/AshCore/AshCoreFFI.xcframework

# Format code
fmt:
	cd core && cargo fmt
	cd bindings && cargo fmt

# Run clippy
lint:
	cd core && cargo clippy -- -D warnings
	cd bindings && cargo clippy --lib -- -D warnings
