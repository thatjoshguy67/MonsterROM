AIRCOMMAND_APK="system/priv-app/AirCommand/AirCommand.apk"

FIND_AIRCOMMAND_SMALI()
{
    local METHOD="$1"
    local SEARCH_DIR="${2:-$AIRCOMMAND_DECODED_DIR}"
    local PREFERRED_FILE="${3:-}"
    local MATCHES

    if [ -n "$PREFERRED_FILE" ] && [ -f "$SEARCH_DIR/$PREFERRED_FILE" ] && \
            grep -qF -- " $METHOD" "$SEARCH_DIR/$PREFERRED_FILE"; then
        printf '%s\n' "${SEARCH_DIR#"$AIRCOMMAND_DECODED_DIR"/}/$PREFERRED_FILE"
        return 0
    fi

    MATCHES="$(grep -rlF -- " $METHOD" "$SEARCH_DIR" 2>/dev/null || true)"
    if [ -z "$MATCHES" ]; then
        LOGE "AirCommand method \"$METHOD\" not found"
        return 1
    fi

    if [ "$(wc -l <<< "$MATCHES")" -ne 1 ]; then
        LOGE "AirCommand method \"$METHOD\" is ambiguous"
        echo -e "\n\033[0;31mPossible matches?" >&2
        echo -e -n "$(head -n 10 <<< "${MATCHES//$AIRCOMMAND_DECODED_DIR\//    }")" >&2
        [ "$(wc -l <<< "$MATCHES")" -gt 10 ] && \
            echo -e -n "\n    ...and other $(($(wc -l <<< "$MATCHES") - 10)) matches" >&2
        echo -e "\033[0m" >&2
        return 1
    fi

    printf '%s\n' "${MATCHES#"$AIRCOMMAND_DECODED_DIR"/}"
}

if [ -f "$WORK_DIR/system/$AIRCOMMAND_APK" ]; then
    LOG_STEP_IN "- Applying AirCommand S Pen logic patch"

    DECODE_APK "system" "$AIRCOMMAND_APK" || return 1
    AIRCOMMAND_DECODED_DIR="$APKTOOL_DIR/system/${AIRCOMMAND_APK//system\//}"

    AIRCOMMAND_PM_SMALI="$(FIND_AIRCOMMAND_SMALI \
        "a(Landroid/content/pm/PackageManager;)I")" || return 1
    AIRCOMMAND_OBFUSCATED_DIR="$(dirname \
        "$AIRCOMMAND_DECODED_DIR/$AIRCOMMAND_PM_SMALI")"
    AIRCOMMAND_FEATURE_SMALI="$(FIND_AIRCOMMAND_SMALI \
        "c()I" "$AIRCOMMAND_OBFUSCATED_DIR" "b.smali")" || return 1

    SMALI_PATCH "system" "$AIRCOMMAND_APK" \
        "$AIRCOMMAND_PM_SMALI" \
        "return" \
        "a(Landroid/content/pm/PackageManager;)I" \
        "70"

    SMALI_PATCH "system" "$AIRCOMMAND_APK" \
        "$AIRCOMMAND_FEATURE_SMALI" \
        "return" \
        "c()I" \
        "70"

    APPLY_PATCH "system" "$AIRCOMMAND_APK" \
        "$SRC_DIR/unica/patches/spen/AirCommand.apk/0001-Add-AirCommand-shortcut-detach-simulator.patch"

    LOG_STEP_OUT
else
    LOGW "AirCommand.apk is not present in work_dir. Skipping AirCommand logic patch"
fi

LOG_STEP_IN "- Applying S Pen floating feature config"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_GARAGE_SPEC" "type=insert, bundled=true"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_VERSION" "70"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SETTINGS_SUPPORT_S_PEN_HOVERING_N_DETACHMENT" "TRUE"
LOG_STEP_OUT

unset AIRCOMMAND_APK AIRCOMMAND_DECODED_DIR AIRCOMMAND_FEATURE_SMALI
unset AIRCOMMAND_OBFUSCATED_DIR AIRCOMMAND_PM_SMALI
unset -f FIND_AIRCOMMAND_SMALI
