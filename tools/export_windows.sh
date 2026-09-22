#!/bin/sh
# Export the build the friends run: export/BOMBA.exe, one file with the pack embedded
# (export_presets.cfg, preset "Windows Desktop"). Needs Godot's 4.7.2 export templates installed
# once, either from the editor (Editor → Manage Export Templates → Download and Install) or:
#   curl -L -o "$TEMP/godot_templates.tpz" \
#     https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
#   unzip -j "$TEMP/godot_templates.tpz" 'templates/windows_*' -d "$APPDATA/Godot/export_templates/4.7.2.stable"
# (macOS: ~/Library/Application Support/Godot/export_templates/4.7.2.stable). Prints the size.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ver=$("$GODOT" --version 2>/dev/null | tail -1 | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?\.[a-z]+).*/\1/')
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) tdir="$APPDATA/Godot/export_templates/$ver" ;;
  Darwin) tdir="$HOME/Library/Application Support/Godot/export_templates/$ver" ;;
  *) tdir="$HOME/.local/share/godot/export_templates/$ver" ;;
esac
if [ ! -f "$tdir/windows_release_x86_64.exe" ]; then
  echo "FAIL  export templates missing: $tdir/windows_release_x86_64.exe (see the comment at the top of $0)"
  exit 1
fi
mkdir -p export
"$GODOT" --headless --path . --export-release "Windows Desktop" export/BOMBA.exe 2>&1 | grep -v -E "^\s*$" | tail -20
if [ -f export/BOMBA.exe ]; then
  echo "PASS  export/BOMBA.exe $(du -m export/BOMBA.exe | cut -f1) MB (templates $ver)"
else
  echo "FAIL  no export/BOMBA.exe written"
  exit 1
fi
