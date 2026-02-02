#!/bin/bash
set -e

# Xcode Cloud post-clone script
# This script runs after the repository is cloned but before the build starts
# It installs Rust and builds the AshCore XCFramework

echo "=== ASH Xcode Cloud Post-Clone Script ==="

# Navigate to repository root
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install Rust
echo "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
source "$HOME/.cargo/env"

# Add iOS targets
echo "Adding iOS targets..."
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios

# Build iOS bindings
echo "Building iOS XCFramework..."
./scripts/build-ios.sh

echo "=== Post-clone complete ==="
echo "XCFramework built at: apps/ios/AshCore/AshCoreFFI.xcframework"
