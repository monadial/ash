#!/bin/bash
set -e

# Build ash-bindings for Android
# This script:
# 1. Builds the Rust library for Android architectures
# 2. Generates Kotlin bindings using UniFFI
# 3. Copies libraries to Android project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINDINGS_DIR="$PROJECT_ROOT/bindings"
ANDROID_DIR="$PROJECT_ROOT/apps/android/app"
JNI_DIR="$ANDROID_DIR/src/main/jniLibs"
KOTLIN_OUTPUT="$ANDROID_DIR/src/main/java/com/monadial/ash/core"

echo "=== Building ash-bindings for Android ==="

# Check for Android NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    # Try common locations
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        # Find latest NDK version
        ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk"/* 2>/dev/null | sort -V | tail -1)
    elif [ -d "$ANDROID_HOME/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$ANDROID_HOME/ndk"/* 2>/dev/null | sort -V | tail -1)
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "Error: Android NDK not found."
    echo ""
    echo "Please set ANDROID_NDK_HOME environment variable or install NDK via Android Studio."
    echo "  export ANDROID_NDK_HOME=/path/to/android-ndk"
    echo ""
    exit 1
fi

echo "Using Android NDK: $ANDROID_NDK_HOME"

# Check if Rust Android targets are installed
check_target() {
    if ! rustup target list --installed | grep -q "$1"; then
        echo "Installing Rust target: $1"
        rustup target add "$1"
    fi
}

check_target "aarch64-linux-android"
check_target "armv7-linux-androideabi"
check_target "x86_64-linux-android"
check_target "i686-linux-android"

# Set up cargo config for Android
setup_cargo_config() {
    local CARGO_CONFIG="$PROJECT_ROOT/.cargo/config.toml"
    mkdir -p "$PROJECT_ROOT/.cargo"

    # Detect host OS
    case "$(uname -s)" in
        Darwin)
            HOST_TAG="darwin-x86_64"
            ;;
        Linux)
            HOST_TAG="linux-x86_64"
            ;;
        *)
            echo "Unsupported host OS"
            exit 1
            ;;
    esac

    local TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"

    cat > "$CARGO_CONFIG" << EOF
[target.aarch64-linux-android]
ar = "$TOOLCHAIN/bin/llvm-ar"
linker = "$TOOLCHAIN/bin/aarch64-linux-android24-clang"

[target.armv7-linux-androideabi]
ar = "$TOOLCHAIN/bin/llvm-ar"
linker = "$TOOLCHAIN/bin/armv7a-linux-androideabi24-clang"

[target.x86_64-linux-android]
ar = "$TOOLCHAIN/bin/llvm-ar"
linker = "$TOOLCHAIN/bin/x86_64-linux-android24-clang"

[target.i686-linux-android]
ar = "$TOOLCHAIN/bin/llvm-ar"
linker = "$TOOLCHAIN/bin/i686-linux-android24-clang"
EOF

    echo "Created cargo config at $CARGO_CONFIG"
}

setup_cargo_config

cd "$BINDINGS_DIR"

# Build for all Android architectures
echo "Building for arm64-v8a (aarch64-linux-android)..."
cargo build --release --target aarch64-linux-android

echo "Building for armeabi-v7a (armv7-linux-androideabi)..."
cargo build --release --target armv7-linux-androideabi

echo "Building for x86_64 (x86_64-linux-android)..."
cargo build --release --target x86_64-linux-android

echo "Building for x86 (i686-linux-android)..."
cargo build --release --target i686-linux-android

# Generate Kotlin bindings
echo "Generating Kotlin bindings..."
mkdir -p "$KOTLIN_OUTPUT"
cargo run --features=bindgen --bin uniffi-bindgen generate \
    --library target/aarch64-linux-android/release/libash_bindings.so \
    --language kotlin \
    --out-dir "$KOTLIN_OUTPUT"

# Create JNI directories and copy libraries
echo "Copying native libraries..."
mkdir -p "$JNI_DIR/arm64-v8a"
mkdir -p "$JNI_DIR/armeabi-v7a"
mkdir -p "$JNI_DIR/x86_64"
mkdir -p "$JNI_DIR/x86"

cp "$BINDINGS_DIR/target/aarch64-linux-android/release/libash_bindings.so" \
   "$JNI_DIR/arm64-v8a/libash_bindings.so"

cp "$BINDINGS_DIR/target/armv7-linux-androideabi/release/libash_bindings.so" \
   "$JNI_DIR/armeabi-v7a/libash_bindings.so"

cp "$BINDINGS_DIR/target/x86_64-linux-android/release/libash_bindings.so" \
   "$JNI_DIR/x86_64/libash_bindings.so"

cp "$BINDINGS_DIR/target/i686-linux-android/release/libash_bindings.so" \
   "$JNI_DIR/x86/libash_bindings.so"

echo ""
echo "=== Build complete ==="
echo "JNI libraries: $JNI_DIR"
echo "Kotlin bindings: $KOTLIN_OUTPUT"
echo ""
echo "Next steps:"
echo "1. Open apps/android in Android Studio"
echo "2. Build and run the app"
