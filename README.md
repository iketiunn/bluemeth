# bluemeth

![BlueMeth](assets/hero.webp)

Timed macOS `pmset disablesleep`.

Keeps a MacBook running for a fixed time when the lid is closed. It is a tiny
wrapper around:

```sh
sudo pmset -a disablesleep 1
```

## Install latest stable

```sh
curl -fsSL https://raw.githubusercontent.com/iketiunn/bluemeth/v1.0.3/install.sh | sh
```

## Install main

```sh
curl -fsSL https://raw.githubusercontent.com/iketiunn/bluemeth/main/install.sh | sh -s -- main
```

Make sure `~/.local/bin` is in your `PATH`.

## ⚠️ Warning

This changes system-wide macOS power settings with `sudo`.

Every activation warns that a closed, running MacBook may overheat in a bag or
sleeve. Keep it ventilated and use your judgment; the timer is not a thermal
safety guarantee.

## Usage

```sh
bluemeth        # 60 minutes
bluemeth 30     # 30 minutes
bluemeth 180 --force
bluemeth off
bluemeth status
bluemeth -h
```

Normal maximum: `120` minutes. Use `--force` for longer sessions, up to the
absolute maximum of `1440` minutes (24 hours).

Bluemeth refuses to start if sleep is already disabled without an active
Bluemeth timer. Resolve the existing owner first, or run `bluemeth off` if you
intend to restore normal sleep.

Timer state lives in `/var/run/bluemeth/disablesleep.token`, so it does not
survive reboot. Newer timers replace older timer tokens, which prevents an old
timer from turning sleep back on during a newer run.

If bluemeth crashes or macOS reboots during a session, the timer may disappear
while `disablesleep` remains enabled. Restore normal sleep with:

```sh
bluemeth off
```

If bluemeth is unavailable, restore the setting directly with:

```sh
sudo pmset -a disablesleep 0
```

## Status

```sh
bluemeth status
# sleep: disabled
# timer: 42m left
```

`sleep` shows the current macOS sleep-disabled state.
`timer` shows the remaining time from bluemeth's stored expiry.

`timer: expired` means the marker is stale; run `bluemeth off` to restore normal
sleep behavior and clear it.

## Why not caffeinate?

`bluemeth` uses:

```sh
sudo pmset -a disablesleep 1
```

Use it for lid-close sleep behavior.

Use `caffeinate` for normal idle-sleep or command-scoped work:

```sh
caffeinate -i make
caffeinate -t 3600
```

## Uninstall

```sh
"$HOME/.local/bin/bluemeth" off && rm -f "$HOME/.local/bin/bluemeth"
```

## Development

```sh
bash test/smoke.sh
shellcheck bin/bluemeth install.sh test/smoke.sh test/behavior.sh
git diff --check
```
