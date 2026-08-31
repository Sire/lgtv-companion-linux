#!/bin/bash
# Symlink lgtvc + lgtvc-watch into ~/.local/bin. With --service, also install
# and enable the systemd user unit for the watcher.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bindir="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$bindir"

for f in lgtvc lgtvc-watch; do
  chmod +x "$here/bin/$f"
  ln -sfn "$here/bin/$f" "$bindir/$f"
  echo "linked $bindir/$f"
done

case ":$PATH:" in
*":$bindir:"*) ;;
*) echo "note: $bindir is not on your PATH" ;;
esac

if [[ ${1:-} == "--service" ]]; then
  unitdir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$unitdir"
  sed "s|@BINDIR@|$bindir|" "$here/lgtvc-watch.service" >"$unitdir/lgtvc-watch.service"
  systemctl --user daemon-reload
  systemctl --user enable --now lgtvc-watch.service
  echo "enabled lgtvc-watch.service"
fi

echo "next: lgtvc setup <ip> <mac> [hdmi-input] && lgtvc pair"
