#!/bin/bash
set -e

echo "=========================================================="
echo "    macOS Sequoia 100% Offline Direct Installer"
echo "=========================================================="

# 1. Locate and cleanly mount the target APFS volume 'macwin'
echo ">>> Checking target APFS volume 'macwin'..."

# Clean up any stale unmounted empty directory in /Volumes to prevent 'macwin 1' collisions
if [ -d "/Volumes/macwin" ] && ! mount | grep -q "on /Volumes/macwin "; then
    echo "Removing stale unmounted /Volumes/macwin folder..."
    rmdir "/Volumes/macwin" 2>/dev/null || rm -rf "/Volumes/macwin" 2>/dev/null || true
fi

# Mount macwin
diskutil mount macwin 2>/dev/null || true

# Determine the actual mount point of macwin
TARGET=$(diskutil info macwin 2>/dev/null | awk -F': *' '/Mount Point/ {print $2}')

# Fallback: search for APFS volume with 'macwin' in diskutil list
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
    for dev in $(diskutil list | awk '/(macwin|APFS Volume)/ {print $NF}'); do
        if diskutil info "$dev" 2>/dev/null | grep -qi "macwin"; then
            diskutil mount "$dev" 2>/dev/null || true
            TARGET=$(diskutil info "$dev" 2>/dev/null | awk -F': *' '/Mount Point/ {print $2}')
            [ -n "$TARGET" ] && [ -d "$TARGET" ] && break
        fi
    done
fi

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
    echo "ERROR: Could not locate mounted target volume 'macwin'!"
    echo "Available volumes in /Volumes:"
    ls -la /Volumes
    exit 1
fi

echo "Target installation volume identified: $TARGET"

# Guard against booting from macwin itself
if [ "$TARGET" = "/Volumes/Image Volume" ]; then
    echo "FATAL ERROR: macwin is currently attached as /Volumes/Image Volume (Read-Only)!"
    echo "You must boot from the USB 'macOS Recovery (dmg)' entry, NOT from macwin."
    exit 1
fi

# Remount read-write if needed
mount -uw "$TARGET" 2>/dev/null || true

# Check write access on target volume
if [ ! -w "$TARGET" ]; then
    echo "Target is not writable, running fsck_apfs and remounting..."
    DEV=$(diskutil info "$TARGET" 2>/dev/null | awk -F': *' '/Device Node/ {print $2}')
    [ -n "$DEV" ] && fsck_apfs -y "$DEV" 2>/dev/null || true
    mount -uw "$TARGET" 2>/dev/null || true
    if [ ! -w "$TARGET" ]; then
        echo "ERROR: Target volume $TARGET is read-only!"
        exit 1
    fi
fi
echo "Target volume $TARGET is verified READ-WRITE."

# 2. Locate startosinstall across all mounted volumes
echo ">>> Locating Apple startosinstall binary..."
SI_BIN=""
for candidate in     "$TARGET/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall"     "/Volumes/INSTALLER/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall"     "/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall"     "/Volumes/Image Volume/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall"; do
    if [ -x "$candidate" ]; then
        SI_BIN="$candidate"
        break
    fi
done

if [ -z "$SI_BIN" ]; then
    SI_BIN=$(find /Applications /Volumes -name "startosinstall" -type f -perm +111 2>/dev/null | head -n 1)
fi

if [ -z "$SI_BIN" ] || [ ! -x "$SI_BIN" ]; then
    echo "ERROR: startosinstall executable not found!"
    echo "Available volumes in /Volumes:"
    ls -la /Volumes
    exit 1
fi

APP_DIR=$(dirname "$(dirname "$(dirname "$SI_BIN")")")
echo "Found installer application at: $APP_DIR"
echo "startosinstall binary: $SI_BIN"

# 3. Verify / Link 15.66 GB SharedSupport.dmg
echo ">>> Verifying offline installer payload..."
DMG="$APP_DIR/Contents/SharedSupport/SharedSupport.dmg"

DMG_VALID=0
if [ -f "$DMG" ]; then
    DMG_SIZE=$(stat -f %z "$DMG" 2>/dev/null || echo 0)
    if [ "$DMG_SIZE" -gt 14000000000 ]; then
        DMG_VALID=1
        echo "Installer payload verified ($DMG_SIZE bytes)."
    fi
fi

if [ "$DMG_VALID" -eq 0 ]; then
    echo "Searching for 15.66 GB InstallAssistant.pkg..."
    PKG=$(find /Volumes -name "InstallAssistant.pkg" -size +14G 2>/dev/null | head -n 1)
    if [ -z "$PKG" ]; then
        echo "ERROR: Could not find 15.66 GB offline installer payload!"
        exit 1
    fi
    echo "Found payload at: $PKG"

    if [ ! -w "$APP_DIR" ]; then
        echo "Installer app is on read-only volume. Staging to $TARGET/Applications..."
        mkdir -p "$TARGET/Applications"
        cp -R "$APP_DIR" "$TARGET/Applications/"
        APP_DIR="$TARGET/Applications/Install macOS Sequoia.app"
        SI_BIN="$APP_DIR/Contents/Resources/startosinstall"
        DMG="$APP_DIR/Contents/SharedSupport/SharedSupport.dmg"
    fi

    mkdir -p "$APP_DIR/Contents/SharedSupport"
    echo "Linking payload to $DMG..."
    ln -f "$PKG" "$DMG" 2>/dev/null || cp "$PKG" "$DMG"
fi

if [ ! -f "$DMG" ]; then
    echo "ERROR: SharedSupport.dmg is missing from $APP_DIR!"
    exit 1
fi

# 4. Clean any stale previous partial install data to ensure fresh Stage 1
if [ -d "$TARGET/macOS Install Data" ]; then
    echo "Cleaning previous install data on $TARGET..."
    rm -rf "$TARGET/macOS Install Data" 2>/dev/null || true
fi

# 5. Execute Apple's official startosinstall
echo ""
echo "=========================================================="
echo ">>> EXECUTING APPLE startosinstall (STAGE 1)"
echo ">>> Target: $TARGET"
echo ">>> Offline Mode: 100% local disk payload"
echo ">>> Preparing: 0% ... 100%"
echo "=========================================================="
echo ""

"$SI_BIN" --agreetolicense --volume "$TARGET"

sync
sync

echo ""
echo "=========================================================="
echo "    STAGE 1 COMPLETED SUCCESSFULLY!"
echo "=========================================================="
echo "NEXT STEPS:"
echo "1. The laptop will restart automatically in 5 seconds."
echo "2. If it pauses at 'Restarting...', wait 30 seconds,"
echo "   hold the power button to turn off, then power back on."
echo "3. In the OpenCore Boot Menu:"
echo "   >>> Press ENTER on: macOS Installer (or macwin)!"
echo "4. Stage 2 will start automatically (Apple logo + progress bar)."
echo "=========================================================="

sleep 5
reboot 2>/dev/null || true
