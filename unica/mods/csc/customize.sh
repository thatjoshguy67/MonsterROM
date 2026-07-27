SYSTEMUI_BASICRUNE_SMALI="$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/smali/com/android/systemui/BasicRune.smali"

DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk" || return 1

SYSTEMUI_ASSIST_REGISTER="$(
    awk '
        /^\.method/ && /<clinit>\(\)V/ { inside = 1 }
        inside && /ASSIST_ASSISTANCE_APP_SETTING_POPUP:Z/ {
            line = $0
            sub(/^[[:space:]]*sput-boolean /, "", line)
            sub(/,.*/, "", line)
            print line
            exit
        }
        inside && /^\.end method/ { exit }
    ' "$SYSTEMUI_BASICRUNE_SMALI"
)"
if [[ ! "$SYSTEMUI_ASSIST_REGISTER" =~ ^[vp][0-9]+$ ]]; then
    ABORT "Failed to find the SystemUI assistance popup register"
    return 1
fi

SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
    "smali/com/android/systemui/BasicRune.smali" "replace" \
    "<clinit>()V" \
    "sput-boolean $SYSTEMUI_ASSIST_REGISTER, Lcom/android/systemui/BasicRune;->ASSIST_ASSISTANCE_APP_SETTING_POPUP:Z" \
    "const/4 $SYSTEMUI_ASSIST_REGISTER, 0x1\n\n    sput-boolean $SYSTEMUI_ASSIST_REGISTER, Lcom/android/systemui/BasicRune;->ASSIST_ASSISTANCE_APP_SETTING_POPUP:Z"

unset SYSTEMUI_ASSIST_REGISTER SYSTEMUI_BASICRUNE_SMALI
