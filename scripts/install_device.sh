#!/usr/bin/env bash
# Build the Umlaut app (+ keyboard extension) and install it on a connected iPhone.
#
# Usage:
#   scripts/install_device.sh                 # first connected device, Debug
#   scripts/install_device.sh --release       # Release configuration
#   scripts/install_device.sh --device <udid|name>
#   scripts/install_device.sh --list          # show connected devices
#   scripts/install_device.sh --launch        # launch the app after installing
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="Debug"
DEVICE=""
LAUNCH=0
DERIVED="$ROOT/build/DerivedData-device"
BUNDLE_ID="de.codext.umlaut"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIG="Release"; shift ;;
    --debug) CONFIG="Debug"; shift ;;
    --device) DEVICE="${2:-}"; shift 2 ;;
    --launch) LAUNCH=1; shift ;;
    --list) xcrun devicectl list devices; exit 0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- pick a device ---------------------------------------------------------
devices_json="$(mktemp -t umlaut-devices)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null

if [[ -n "$DEVICE" ]]; then
  UDID="$(python3 - "$devices_json" "$DEVICE" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))["result"]["devices"]
q=sys.argv[2].lower()
for d in data:
    if d.get("connectionProperties",{}).get("tunnelState")=="unavailable": pass
    ident=d["identifier"]; name=d.get("deviceProperties",{}).get("name","")
    udid=d.get("hardwareProperties",{}).get("udid","")
    if q in (ident.lower(), name.lower(), udid.lower()):
        print(ident); break
PY
)"
  [[ -z "$UDID" ]] && { echo "No device matching '$DEVICE'. Try --list." >&2; exit 1; }
  DEVICE_NAME="$DEVICE"
else
  read -r UDID DEVICE_NAME < <(python3 - "$devices_json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))["result"]["devices"]
for d in data:
    if d.get("connectionProperties",{}).get("tunnelState")=="unavailable": continue
    props=d.get("deviceProperties",{})
    hw=d.get("hardwareProperties",{})
    if hw.get("platform")!="iOS": continue
    print(d["identifier"], props.get("name","iPhone")); break
PY
)
  [[ -z "${UDID:-}" ]] && { echo "No connected iOS device found. Unlock it and trust this Mac, then retry." >&2; exit 1; }
fi

echo "==> Device: $DEVICE_NAME ($UDID)"
echo "==> Configuration: $CONFIG"

# --- regenerate the Xcode project if project.yml changed -------------------
if command -v xcodegen >/dev/null 2>&1; then
  if [[ project.yml -nt Umlaut.xcodeproj/project.pbxproj ]]; then
    echo "==> project.yml changed, regenerating Xcode project"
    xcodegen generate
  fi
fi

# --- build -----------------------------------------------------------------
echo "==> Building"
XCB=(xcodebuild
  -project Umlaut.xcodeproj
  -scheme Umlaut
  -configuration "$CONFIG"
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED"
  -allowProvisioningUpdates
  build)

if command -v xcbeautify >/dev/null 2>&1; then
  "${XCB[@]}" | xcbeautify
else
  "${XCB[@]}"
fi

APP="$DERIVED/Build/Products/$CONFIG-iphoneos/Umlaut.app"
[[ -d "$APP" ]] || { echo "Build product not found at $APP" >&2; exit 1; }

# --- install ---------------------------------------------------------------
echo "==> Installing $APP"
xcrun devicectl device install app --device "$UDID" "$APP"

if [[ "$LAUNCH" == "1" ]]; then
  echo "==> Launching $BUNDLE_ID"
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
fi

cat <<'DONE'

Done. Reminder for the keyboard extension:
  Settings > General > Keyboard > Keyboards > Add New Keyboard… > Umlaut
  (and enable "Allow Full Access" if the keyboard needs it)
DONE
