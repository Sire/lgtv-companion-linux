# LGTV Companion for Linux

Turn an LG webOS TV on and off together with your Linux desktop. A TV used as
a monitor wakes when you touch the keyboard and sleeps when the desktop blanks
the screen.

This is an unofficial Linux port of the mechanism in
[LGTV Companion](https://github.com/JPersson77/LGTVCompanion) by
Jörgen Persson ([@JPersson77](https://github.com/JPersson77)). The approach
is his: Wake-on-LAN plus the webOS SSAP websocket, the pairing manifests, the
power-state machine, and the trick that enables WOL on the TV after pairing.
This project only redoes the Linux side. On Windows, use the original.
Not affiliated with LG Electronics or with LGTV Companion.

```
$ lgtvc off           # TV to standby
$ lgtvc on            # WOL + SSAP, TV back on (about 0.5 s with Quick Start+)
```

## Why

An LG TV on HDMI does not honor DPMS. When the compositor turns the output
off, the TV sees "no signal", goes to standby on its own timer, and a
returning signal does not bring it back. You reach for the remote. These TVs
have no DDC/CI over HDMI and most desktop GPUs have no CEC, so the only
reliable channel is the network.

- Wake: Wake-on-LAN magic packets (broadcast and direct to the TV's IP, once
  a second), then a websocket connection to get the TV to `Active`. A
  `Screen Off` state is unblanked, an `Active Standby` state is toggled on.
- Sleep: `ssap://system/turnOff` (standby) or `turnOffScreen` (panel
  blanked, TV stays on), optionally only if the TV is showing your HDMI input.

## What's in the box

| | |
|---|---|
| `bin/lgtvc` | The TV client. Python 3, standard library only, with its own small websocket implementation. No pip packages. |
| `bin/lgtvc-watch` | Polls the desktop's display-power state and runs `lgtvc on` / `lgtvc off` in step, and follows suspend and resume through logind. Backends: Hyprland, sway, X11, or a custom command. |
| `lgtvc-watch.service` | systemd user unit for the watcher. |
| `install.sh` | Symlinks both into `~/.local/bin`. `--service` installs and enables the unit. |

## Requirements

- Python 3.8 or newer, `bash`, `jq` (for the Hyprland and sway backends).
- For the suspend hook: logind, `systemd-inhibit`, and `gdbus` (glib2) or
  `dbus-monitor`. Missing, the watcher says so in its log and mirrors DPMS only.
- PC and TV on the same layer-2 network, since WOL is a broadcast. Give the
  TV a fixed IP or a DHCP reservation.
- A wired TV if possible. WOL over Wi-Fi works on some models and firmwares
  and not on others.
- On the TV: General > Devices/External devices > TV On With Mobile > Turn on
  via Wi-Fi/LAN, switched on (`lgtvc pair` tries to do this for you). Also
  switch on Quick Start+ if the model has it. It keeps the network stack alive
  in standby, which is the difference between a sub-second wake and a 10 to
  20 second one.

## Install

```bash
git clone https://github.com/Sire/lgtv-companion-linux.git
cd lgtv-companion-linux
./install.sh
```

Find the TV. It answers on TCP 3000 and 3001. IP and MAC are in its network
settings, or in `ip neigh` after you have talked to it once.

```bash
lgtvc setup 192.168.1.40 20:28:bc:b2:b4:30   # optional 3rd arg: HDMI input number
lgtvc pair                                   # accept the prompt on the TV with the remote
lgtvc state                                  # {"state": "Active", "returnValue": true}
lgtvc off && sleep 10 && lgtvc on            # round trip
```

`pair` stores the client key in `~/.config/lgtvc/config.json` (mode 600).
Giving `setup` your HDMI input number makes `off` a no-op while the TV is
showing anything else, so you do not cut someone's Netflix from the other
room.

## Run the watcher

### Omarchy

Omarchy's shell already handles the desktop side (idle, screensaver, lock,
DPMS off, and DPMS on at the first key press). The watcher mirrors that to
the TV. Add to `~/.config/hypr/autostart.lua`:

```lua
o.launch_on_start("lgtvc-watch")
```

### Hyprland or sway (exec-once)

```
exec-once = lgtvc-watch
```

### Anything else (systemd user unit)

```bash
./install.sh --service      # enables lgtvc-watch.service on graphical-session.target
```

The watcher needs the compositor's environment (`HYPRLAND_INSTANCE_SIGNATURE`,
`SWAYSOCK`, or `DISPLAY`). Most sessions import it into the systemd user
manager. If yours does not, launch the watcher from the compositor instead.

### Suspend and resume

Besides the display state, the watcher follows the machine's own sleep through
logind's `PrepareForSleep` signal:

- Going down: `lgtvc off`, skipped when the TV is already off. A delay
  inhibitor holds the suspend until the command returns, capped by
  `LGTV_SLEEP_TIMEOUT`. A reachable TV answers in about 0.3 s.
- Coming back: wait for a default route, then apply the current display state
  even when the TV is believed to be in it already.

The second half is the reason this exists. A machine suspended from a lit
screen comes back with the display still lit, so there is no DPMS transition to
poll for, while the TV has been in standby since the HDMI signal went away.
Polling alone sees no change and concludes it is in sync, and you reach for the
remote.

Between the two signals nothing is mirrored. The display can still answer "on"
long after the TV was told to stand by, and acting on that would wake the TV a
second before the machine suspends.

Shutdown and reboot are not handled. They tear the session down, and the TV
falls back to its own no-signal timer.

### Not every blank is bedtime

Mirroring the display state one to one works on a monitor and misbehaves on a
TV, where every transition costs a standby cycle and several seconds of
Wake-on-LAN. Two rules keep that in check.

A blank has to last `LGTV_OFF_DELAY` (60 s) before the TV is told to stand by.
Omarchy's lock screen blanks five seconds after the last keypress, so without
the delay the TV goes to standby, gets woken, and is dark again before you have
finished typing your password. Short blanks now never reach it. Set it to `0`
for the old behavior.

The TV is only woken while the user is there. When a TV powers off it drops the
HDMI link, the compositor loses the output, and the output that comes back a
second later reads as lit. Treating that as a wake had the TV switching itself
on in the middle of the night, the lock screen blanking it again five seconds
later, and round it went until the set stopped answering Wake-on-LAN at all.
The compositor's idle monitor is what tells a returning output from somebody
pressing a key. On Omarchy that source is found automatically; elsewhere set
`LGTV_ACTIVITY_CMD` to a command that prints `true` while the user is present.
With no source, every lit display counts as a wake, which is what it did
before.

### Settings

| Env | Meaning | Default |
|---|---|---|
| `LGTV_OFF_CMD` | `off` (TV standby) or `screen-off` (blank panel, TV stays on) | `off` |
| `LGTV_MONITOR` | Output to watch (Hyprland and sway) | first output |
| `LGTV_POLL` | Poll interval in seconds | `1` |
| `LGTV_RETRY` | Seconds before retrying a failed command, doubling on each further failure | `30` |
| `LGTV_RETRY_MAX` | Ceiling for that wait | `300` |
| `LGTV_OFF_DELAY` | Seconds the display must stay dark before the TV is put into standby | `60` |
| `LGTV_ACTIVITY_CMD` | Command printing `true` while the user is present | omarchy-shell, if installed |
| `LGTV_BACKEND` | `hyprland`, `sway`, `x11`, or `custom` | auto |
| `LGTV_QUERY_CMD` | For `custom`: a command that prints `true` or `false` | none |
| `LGTV_SLEEP` | `1` follows suspend and resume, `0` is DPMS only | `1` |
| `LGTV_SLEEP_TIMEOUT` | Seconds the off before suspend may take | `5` |
| `LGTV_RESUME_WAIT` | Seconds to wait for a default route after resume before waking the TV anyway | `30` |
| `LGTV_SLEEP_MONITOR` | Command printing logind sleep events, for tests | `gdbus`, else `dbus-monitor` |

### Turning the sleep hook back off

`LGTV_SLEEP=0` leaves the plain DPMS mirror, with no inhibitor and no D-Bus
client. Per run:

```bash
LGTV_SLEEP=0 lgtvc-watch
```

For a session-wide setting, put it where the session manager will import it,
then restart the watcher:

```bash
echo LGTV_SLEEP=0 > ~/.config/environment.d/lgtvc.conf
```

To drop the feature entirely, revert the commit that added it: `bin/lgtvc-watch`
is the only file with any of it.

## Command reference

```
lgtvc setup <ip> <mac> [hdmi]   write ~/.config/lgtvc/config.json
lgtvc pair                      pair with the TV (60 s to accept on screen); enables WOL on the TV
lgtvc state                     print the power state JSON
lgtvc on                        WOL + connect loop (30 s max) until the TV is Active
lgtvc off                       standby (skipped if the TV is not on your HDMI input)
lgtvc screen-off / screen-on    blank / unblank the panel, TV stays on
lgtvc wol                       send the magic packets and exit
```

## Does it work on my distro or desktop?

`lgtvc` runs anywhere with Python 3: every Linux, also macOS and BSD.

`lgtvc-watch` needs a way to read the display power state.

| Desktop | Backend | Status |
|---|---|---|
| Hyprland (Omarchy and others) | `hyprctl monitors -j` | tested |
| sway and other wlroots compositors with sway IPC | `swaymsg -t get_outputs` | untested |
| X11, any desktop | `xset q` | untested |
| GNOME or KDE on Wayland | none | no public DPMS query. Use `LGTV_QUERY_CMD`, or call `lgtvc on` and `lgtvc off` from your idle tool. |

If your idle daemon can run commands (`hypridle`, `swayidle`, `xss-lock`),
you do not need the watcher at all:

```
listener { timeout = 300; on-timeout = lgtvc off; on-resume = lgtvc on }
```

## Troubleshooting

If pairing fails with `403 Pairing rejected: blacklisted certificate
detected`, the client is sending the classic signed `com.lge.test` manifest.
This project uses the unsigned manifest (LGTV Companion's "V3"), which
current firmware accepts.

`server closed websocket` right after `off` is normal. In standby the TV
still accepts TCP on 3001 but drops the socket at registration. `lgtvc on`
handles it with WOL and a retry loop.

If the TV does not wake, check that WOL is on in the TV's settings and that
the TV is on the same subnet. Try Ethernet instead of Wi-Fi. `lgtvc wol`
sends packets without waiting; watch the TV's status LED.

If the TV wakes on the wrong input, set the HDMI input as the default in the
TV. Launching `com.webos.app.hdmiN` the way LGTV Companion does is not
implemented yet.

To see what the watcher is doing, read its log: `journalctl --user -t lgtvc-watch -f`.
It routes stderr into the journal whenever stderr is not a terminal, because a
session autostart usually hands it `/dev/null` and every diagnostic would be
lost. Run it in a terminal (`lgtvc-watch`) and the lines come back to you
instead.

## How this maps to LGTV Companion

| LGTV Companion (Windows) | Here |
|---|---|
| Windows service on `PBT_POWERSETTINGCHANGE` display on/off, plus its own user-idle tracking | `lgtvc-watch` polling the compositor's DPMS state. Idle detection is left to the desktop. |
| `onWOL`: magic packet to broadcast and to the IP every second | `wol()` every second inside `cmd_on` |
| `POWER_ON` state machine: `Active`, `Screen Off` to `turnOnScreen`, `Active Standby` to `turnOff` toggle | `cmd_on` |
| `POWER_OFF` and `BLANK_SCREEN` with the foreground-app HDMI check | `cmd_off` and `hdmi_ok` |
| System suspend and resume handling in the service | logind `PrepareForSleep` in `lgtvc-watch`, with a delay inhibitor |
| Pairing with the unsigned "V3" manifest, client key persisted | `TV.connect`, `~/.config/lgtvc/config.json` |
| `JSON_LUNA_SET_WOL` alert trick to enable WOL after pairing | `cmd_pair` |
| boost.beast websocket, wss 3001 and ws 3000 | About 80 lines of RFC 6455 on `ssl` and `socket`, tries 3001 then 3000 |

Not ported: the GUI, multi-device and remote-desktop handling, button and
luna commands, HDMI input switching, the Windows updater.

## Status

Early. Tested with one 2023 LG TV (webOS, "LG TV SSCR2") on Hyprland and
Omarchy over Wi-Fi. Reports from other models and desktops are welcome.

## License

MIT, see [LICENSE](LICENSE). LGTV Companion is copyright Jörgen Persson, MIT.
