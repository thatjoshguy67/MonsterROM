DELETE_FROM_WORK_DIR "system" "system/etc/ldu_blocklist.xml"

APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/services.jar/0001-Allow-custom-PackageBlockListPolicy.patch"

INSTALL_PACKAGE_HELPER="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/InstallPackageHelper.smali"
INSTALL_PACKAGE_HELPER_TMP="$INSTALL_PACKAGE_HELPER.tmp"

LOG "- Removing the RDU-only blocklist check from /system/system/framework/services.jar"
if ! awk '
    index($0, "PackageBlockListPolicy;->sIsRduDevice:") {
        found = 1
        skipping = 1
        next
    }
    skipping && index($0, "AtomicBoolean;->get()Z") {
        skipping = 0
        next
    }
    !skipping { print }
    END { if (!found || skipping) exit 1 }
' "$INSTALL_PACKAGE_HELPER" > "$INSTALL_PACKAGE_HELPER_TMP"; then
    rm -f "$INSTALL_PACKAGE_HELPER_TMP"
    LOGE "Failed to remove the RDU-only blocklist check from InstallPackageHelper.smali"
    return 1
fi
mv "$INSTALL_PACKAGE_HELPER_TMP" "$INSTALL_PACKAGE_HELPER" || return 1

SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/pm/InstallPackageHelper.smali" "replaceall" \
    "sLduBlocklist:Ljava/util/HashSet;" "sBlocklist:Ljava/util/HashSet;"
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/pm/InstallPackageHelper.smali" "replaceall" \
    "/system/etc/ldu_blocklist.xml" "/system/etc/unica_blocklist.xml"

unset INSTALL_PACKAGE_HELPER INSTALL_PACKAGE_HELPER_TMP

SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/samsung/android/server/pm/install/PackageBlockListPolicy\$1.smali" 'remove'
