# osystemd

**Manage systemd units from the Omarchy bar.**

List, search, filter, inspect, start/stop, enable/disable, mask, and view unit
files and journals — all from a compact bar widget and a rich panel UI.

## Features

- **List & Search** — View all units with real-time filtering by name or description.
- **Type & State Filters** — Chip-based toggles for service, timer, socket, mount, and more; filter by active/inactive/failed state.
- **Status Inspection** — Key fields at a glance: PID, load state, fragment path, activation timestamp.
- **Mutations** — Start, stop, restart, enable, disable, mask, unmask with confirmation-aware UI.
- **Unloaded Units Section** — View unit files installed on disk but not currently loaded by systemd (e.g., D-Bus-activated services like `fprintd`). Start, enable, disable, or mask them from the same panel.
- **Unit File Viewer** — Monospace rendering of unit file contents via `systemctl cat`.
- **Journal Peek** — Tail recent journal lines for any unit without leaving the panel.
- **Scope Toggle** — Switch between user and system scope instantly; system mutations use polkit elevation.
- **Bar Indicator** — Traffic-light dot with tooltip; pulses on failures, shows count badge.
- **Persistent Settings** — Type filters, state filters, refresh interval, and pinned units survive restarts via `settings.json`.

## Install

```bash
omarchy plugin add https://github.com/rickycbanks/osystemd.git
```

Then restart `omarchy-shell` (or wait for the shell to auto-detect the new plugin).

## Polkit Setup

System-scope mutations trigger `pkexec`, which prompts for your password by
default. If you want to cache the authorization for the session, see
[polkit/README.md](polkit/README.md) for an optional `.pkla` snippet.

> **Warning:** The polkit snippet grants `pkexec` access to all executables, not
> just `systemctl`.  Use only on single-user desktops.

## Configuration

Settings are stored as JSON at:

```
~/.local/state/quickshell/by-shell/<shell>/plugins/io.github.rickycbanks.osystemd/settings.json
```

| Field               | Type             | Default   | Description                                     |
|---------------------|------------------|-----------|-------------------------------------------------|
| `scope`             | string           | `"user"`  | `"user"` or `"system"`                          |
| `refreshIntervalMs` | int              | `30000`   | Auto-refresh interval in milliseconds            |
| `journalLines`      | int              | `100`     | Number of journal lines to fetch                |
| `typeFilter`        | list\<string\>   | (all)     | Unit types to show                              |
| `stateFilter`       | list\<string\>   | (active, inactive, failed) | Unit states to show       |
| `pinned`            | list\<string\>   | `[]`      | Unit names pinned to the top of the list        |

## Screenshots

> _Screenshots coming soon._

## Troubleshooting

### `python3: not found`
Ensure Python 3 is installed and on your `$PATH`. The plugin uses `python3` to
run the `units.py` helper.

### `pkexec` fails / no password prompt
- Verify `pkexec` is installed: `which pkexec`
- Ensure your user is in a group that polkit allows (usually `sudo` or `wheel`).
- Check polkit logs: `journalctl -u polkit.service`

### Journal access denied
Add your user to the `systemd-journal` group:
```bash
sudo usermod -aG systemd-journal $USER
```
Then log out and back in.

### Units missing
- Check that the scope matches what `systemctl list-units` shows.
- Ensure you're looking at the right type filter (some units are timers, not services).

### Panel doesn't appear
- Check `omarchy-shell` logs for QML errors.
- Verify the plugin directory is in the correct location for your shell profile.
- Ensure `units.py` is executable: `chmod +x units.py`.

## Credits

- [lgse/sandman](https://github.com/lgse/sandman) — Omarchy plugin patterns
- [Quickshell](https://quickshell.outfoxxed.me/) — QML shell framework
- [Omarchy](https://github.com/basecamp/omarchy) — Desktop environment
- [systemd](https://systemd.io/) — The init system

## License

[MIT](LICENSE)
