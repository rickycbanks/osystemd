# polkit — System-Scope Authorization

System-scope mutations (start, stop, enable, disable, mask, unmask, daemon-reload)
invoke `systemctl` directly. If your user has sufficient privileges (e.g. is in
the `wheel` / `sudo` group with an appropriate polkit rule, or systemd's built-in
user/group checks allow the operation), the action succeeds. Otherwise systemd
itself will trigger a polkit authentication prompt via the session's polkit agent.

## Previous versions used pkexec

Earlier releases of osystemd wrapped system-scope `systemctl` calls with
`pkexec`, which shells out to `org.freedesktop.policykit.exec`. A
`.pkla`-file example was included in this directory that granted unconditional
`ResultAny=yes` for `Action=org.freedesktop.policykit.exec` with `Identity=*`.

**That policy must be removed if you installed it.** The file is typically at:

```
/etc/polkit-1/localauthority/50-local.d/osystemd.pkla
```

Removing the dangerous `.pkla` or its JavaScript equivalent is critical because:

- `org.freedesktop.policykit.exec` authorises **any** program the invoking user
  chooses to run via `pkexec`, not merely `systemctl`. A user with this rule can
  execute arbitrary commands as root — it is not a narrowly scoped osystemd
  authorization.
- Caching a passwordless grant for `org.freedesktop.policykit.exec` with
  `Identity=*` effectively gives every local user unrestricted root access for
  the duration of the session.

## Why no passwordless policy rule

A polkit rule for the current `systemctl` command form cannot safely constrain
arguments. The `pkexec` action (`org.freedesktop.policykit.exec`) is
action-generic — polkit sees only the executable name and the action ID, not
the full argument vector. Any rule that grants `org.freedesktop.policykit.exec`
unconditionally authorises arbitrary pkexec invocations, not just the intended
`systemctl start nginx.service`.

## Recommended approach

Use your desktop environment's normal polkit authentication:

- Ensure a polkit authentication agent is running in your session (e.g.
  `polkit-gnome`, `polkit-kde-agent`, or Omarchy's built-in
  `Quickshell.Services.Polkit` agent).
- For passwordless operation, configure a polkit rule scoped to a **specific
  system unit** via a custom `.rules` or `.pkla` file that matches the unit
  name in the action details — not the generic `pkexec` action. Consult your
  distribution's polkit documentation for the correct rule format.

Do **not** grant `org.freedesktop.policykit.exec` unconditionally or with
`Identity=*`.
