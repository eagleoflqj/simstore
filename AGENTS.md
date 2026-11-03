# Development guidelines

- Implement one reviewable feature at a time. Complete the relevant build and verification, report the result, and wait for review before starting the next feature.
- This repository contains the macOS client. App recipes and release publishing belong in the separate simstore-builds repository.
- Use Swift and SwiftUI with native macOS APIs. Support only Apple Silicon macOS.
- Build with CMake and Ninja using the Xcode SDK and Swift toolchain. Do not use an Xcode project or xcodebuild to build the client.
- Keep generated files and build output under build/. Do not hardcode personal machine paths.
- Write documentation in English. Keep each prose paragraph on one physical line. Keep the README focused on the project's purpose. Keep temporary progress reports and conversation history out of repository documentation.
- Keep product UI focused on user tasks. Do not show mock catalog entries, simulated install results, or implementation details as real functionality.
- Run appropriate checks and an actual build when changing build logic. Verify launch and window behavior when changing app startup. Report build, launch, and functional verification separately.
