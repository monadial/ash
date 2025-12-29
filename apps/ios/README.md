# Ash iOS App

SwiftUI app for Ash secure messaging.

## Prerequisites

1. **Xcode 15+** installed
2. **Rust** with iOS targets:
   ```bash
   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
   ```
3. **Xcode selected** (not CommandLineTools):
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

## Building

### 1. Build the Rust FFI library

From the project root:

```bash
make build-ios
```

This compiles the Rust library for iOS device and simulator, and creates an XCFramework.

### 2. Open in Xcode

```bash
open apps/ios/Ash.xcworkspace
```

### 3. Add AshCore to the project

In Xcode:

1. **Add Swift file**: Drag `AshCore/AshCore.swift` into your project
   - Check "Copy items if needed" → **NO**
   - Check "Add to targets" → **Ash**

2. **Add XCFramework**: Drag `AshCore/AshCoreFFI.xcframework` into "Frameworks, Libraries, and Embedded Content"
   - Set "Embed" to **Do Not Embed** (it's a static library)

3. **Build & Run** (⌘R)

## Project Structure

```
apps/ios/
├── Ash/                    # Xcode project
│   ├── Ash/                # App source
│   │   ├── AshApp.swift
│   │   └── ContentView.swift
│   └── Ash.xcodeproj
├── AshCore/                # Rust FFI bindings
│   ├── AshCore.swift       # Generated Swift bindings
│   ├── AshCoreFFI.h        # C header
│   ├── AshCoreFFI.modulemap
│   ├── AshCoreFFI.xcframework/  # Built library (after make build-ios)
│   └── lib/                # Static libraries
└── Ash.xcworkspace         # Workspace (open this)
```

## Usage Example

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Button("Generate Mnemonic") {
                let testData: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE]
                let words = generateMnemonic(padBytes: testData)
                print("Mnemonic: \(words.joined(separator: " "))")
            }
        }
    }
}
```

## Rebuilding After Rust Changes

If you modify the Rust code:

```bash
make build-ios
```

Then rebuild in Xcode (⌘B).
