# Stage a verification-disabled vbmeta so the flashable zip can write it.
#
# The ROM re-signs system/vendor/product with the AVB test key, so their
# hashes no longer match the descriptors in the device's stock (verification-
# enabled) vbmeta. Leaving that stock vbmeta in place makes the bootloader
# reject the modified partitions and silently reboot before the kernel starts
# (bootloops at the Samsung logo, no kernel log). extract_fw.sh already built
# a disabled copy (flags 0x03 = hashtree + verification disabled) from the
# target BL; copy it into the zip for install-end.edify to flash. This mirrors
# what every other target does (see r9s / a73xq); it was missing here because
# the r9q2 installer only had assertions.edify.
#
# Only vbmeta is staged - unlike a73xq/r9s this does NOT rewrite the bootloader,
# since the device is expected to already be on the pinned F-base.
_R9Q2_FW_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
_R9Q2_VBMETA="$FW_DIR/$_R9Q2_FW_PATH/avb/vbmeta_patched.img"
if [ ! -f "$_R9Q2_VBMETA" ]; then
    LOG "\033[0;31m! Disabled vbmeta not found: ${_R9Q2_VBMETA//$SRC_DIR\//}\033[0m"
    return 1
fi
LOG "- Staging verification-disabled vbmeta.img"
EVAL "cp -a \"$_R9Q2_VBMETA\" \"$TMP_DIR/vbmeta.img\"" || return 1
unset _R9Q2_FW_PATH _R9Q2_VBMETA
