# Security Policy

## Supported versions

Security fixes are provided for the latest published version of Launchd TOC.

## Reporting

Please report suspected vulnerabilities privately through GitHub’s repository Security Advisories rather than a public issue. Include reproduction steps, affected paths or launchd labels, and the observed macOS version.

Do not include private property-list contents, credentials, tokens, or personal log data.

## Security model

Launchd TOC:

- has no privileged helper and never asks for administrator authentication;
- modifies only direct, non-symlinked property lists under `~/Library/LaunchAgents`;
- treats `/Library` and `/System/Library` as read-only;
- invokes only fixed Apple executables without a shell;
- performs network access only after Help → Check for Updates;
- retains recoverable property-list backups and uses the macOS Trash.

These invariants are treated as release-blocking.
