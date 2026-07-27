# Fix SDHMS crash loop: siop_default.xml references OverheatComplexType.DEX which doesn't exist in the enum
DECODE_APK "system" "system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk" || return 1
_SDHMS_XML="$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/assets/siop_default.xml"
if grep -q '<DEX ' "$_SDHMS_XML" 2>/dev/null; then
    LOG "- Removing unsupported DEX overheat complex type from SDHMS siop_default.xml"
    sed -i '/<DEX /d' "$_SDHMS_XML"
else
    LOG "- siop_default.xml: DEX entry not found (already removed or not present)"
fi
unset _SDHMS_XML

# Hide Knox HDM and DualDAR versions. Method-level patches tolerate body changes
# between donor releases, and SMALI_PATCH resolves classes that moved dex buckets.
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "smali_classes3/com/samsung/android/knox/hdm/HdmManager.smali" \
    "return" "getHdmVersion()Ljava/lang/String;" "null"

SMALI_PATCH "system" \
    "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
    "smali_classes3/com/samsung/android/knox/ddar/DualDARPolicy.smali" \
    "return" "getDualDARVersion()Ljava/lang/String;" "null"
SMALI_PATCH "system" \
    "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
    "smali_classes3/com/samsung/android/knox/hdm/HdmManager.smali" \
    "return" "getHdmVersion()Ljava/lang/String;" "null"

SMALI_PATCH "system" "system/framework/knoxsdk.jar" \
    "smali_classes3/com/samsung/android/knox/ddar/DualDARPolicy.smali" \
    "return" "getDualDARVersion()Ljava/lang/String;" "null"
SMALI_PATCH "system" "system/framework/knoxsdk.jar" \
    "smali_classes3/com/samsung/android/knox/hdm/HdmManager.smali" \
    "return" "getHdmVersion()Ljava/lang/String;" "null"

SMALI_PATCH "system_ext" "priv-app/StorageManager/StorageManager.apk" \
    "smali_classes3/com/samsung/android/knox/ddar/DualDARPolicy.smali" \
    "return" "getDualDARVersion()Ljava/lang/String;" "null"
SMALI_PATCH "system_ext" "priv-app/StorageManager/StorageManager.apk" \
    "smali_classes3/com/samsung/android/knox/hdm/HdmManager.smali" \
    "return" "getHdmVersion()Ljava/lang/String;" "null"

# Skip KnoxGuard startup using SystemServer's existing end-of-block label.
DECODE_APK "system" "system/framework/services.jar" || return 1
_SYSTEM_SERVER_SMALI="$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/SystemServer.smali"
LOG "- Disabling KnoxGuardService startup in /system/system/framework/services.jar"
python3 - "$_SYSTEM_SERVER_SMALI" << 'PYEOF' || return 1
import re
import sys

path = sys.argv[1]
with open(path) as stream:
    lines = stream.readlines()

markers = [
    index for index, line in enumerate(lines)
    if '"StartKnoxGuard"' in line
]
if len(markers) != 1:
    print(f"Expected one StartKnoxGuard marker, found {len(markers)}", file=sys.stderr)
    sys.exit(1)

marker = markers[0]
window_start = max(0, marker - 30)
if not any(
    "FactoryTest;->isFactoryBinary()Z" in line
    for line in lines[window_start:marker]
):
    print("FactoryTest guard not found before StartKnoxGuard", file=sys.stderr)
    sys.exit(1)

target = None
for index in range(marker - 1, window_start - 1, -1):
    match = re.match(r"\s*if-\w+\s+[^,]+,\s+(:[A-Za-z0-9_]+)\s*$", lines[index])
    if match:
        candidate = match.group(1)
        if any(line.strip() == candidate for line in lines[marker + 1:]):
            target = candidate
            break

if target is None:
    print("KnoxGuard skip label not found", file=sys.stderr)
    sys.exit(1)

if marker > 0 and lines[marker - 1].strip() == f"goto {target}":
    sys.exit(0)

lines[marker:marker] = [f"    goto {target}\n", "\n"]
with open(path, "w") as stream:
    stream.writelines(lines)
PYEOF
unset _SYSTEM_SERVER_SMALI

# KnoxGuard
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxGuard"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.kgclient.xml"

# DualDAR
DELETE_FROM_WORK_DIR "system" "system/bin/dualdard"
DELETE_FROM_WORK_DIR "system" "system/etc/init/dualdard.rc"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libdualdar.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/aidl_comm_ddar_client.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.tlc.ddar-V1-ndk.so"

# Blockchain
DELETE_FROM_WORK_DIR "system" "system/app/BlockchainBasicKit"
DELETE_FROM_WORK_DIR "system" "system/framework/service-samsung-blockchain.jar"
DELETE_FROM_WORK_DIR "system" "system/etc/sysconfig/preinstalled-packages-com.samsung.android.coldwalletservice.xml"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libtlc_blockchain_comm.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libtlc_blockchain_keystore.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libtlc_blockchain_direct_comm.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.tlc.blockchain@1.0.so"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_BLOCKCHAIN_SERVICE" --delete

# Payment
# DELETE_FROM_WORK_DIR "system" "system/lib64/libtlc_payment_direct_comm.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libtlc_payment_spay.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libtlc_payment_comm.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.tlc.payment@1.0.so"

# MPOS
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.mpos.xml"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libhidl_comm_mpos_tui_client.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.mpos-V1-ndk.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.tlc.mpos_tui@1.0.so"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxMposAgent"

# eSE COS
DELETE_FROM_WORK_DIR "system" "system/bin/sem_daemon"
DELETE_FROM_WORK_DIR "system" "system/etc/init/sem_early.rc"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.sem.factoryapp.xml"
DELETE_FROM_WORK_DIR "system" "system/lib64/libsec_sem.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/libsec_semAidl.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libsec_semRil.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/libsec_semTlc.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/libspictrl.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.security.sem-V1-ndk.so"
DELETE_FROM_WORK_DIR "system" "system/priv-app/SEMFactoryApp"

# Weaver
# DELETE_FROM_WORK_DIR "system" "system/lib64/libhermes_cred.so"
# DELETE_FROM_WORK_DIR "system" "system/lib64/android.hardware.weaver-V2-ndk.so"

# HDM
DELETE_FROM_WORK_DIR "system" "system/priv-app/HdmApk"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.hdmapp.xml"

# WSM
DELETE_FROM_WORK_DIR "system" "system/etc/public.libraries-wsm.samsung.txt"
DELETE_FROM_WORK_DIR "system" "system/lib64/libhal.wsm.samsung.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.security.wsm.service-V1-ndk.so"

# Knox ZeroTrust
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.zt.framework.xml"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxZtFramework"

# Knox Matrix
DELETE_FROM_WORK_DIR "system" "system/bin/fabric_crypto"
DELETE_FROM_WORK_DIR "system" "system/etc/init/fabric_crypto.rc"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/FabricCryptoLib.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.kmxservice.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/vintf/manifest/fabric_crypto_manifest.xml"
DELETE_FROM_WORK_DIR "system" "system/framework/FabricCryptoLib.jar"
DELETE_FROM_WORK_DIR "system" "system/lib64/com.samsung.security.fabric.cryptod-V1-cpp.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.security.fkeymaster-V1-cpp.so"
DELETE_FROM_WORK_DIR "system" "system/lib64/vendor.samsung.hardware.security.fkeymaster-V1-ndk.so"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KmxService"

# Other Knox APKs
DELETE_FROM_WORK_DIR "system" "system/priv-app/KPECore"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxCore"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxERAgent"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxFrameBufferProvider"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxNetworkFilter"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxNeuralNetworkRuntime"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxPushManager"
DELETE_FROM_WORK_DIR "system" "system/priv-app/KnoxSandbox"
DELETE_FROM_WORK_DIR "system" "system/priv-app/knoxanalyticsagent"
DELETE_FROM_WORK_DIR "system" "system/priv-app/knoxvpnproxyhandler"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.knox.vpn.proxyhandler.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.analytics.uploader.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.app.networkfilter.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.er.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.kfbp.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.knnr.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.kpecore.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.pushmanager.xml"
DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.knox.sandbox.xml"
