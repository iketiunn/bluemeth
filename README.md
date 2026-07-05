# bluemeth

Timed macOS `pmset disablesleep`.

Keeps a MacBook running for a fixed time when the lid is closed. It is a tiny
wrapper around:

```sh
sudo pmset -a disablesleep 1
```

## Install latest stable

```sh
curl -fsSL https://raw.githubusercontent.com/iketiunn/bluemeth/v1.0.1/install.sh | sh
```

## Install main

```sh
curl -fsSL https://raw.githubusercontent.com/iketiunn/bluemeth/main/install.sh | sh -s -- main
```

Make sure `~/.local/bin` is in your `PATH`.

## Usage

```sh
bluemeth        # 60 minutes
bluemeth 30     # 30 minutes
bluemeth off
bluemeth status
bluemeth -h
```

Max duration: `1440` minutes.

Timer state lives in `/var/run/bluemeth/disablesleep.token`, so it does not
survive reboot. Newer timers replace older timer tokens, which prevents an old
timer from turning sleep back on during a newer run.

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

## Warning

This changes system-wide macOS power settings with `sudo`.

Do not put the MacBook in a bag while active. Tiny CLI, real heat, bad physics.

## Uninstall

```sh
"$HOME/.local/bin/bluemeth" off && rm -f "$HOME/.local/bin/bluemeth"
```

## Development

```sh
bash test/smoke.sh
shellcheck bin/bluemeth install.sh test/smoke.sh
git diff --check
```
