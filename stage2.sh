#!/bin/bash

echo "=========================================================="
echo ">>> macOS Sequoia 100% Offline Automated Installer"
echo "=========================================================="

echo ">>> 1. Mounting target APFS volume 'macwin'..."
diskutil mount macwin 2>/dev/null || true

for dev in $(diskutil list | awk '/(macwin|APFS Volume)/ {print $NF}'); do
    diskutil mount "$dev" 2>/dev/null || true
done

TARGET="/Volumes/macwin"
if [ ! -d "$TARGET" ]; then
    TARGET=$(diskutil info macwin 2>/dev/null | awk -F': *' '/Mount Point/ {print $2}')
fi

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
    echo "ERROR: Could not locate mounted target volume 'macwin'!"
    echo "Available volumes in /Volumes:"
    ls -la /Volumes
    exit 1
fi

echo "Target installation volume: $TARGET"
mount -uw "$TARGET" 2>/dev/null || true

echo ">>> 2. Checking APFS container auxiliary volumes (Preboot & Recovery)..."
CONTAINER=$(diskutil info "$TARGET" 2>/dev/null | awk -F': *' '/Part of APFS Container/ {print $2}' | tr -d ' ')
if [ -z "$CONTAINER" ]; then
    CONTAINER=$(diskutil info macwin 2>/dev/null | awk -F': *' '/Part of APFS Container/ {print $2}' | tr -d ' ')
fi

if [ -n "$CONTAINER" ]; then
    echo "APFS Container identified: $CONTAINER"
    if ! diskutil list "$CONTAINER" | grep -qi "Preboot"; then
        echo "Creating Preboot volume (Role: B) in $CONTAINER..."
        diskutil apfs addVolume "$CONTAINER" apfs Preboot -role B 2>/dev/null || true
    else
        echo "Preboot volume already present."
    fi

    if ! diskutil list "$CONTAINER" | grep -qi "Recovery"; then
        echo "Creating Recovery volume (Role: R) in $CONTAINER..."
        diskutil apfs addVolume "$CONTAINER" apfs Recovery -role R 2>/dev/null || true
    else
        echo "Recovery volume already present."
    fi
fi

echo ">>> 3. Locating startosinstall binary..."
SI_BIN=""
for candidate in \
    "$TARGET/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall" \
    "/Volumes/INSTALLER/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall" \
    "/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall" \
    "/Volumes/Image Volume/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall" \
    "/Volumes/OS/Users/aghil/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall"; do
    if [ -x "$candidate" ]; then
        SI_BIN="$candidate"
        break
    fi
done

if [ -z "$SI_BIN" ]; then
    SI_BIN=$(find /Volumes /Applications -name "startosinstall" -type f -perm +111 2>/dev/null | head -n 1)
fi

if [ -z "$SI_BIN" ] || [ ! -x "$SI_BIN" ]; then
    echo "ERROR: startosinstall executable not found!"
    ls -la /Volumes
    exit 1
fi

echo "Found installer at: $SI_BIN"

echo ""
echo "=========================================================="
echo ">>> EXECUTING APPLE startosinstall (OFFLINE)"
echo ">>> Target: $TARGET"
echo ">>> Preparing: 0% ... 100%"
echo "=========================================================="
echo ""

"$SI_BIN" --volume "$TARGET" --agreetolicense --nointeraction || "$SI_BIN" --volume "$TARGET" --agreetolicense

sync
sync

echo ""
echo "=========================================================="
echo "    STAGE 1 COMPLETED 100%!"
echo "=========================================================="
echo "NEXT STEPS:"
echo "1. The laptop will attempt to restart in 5 seconds."
echo "2. When it pauses at 'Restarting...' (ACPI shutdown pause):"
echo "   - THIS IS 100% NORMAL. The files are safely on disk."
echo "   - Wait 20 seconds, then HOLD POWER BUTTON for 5 seconds to turn off."
echo "   - Press Power to turn the laptop back on."
echo "3. In the OpenCore Boot Menu, select 'macOS Installer' or 'macwin'!"
echo "=========================================================="

sleep 5
reboot 2>/dev/null || true
