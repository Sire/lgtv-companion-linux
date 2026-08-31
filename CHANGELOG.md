# Changelog

## Unreleased

First working version. Port of LGTV Companion's Wake-on-LAN plus webOS SSAP
power control to Linux.

- `lgtvc`: stdlib-only Python client (`setup`, `pair`, `state`, `on`, `off`,
  `screen-on`, `screen-off`, `wol`). Unsigned pairing manifest for current
  firmware. `on` sends magic packets at a steady 1 Hz from a thread while it
  connects, unblanks a `Screen Off` panel, and toggles the TV out of
  `Active Standby` once. `off` acts from `Screen Off` as well as `Active`.
  SSAP error replies and pairing problems are reported and exit 1, rather
  than being mistaken for an unreachable TV. `setup` validates IP, MAC and
  HDMI input and keeps an existing pairing key. `LGTVC_CONFIG` overrides the
  config path.
- `lgtvc-watch`: display-power watcher with Hyprland, sway, X11 and custom
  backends. Marks the TV in sync only after the command succeeds and retries
  a failed one every `LGTV_RETRY` seconds. Finds `lgtvc` next to itself when
  `~/.local/bin` is not on PATH.
- `install.sh`, systemd user unit, Omarchy autostart instructions.
