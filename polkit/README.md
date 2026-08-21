# polkit — Optional Elevation Rules

By default, **osystemd** invokes `pkexec` for system-scope mutations (start,
stop, enable, disable, mask, unmask, daemon-reload). This triggers a graphical
password prompt each time — the standard polkit behaviour.

## Optional: Passwordless (cached) elevation

If you trust the logged-in user and want the password prompt only once per
session, you can install a polkit rule that caches the authorization.

Create the file `/etc/polkit-1/localauthority/50-local.d/osystemd.pkla`:

```ini
[Allow osystemd systemctl mutations]
Identity=*
Action=org.freedesktop.policykit.exec
ResultAny=yes
ResultInactive=yes
ResultActive=yes
```

### Why we don't ship this by default

- The `.pkla` snippet grants `pkexec` access to **all** executables, not just
  `systemctl`.  It is a blunt instrument.
- Security-sensitive systems (shared workstations, CI boxes) should keep the
  default prompt-for-password behavior.
- Some distributions have migrated from `.pkla` files to JavaScript rules
  (`/etc/polkit-1/rules.d/`).  The snippet above works on Debian/Ubuntu and
  older Fedora/RHEL; check your distro's polkit documentation for the
  equivalent rule syntax.

### Security / UX tradeoff

| Setting          | Security          | UX          |
|------------------|-------------------|-------------|
| Default (prompt) | Full sudo gate    | Password on each action |
| `.pkla` above    | Session-cached    | Prompt once, then cached |

Choose based on your threat model.
