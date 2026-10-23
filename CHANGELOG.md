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
- `lgtvc-watch` follows system suspend and resume through logind's
  `PrepareForSleep` signal, because neither has to produce a DPMS transition:
  a machine suspended from a lit screen resumes with the display still lit
  while the TV has long since stood by on no signal. Off before the suspend
  (a delay inhibitor holds it until the command returns), and after resume the
  current display state is applied even when the TV is believed to match.
  Nothing is mirrored between the two signals. `LGTV_SLEEP=0` turns the whole
  hook off, `LGTV_SLEEP_TIMEOUT`, `LGTV_RESUME_WAIT` and `LGTV_SLEEP_MONITOR`
  tune it.
- `lgtvc-watch` waits `LGTV_OFF_DELAY` (60 s) of unbroken darkness before
  putting the TV into standby, and only wakes it while the user is present,
  asked of the compositor's idle monitor (`LGTV_ACTIVITY_CMD`, auto-detected
  on Omarchy). Mirroring every transition put the set through a standby cycle
  each time a lock screen blanked after five seconds, and a TV that powers off
  drops the HDMI link, so the output the compositor gets back reads as lit and
  looked like a wake. The two together had the TV cycling itself all night.
- `lgtvc-watch` doubles the wait after each consecutive failure up to
  `LGTV_RETRY_MAX` (300 s), instead of retrying a TV that is not answering
  every 30 s forever.
- `lgtvc-watch` routes stderr into the journal (`journalctl --user -t
  lgtvc-watch`) when stderr is not a terminal. Session autostarts hand it
  `/dev/null`, which made every diagnostic disappear.
- `lgtvc wol` also sends the magic packet to the directed broadcast of the
  local subnet holding the TV's IP. `255.255.255.255` only leaves through the
  default route, so a TV on a second interface (a direct cable) never saw it,
  and the unicast copy needs an ARP reply a sleeping TV does not give.
- `install.sh`, systemd user unit, Omarchy autostart instructions.
