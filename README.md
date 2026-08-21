# osystemd — Omarchy plugin

A systemd unit manager for the Omarchy (Quickshell) bar.

> **Rename note:** This plugin was previously published as `lgse.systemd`. The new id
> is `osystemd`. After upgrading, your preferences will reset — the settings file
> moved from `~/.config/omarchy/systemd.json` to `~/.config/omarchy/osystemd.json`.

## Features

- List, search, and filter units (services, timers, sockets, paths)
- Start / stop / restart / reload
- Enable / disable / reenable / mask / unmask
- View recent journal logs
- View unit file content
- Edit unit files (launches a terminal with `systemctl edit --full`)
- User and system scope (separate or combined)
- Favorites
- Persistent settings (favorites, last scope/filters)

## Install

```
omarchy plugin add <repo-url>
```

Replace `<repo-url>` with the GitHub URL of this repository once it is published.

## Permissions

User-scope units are unprivileged. System-scope actions (start, stop, enable, etc.) require polkit authentication — the existing `omarchy.polkit` plugin handles the themed dialog automatically.

If you want system actions without repeated prompts, you can install a polkit rule allowing your user to manage systemd units without password. Create `/etc/polkit-1/rules.d/99-systemd-user.rules`:

```
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.systemd1.") === 0 &&
      subject.local && subject.active && subject.isInGroup("wheel")) {
    return polkit.Result.YES;
  }
});
```

## Settings

Right-click the bar icon (or whatever your shell uses for settings) to configure:
- Show failed-unit count on the bar icon
- Default scope (user / system / all)
- Default unit type filter
- Default state filter
- Refresh interval (seconds)
- Journal lines to load initially
- Show sub-state in unit rows

## Troubleshooting

- **Bar icon shows `󰅖` and tooltip says "systemctl not found"** — install systemd, or check that `systemctl` is on `$PATH`.
- **User scope disabled** — your user session has no systemd user instance. Try `systemctl --user status`; if it errors, you may need `loginctl enable-linger $USER`.
- **Actions fail with "Access denied"** — polkit denied authorization. Check `/var/log/auth.log` or run the action in a terminal to see the full message.
- **System unit file edits fail** — `systemctl edit` requires a terminal and `$EDITOR` set. Install your editor and set `EDITOR` in your shell rc.

## Credits

- Visual design inspired by [lgse/sandman](https://github.com/lgse/sandman)
- Feature reference: [plrigaux/sysd-manager](https://github.com/plrigaux/sysd-manager)
- Built for [Omarchy](https://omarchy.org)
