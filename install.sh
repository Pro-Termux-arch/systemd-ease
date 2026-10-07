#!/usr/bin/env bash
# Systemd Ease installer for Omarchy.
# Copies this plugin into ~/.config/omarchy/plugins/, validates it,
# enables it, and puts it on the bar. Idempotent — safe to re-run
# for updates (your services and watchdogs are untouched).
#
# Usage: ./install.sh [--section right] [--no-bar] [--restart] [--yes]
set -euo pipefail

SECTION="right"
PLACE_BAR=1
DO_RESTART=0

for arg in "$@"; do
  case "$arg" in
    --section=*) SECTION="${arg#--section=}" ;;
    --section) shift ;;
    --no-bar) PLACE_BAR=0 ;;
    --restart) DO_RESTART=1 ;;
    --yes|-y) ;;
    -h|--help)
      echo "Usage: ./install.sh [--section right] [--no-bar] [--restart]"
      exit 0 ;;
    *) echo "Unknown flag: $arg (see --help)"; exit 2 ;;
  esac
  shift || true
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(python3 -c "import json; print(json.load(open('$SRC/manifest.json'))['id'])")"
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need omarchy; need omarchy-shell; need python3; need systemctl

echo "→ Installing $PLUGIN_ID"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$SRC/manifest.json" "$SRC/BarWidget.qml" "$SRC/Panel.qml" \
   "$SRC/Wizard.qml" "$SRC/Model.js" "$SRC/README.md" "$SRC/LICENSE" "$DEST/"
mkdir -p "$DEST/bin"
cp "$SRC/bin/systemd-ease" "$DEST/bin/"
chmod +x "$DEST/bin/systemd-ease"

echo "→ Validating"
omarchy plugin validate "$DEST"

echo "→ Registering with the shell"
omarchy-shell shell rescanPlugins
# Discovery is async — wait until the shell actually knows the plugin.
for i in $(seq 1 15); do
  if omarchy plugin list --json 2>/dev/null | grep -q "\"id\": *\"$PLUGIN_ID\""; then
    break
  fi
  sleep 1
done
omarchy plugin enable "$PLUGIN_ID"
if [ "$PLACE_BAR" -eq 1 ]; then
  omarchy bar put "$PLUGIN_ID" --section "$SECTION" || true
fi

echo ""
echo "✓ Installed. Click the cog in the bar to manage your services."
if [ "$DO_RESTART" -eq 1 ]; then
  echo "→ Restarting shell (required once for brand-new plugins)"
  omarchy restart shell
else
  echo "  First install? Run: omarchy restart shell   (one time only)"
  echo "  (Updates apply live — no restart needed next time.)"
fi
