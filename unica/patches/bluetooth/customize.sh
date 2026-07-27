SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"

if [[ "$(sha1sum "$WORK_DIR/system/system/apex/com.android.bt.apex" | cut -d " " -f 1)" != \
        "$(sha1sum "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/apex/com.android.bt.apex" | cut -d " " -f 1)" ]]; then
    LOG "\033[0;33m! Nothing to do\033[0m"
    unset SOURCE_FIRMWARE_PATH
    return 0
fi

# [
BUILD_APK_IN_APEX()
{
    local INPUT_FILE="$1"
    local OUTPUT_FILE

    if [[ "$INPUT_FILE" == *"javalib"* ]]; then
        OUTPUT_FILE="$WORK_DIR/system/system/framework/$(basename "$INPUT_FILE")"
    else
        OUTPUT_FILE="$WORK_DIR/system/system/${INPUT_FILE/$TMP_DIR\/apex_payload\//}"
    fi

    if [ -d "$APKTOOL_DIR/${OUTPUT_FILE//$WORK_DIR\/system\//}" ]; then
        LOG "- Building ${INPUT_FILE//$TMP_DIR\//}"
        "$SRC_DIR/scripts/apktool.sh" b "system" "${OUTPUT_FILE//$WORK_DIR\/system\//}" > /dev/null
        LOG "- Signing ${INPUT_FILE//$TMP_DIR\//}"
        mv -f "$OUTPUT_FILE" "$INPUT_FILE"

        if [[ "$OUTPUT_FILE" == *".apk" ]]; then
            rm -rf "$(dirname "${APKTOOL_DIR:?}/${OUTPUT_FILE//$WORK_DIR\/system\//}")" "$(dirname "$OUTPUT_FILE")"
        else
            rm -rf "${APKTOOL_DIR:?}/${OUTPUT_FILE//$WORK_DIR\/system\//}" "$OUTPUT_FILE"
        fi
    fi
}

BUILD_PAYLOAD()
{
    LOG "- Building apex_payload.img"

    "$SRC_DIR/scripts/build_fs_image.sh" "ext4" --no-avb \
        -o "$TMP_DIR/apex_payload.img" -p "system" \
        "$TMP_DIR/apex_payload" "$TMP_DIR/file_context-apex_payload" "$TMP_DIR/fs_config-apex_payload" \
        > /dev/null
    rm -rf "$TMP_DIR/apex_payload" "$TMP_DIR/file_context-apex_payload" "$TMP_DIR/fs_config-apex_payload"
}

DECODE_APK_IN_APEX()
{
    local INPUT_FILE="$1"
    local OUTPUT_FILE

    if [[ "$INPUT_FILE" == *"javalib"* ]]; then
        OUTPUT_FILE="$WORK_DIR/system/system/framework/$(basename "$INPUT_FILE")"
    else
        mkdir -p "$WORK_DIR/system/system/$(dirname "${INPUT_FILE/$TMP_DIR\/apex_payload\//}")"
        OUTPUT_FILE="$WORK_DIR/system/system/${INPUT_FILE/$TMP_DIR\/apex_payload\//}"
    fi

    if [ ! -f "$OUTPUT_FILE" ]; then
        mv -f "$INPUT_FILE" "$OUTPUT_FILE"
        LOG "- Decoding ${INPUT_FILE//$TMP_DIR\//}"
        DECODE_APK "system" "${OUTPUT_FILE//$WORK_DIR\/system\//}" > /dev/null
    fi
}

EXTRACT_PAYLOAD()
{
    local CONTEXT
    local CONTEXT_PATH
    local FS_PATH
    local HOST_PATH
    local IMAGE_PATH
    local MODE
    local OWNER
    local RELATIVE
    local STAT_OUTPUT

    LOG_STEP_IN "- Extracting apex_payload.img from $(basename "$1")"

    EVAL "unzip -j \"$1\" \"apex_payload.img\" -d \"$TMP_DIR\""

    LOG_STEP_OUT

    LOG "- Unpacking apex_payload.img"

    if ! command -v debugfs > /dev/null 2>&1; then
        ABORT "debugfs is required to unpack APEX image"
    fi

    mkdir -p "$TMP_DIR/apex_payload"
    if ! debugfs -R "rdump / $TMP_DIR/apex_payload" "$TMP_DIR/apex_payload.img" \
            2> "$TMP_DIR/debugfs.log"; then
        cat "$TMP_DIR/debugfs.log" >&2
        ABORT "Failed to unpack APEX image with debugfs"
    fi
    rm -f "$TMP_DIR/debugfs.log"

    LOG "- Generating fs_config/file_context for apex_payload.img"

    : > "$TMP_DIR/fs_config-apex_payload"
    : > "$TMP_DIR/file_context-apex_payload"

    while IFS= read -r -d '' HOST_PATH; do
        RELATIVE="${HOST_PATH#"$TMP_DIR/apex_payload"}"
        IMAGE_PATH="${RELATIVE:-/}"
        STAT_OUTPUT="$(debugfs -R "stat $IMAGE_PATH" "$TMP_DIR/apex_payload.img" 2> /dev/null)"

        MODE="$(sed -n 's/^Inode:.*Mode:[[:space:]]*\([0-7]*\).*/\1/p' <<< "$STAT_OUTPUT")"
        OWNER="$(sed -n 's/^User:[[:space:]]*\([0-9]*\)[[:space:]]*Group:[[:space:]]*\([0-9]*\).*/\1 \2/p' <<< "$STAT_OUTPUT")"
        CONTEXT="$(sed -n 's/.*security\.selinux.*= "\(.*\)\\000"/\1/p' <<< "$STAT_OUTPUT")"

        if [[ ! "$MODE" || ! "$OWNER" || ! "$CONTEXT" ]]; then
            ABORT "Failed to read APEX metadata for $IMAGE_PATH"
        fi

        FS_PATH="${RELATIVE#/}"
        CONTEXT_PATH="$(sed \
            -e 's|\.|\\\.|g' \
            -e 's|\+|\\\+|g' \
            -e 's|\[|\\\[|g' \
            -e 's|\]|\\\]|g' \
            -e 's|\*|\\\*|g' <<< "$IMAGE_PATH")"

        printf "%s %s %s capabilities=0x0\n" "$FS_PATH" "$OWNER" "$MODE" \
            >> "$TMP_DIR/fs_config-apex_payload"
        printf "%s %s\n" "$CONTEXT_PATH" "$CONTEXT" \
            >> "$TMP_DIR/file_context-apex_payload"
    done < <(find "$TMP_DIR/apex_payload" -print0)

    sort -o "$TMP_DIR/file_context-apex_payload" "$TMP_DIR/file_context-apex_payload"
    sort -o "$TMP_DIR/fs_config-apex_payload" "$TMP_DIR/fs_config-apex_payload"

    rm -rf "$TMP_DIR/apex_payload/lost+found"
    rm -f "$TMP_DIR/apex_payload.img"
}

LOG_MISSING_PATCHES()
{
    local MESSAGE="Missing SPF patches for condition ($1: [${!1}], $2: [${!2}])"

    if $DEBUG; then
        LOGW "$MESSAGE"
    else
        ABORT "${MESSAGE}. Aborting"
    fi
}

REPACK_PAYLOAD()
{
    LOG "- Adding apex_payload.img to $(basename "$1")"
    # https://android.googlesource.com/platform/system/apex/+/refs/tags/android-16.0.0_r4/apexer/apexer.py#901
    EVAL "7z a -tzip -mx=0 -mmt=$(nproc) \"$1\" \"$TMP_DIR/apex_payload.img\""
    LOG "- Adding apex_pubkey to $(basename "$1")"
    EVAL "7z a -tzip -mx=0 -mmt=$(nproc) \"$1\" \"$TMP_DIR/apex_pubkey\""
}

SIGN_APEX()
{
    LOG "- Signing $(basename "$1") with platform keys"

    local CERT_PREFIX="aosp"
    if $ROM_IS_OFFICIAL; then
        CERT_PREFIX="unica"
    fi

    # https://android.googlesource.com/platform/build/+/refs/tags/android-16.0.0_r4/tools/releasetools/apex_utils.py#394
    EVAL "signapk -a 4096 --align-file-size \"$SRC_DIR/security/${CERT_PREFIX}_platform.x509.pem\" \"$SRC_DIR/security/${CERT_PREFIX}_platform.pk8\" \"$1\" \"$(dirname "$1")/temp.apex\""
    mv -f "$(dirname "$1")/temp.apex" "$1"
}

SIGN_PAYLOAD()
{
    LOG "- Signing apex_payload.img with AVB"

    local SALT
    # https://android.googlesource.com/platform/system/apex/+/refs/tags/android-16.0.0_r4/apexer/apexer.py#689
    SALT="$(unzip -p "$1" "apex_manifest.pb" | sha256sum | cut -d " " -f 1)"

    # https://android.googlesource.com/platform/system/apex/+/refs/tags/android-16.0.0_r4/apexer/apexer.py#682
    EVAL "avbtool add_hashtree_footer --do_not_generate_fec --algorithm \"SHA256_RSA4096\" --hash_algorithm \"sha256\" --key \"$SRC_DIR/security/avb/testkey_rsa4096.pem\" --prop \"apex.key:com.android.bt\" --salt \"$SALT\" --image \"$TMP_DIR/apex_payload.img\""
    # https://android.googlesource.com/platform/build/+/refs/tags/android-16.0.0_r4/tools/releasetools/common.py#3775
    EVAL "avbtool extract_public_key --key \"$SRC_DIR/security/avb/testkey_rsa4096.pem\" --output \"$TMP_DIR/apex_pubkey\""
}
# ]

if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"

EXTRACT_PAYLOAD "$WORK_DIR/system/system/apex/com.android.bt.apex"

BLUETOOTH_APK="$(find "$TMP_DIR/apex_payload/app" -mindepth 2 -maxdepth 2 \
    -type f -name "Bluetooth.apk" -print -quit)"
if [ ! "$BLUETOOTH_APK" ]; then
    ABORT "Bluetooth.apk not found in com.android.bt.apex"
fi
BLUETOOTH_APK_RELATIVE_PATH="${BLUETOOTH_APK#"$TMP_DIR/apex_payload/"}"
BLUETOOTH_APK_WORK_PATH="system/$BLUETOOTH_APK_RELATIVE_PATH"

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE
if $SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
    if ! $TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
        DECODE_APK_IN_APEX "$BLUETOOTH_APK"
        LOG "- Disabling SUPPORT_A2DPSINK_PROFILE support in apex_payload/$BLUETOOTH_APK_RELATIVE_PATH"
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
            SMALI_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
                "smali/com/samsung/bt/a2dp/InstantProfile\$1.smali" "null" \
                'onReceive(Landroid/content/Context;Landroid/content/Intent;)V' \
                > /dev/null
        else
            APPLY_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
                "$MODPATH/a2dp_sink/Bluetooth.apk/0001-Disable-SUPPORT_A2DPSINK_PROFILE-support.patch" \
                > /dev/null
        fi
        DECODE_APK_IN_APEX "$TMP_DIR/apex_payload/javalib/framework-bluetooth.jar"
        LOG "- Disabling SUPPORT_A2DPSINK_PROFILE support in apex_payload/javalib/framework-bluetooth.jar"
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
            SMALI_PATCH "system" "system/framework/framework-bluetooth.jar" \
                "smali/android/bluetooth/BluetoothAdapter.smali" "return" \
                'semIsSinkServiceSupported()Z' "false" \
                > /dev/null
        else
            APPLY_PATCH "system" "system/framework/framework-bluetooth.jar" \
                "$MODPATH/a2dp_sink/framework-bluetooth.jar/0001-Disable-SUPPORT_A2DPSINK_PROFILE-support.patch" \
                > /dev/null
        fi
    fi
else
    if $TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE" "TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE"
    fi
fi

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_A2DP_SBM
if ! $SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM; then
    if $TARGET_BLUETOOTH_SUPPORT_A2DP_SBM; then
        DECODE_APK_IN_APEX "$BLUETOOTH_APK"
        LOG "- Applying \"Enable SUPPORT_A2DP_SBM support\" to apex_payload/$BLUETOOTH_APK_RELATIVE_PATH"
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]; then
            APPLY_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
                "$MODPATH/sbm/Bluetooth.apk/0002-Enable-SUPPORT_A2DP_SBM-support-on-One-UI-9.patch" \
                > /dev/null
        else
            APPLY_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
                "$MODPATH/sbm/Bluetooth.apk/0001-Enable-SUPPORT_A2DP_SBM-support.patch" \
                > /dev/null
        fi
    fi
else
    if ! $TARGET_BLUETOOTH_SUPPORT_A2DP_SBM; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM" "TARGET_BLUETOOTH_SUPPORT_A2DP_SBM"
    fi
fi

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF
if ! $SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
    if $TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
        DECODE_APK_IN_APEX "$BLUETOOTH_APK"
        LOG "- Applying \"Enable SUPPORT_HEAD_SAR_BACKOFF support\" to apex_payload/$BLUETOOTH_APK_RELATIVE_PATH"
        APPLY_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
            "$MODPATH/head_sar/Bluetooth.apk/0001-Enable-SUPPORT_HEAD_SAR_BACKOFF-support.patch" \
            > /dev/null
    fi
else
    if ! $TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF" "TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF"
    fi
fi

# SEC_PRODUCT_FEATURE_BLUETOOTH_SUPPORT_XLNA_CONTROL
if $SOURCE_BLUETOOTH_SUPPORT_XLNA_CONTROL; then
    if ! $TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL; then
        DECODE_APK_IN_APEX "$BLUETOOTH_APK"
        LOG "- Applying \"Disable SUPPORT_XLNA_CONTROL support\" to apex_payload/$BLUETOOTH_APK_RELATIVE_PATH"
        APPLY_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
            "$MODPATH/xlna/Bluetooth.apk/0001-Disable-SUPPORT_XLNA_CONTROL-support.patch" \
            > /dev/null
    fi
else
    if $TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL; then
        DECODE_APK_IN_APEX "$BLUETOOTH_APK"
        LOG "- Applying \"Enable SUPPORT_XLNA_CONTROL support\" to apex_payload/$BLUETOOTH_APK_RELATIVE_PATH"
        APPLY_PATCH "system" "$BLUETOOTH_APK_WORK_PATH" \
            "$MODPATH/xlna/Bluetooth.apk/0001-Enable-SUPPORT_XLNA_CONTROL-support.patch" \
            > /dev/null
    fi
fi

# Disable VaultKeeper support
# Before: [tbnz w8, #0, #0xXXXXXX]
# After: [b #0xXXXXXX]
if xxd -p -c 0 "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" | grep -q "2897773948050037"; then
    LOG "- Patching \"2897773948050037\" to \"289777392a000014\" in apex_payload/lib64/libbluetooth_jni.so"
    HEX_PATCH "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" \
        "2897773948050037" "289777392a000014" > /dev/null
elif xxd -p -c 0 "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" | grep -q "2897663948050037"; then
    LOG "- Patching \"2897663948050037\" to \"289766392a000014\" in apex_payload/lib64/libbluetooth_jni.so"
    HEX_PATCH "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" \
        "2897663948050037" "289766392a000014" > /dev/null
elif xxd -p -c 0 "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" | grep -q "88b65a3948050037"; then
    LOG "- Patching \"88b65a3948050037\" to \"88b65a392a000014\" in apex_payload/lib64/libbluetooth_jni.so"
    HEX_PATCH "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" \
        "88b65a3948050037" "88b65a392a000014" > /dev/null
elif xxd -p -c 0 "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" | grep -q "8876523948050037"; then
    LOG "- Patching \"8876523948050037\" to \"887652392a000014\" in apex_payload/lib64/libbluetooth_jni.so"
    HEX_PATCH "$TMP_DIR/apex_payload/lib64/libbluetooth_jni.so" \
        "8876523948050037" "887652392a000014" > /dev/null
else
    # The One UI 9 source firmware restructured this code, so none of the
    # known TBNZ signatures match and VaultKeeper cannot be disabled here.
    # This is not fatal to the build: leave libbluetooth_jni.so unpatched
    # and warn instead of aborting. Bluetooth may misbehave until the patch
    # is regenerated against the current firmware.
    # shellcheck disable=SC2317
    if $DEBUG; then
        ABORT "No known VaultKeeper patch available for libbluetooth_jni.so"
    else
        LOGW "No known VaultKeeper patch available for libbluetooth_jni.so, skipping"
    fi
fi

BUILD_APK_IN_APEX "$BLUETOOTH_APK"
BUILD_APK_IN_APEX "$TMP_DIR/apex_payload/javalib/framework-bluetooth.jar"
BUILD_PAYLOAD
SIGN_PAYLOAD "$WORK_DIR/system/system/apex/com.android.bt.apex"
REPACK_PAYLOAD "$WORK_DIR/system/system/apex/com.android.bt.apex"
SIGN_APEX "$WORK_DIR/system/system/apex/com.android.bt.apex"

rm -rf "$TMP_DIR"

unset BLUETOOTH_APK BLUETOOTH_APK_RELATIVE_PATH BLUETOOTH_APK_WORK_PATH SOURCE_FIRMWARE_PATH
unset -f BUILD_APK_IN_APEX BUILD_PAYLOAD DECODE_APK_IN_APEX \
    EXTRACT_PAYLOAD LOG_MISSING_PATCHES REPACK_PAYLOAD \
    SIGN_APEX SIGN_PAYLOAD
