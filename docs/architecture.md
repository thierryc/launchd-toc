# Architecture and Safety

## Boundaries

The app separates filesystem, process, clock, and networking effects behind injectable boundaries:

- `PlistRepository` scans, parses, validates, saves, backs up, and trashes property lists.
- `LaunchctlClient` is an actor behind `LaunchctlRunning`.
- `JobStore` is main-actor state that merges inventory and runtime information.
- `SchedulePreview`, `LogTailer`, and `UpdateChecker` are isolated services.
- `CommandExecuting` and `HTTPFetching` prevent tests from invoking real commands or networks.

`LaunchdJob`, `JobConfiguration`, `JobSource`, and `JobRuntimeState` are value models.

## Inventory

| Location | Source | Access |
| --- | --- | --- |
| `~/Library/LaunchAgents` | User Agents | Editable |
| `/Library/LaunchAgents` | Global Agents | Read-only |
| `/Library/LaunchDaemons` | Daemons | Read-only |
| `/System/Library/LaunchAgents` | Apple Agents | Read-only, opt-in display |
| `/System/Library/LaunchDaemons` | Apple Daemons | Read-only, opt-in display |

The Apple locations are disabled in Settings by default.

## Mutation safety

Before save or trash, the repository:

1. standardizes the requested URL;
2. requires a direct `.plist` child of the configured user LaunchAgents directory;
3. resolves the parent and destination against the canonical user directory;
4. rejects symbolic links and traversal;
5. rejects control characters and path separators;
6. validates the property-list tree through Foundation and `/usr/bin/plutil -lint`;
7. backs up existing files and writes atomically.

Only `/bin/launchctl` and `/usr/bin/plutil` are accepted by the live process runner. Arguments are always passed as arrays. Shells and constructed command strings are not used.

Global and Apple jobs are rejected by every mutation entry point. The app has no privileged helper and does not request administrator authentication.

## State degradation

The launchctl parser recognizes the narrow fields needed for the interface: state, PID, and last exit code. An absent service becomes Unloaded. Unrecognized successful output becomes Unknown so a future macOS text-format change cannot be mistaken for a safe known state.

## Editing preservation

The structured editor mutates supported keys on top of the complete parsed property-list tree. Unknown outer keys and nested values remain present. Advanced KeepAlive dictionaries and unknown calendar-entry values are preserved and displayed read-only. Existing XML or binary encoding is retained; new jobs use XML.

## Networking

There are no automatic requests. Help → Check for Updates fetches only:

`https://api.github.com/repos/thierryc/launchd-toc/releases/latest`

Drafts and prereleases are ignored. No authentication token or user data is sent.
