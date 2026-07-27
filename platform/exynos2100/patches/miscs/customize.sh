# shellcheck disable=SC2015,SC2016,SC2043,SC2155
LOG_STEP_IN "- Setting FUSE passthrough"
SET_PROP "vendor" "persist.sys.fuse.passthrough.enable" "true"
LOG_STEP_OUT
LOG "- Disabling encryption"
# Encryption
LINE=$(sed -n "/^\/dev\/block\/by-name\/userdata/=" "$WORK_DIR/vendor/etc/fstab.exynos2100")
sed -i "${LINE}s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" "$WORK_DIR/vendor/etc/fstab.exynos2100"

# ODE
sed -i -e "/ODE/d" -e "/keydata/d" -e "/keyrefuge/d" "$WORK_DIR/vendor/etc/fstab.exynos2100"

LOG_STEP_IN "- Fixing vendor display props"
# DPI
LCD_DENSITY="$(GET_PROP "vendor" "ro.sf.lcd_density")"
if [ "$LCD_DENSITY" ]; then
    SET_PROP "vendor" "ro.sf.init.lcd_density" "$LCD_DENSITY"
else
    ABORT "ro.sf.lcd_density prop not found in vendor"
fi
LOG_STEP_OUT

LOG_STEP_IN "- Removing unsupported Qualcomm location/QCC stack"
GET_SYSTEM_EXT()
{
    if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
        echo "system_ext"
    else
        echo "system/system/system_ext"
    fi
}

_SED_DELETE_IF_EXISTS()
{
    local FILE="$1"
    shift

    [ -f "$FILE" ] || return 0
    sed -i "$@" "$FILE"
}

_DISABLE_PERFETTO_TRACED()
{
    local PERFETTO_RC="$WORK_DIR/system/system/etc/init/perfetto.rc"

    [ -f "$PERFETTO_RC" ] || return 0

    LOG "- Disabling Perfetto traced daemon for legacy Exynos kernel"
    sed -i \
        -e 's/^\([[:space:]]*\)setprop persist\.traced\.enable 1$/\1# setprop persist.traced.enable 1/g' \
        -e 's/^\([[:space:]]*\)start traced$/\1# start traced/g' \
        -e 's/^\([[:space:]]*\)start traced_relay$/\1# start traced_relay/g' \
        -e 's/^\([[:space:]]*\)start traced_probes$/\1# start traced_probes/g' \
        -e 's/^\([[:space:]]*\)wait_for_prop sys\.trace\.traced_started 1$/\1# wait_for_prop sys.trace.traced_started 1/g' \
        "$PERFETTO_RC"
    SET_PROP_IF_DIFF "system" "persist.traced.enable" "0"
}

_FIX_STRONGBOX_KEYMASTER_RC()
{
    local RC="$WORK_DIR/vendor/etc/init/android.hardware.keymaster@4.0_strongbox-service.rc"

    [ -f "$RC" ] || return 0

    if ! grep -q "^    interface android\.hardware\.keymaster@4\.0::IKeymasterDevice strongbox$" "$RC"; then
        sed -i '/^service vendor\.keymaster-4-0_strongbox /a \    interface android.hardware.keymaster@4.0::IKeymasterDevice strongbox' "$RC"
    fi
}

_DISABLE_STALE_KEYMASTER_WAIT()
{
    local INIT_RC="$WORK_DIR/vendor/etc/init/hw/init.exynos2100.rc"
    
    [ -f "$INIT_RC" ] || return 0

    LOG "- Disabling stale wait_for_keymaster init hook"
    sed -i 's/^\([[:space:]]*\)exec_start wait_for_keymaster$/\1# exec_start wait_for_keymaster/g' "$INIT_RC"
}

_PATCH_SENSORHUB_SYSFS_LOG_NOISE()
{
    local SENSORHUB="$WORK_DIR/vendor/lib64/sensors.sensorhub.so"

    [ -f "$SENSORHUB" ] || return 0

    LOG "- Suppressing noisy sensorhub sysfs write error logs"
    HEX_PATCH "$SENSORHUB" \
        "c0008052e30316aae503142a245d0094e00315aa" \
        "c0008052e30316aae503142a1f2003d5e00315aa" || true
    HEX_PATCH "$SENSORHUB" \
        "c0008052e30313aae503142a115d0094" \
        "c0008052e30313aae503142a1f2003d5" || true
}

_DROP_MISSING_SENSOR_HAL_BLOBS()
{
    local HALS_CONF="$WORK_DIR/vendor/etc/sensors/hals.conf"
    local HAL_BLOB
    local HAL_PATTERN

    [ -f "$HALS_CONF" ] || return 0

    for HAL_BLOB in sensors.bio.so; do
        [ ! -f "$WORK_DIR/vendor/lib64/$HAL_BLOB" ] || continue
        HAL_PATTERN="${HAL_BLOB//./\\.}"

        if grep -q "$HAL_BLOB" "$HALS_CONF"; then
            LOG "- Removing absent $HAL_BLOB from vendor sensors hals.conf"
            sed -i "/$HAL_PATTERN/d" "$HALS_CONF"
        fi
    done
}

_BACKPORT_HIDL_VAULTKEEPER_CLIENT()
{
    local TARGET_FIRMWARE_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
    local CURRENT_MANAGER="$WORK_DIR/system/system/lib64/libvkmanager.so"
    local LEGACY_MANAGER="$TARGET_FIRMWARE_DIR/system/system/lib64/libvkmanager.so"
    local LEGACY_INTERFACE="$TARGET_FIRMWARE_DIR/system/system/lib64/vendor.samsung.hardware.security.vaultkeeper@2.0.so"
    local VENDOR_INTERFACE="$WORK_DIR/vendor/lib64/vendor.samsung.hardware.security.vaultkeeper@2.0.so"

    [ -f "$CURRENT_MANAGER" ] || return 0

    if ! strings "$CURRENT_MANAGER" | grep -qF "vaultkeeper-V1-ndk.so"; then
        return 0
    fi
    if [ ! -f "$VENDOR_INTERFACE" ]; then
        LOG "- Skipping HIDL VaultKeeper client backport: vendor HIDL service is absent"
        return 0
    fi
    if [ ! -f "$LEGACY_MANAGER" ] || [ ! -f "$LEGACY_INTERFACE" ]; then
        ABORT "Target HIDL VaultKeeper client libraries are missing"
    fi

    # One UI 9 uses an AIDL client, but the legacy t2s vendor exposes HIDL 2.0.
    LOG "- Backporting HIDL VaultKeeper client for the legacy vendor HAL"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libvkmanager.so" \
        0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
        "system/lib64/vendor.samsung.hardware.security.vaultkeeper@2.0.so" \
        0 0 644 "u:object_r:system_lib_file:s0"
}

_BACKPORT_HIDL_ENGMODE_CLIENT()
{
    local TARGET_FIRMWARE_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
    local CURRENT_MANAGER="$WORK_DIR/system/system/lib64/lib.engmode.samsung.so"
    local LEGACY_MANAGER="$TARGET_FIRMWARE_DIR/system/system/lib64/lib.engmode.samsung.so"
    local LEGACY_INTERFACE="$TARGET_FIRMWARE_DIR/system/system/lib64/vendor.samsung.hardware.security.engmode@1.0.so"
    local VENDOR_INTERFACE="$WORK_DIR/vendor/lib64/vendor.samsung.hardware.security.engmode@1.0.so"

    [ -f "$CURRENT_MANAGER" ] || return 0

    if ! strings "$CURRENT_MANAGER" | grep -qF "engmode-V1-ndk.so"; then
        return 0
    fi
    if [ ! -f "$VENDOR_INTERFACE" ]; then
        LOG "- Skipping HIDL EngMode client backport: vendor HIDL service is absent"
        return 0
    fi
    if [ ! -f "$LEGACY_MANAGER" ] || [ ! -f "$LEGACY_INTERFACE" ]; then
        ABORT "Target HIDL EngMode client libraries are missing"
    fi

    # The source JNI bridge uses the stable EngMode C ABI exposed by this client.
    LOG "- Backporting HIDL EngMode client for the legacy vendor HAL"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/lib.engmode.samsung.so" \
        0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
        "system/lib64/vendor.samsung.hardware.security.engmode@1.0.so" \
        0 0 644 "u:object_r:system_lib_file:s0"
}

_BACKPORT_LEGACY_DEX_STACK()
{
    local TARGET_FIRMWARE_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
    local LEGACY_UI="$TARGET_FIRMWARE_DIR/system/system/priv-app/DesktopModeUiService/DesktopModeUiService.apk"
    local FILE

    [ -f "$LEGACY_UI" ] || return 0
    [ ! -f "$WORK_DIR/system/system/priv-app/DesktopModeUiService/DesktopModeUiService.apk" ] || return 0

    # One UI 9 moved this stack off the system image; retain the target's HAL-compatible DeX UI.
    LOG "- Backporting legacy DeX stack for the target display pipeline"
    for FILE in \
        system/priv-app/DesktopSystemUI \
        system/priv-app/DesktopModeUiService \
        system/priv-app/KnoxDesktopLauncher \
        system/framework/DesktopSystemUICoreLib.jar \
        system/framework/DesktopSystemUIKnoxLib.jar \
        system/etc/permissions/DesktopSystemUICoreLib_permissions.xml \
        system/etc/permissions/DesktopSystemUIKnoxLib_permissions.xml \
        system/etc/permissions/privapp-permissions-com.sec.android.app.desktoplauncher.xml \
        system/etc/permissions/privapp-permissions-com.sec.android.desktopmode.uiservice.xml \
        system/lib/libknox_remotedesktopclient.knox.samsung.so \
        system/lib/libremotedesktopservice.so \
        system/lib64/libknox_remotedesktopclient.knox.samsung.so \
        system/lib64/libremotedesktopservice.so; do
        [ -e "$TARGET_FIRMWARE_DIR/system/$FILE" ] || continue
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "$FILE"
    done

    _BACKPORT_LEGACY_DEX_SERVICE
}

_BACKPORT_LEGACY_DEX_SERVICE()
{
    local TARGET_FIRMWARE_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
    local SOURCE_SERVICES="$APKTOOL_DIR/system/framework/services.jar"
    local SOURCE_SYSTEM_SERVER="$SOURCE_SERVICES/smali/com/android/server/SystemServer.smali"
    local TARGET_SERVICES="$TARGET_FIRMWARE_DIR/system/system/framework/services.jar"
    local TARGET_APKTOOL="$TMP_DIR/legacy_dex_services"
    local TARGET_DESKTOPMODE=""
    local SOURCE_DESKTOPMODE="$SOURCE_SERVICES/smali_classes3/com/android/server/desktopmode"
    local START_PATCH="$MODPATH/dex/services.jar/0001-Start-legacy-DesktopModeService.patch"

    if [ ! -f "$TARGET_SERVICES" ]; then
        LOG "- Skipping legacy DeX service backport: target services.jar is absent"
        return 0
    fi

    DECODE_APK "system" "system/framework/services.jar" || return 1

    if [ ! -f "$SOURCE_SYSTEM_SERVER" ]; then
        ABORT "Source SystemServer smali is missing"
    fi
    if grep -qF 'Lcom/android/server/desktopmode/DesktopModeService$Lifecycle;' "$SOURCE_SYSTEM_SERVER"; then
        return 0
    fi
    if find "$SOURCE_SERVICES" -type d -path '*/com/android/server/desktopmode' -print -quit | grep -q .; then
        LOG "- Skipping legacy DeX service backport: source already provides desktopmode classes"
        return 0
    fi

    LOG "- Backporting legacy DeX system service for the target display pipeline"
    if [ ! -d "$TARGET_APKTOOL" ]; then
        EVAL "mkdir -p \"$(dirname "$TARGET_APKTOOL")\""
        EVAL "\"$TOOLS_DIR/bin/apktool\" -JXX:TieredStopAtLevel=1 d --no-debug-info -j 1 -p \"$APKTOOL_DIR/framework\" -o \"$TARGET_APKTOOL\" \"$TARGET_SERVICES\"" || return 1
    fi

    TARGET_DESKTOPMODE="$(find "$TARGET_APKTOOL" -type d \
        -path '*/com/android/server/desktopmode' -print -quit)"
    if [ -z "$TARGET_DESKTOPMODE" ] || \
            [ ! -f "$TARGET_DESKTOPMODE/DesktopModeService.smali" ]; then
        LOG "- Skipping legacy DeX service backport: target firmware uses the newer DexModeService"
        return 0
    fi

    EVAL "mkdir -p \"$(dirname "$SOURCE_DESKTOPMODE")\""
    EVAL "cp -a \"$TARGET_DESKTOPMODE\" \"$(dirname "$SOURCE_DESKTOPMODE")\""
    APPLY_PATCH "system" "system/framework/services.jar" "$START_PATCH"
}

_DROP_INCOMPATIBLE_CIDMANAGER()
{
    local CID_APK="$WORK_DIR/system/system/priv-app/CIDManager/CIDManager.apk"

    [ -f "$CID_APK" ] || return 0

    LOG "- Removing S26 CIDManager carrier activation incompatible with t2s"
    DELETE_FROM_WORK_DIR "system" "system/priv-app/CIDManager"
    DELETE_FROM_WORK_DIR "system" "system/etc/sysconfig/preinstalled-packages-com.samsung.android.cidmanager.xml"
    DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.cidmanager.xml"
}

_DISABLE_SURFACEFLINGER_SHADER_CACHE()
{
    local INIT_RC="$WORK_DIR/system/system/etc/init/hw/init.rc"
    local PROP

    [ -f "$INIT_RC" ] || return 0

    if grep -q "^[[:space:]]*setprop service\.sf\.cache_dir_available 1$" "$INIT_RC"; then
        LOG "- Disabling SurfaceFlinger shader cache priming for legacy gralloc"
        sed -i \
            's/^\([[:space:]]*\)setprop service\.sf\.cache_dir_available 1$/\1# setprop service.sf.cache_dir_available 1/g' \
            "$INIT_RC"
    fi

    LOG "- Disabling SurfaceFlinger prime shader cache"
    SET_PROP "product" "service.sf.cache_dir_available" "0"
    SET_PROP "product" "service.sf.prime_shader_cache" "0"

    for PROP in \
        debug.sf.prime_shader_cache.clipped_dimmed_image_layers \
        debug.sf.prime_shader_cache.clipped_layers \
        debug.sf.prime_shader_cache.edge_extension_shader \
        debug.sf.prime_shader_cache.hole_punch \
        debug.sf.prime_shader_cache.image_dimmed_layers \
        debug.sf.prime_shader_cache.image_layers \
        debug.sf.prime_shader_cache.pip_image_layers \
        debug.sf.prime_shader_cache.shadow_layers \
        debug.sf.prime_shader_cache.solid_dimmed_layers \
        debug.sf.prime_shader_cache.solid_layers \
        debug.sf.prime_shader_cache.transparent_image_dimmed_layers; do
        SET_PROP "product" "$PROP" "0"
    done
}

_DISABLE_UNSUPPORTED_MAINLINE_FEATURES()
{
    LOG "- Disabling UFFD GC, virtual Perfetto relay, and RKP paths unsupported by Exynos2100 vendor"
    SET_PROP "product" "ro.dalvik.vm.enable_uffd_gc" "false"
    SET_PROP "product" "persist.device_config.runtime_native_boot.enable_uffd_gc_2" "false"
    SET_PROP "product" "persist.device_config.runtime_native_boot.enable_uffd_gc" "false"
    SET_PROP "product" "persist.device_config.runtime_native_boot.force_disable_uffd_gc" "true"
    SET_PROP "product" "traced.relay_producer_port" --delete
    SET_PROP "product" "remote_provisioning.enable_rkpd" "false"
    SET_PROP "product" "remote_provisioning.tee.rkp_only" "0"
    DELETE_FROM_WORK_DIR "system" "system/apex/com.google.android.rkpd_compressed.apex"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/irremovable_list.txt" "/com\.\(android\|google\.android\)\.rkpd/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/permissions/platform.xml" "/com\.android\.rkpdapp/d"
}

_DISABLE_UNSUPPORTED_BT_OFFLOAD()
{
    LOG "- Disabling Bluetooth audio offload paths unsupported by Exynos2100 vendor"
    SET_PROP "product" "persist.bluetooth.a2dp_offload.disabled" "true"
    SET_PROP "product" "persist.bluetooth.leaudio_offload.disabled" "true"
    SET_PROP "product" "persist.vendor.bt.a2dp_offload.disabled" "true"
    SET_PROP "product" "persist.vendor.bluetooth.a2dp_offload.disabled" "true"
    SET_PROP "product" "ro.bluetooth.leaudio_offload.supported" "false"
    SET_PROP "product" "persist.bluetooth.samsung.a2dp_offload.cap" --delete
    SET_PROP "product" "persist.bluetooth.samsung.a2dp.cap" "SBC,AAC"
    SET_PROP "product" "persist.bluetooth.samsung.leaudio.livecast" "false"
    SET_PROP "product" "media.stagefright.enable-fma2dp" "false"
    SET_PROP "product" "ro.bluetooth.library_name" --delete
    SET_PROP "product" "bluetooth.a2dp.source.sbc_priority.config" "1001"
    SET_PROP "product" "bluetooth.a2dp.source.aac_priority.config" "900000"
    SET_PROP "product" "bluetooth.a2dp.source.aptx_priority.config" "-1"
    SET_PROP "product" "bluetooth.a2dp.source.aptx_hd_priority.config" "-1"
    SET_PROP "product" "bluetooth.a2dp.source.ldac_priority.config" "-1"
    SET_PROP "product" "bluetooth.a2dp.source.opus_priority.config" "-1"
    SET_PROP "product" "bluetooth.a2dp.source.lhdcv5_priority.config" "-1"
    SET_PROP "product" "audio.offload.disable" "1"
    SET_PROP "product" "audio.offload.video" "false"
    SET_PROP "product" "audio.deep_buffer.media" "false"
    SET_PROP "product" "tunnel.audio.encode" "false"
    SET_PROP "product" "media.stagefright.audio.deep" "false"
}

_DISABLE_UNSUPPORTED_OUI9_INIT_WRITES()
{
    LOG "- Removing One UI 9 init writes rejected by the Exynos2100 kernel"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/init/hw/init.rc" \
        -e "/^[[:space:]]*exec_start init_dev_config$/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/init/init.memory.rc" "/\/sys\/kernel\/mm\/transparent_hugepage\/khugepaged\/max_ptes_shared/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/init/atrace.rc" "/\/sys\/kernel\/tracing\/synthetic_events/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/init/hw/init.rc" \
        -e "/\/dev\/blkio\/blkio\.weight/d" \
        -e "/\/dev\/blkio\/background\/blkio\.weight/d" \
        -e "/\/dev\/blkio\/background\/blkio\.bfq\.weight/d" \
        -e "/\/dev\/blkio\/blkio\.group_idle/d" \
        -e "/\/dev\/blkio\/background\/blkio\.group_idle/d" \
        -e "/\/dev\/blkio\/background\/blkio\.prio\.class/d" \
        -e "/\/dev\/blkio\/top\/blkio\.ssg\.boost_on/d" \
        -e "/\/dev\/blkio\/high\/blkio\.ssg\.max_available_ratio/d" \
        -e "/\/dev\/blkio\/normal\/blkio\.ssg\.max_available_ratio/d" \
        -e "/\/dev\/blkio\/low\/blkio\.ssg\.max_available_ratio/d" \
        -e "/\/sys\/class\/sensors\/grip_sensor\/grip_request_firmware/d" \
        -e "/\/dev\/sys\/fs\/by-name\/userdata\/seq_file_ra_mul/d" \
        -e "/\/sys\/class\/power_supply\/battery\/batt_update_data/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/system/system/etc/init/init.sec-charger.rc" "/\/sys\/class\/power_supply\/battery\/batt_update_data/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/vendor/etc/init/init.exynos2100.rc" \
        -e "/\/dev\/freezer\/frozen\/freezer\.killable/d" \
        -e "/\/dev\/cpuctl\/foreground\/cpu\.rt_runtime_us/d" \
        -e "/\/dev\/cpuctl\/background\/cpu\.rt_runtime_us/d" \
        -e "/\/dev\/cpuctl\/top-app\/cpu\.rt_runtime_us/d" \
        -e "/\/proc\/sys\/net\/core\/netdev_max_backlog/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/vendor/etc/init/init.baseband.rc" "/\/proc\/sys\/net\/core\/netdev_max_backlog/d"
    _SED_DELETE_IF_EXISTS "$WORK_DIR/vendor/etc/init/init.nfc.samsung.rc" "/\/sys\/class\/nfc_sec\/pvdd/d"
}

_DISABLE_BOOTCHECKER_RESCUE_LOOP()
{
    LOG "- Disabling bootchecker rescue-party loop for legacy Exynos2100 boots"
    DELETE_FROM_WORK_DIR "system" "system/etc/init/bootchecker.rc"
}

_DISABLE_ZYGOTE_NEXT_BOOT()
{
    LOG "- Disabling zygote_next on legacy Exynos2100 vendor stack"
    DELETE_FROM_WORK_DIR "system" "system/etc/init/zygote_next.rc"
    SET_PROP "product" "persist.zygote.zygote_next.start_on_boot" "false"
    SET_PROP "product" "zygote.zygote_next.server_ready" "false"
}

_RELAX_VOLD_REBOOT_ON_FAILURE()
{
    local VOLD_RC="$WORK_DIR/system/system/etc/init/vold.rc"

    [ -f "$VOLD_RC" ] || return 0

    if grep -q "^[[:space:]]*reboot_on_failure " "$VOLD_RC"; then
        LOG "- Removing vold reboot_on_failure on legacy Exynos2100 vendor stack"
        sed -i '/^[[:space:]]*reboot_on_failure /d' "$VOLD_RC"
    fi
}

_SET_LOG_TAG_LEVEL()
{
    local TAG="$1"
    local LEVEL="$2"

    SET_PROP "product" "log.tag.$TAG" "$LEVEL"
    SET_PROP "product" "persist.log.tag.$TAG" "$LEVEL"
}

_PATCH_CONST_BEFORE_BOOL_IPUT()
{
    local FILE="$1"
    local FIELD="$2"
    local COUNT

    awk -v FIELD="$FIELD" '
        { line[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (index(line[i], FIELD) && line[i] ~ /iput-boolean/) {
                    for (j = i - 1; j >= 1 && j >= i - 6; j--) {
                        if (line[j] ~ /^[[:space:]]*const\/4 [vp][0-9]+, 0x1$/) {
                            sub(/0x1$/, "0x0", line[j])
                            changed++
                            break
                        }
                    }
                }
            }
            for (i = 1; i <= NR; i++) print line[i]
            if (!changed) exit 2
            print changed > "/dev/stderr"
        }
    ' "$FILE" > "$FILE.tmp" 2> "$FILE.count" && mv "$FILE.tmp" "$FILE" || {
        rm -f "$FILE.tmp" "$FILE.count"
        ABORT "Failed to patch boolean assignment for $FIELD in ${FILE//$SRC_DIR\//}"
    }

    COUNT="$(cat "$FILE.count")"
    rm -f "$FILE.count"
    LOG "- Patched $COUNT boolean assignment(s) for $FIELD"
}

_PATCH_BOOL_METHOD_RETURN()
{
    local FILE="$1"
    local METHOD="$2"
    local VALUE="$3"
    local HEX="0x0"

    [ "$VALUE" = "true" ] && HEX="0x1"

    awk -v METHOD="$METHOD" -v HEX="$HEX" '
        BEGIN { inside = 0; changed = 0 }
        /^\.method/ && index($0, METHOD) {
            print
            print "    .locals 1"
            print ""
            print "    const/4 v0, " HEX
            print ""
            print "    return v0"
            inside = 1
            changed = 1
            next
        }
        inside && /^\.end method/ {
            print
            print
            inside = 0
            next
        }
        inside { next }
        { print }
        END { if (!changed) exit 2 }
    ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE" || {
        rm -f "$FILE.tmp"
        ABORT "Failed to patch method $METHOD in ${FILE//$SRC_DIR\//}"
    }

    LOG "- Forced $METHOD to return $VALUE"
}

_PATCH_A2DP_LEGACY_CODEC_PRIORITIES()
{
    local SMALI="$1"

    [ -f "$SMALI" ] || ABORT "A2dpCodecConfig.smali not found"

    if grep -q "MonsterROM One UI 9 legacy BT codec guard" "$SMALI"; then
        LOG "- A2DP legacy codec priorities already patched"
        return 0
    fi

    awk '
        {
            print
            if ($0 ~ /iput v1, p0, Lcom\/android\/bluetooth\/a2dp\/A2dpCodecConfig;->mA2dpSourceCodecPrioritySscUhq:I/) {
                print ""
                print "    # MonsterROM One UI 9 legacy BT codec guard"
                print "    const/16 v0, 1001"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPrioritySbc:I"
                print ""
                print "    const v0, 0xdbba0"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPriorityAac:I"
                print ""
                print "    const/4 v0, -0x1"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPriorityAptx:I"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPriorityAptxHd:I"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPriorityLdac:I"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPriorityOpus:I"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPriorityLhdcv5:I"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPrioritySsc:I"
                print "    iput v0, p0, Lcom/android/bluetooth/a2dp/A2dpCodecConfig;->mA2dpSourceCodecPrioritySscUhq:I"
                patched = 1
            }
        }
        END { if (!patched) exit 2 }
    ' "$SMALI" > "$SMALI.tmp" && mv "$SMALI.tmp" "$SMALI" || {
        rm -f "$SMALI.tmp"
        ABORT "Failed to patch A2DP legacy codec priorities"
    }

    LOG "- Forced A2DP codec priorities to AAC/SBC and disabled LDAC/SSC/aptX"
}

_PATCH_AUDIO_MUTE_AWAIT_CONNECTION_DUPLICATE()
{
    local SMALI
    local COUNT

    LOG "- Making duplicate Bluetooth mute-await requests non-fatal"
    DECODE_APK "system" "system/framework/services.jar" || ABORT "Failed to decode services.jar"

    SMALI="$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/audio/AudioService.smali"
    [ -f "$SMALI" ] || ABORT "AudioService.smali not found in decoded services.jar"

    if ! grep -q "muteAwaitConnection already in progress" "$SMALI"; then
        LOG "- AudioService duplicate mute-await branch already patched"
        return 0
    fi

    awk '
        BEGIN {
            inside = 0
            skip_throw_branch = 0
            cleanup_catch = 0
            patched = 0
        }
        /^\.method/ && index($0, "muteAwaitConnection([ILandroid/media/AudioDeviceAttributes;J)V") {
            inside = 1
        }
        inside && index($0, "new-instance p0, Ljava/lang/IllegalStateException;") {
            print "    monitor-exit v1"
            print "    :try_end_1"
            print "    .catchall {:try_start_1 .. :try_end_1} :catchall_0"
            print ""
            print "    return-void"
            print ""
            skip_throw_branch = 1
            patched = 1
            next
        }
        inside && skip_throw_branch {
            if ($0 ~ /^[[:space:]]*:goto_0/) {
                print
                skip_throw_branch = 0
                cleanup_catch = 1
            }
            next
        }
        inside && cleanup_catch && ($0 ~ /^[[:space:]]*:try_end_1$/ || index($0, ".catchall {:try_start_1 .. :try_end_1} :catchall_0")) {
            next
        }
        inside && /^\.end method/ {
            inside = 0
            cleanup_catch = 0
        }
        { print }
        END {
            if (!patched) exit 2
            print patched > "/dev/stderr"
        }
    ' "$SMALI" > "$SMALI.tmp" 2> "$SMALI.count" && mv "$SMALI.tmp" "$SMALI" || {
        rm -f "$SMALI.tmp" "$SMALI.count"
        ABORT "Failed to patch AudioService duplicate mute-await branch"
    }

    COUNT="$(cat "$SMALI.count")"
    rm -f "$SMALI.count"
    LOG "- Patched $COUNT AudioService duplicate mute-await branch"
}

_APEX_PAYLOAD_COPY_OUT()
{
    local PAYLOAD="$1"
    local SRC="$2"
    local DST="$3"

    if command -v e2cp > /dev/null 2>&1; then
        EVAL "e2cp \"$PAYLOAD:$SRC\" \"$DST\""
    elif command -v debugfs > /dev/null 2>&1; then
        EVAL "debugfs -R \"dump -p $SRC $DST\" \"$PAYLOAD\""
    else
        ABORT "Neither e2cp nor debugfs is available to unpack APEX image"
    fi
}

_APEX_PAYLOAD_COPY_IN()
{
    local SRC="$1"
    local PAYLOAD="$2"
    local DST="$3"

    if command -v e2cp > /dev/null 2>&1 && command -v e2rm > /dev/null 2>&1; then
        EVAL "e2rm \"$PAYLOAD:$DST\""
        EVAL "e2cp \"$SRC\" \"$PAYLOAD:$DST\""
    elif command -v debugfs > /dev/null 2>&1; then
        debugfs -w -R "rm $DST" "$PAYLOAD" >/dev/null 2>&1 || true
        EVAL "debugfs -w -R \"write $SRC $DST\" \"$PAYLOAD\""
    else
        ABORT "Neither e2cp/e2rm nor debugfs is available to update APEX image"
    fi
}

_PATCH_BEACONMANAGER_LOCATION_PERMISSIONS()
{
    local BEACON_APK="system/priv-app/BeaconManager/BeaconManager.apk"
    local BEACON_DECODED="$APKTOOL_DIR/system/${BEACON_APK//system\/}"
    local MANIFEST="$BEACON_DECODED/AndroidManifest.xml"
    local PERM

    [ -f "$WORK_DIR/system/$BEACON_APK" ] || return 0

    LOG_STEP_IN "- Adding BeaconManager BLE location permissions"
    DECODE_APK "system" "$BEACON_APK" || ABORT "Failed to decode BeaconManager.apk"

    [ -f "$MANIFEST" ] || ABORT "Decoded BeaconManager manifest not found"

    for PERM in \
        android.permission.ACCESS_COARSE_LOCATION \
        android.permission.ACCESS_FINE_LOCATION \
        android.permission.ACCESS_BACKGROUND_LOCATION; do
        if ! grep -q "android:name=\"$PERM\"" "$MANIFEST"; then
            sed -i "0,/^[[:space:]]*<application/{s#^[[:space:]]*<application#    <uses-permission android:name=\"$PERM\" />\n\n    <application#}" "$MANIFEST"
            LOG "- Added $PERM"
        fi
    done

    LOG_STEP_OUT
}

ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/selinux/mapping/29.0.cil" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/selinux/mapping/29.0.compat.cil" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/selinux/mapping/30.0.cil" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/selinux/mapping/30.0.compat.cil" 0 0 644 "u:object_r:system_file:s0"

ADD_TO_WORK_DIR "platform/exynos2100/patches/miscs" "vendor" "etc/ueventd.rc" 0 0 644 "u:object_r:vendor_configs_file:s0"
ADD_TO_WORK_DIR "platform/exynos2100/patches/miscs" "vendor" "etc/bluetooth_audio_policy_configuration.xml" 0 0 644 "u:object_r:vendor_configs_file:s0"
ADD_TO_WORK_DIR "platform/exynos2100/patches/miscs" "vendor" "etc/init/android.hardware.sensors@2.0-service-multihal.rc" 0 0 644 "u:object_r:vendor_configs_file:s0"
ADD_TO_WORK_DIR "platform/exynos2100/patches/miscs" "vendor" "bin/monsterrom_wait_sensors_ready.sh" 0 2000 755 "u:object_r:vendor_file:s0"
ADD_TO_WORK_DIR "platform/exynos2100/patches/miscs" "system" "system/etc/default-permissions/default-permissions-com.samsung.android.beaconmanager.xml" 0 0 644 "u:object_r:system_file:s0"

_FIX_STRONGBOX_KEYMASTER_RC
_DISABLE_STALE_KEYMASTER_WAIT
_PATCH_SENSORHUB_SYSFS_LOG_NOISE
_DROP_MISSING_SENSOR_HAL_BLOBS
_BACKPORT_HIDL_VAULTKEEPER_CLIENT
_BACKPORT_HIDL_ENGMODE_CLIENT
_BACKPORT_LEGACY_DEX_STACK
_DROP_INCOMPATIBLE_CIDMANAGER
_DISABLE_SURFACEFLINGER_SHADER_CACHE
_DISABLE_UNSUPPORTED_MAINLINE_FEATURES
_DISABLE_UNSUPPORTED_BT_OFFLOAD
_DISABLE_UNSUPPORTED_OUI9_INIT_WRITES
_DISABLE_BOOTCHECKER_RESCUE_LOOP
_DISABLE_ZYGOTE_NEXT_BOOT
_RELAX_VOLD_REBOOT_ON_FAILURE
_PATCH_BEACONMANAGER_LOCATION_PERMISSIONS