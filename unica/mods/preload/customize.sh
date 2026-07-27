KSUNEXT_MANAGER_VERSION="3.3.0"
KSUNEXT_MANAGER_VERSION_CODE="33214"
KSUNEXT_MANAGER_URL="${FLOPPY_KSUNEXT_MANAGER_URL:-https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.3.0/KernelSU_Next_v3.3.0_33214-release.apk}"
# Pin the exact unspoofed release. Its v2 certificate is 0x3e6 bytes with
# SHA-256 79e590113c4c4c0c222978e413a5faa801666957b1212a328e46c00c69821bf7,
# matching the manager identity compiled into this Floppy KernelSU tree.
KSUNEXT_MANAGER_SHA256="fd0b12385c98fe9d5f4f1257b5f184e55c74c1376637507df0718305f5d7a924"
KSUNEXT_MANAGER_CACHE="$SRC_DIR/out/kernel-cache/KernelSU_Next_v${KSUNEXT_MANAGER_VERSION}_${KSUNEXT_MANAGER_VERSION_CODE}-release.apk"

_INSTALL_KSUNEXT_MANAGER_PRELOAD()
{
    local APK_PATH="$WORK_DIR/system/system/preload/KernelSU-Next/com.rifsxd.ksunext-mesa==/base.apk"
    local CACHE_TMP="${KSUNEXT_MANAGER_CACHE}.tmp.$$"
    local ACTUAL_SHA256=""

    if [ -f "$KSUNEXT_MANAGER_CACHE" ]; then
        ACTUAL_SHA256="$(sha256sum "$KSUNEXT_MANAGER_CACHE" | cut -d ' ' -f 1)"
    fi
    if [ "$ACTUAL_SHA256" != "$KSUNEXT_MANAGER_SHA256" ]; then
        case "$CACHE_TMP" in
            "$SRC_DIR"/out/kernel-cache/KernelSU_Next_*.apk.tmp.*) rm -f "$CACHE_TMP" ;;
            *) ABORT "Refusing to replace an unexpected KernelSU manager cache path" ;;
        esac
        LOG "- Downloading KernelSU Next manager v$KSUNEXT_MANAGER_VERSION ($KSUNEXT_MANAGER_VERSION_CODE)"
        if ! DOWNLOAD_FILE "$KSUNEXT_MANAGER_URL" "$CACHE_TMP"; then
            rm -f "$CACHE_TMP"
            ABORT "Failed to download the pinned KernelSU Next manager"
            return 1
        fi
        ACTUAL_SHA256="$(sha256sum "$CACHE_TMP" | cut -d ' ' -f 1)"
        if [ "$ACTUAL_SHA256" != "$KSUNEXT_MANAGER_SHA256" ]; then
            rm -f "$CACHE_TMP"
            ABORT "KernelSU Next manager checksum mismatch: $ACTUAL_SHA256"
            return 1
        fi
        mv -f "$CACHE_TMP" "$KSUNEXT_MANAGER_CACHE"
    fi

    mkdir -p "$(dirname "$APK_PATH")"
    cp -f "$KSUNEXT_MANAGER_CACHE" "$APK_PATH"
    LOG "- Preloading KernelSU Next manager v$KSUNEXT_MANAGER_VERSION ($KSUNEXT_MANAGER_VERSION_CODE)"
    LOG "- KernelSU Next v3.3 filesystem modules require an active MetaModule (meta-overlayfs)"
}

if [ "$TARGET_PLATFORM" = "exynos2100" ]; then
    _INSTALL_KSUNEXT_MANAGER_PRELOAD
fi

# Samsung Internet Browser
# https://play.google.com/store/apps/details?id=com.sec.android.app.sbrowser
LOG "- Downloading Samsung Internet app"
DOWNLOAD_GALAXY_STORE_APP "com.sec.android.app.sbrowser" \
    "$WORK_DIR/system/system/preload/SBrowser/SBrowser.apk"

VPL_LIST="$WORK_DIR/system/system/etc/vpl_apks_count_list.txt"
mkdir -p "$(dirname "$VPL_LIST")"
touch "$VPL_LIST"

while IFS= read -r i; do
    i="${i//$WORK_DIR\/system\//}"

    if [ -d "$WORK_DIR/system/$i" ]; then
        SET_METADATA "system" "$i" 0 0 755 "u:object_r:system_file:s0"
    else
        SET_METADATA "system" "$i" 0 0 644 "u:object_r:system_file:s0"
    fi

    if [[ "$i" == *".apk" ]] && \
            ! grep -qF "$i" "$VPL_LIST"; then
        LOG "- Adding \"$i\" to /system/system/etc/vpl_apks_count_list.txt"
        EVAL "echo \"$i\" >> \"$VPL_LIST\""
    fi
done <<< "$(find "$WORK_DIR/system/system/preload")"

LC_ALL=C sort -u -o "$VPL_LIST" "$VPL_LIST"
SET_METADATA "system" "system/etc/vpl_apks_count_list.txt" \
    0 0 644 "u:object_r:system_file:s0"

unset KSUNEXT_MANAGER_VERSION KSUNEXT_MANAGER_VERSION_CODE
unset KSUNEXT_MANAGER_URL KSUNEXT_MANAGER_SHA256 KSUNEXT_MANAGER_CACHE VPL_LIST
unset -f _INSTALL_KSUNEXT_MANAGER_PRELOAD
