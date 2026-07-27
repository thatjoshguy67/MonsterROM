SET_PROP_IF_DIFF "vendor" "ro.oem_unlock_supported" "0"

# Better device/model detection in CoreRune
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/rune/CoreRune.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/rune/CoreRune.smali" "replace" \
    '<clinit>()V' \
    'ro.product.device' \
    'ro.product.vendor.device'

# Disable vendor mismatch warning
DECODE_APK "system" "system/framework/services.jar" || return 1
VENDOR_MISMATCH_SMALI="$(grep -R -l -F \
    "Build fingerprint is not consistent, warning user" \
    "$APKTOOL_DIR/system/framework/services.jar"/smali* 2> /dev/null | head -n 1 || true)"
if [ "$VENDOR_MISMATCH_SMALI" ]; then
    LOG "- Disabling vendor mismatch warning in /system/system/framework/services.jar/${VENDOR_MISMATCH_SMALI//$APKTOOL_DIR\/system\/framework\/services.jar\//}"
    sed -i "s/Build fingerprint is not consistent, warning user/Build fingerprint is not consistent/" \
        "$VENDOR_MISMATCH_SMALI"
    python3 - "$VENDOR_MISMATCH_SMALI" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
start = text.find("\n    iget-object v2, p0, Lcom/android/server/wm/ActivityTaskManagerService$LocalService;->this$0:Lcom/android/server/wm/ActivityTaskManagerService;\n")
end_marker = "\n    invoke-virtual {v2, v4}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\n"
if start != -1:
    end = text.find(end_marker, start)
    if end != -1:
        text = text[:start] + text[end + len(end_marker):]
        path.write_text(text)
PY
else
    LOG "- Skipping vendor mismatch warning disable: warning smali not found in /system/system/framework/services.jar"
fi

# shellcheck disable=SC2016
# Disable RescueParty
DECODE_APK "system" "system/framework/services.jar" || return 1
SEC_RESCUE_PARTY_SMALI="$(find "$APKTOOL_DIR/system/framework/services.jar" \
    -path "*/com/android/server/SecRescueParty.smali" \
    -printf "%P\n" -quit)"
if [ "$SEC_RESCUE_PARTY_SMALI" ]; then
    SMALI_PATCH "system" "system/framework/services.jar" \
        "$SEC_RESCUE_PARTY_SMALI" "null" \
        "executeEraseAppData(Landroid/content/Context;Ljava/lang/String;I)V"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "$SEC_RESCUE_PARTY_SMALI" "null" \
        "executeRescueRecovery(Landroid/content/Context;Ljava/lang/String;I)V"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "$SEC_RESCUE_PARTY_SMALI" "null" \
        "executeResetOthers(Landroid/content/Context;Ljava/lang/String;I)V"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "$SEC_RESCUE_PARTY_SMALI" "null" \
        "executeSecRescueLevel(Landroid/content/Context;Ljava/lang/String;I)V"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "$SEC_RESCUE_PARTY_SMALI" "null" \
        "executeWarmReboot(Landroid/content/Context;Ljava/lang/String;I)V"
else
    LOG "- Skipping RescueParty disable: SecRescueParty.smali not found in /system/system/framework/services.jar"
fi

# Better model detection in FreecessController
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali/com/android/server/am/FreecessController.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'
