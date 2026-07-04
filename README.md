# bluemeth

Keep your agent alive when the lid is closed.

Timed lid-close sleep disable for macOS. Tiny script, sharp edge, clear timer.

`bluemeth` is a tiny wrapper around:

```sh
sudo pmset -a disablesleep 1
```

It is intentionally not a `caffeinate` clone. `caffeinate` creates temporary
I/O Kit power assertions for idle sleep or command-scoped work. `bluemeth`
changes the macOS `pmset` `disablesleep` setting, which is the rough tool for
the "keep running when I close the MacBook lid" case.

## Safety First

- This changes system-wide macOS power settings with `sudo`.
- It is for lid-close sleep behavior, not general power management.
- Maximum runtime is `1440` minutes, or 24 hours.
- Bad input exits before changing `pmset`.
- It does not manage display sleep, hibernation, standby, or external-display
  clamshell mode.
- Timer state lives in `/var/run`; it does not need to survive reboot.

## Install

```sh
mkdir -p "$HOME/.local/bin" && curl -fsSL https://raw.githubusercontent.com/iketiunn/bluemeth/main/bin/bluemeth -o "$HOME/.local/bin/bluemeth" && chmod +x "$HOME/.local/bin/bluemeth"
```

Make sure `~/.local/bin` is in your shell path:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Usage

```sh
bluemeth        # enable for 60 minutes
bluemeth 30     # enable for 30 minutes
bluemeth 1440   # enable for one day, the maximum allowed duration
bluemeth off    # turn it off now
bluemeth status # show SleepDisabled and bluemeth token state
bluemeth -h     # help
```

Every command that changes sleep state uses `sudo`, because `pmset` writes
system power settings. Durations must be positive whole minutes and cannot be
longer than `1440` minutes, or 24 hours. Invalid input exits before changing
`pmset`.

## What It Does

When enabled, `bluemeth`:

1. Writes a timer token to `/var/run/bluemeth/disablesleep.token`.
2. Runs `sudo pmset -a disablesleep 1`.
3. Starts a background timer.
4. After the timer expires, turns sleep back on only if its token is still the
   current token.

That token check avoids the old-timer problem:

```sh
bluemeth 30
bluemeth 60
```

The 30-minute timer will not turn sleep back on early, because the 60-minute
run replaces the token.

## bluemeth vs caffeinate

Use `bluemeth` when your target behavior is lid-close sleep disabling through
`pmset disablesleep`.

Use `caffeinate` when your target behavior is temporary idle-sleep prevention
while a command runs:

```sh
caffeinate -i make
caffeinate -t 3600
```

`caffeinate -s` creates a system-sleep assertion, but Apple's man page notes
that assertion is valid only on AC power. `bluemeth` is intentionally aimed at
the different `pmset disablesleep` behavior.

## Status

```sh
bluemeth status
```

Example:

```text
SleepDisabled: 1
token: present
```

`SleepDisabled` comes from `pmset -g`.

## Uninstall

```sh
"$HOME/.local/bin/bluemeth" off && rm -f "$HOME/.local/bin/bluemeth"
```

## Development

Run tests:

```sh
bash test/bluemeth_test.sh
```

The tests use fake `sudo`, `pmset`, and `sleep` commands. They do not change
real macOS power settings.
