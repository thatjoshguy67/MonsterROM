DAAGENT_RECEIVER_SMALI="$APKTOOL_DIR/system/app/DAAgent/DAAgent.apk/smali/com/samsung/android/da/daagent/receiver/DualAppIntentReceiver.smali"
DAAGENT_RECEIVER_TMP="$DAAGENT_RECEIVER_SMALI.tmp"

DECODE_APK "system" "system/app/DAAgent/DAAgent.apk" || return 1

DAAGENT_RECEIVER_METHOD="$(
    awk '
        /^\.method/ { method = $NF }
        index($0, "DAUtility;->updateWhitelistAppsInSystemServer(Landroid/content/Context;)V") {
            print method
            exit
        }
    ' "$DAAGENT_RECEIVER_SMALI"
)"
if [ -z "$DAAGENT_RECEIVER_METHOD" ]; then
    ABORT "Failed to find the existing Dual Messenger whitelist update"
    return 1
fi

LOG "- Moving the Dual Messenger whitelist update in $DAAGENT_RECEIVER_METHOD"
if ! awk -v FN="$DAAGENT_RECEIVER_METHOD" '
    /^\.method/ && index($0, FN) { inside = 1 }
    inside && index($0, "DAUtility;->updateWhitelistAppsInSystemServer(Landroid/content/Context;)V") {
        removed++
        next
    }
    inside && !inserted && index($0, "SendSaLogService;->schedule(Landroid/content/Context;)V") {
        line = $0
        sub("Lcom/samsung/android/da/daagent/service/SendSaLogService;->schedule", "Lcom/samsung/android/da/daagent/utils/DAUtility;->updateWhitelistAppsInSystemServer", line)
        print line
        print ""
        inserted = 1
    }
    inside && /^\.end method/ { inside = 0 }
    { print }
    END { if (removed != 1 || inserted != 1) exit 1 }
' "$DAAGENT_RECEIVER_SMALI" > "$DAAGENT_RECEIVER_TMP"; then
    rm -f "$DAAGENT_RECEIVER_TMP"
    LOGE "Failed to move the Dual Messenger whitelist update"
    return 1
fi
mv "$DAAGENT_RECEIVER_TMP" "$DAAGENT_RECEIVER_SMALI" || return 1

unset DAAGENT_RECEIVER_METHOD DAAGENT_RECEIVER_SMALI DAAGENT_RECEIVER_TMP
