#!/usr/bin/env bash
# Systemd Ease uninstaller. Removes the plugin; your own services,
# watchdog diaries (~/Documents/<name>), and unit files are left alone.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(python3 -c "import json; print(json.load(open('$SRC/manifest.json'))['id'])")"

omarchy plugin remove "$PLUGIN_ID" || rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
echo "✓ Removed. Run 'omarchy restart shell' to clear it from the bar."
