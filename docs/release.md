# Release Process

Launchd TOC is distributed as a universal Developer ID application in a notarized DMG.

## Versioning

- `MARKETING_VERSION` starts at `0.1.0`.
- The first planned tag is `v0.1.0-beta.1`.
- The release workflow requires the stable numeric portion of the tag to equal `MARKETING_VERSION`.
- Tags containing a hyphen are published as GitHub prereleases.
- The in-app checker follows only GitHub’s stable `/releases/latest` response.

## Required GitHub Actions secrets

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 Developer ID Application certificate and private key |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Export password for the P12 |
| `KEYCHAIN_PASSWORD` | Password for the ephemeral CI keychain |
| `APP_STORE_CONNECT_KEY_ID` | Notarytool API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | Base64 contents of the `.p8` API key |

Secrets must never be committed or written to logs.

## Automated checks

On a signed `v*` tag, `.github/workflows/release.yml`:

1. verifies the tag/version relationship;
2. imports the certificate into an ephemeral keychain;
3. archives a universal arm64/x86_64 app with Hardened Runtime;
4. verifies the signature, architectures, bundle identifier, and absence of sandbox entitlement;
5. builds a DMG containing the app and an Applications shortcut;
6. submits with `notarytool --wait`;
7. staples and validates the ticket;
8. runs Gatekeeper assessment and a mounted-image smoke check;
9. emits a SHA-256 checksum;
10. creates a stable release or prerelease with generated notes.

The ephemeral keychain and API key file are removed by an always-run cleanup step.

## Local unsigned package check

After a Release build:

```sh
scripts/package_dmg.sh \
  "/path/to/Launchd TOC.app" \
  "0.1.0" \
  "build"
```

Notarization requires CI secrets or equivalent local App Store Connect credentials.
