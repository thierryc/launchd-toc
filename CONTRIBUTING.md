# Contributing

Thank you for helping improve Launchd TOC.

## Before opening a pull request

1. Keep the project native Swift/SwiftUI with no third-party runtime dependencies.
2. Preserve the user-only mutation boundary and fixed-executable process model.
3. Add or update tests for every filesystem, parsing, or launchctl behavior change.
4. Run the unit and UI suites on macOS 26 with Xcode 26.3 or later.
5. Treat warnings as errors and retain Swift 6 strict concurrency.
6. Do not add analytics, automatic network requests, administrator access, or an undocumented launchd option.
7. Do not copy code, assets, UI text, or icons from `azu/launchd-ui` or other applications.

Use clear commits and explain user-visible safety implications in the pull request.

## Rights

This repository does not include an open-source license. Copyright © 2026 Thierry Charbonnel. All rights reserved. A contribution does not change that status unless the copyright holder agrees separately in writing.
