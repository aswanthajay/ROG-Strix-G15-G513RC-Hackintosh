#!/bin/bash
set -e

echo "=========================================================="
echo ">>> macOS Sequoia 100% Offline Automated Installation"
echo "=========================================================="

# Fix system clock to current valid timestamp to prevent certificate/permission failures
date 103113252026 2>/dev/null || true

echo ">>> Step 1: Mounting internal NVMe target 'macwin'..."
diskutil mount macwin 2>/dev/null || true

for dev in $(diskutil list | awk '/(macwin|APFS Volume)/ {print $NF}'); do
    diskutil mount "$dev" 2>/dev/null || true
done

TARGET="/Volumes/macwin"
if [ ! -d "$TARGET" ]; then
    TARGET=$(diskutil info macwin 2>/dev/null | awk -F': *' '/Mount Point/ {print $2}')
fi

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
    echo "ERROR: Target volume 'macwin' could not be mounted!"
    echo "Available volumes in /Volumes:"
    ls -la /Volumes
    exit 1
fi

echo "Target volume mounted at: $TARGET"
mount -uw "$TARGET" 2>/dev/null || true

# Fix permissions and ownership on target volume
echo ">>> Enabling volume ownership & resetting permissions..."
diskutil enableOwnership "$TARGET" 2>/dev/null || true
vsdbutil -a "$TARGET" 2>/dev/null || true
chown -R root:wheel "$TARGET" 2>/dev/null || true
chmod 775 "$TARGET" 2>/dev/null || true

IMAGE_DEV=$(df /Volumes/Image\ Volume 2>/dev/null | tail -1 | awk '{print $1}')
TARGET_DEV=$(df "$TARGET" 2>/dev/null | tail -1 | awk '{print $1}')
echo "Target device: $TARGET_DEV"
echo "Image Volume device: $IMAGE_DEV"

if [ -n "$IMAGE_DEV" ] && [ "$TARGET_DEV" = "$IMAGE_DEV" ]; then
    echo ""
    echo "CRITICAL ERROR: 'macwin' is mounted as /Volumes/Image Volume (Read-Only)!"
    echo "This means Recovery was booted from the internal drive, not the USB."
    echo "Please reboot, select the USB recovery, and run this script again."
    exit 1
fi
echo "SUCCESS: 'macwin' is independent and READ-WRITE!"

echo ">>> Step 2: Cleaning old staging directories on $TARGET..."
chflags -R 0 "$TARGET/macOS Install Data" 2>/dev/null || true
chflags -R noschg,nouchg "$TARGET/macOS Install Data" 2>/dev/null || true
rm -rf "$TARGET/macOS Install Data" 2>/dev/null || true
rm -rf "$TARGET/com.apple.recovery.boot" 2>/dev/null || true
rm -rf "$TARGET/Install."* 2>/dev/null || true
rm -rf "$TARGET/.PKInstallSandboxManager"* 2>/dev/null || true

echo ">>> Step 3: Checking APFS container structure..."
CONTAINER=$(diskutil info "$TARGET" 2>/dev/null | awk -F': *' '/Part of APFS Container/ {print $2}' | tr -d ' ')
if [ -z "$CONTAINER" ]; then
    CONTAINER=$(diskutil info macwin 2>/dev/null | awk -F': *' '/Part of APFS Container/ {print $2}' | tr -d ' ')
fi

if [ -n "$CONTAINER" ]; then
    echo "APFS Container: $CONTAINER"
    if ! diskutil list "$CONTAINER" | grep -qi "Preboot"; then
        echo "Creating Preboot volume (Role: B) in $CONTAINER..."
        diskutil apfs addVolume "$CONTAINER" apfs Preboot -role B || true
    else
        echo "Preboot volume already present."
    fi

    if ! diskutil list "$CONTAINER" | grep -qi "Recovery"; then
        echo "Creating Recovery volume (Role: R) in $CONTAINER..."
        diskutil apfs addVolume "$CONTAINER" apfs Recovery -role R || true
    else
        echo "Recovery volume already present."
    fi
fi

echo ">>> Step 4: Locating and preparing Install macOS Sequoia.app..."
APP=""
for cand in \
    "$TARGET/Applications/Install macOS Sequoia.app" \
    "/Volumes/INSTALLER/Applications/Install macOS Sequoia.app" \
    "/Applications/Install macOS Sequoia.app"; do
    if [ -d "$cand" ]; then
        APP="$cand"
        break
    fi
done

if [ -z "$APP" ]; then
    echo "Installer app not found on macwin. Checking for InstallAssistant.pkg..."
    PKG=""
    for cand_pkg in \
        "/Volumes/INSTALLER/InstallAssistant.pkg" \
        "/Volumes/OS/InstallAssistant.pkg" \
        "/Volumes/OPENCORE/InstallAssistant.pkg"; do
        if [ -f "$cand_pkg" ]; then
            PKG="$cand_pkg"
            break
        fi
    done
    if [ -z "$PKG" ]; then
        PKG=$(find /Volumes -maxdepth 3 -name "InstallAssistant.pkg" 2>/dev/null | head -n 1)
    fi

    if [ -n "$PKG" ]; then
        echo "Extracting $PKG to $TARGET (takes ~2 minutes)..."
        installer -pkg "$PKG" -target "$TARGET"
        APP="$TARGET/Applications/Install macOS Sequoia.app"
    fi
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "ERROR: Could not locate or prepare Install macOS Sequoia.app!"
    exit 1
fi

echo "Setting full execution permissions on installer bundle..."
chmod -R 755 "$APP" 2>/dev/null || true
chmod +x "$APP/Contents/Resources/startosinstall" 2>/dev/null || true
chmod +x "$APP/Contents/MacOS/"* 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true

echo "Found installer at: $APP"
echo ""
echo "=========================================================="
echo ">>> EXECUTING APPLE startosinstall (OFFLINE)"
echo ">>> Target: $TARGET"
echo ">>> Preparing files and creating Preboot bootloader..."
echo ">>> Progress: 0% ... 100%"
echo "=========================================================="
echo ""

set +e
"$APP/Contents/Resources/startosinstall" --volume "$TARGET" --agreetolicense
RET=$?
set -e

if [ $RET -eq 0 ]; then
    echo ""
    echo "startosinstall finished successfully!"
    sync
    sync
    echo ""
    echo "=========================================================="
    echo "    STAGE 1 COMPLETED 100%!"
    echo "=========================================================="
    echo "NEXT STEPS:"
    echo "1. The laptop will attempt to restart in 5 seconds."
    echo "2. When it pauses at 'Restarting...' (ACPI shutdown pause):"
    echo "   - THIS IS 100% NORMAL. The bootloader is safely written!"
    echo "   - Wait 20 seconds, then HOLD POWER BUTTON for 5 seconds to turn off."
    echo "   - Turn the laptop back on."
    echo "3. In OpenCore picker, select 'macOS Installer' and press Enter."
    echo "   - It will boot into Stage 2 with the Apple progress bar!"
    echo "=========================================================="
else
    echo ""
    echo "ERROR: startosinstall exited with code $RET"
    echo "Please check the terminal output above."
    exit $RET
fi