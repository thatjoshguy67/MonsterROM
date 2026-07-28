LOG_STEP_IN "- Disabling /data encryption in the vendor fstab"

# r9q2 ships a One UI 9 (Android 16) system on its stock Android 11 vendor. The
# stock vendor fstab requires FBE + dm-default-key metadata encryption on /data,
# whose keys are provisioned in first-stage init through the vendor keymaster.
# The new vold cannot provision them against the old keymaster, so first-stage
# init aborts and the device bootloops at the logo before the boot animation
# (empty pstore, no kernel log) - unaffected by Format Data.
#
# Turn the fileencryption/forceencrypt flag into the legacy "encryptable" marker
# so /data mounts unencrypted and no dm-default-key provisioning is attempted.
# This mirrors the fix AstroROM/ProjectAstro use for the same device. The
# original line is preserved, commented out, above the patched one.
if [ ! -d "$WORK_DIR/vendor/etc" ]; then
    LOG "\033[0;33m! vendor/etc not found; nothing to do\033[0m"
    LOG_STEP_OUT
    return 0
fi

while IFS= read -r -d '' FSTAB; do
    if grep -qE 'fileencryption=|forceencrypt=' "$FSTAB"; then
        LOG "- Patching ${FSTAB//$WORK_DIR\//}"
        sed -i -E 's/^([^#].*)fileencryption=[^,]*(.*)$/# &\n\1encryptable\2/' "$FSTAB" || return 1
        sed -i -E 's/^([^#].*)forceencrypt=[^,]*(.*)$/# &\n\1encryptable\2/' "$FSTAB" || return 1
    fi
done < <(find "$WORK_DIR/vendor/etc" -type f -name "fstab*" -print0)

LOG_STEP_OUT
