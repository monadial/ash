#!/bin/bash
set -e

# Build ash-bindings for iOS
# This script:
# 1. Builds the Rust library for iOS device and simulator
# 2. Generates Swift bindings using UniFFI
# 3. Applies Swift 6 compatibility patches
# 4. Creates XCFramework

# Check if Xcode (not just CommandLineTools) is selected
if ! xcrun --sdk iphoneos --show-sdk-path &>/dev/null; then
    echo "Error: iOS SDK not found."
    echo ""
    echo "Run this command to fix:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo ""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINDINGS_DIR="$PROJECT_ROOT/bindings"
IOS_DIR="$PROJECT_ROOT/apps/ios"
OUTPUT_DIR="$IOS_DIR/AshCore"
SWIFT_OUTPUT="$OUTPUT_DIR/Sources/AshCore.swift"

echo "=== Building ash-bindings for iOS ==="

# Check if Rust iOS targets are installed
check_target() {
    if ! rustup target list --installed | grep -q "$1"; then
        echo "Installing Rust target: $1"
        rustup target add "$1"
    fi
}

check_target "aarch64-apple-ios"
check_target "aarch64-apple-ios-sim"

cd "$BINDINGS_DIR"

# Build for iOS device (arm64)
echo "Building for iOS device (aarch64-apple-ios)..."
cargo build --release --target aarch64-apple-ios

# Build for iOS simulator (arm64)
echo "Building for iOS simulator (aarch64-apple-ios-sim)..."
cargo build --release --target aarch64-apple-ios-sim

# Generate Swift bindings
echo "Generating Swift bindings..."
mkdir -p "$OUTPUT_DIR/Sources"
cargo run --features=bindgen --bin uniffi-bindgen generate \
    --library target/aarch64-apple-ios-sim/release/libash_bindings.a \
    --language swift \
    --out-dir "$OUTPUT_DIR"

# Move Swift file to Sources directory
mv "$OUTPUT_DIR/AshCore.swift" "$SWIFT_OUTPUT"

# Apply Swift 6 compatibility patches
echo "Applying Swift 6 compatibility patches..."
"$SCRIPT_DIR/patch-swift6.sh" "$SWIFT_OUTPUT"

# Create output directories
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/headers"

# Copy static libraries
echo "Copying libraries..."
cp "$BINDINGS_DIR/target/aarch64-apple-ios/release/libash_bindings.a" \
   "$OUTPUT_DIR/lib/libash_bindings-ios.a"
cp "$BINDINGS_DIR/target/aarch64-apple-ios-sim/release/libash_bindings.a" \
   "$OUTPUT_DIR/lib/libash_bindings-ios-sim.a"

# Copy headers to separate directory
cp "$OUTPUT_DIR/AshCoreFFI.h" "$OUTPUT_DIR/headers/"
cp "$OUTPUT_DIR/AshCoreFFI.modulemap" "$OUTPUT_DIR/headers/module.modulemap"

# Create XCFramework
echo "Creating XCFramework..."
rm -rf "$OUTPUT_DIR/AshCoreFFI.xcframework"

xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/lib/libash_bindings-ios.a" \
    -headers "$OUTPUT_DIR/headers" \
    -library "$OUTPUT_DIR/lib/libash_bindings-ios-sim.a" \
    -headers "$OUTPUT_DIR/headers" \
    -output "$OUTPUT_DIR/AshCoreFFI.xcframework"

echo ""
echo "=== Build complete ==="
echo "XCFramework: $OUTPUT_DIR/AshCoreFFI.xcframework"
echo "Swift file:  $SWIFT_OUTPUT (Swift 6 compatible)"
echo ""
echo "Next steps:"
echo "1. In Xcode, add the AshCore package from apps/ios/AshCore"
echo "2. Or manually add AshCore.swift and AshCoreFFI.xcframework to your project"
