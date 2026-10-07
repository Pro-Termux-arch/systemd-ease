# Systemd Ease — an Omarchy plugin

Manage systemd services without learning systemd. A cog icon lives in your
bar (it turns red with a count when something crashes); click it and you get
plain-word control over every service on the machine.

No terminal needed. No unit-file syntax to memorize.

## Install (one command)

```sh
./install.sh
```

That copies the plugin into `~/.config/omarchy/plugins/`, validates it,
enables it, and puts the cog on your bar. Then restart the shell once when
asked (`omarchy restart shell`) — click the cog, that's it.

Options: `./install.sh --section left` to choose the bar section,
`./install.sh --no-bar` to skip bar placement. `./uninstall.sh` removes it.

## Manual install

If you'd rather do it by hand:

```sh
cp -r . ~/.config/omarchy/plugins/io.github.proadmin.systemd-ease
omarchy plugin validate ~/.config/omarchy/plugins/io.github.proadmin.systemd-ease
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.proadmin.systemd-ease
omarchy bar put io.github.proadmin.systemd-ease --section right
omarchy restart shell
```

To remove: `omarchy plugin remove io.github.proadmin.systemd-ease`,
then `omarchy restart shell`.

## What you can do

- **See everything** — every service, system + user, with live state.
- **Search** — type a few letters (`/` jumps to the search box).
- **Filter by whose it is** — *Everything*, *Mine + added* (your units and
  anything downloaded software installed), or *Preinstalled* (ships with the
  OS, hands off). Plus scope (System/User) and state (Running/Crashed/At boot)
  filters.
- **Start / Stop** — one button, plain words.
- **Boot toggle** — one switch: does it start when you log in?
- **Restart, Block/Unblock** — block means "can't start at all, not even by
  hand" (systemd mask, with a confirm step).
- **Logs** — view, reload, save to a file, or copy for your AI agent.
- **Boot times** — which units slow down your startup.
- **Delete** — only for units that are safe to delete (yours + added ones).
  Preinstalled services can never be deleted from here, only stopped.
- **Create** — a 3-step guide:
  1. *What runs?* An installed app (pick from the searchable list), a
     command (e.g. `btop`, with an optional terminal window), or an
     AppImage (file picker, auto made executable).
  2. *Name it* — plus start-at-login, restart-on-crash, and watchdog options.
  3. *Done* — it starts right away.

## The watchdog (crash diary)

When creating a service you are asked: **watch over it?**

- **No** — plain service, nothing extra.
- **Yes** — three things happen:
  1. The service restarts itself if it crashes (`Restart=on-failure`).
  2. A per-minute checker is installed (`<name>-watchdog.timer`).
  3. A folder `~/Documents/<name>/` is created with `watchdogdata.txt` —
     state snapshots + recent logs, appended every minute, trimmed so it
     stays shareable.

If the service ever fails: stop it, open `~/Documents/<name>/watchdogdata.txt`,
hand the file to your AI agent. It contains everything needed to diagnose.

## Safety

- Vendor (preinstalled) units: **delete is refused**, always.
- System-scope changes may ask for your password **once** via the normal
  polkit dialog — the plugin never stores it.
- Destructive actions (delete, block, boot-off for system services) ask for
  confirmation first.
- Everything the plugin creates lives in `~/.config/systemd/user/` (no root
  needed) except the optional debug folder in `~/Documents/`.

## Files

| File | What it is |
|---|---|
| `manifest.json` | Plugin contract (bar-widget) |
| `BarWidget.qml` | Bar icon + crash badge + panel loader |
| `Panel.qml` | List / logs / boot-times views |
| `Wizard.qml` | 3-step service creator |
| `Model.js` | Filter + wording helpers |
| `bin/systemd-ease` | Backend: list/action/logs/apps/create/delete/watchdog (python3, stdlib only) |

Theming is automatic: every color, font, spacing and corner comes from the
Omarchy `Style`/`Color`/bar tokens, so it follows your theme with zero config.

## Scripting (IPC)

```sh
omarchy-shell io.github.proadmin.systemd-ease toggle   # open/close the panel
omarchy-shell io.github.proadmin.systemd-ease status   # e.g. "0 failed"
omarchy-shell io.github.proadmin.systemd-ease refresh  # refresh the bar badge
```

## Requirements

Omarchy Quattro shell, `systemctl`, `journalctl`, `python3` (stdlib only),
`wl-copy` + `xdg-open` (both ship with Omarchy).
