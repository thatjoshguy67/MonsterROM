# shellcheck disable=SC2034
SKIPUNZIP=1

if [ ! -d "$SRC_DIR/prebuilts/samsung/${TARGET_CODENAME}cxx" ]; then
    LOG "- China firmware blobs not present, skipping"
    return 0
fi

mkdir -p "$WORK_DIR/odm/firmware"
cp -a --preserve=all "$SRC_DIR/platform/sm8550/patches/china/vendor/etc/init/hw/"* "$WORK_DIR/vendor/etc/init/hw"

BLOBS="
CAMERA_ICP.b20
CAMERA_ICP.mbn
CAMERA_ICP.mdt
a740_zap.b02
a740_zap.mbn
a740_zap.mdt
evass.b19
evass.mbn
evass.mdt
vpu30_4v.mbn
"

SET_METADATA "odm" "firmware" 0 0 755 "u:object_r:vendor_firmware_file:s0"

for blob in $BLOBS; do
    ADD_TO_WORK_DIR "${TARGET_CODENAME}cxx" "odm" "firmware/$blob" 0 0 644 "u:object_r:vendor_firmware_file:s0"
done

SET_METADATA "vendor" "etc/init/hw/init.samsung.firmware.rc" 0 0 644 "u:object_r:vendor_configs_file:s0"

if ! grep -q "samsung.firmware" "$WORK_DIR/vendor/etc/init/hw/init.samsung.rc"; then
    sed -i "/samsung.connector/a import /vendor/etc/init/hw/init.samsung.firmware.rc" "$WORK_DIR/vendor/etc/init/hw/init.samsung.rc"
fi

VENDOR_CIL_VERSION="$(head -n 1 "$WORK_DIR/vendor/etc/selinux/plat_sepolicy_vers.txt")"
INIT_TYPE="init_${VENDOR_CIL_VERSION//./_}"
if ! grep -q "vendor_firmware_file (file (mounton" "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"; then
    echo "(allow $INIT_TYPE vendor_firmware_file (file (mounton)))" >> "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
fi

unset VENDOR_CIL_VERSION INIT_TYPE
