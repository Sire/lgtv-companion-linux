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
| `bin/lgtvc-watch` | Polls the desktop's display-power state and runs `lgtvc on` / `lgtvc off` in step. Backends: Hyprland, sway, X11, or a custom command. |
| `lgtvc-watch.service` | systemd user unit for the watcher. |
| `install.sh` | Symlinks both into `~/.local/bin`. `--service` installs and enables the unit. |

## Requirements

- Python 3.8 or newer, `bash`, `jq` (for the Hyprland and sway backends).
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

### Settings

| Env | Meaning | Default |
|---|---|---|
| `LGTV_OFF_CMD` | `off` (TV standby) or `screen-off` (blank panel, TV stays on) | `off` |
| `LGTV_MONITOR` | Output to watch (Hyprland and sway) | first output |
| `LGTV_POLL` | Poll interval in seconds | `1` |
| `LGTV_BACKEND` | `hyprland`, `sway`, `x11`, or `custom` | auto |
| `LGTV_QUERY_CMD` | For `custom`: a command that prints `true` or `false` | none |

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

To see what the watcher is doing, run it in a terminal: `LGTV_POLL=1 lgtvc-watch`.

## How this maps to LGTV Companion

| LGTV Companion (Windows) | Here |
|---|---|
| Windows service on `PBT_POWERSETTINGCHANGE` display on/off, plus its own user-idle tracking | `lgtvc-watch` polling the compositor's DPMS state. Idle detection is left to the desktop. |
| `onWOL`: magic packet to broadcast and to the IP every second | `wol()` every second inside `cmd_on` |
| `POWER_ON` state machine: `Active`, `Screen Off` to `turnOnScreen`, `Active Standby` to `turnOff` toggle | `cmd_on` |
| `POWER_OFF` and `BLANK_SCREEN` with the foreground-app HDMI check | `cmd_off` and `hdmi_ok` |
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
