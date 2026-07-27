# shellcheck disable=SC2181
DECODE_APK "system" "system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk"

_SETUPWIZARD_APK_DIR="$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk"
_SETUPWIZARD_ACTIVITY_SMALI="$_SETUPWIZARD_APK_DIR/smali/com/sec/android/app/SecSetupWizard/SecSetupWizardActivity.smali"

_SETUPWIZARD_LIST_SMALI="$(find "$_SETUPWIZARD_APK_DIR" -type f -name "*.smali" \
    -exec grep -l "navigationbar_setting" {} +)"
if [ -z "$_SETUPWIZARD_LIST_SMALI" ] || \
        [ "$(printf "%s\n" "$_SETUPWIZARD_LIST_SMALI" | wc -l)" -ne 1 ]; then
    LOG "\033[0;31m! ERROR: failed to resolve the Setup Wizard list builder\033[0m"
    return 1
fi

LOG "- Enabling navigation bar type settings step"
if grep -q "navigationbar_setting" "$_SETUPWIZARD_LIST_SMALI"; then
    sed -i "s/navigationbar_setting/this_string_does_not_exist/g" \
        "$_SETUPWIZARD_LIST_SMALI"
fi
if grep -q "navigationbar_setting" "$_SETUPWIZARD_ACTIVITY_SMALI"; then
    SMALI_PATCH "system" "system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk" \
        "smali/com/sec/android/app/SecSetupWizard/SecSetupWizardActivity.smali" "replace" \
        "e(Ljava/lang/String;)Z" \
        "navigationbar_setting" \
        "this_string_does_not_exist" \
        > /dev/null
fi

LOG "- Disabling Recommended apps step"
EVAL "sed -i \"/omcagent/d\" \"$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/res/values/arrays.xml\""

# Dynamically patch SecSetupWizard_Global
# - Add missing/non-xml files in place
# - Patch existing files
#   - Use the first line of the file to tell sed how to apply the rest of the content
#   - Exception made for files under *res/values* where the "resources" tag gets nuked
while IFS= read -r f; do
    f="${f//$MODPATH\/SecSetupWizard_Global.apk\//}"

    if [ ! -f "$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/$f" ] || \
            [[ "$f" != *".xml" ]]; then
        LOG "- Adding \"$f\" to /system/system/priv-app/SecSetupWizard_Global.apk"
        EVAL "mkdir -p \"$(dirname "$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/$f")\""
        EVAL "cp -a \"$MODPATH/SecSetupWizard_Global.apk/${f//\$/\\$}\" \"$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/${f//\$/\\$}\""
    else
        LOG "- Patching \"$f\" in /system/system/priv-app/SecSetupWizard_Global.apk"
        if [[ "$f" == *"res/values"* ]]; then
            PATCH_INST="/<\/resources>/i"
            while IFS= read -r RESOURCE_NAME; do
                EVAL "sed -i \"/name=\\\"$RESOURCE_NAME\\\"/d\" \"$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/$f\""
            done < <(sed -n 's/.*name="\([^"]*\)".*/\1/p' "$MODPATH/SecSetupWizard_Global.apk/$f")
            CONTENT="$(sed -e "/?xml/d" -e "/resources>/d" "$MODPATH/SecSetupWizard_Global.apk/$f")"
        else
            PATCH_INST="$(head -n 1 "$MODPATH/SecSetupWizard_Global.apk/$f")"
            CONTENT="$(tail -n +2 "$MODPATH/SecSetupWizard_Global.apk/$f")"
        fi
        CONTENT="$(sed -e "s/\"/\\\\\"/g" -e "s/\\\\\\\\\"/\\\\\\\\\\\\\\\\\\\\\"/g" -e "s/\\$/\\\\$/g" -e "s/ /\\\ /g" -e "s/\\\\n/\\\\\\\\\n/g" <<< "$CONTENT")"
        CONTENT="$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' <<< "$CONTENT")"
        EVAL "sed -i \"$PATCH_INST $CONTENT\" \"$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/$f\""
    fi
done < <(find "$MODPATH/SecSetupWizard_Global.apk" -type f)

_SETUPWIZARD_PUBLIC_ID()
{
    local TYPE="$1"
    local NAME="$2"
    local PUBLIC_XML="$APKTOOL_DIR/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk/res/values/public.xml"
    local ID
    local LAST
    local NEXT

    ID="$(sed -n "s/.*<public type=\"$TYPE\" name=\"$NAME\" id=\"\\(0x[0-9a-fA-F]*\\)\".*/\\1/p" "$PUBLIC_XML" | head -n 1)"
    if [ "$ID" ]; then
        echo "$ID"
        return 0
    fi

    LAST="$(sed -n "s/.*<public type=\"$TYPE\" .* id=\"0x\\([0-9a-fA-F]*\\)\".*/\\1/p" "$PUBLIC_XML" | tail -n 1)"
    [ "$LAST" ] || return 1

    NEXT="$(printf "0x%08x" "$((16#$LAST + 1))")"
    sed -i "/<\/resources>/i\\    <public type=\"$TYPE\" name=\"$NAME\" id=\"$NEXT\" />" "$PUBLIC_XML"
    echo "$NEXT"
}

_SETUPWIZARD_ICON_ID="$(_SETUPWIZARD_PUBLIC_ID "drawable" "suw_ic_unica")" || return 1
_SETUPWIZARD_TEXT_ID="$(_SETUPWIZARD_PUBLIC_ID "string" "disclaimer_unica_description")" || return 1

LOG "- Patching custom disclaimer page in /system/system/priv-app/SecSetupWizard_Global.apk"
if ! grep -q "UN1CA force disclaimer step" "$_SETUPWIZARD_LIST_SMALI"; then
    awk '
        BEGIN { in_disclaimer = 0; changed = 0 }
        /const-string .*"disclaimer"/ { in_disclaimer = 1 }
        in_disclaimer && index($0, "if-lez v9, :cond_46") {
            match($0, /^[ \t]+/)
            indent = substr($0, RSTART, RLENGTH)
            print indent "# UN1CA force disclaimer step"
            print indent "goto :cond_19"
            changed = 1
            in_disclaimer = 0
            next
        }
        { print }
        END { if (!changed) exit 1 }
    ' "$_SETUPWIZARD_LIST_SMALI" > "$_SETUPWIZARD_LIST_SMALI.tmp" && \
        mv "$_SETUPWIZARD_LIST_SMALI.tmp" "$_SETUPWIZARD_LIST_SMALI"
    [ $? -ne 0 ] && { LOG "\033[0;31m! ERROR: custom disclaimer sequence patch failed\033[0m"; return 1; }
fi

_SETUPWIZARD_DISCLAIMER_SMALI="$_SETUPWIZARD_APK_DIR/smali/com/sec/android/app/SecSetupWizard/UI/DisclaimerActivity.smali"
if ! grep -q "UN1CA custom disclaimer" "$_SETUPWIZARD_DISCLAIMER_SMALI"; then
    awk -v ICON_ID="$_SETUPWIZARD_ICON_ID" -v TEXT_ID="$_SETUPWIZARD_TEXT_ID" '
        BEGIN { icon_done = 0; text_done = 0 }
        {
            print

            if (!icon_done && index($0, "invoke-virtual {p0, p1}, Ll7/a;->setContentView(I)V")) {
                print ""
                print "    # UN1CA custom disclaimer icon"
                print "    invoke-virtual {p0}, Lh/j;->getResources()Landroid/content/res/Resources;"
                print ""
                print "    move-result-object p1"
                print ""
                print "    const v1, " ICON_ID
                print ""
                print "    invoke-virtual {p0}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;"
                print ""
                print "    move-result-object v2"
                print ""
                print "    invoke-virtual {p1, v1, v2}, Landroid/content/res/Resources;->getDrawable(ILandroid/content/res/Resources$Theme;)Landroid/graphics/drawable/Drawable;"
                print ""
                print "    move-result-object p1"
                print ""
                print "    invoke-virtual {p0, p1}, Ll7/a;->z(Landroid/graphics/drawable/Drawable;)V"
                icon_done = 1
            }

            if (!text_done && index($0, "check-cast p1, Landroid/widget/TextView;")) {
                print ""
                print "    # UN1CA custom disclaimer"
                print "    const v0, " TEXT_ID
                print ""
                print "    invoke-virtual {p0, v0}, Landroid/content/Context;->getString(I)Ljava/lang/String;"
                print ""
                print "    move-result-object p0"
                print ""
                print "    invoke-virtual {p1, p0}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V"
                print ""
                print "    return-void"
                text_done = 1
            }
        }
        END { if (!icon_done || !text_done) exit 1 }
    ' "$_SETUPWIZARD_DISCLAIMER_SMALI" > "$_SETUPWIZARD_DISCLAIMER_SMALI.tmp" && \
        mv "$_SETUPWIZARD_DISCLAIMER_SMALI.tmp" "$_SETUPWIZARD_DISCLAIMER_SMALI"
    [ $? -ne 0 ] && { LOG "\033[0;31m! ERROR: custom disclaimer patch failed\033[0m"; return 1; }
fi

unset PATCH_INST CONTENT
