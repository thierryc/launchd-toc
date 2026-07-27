# Independent Implementation Provenance

Launchd TOC is an original native Swift/SwiftUI implementation created for `thierryc/launchd-toc`.

The product requirements were derived from:

- the public behavior of macOS `launchd` and documented `launchctl` commands;
- Apple’s public macOS design and Liquid Glass guidance;
- the product specification maintained in this repository;
- visual hierarchy cues from Apple utility applications, without copying their assets or interfaces.

The existence and broad purpose of `azu/launchd-ui` informed the idea that a visual launchd utility is useful. No source code, assets, interface text, layouts, icons, tests, or implementation details were copied from that repository. The code and artwork in this repository were authored independently for Launchd TOC.

This note documents provenance and engineering intent. It does not claim a formal, audited legal “clean-room” certification and is not legal advice.
