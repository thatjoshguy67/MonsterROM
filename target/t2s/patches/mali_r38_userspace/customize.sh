# shellcheck disable=SC2016,SC2034
SKIPUNZIP=1

MALI_R38_KERNEL_MANIFEST="$SRC_DIR/out/kernel-builds/latest-mali-ddk.txt"
MALI_R38_BOOT_IMAGE="$WORK_DIR/kernel/boot.img"
MALI_R38_VENDOR_BOOT_IMAGE="$WORK_DIR/kernel/vendor_boot.img"

for TOOL in cmp curl cut git grep readelf sed sha256sum strings; do
    command -v "$TOOL" >/dev/null || \
        ABORT "Required Mali r38 userspace tool is missing: $TOOL"
done

_T2S_MALI_R38_FILE_MATCHES()
{
    local FILE="$1"
    local EXPECTED="$2"

    [ -f "$FILE" ] && [ "$(sha256sum "$FILE" | cut -d ' ' -f 1)" = "$EXPECTED" ]
}

_T2S_MALI_R38_MANIFEST_VALUE()
{
    sed -n "s/^$1=//p" "$MALI_R38_KERNEL_MANIFEST" | tail -n 1
}

_T2S_MALI_R38_VERIFY_KERNEL_PAIRING()
{
    local BOOT_HASH VENDOR_BOOT_HASH

    [ -s "$MALI_R38_KERNEL_MANIFEST" ] || \
        ABORT "Mali kernel build manifest is missing"
    [ "$(_T2S_MALI_R38_MANIFEST_VALUE target)" = "t2s" ] || \
        ABORT "Mali kernel manifest belongs to a different target"
    [ "$(_T2S_MALI_R38_MANIFEST_VALUE ddk)" = "r38p1-01eac0" ] || \
        ABORT "Mali userspace requires the r38p1-01eac0 kernel driver"
    [ "$(_T2S_MALI_R38_MANIFEST_VALUE uk_abi)" = "11.35" ] || \
        ABORT "Mali userspace requires Job Manager UK ABI 11.35"
    [ -n "$(_T2S_MALI_R38_MANIFEST_VALUE kernel_module_sha256)" ] || \
        ABORT "Mali kernel module checksum is missing"

    [ -f "$MALI_R38_BOOT_IMAGE" ] || ABORT "Installed boot.img is missing"
    [ -f "$MALI_R38_VENDOR_BOOT_IMAGE" ] || ABORT "Installed vendor_boot.img is missing"
    BOOT_HASH="$(sha256sum "$MALI_R38_BOOT_IMAGE" | cut -d ' ' -f 1)"
    VENDOR_BOOT_HASH="$(sha256sum "$MALI_R38_VENDOR_BOOT_IMAGE" | cut -d ' ' -f 1)"
    [ "$(_T2S_MALI_R38_MANIFEST_VALUE boot_sha256)" = "$BOOT_HASH" ] || \
        ABORT "boot.img no longer matches the verified Mali kernel build"
    [ "$(_T2S_MALI_R38_MANIFEST_VALUE vendor_boot_sha256)" = "$VENDOR_BOOT_HASH" ] || \
        ABORT "vendor_boot.img no longer matches the verified Mali kernel build"
}

MALI_R38_REPOSITORY="RandomPush/samsung_a54x_dump"
MALI_R38_COMMIT="a205e1ffdd8f483b30fc8100bd9eb13944462e62"
MALI_R38_BASE_URL="https://raw.githubusercontent.com/$MALI_R38_REPOSITORY/$MALI_R38_COMMIT"
MALI_R38_CACHE_DIR="$SRC_DIR/out/gpu-cache/a54x-r38p1-$MALI_R38_COMMIT"
MALI_R38_LOCAL_DONOR_DIR="$SRC_DIR/out/gpu-donors/a54x-dump"

# relative destination|sha256|ELF class|SELinux label
MALI_R38_FILES=(
    "vendor/lib/egl/libGLES_mali.so|2d17d55694b70f5e63023bcc1e89f17077f95f05a008b87b1547452b54d464fe|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/egl/libGLES_mali.so|11b09aed6a1504ff5e49f3f12f4ebef18786ae31ca53af4383c8eadb93a30d1d|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib/hw/vulkan.mali.so|71410b2c08b5064c1106a87e548764c8c5f0c25d90aec763d40801664dc7a777|ELF32|u:object_r:vendor_file:s0"
    "vendor/lib64/hw/vulkan.mali.so|95275e8ff53d469e7b102bc1d3e0269ff643ab6519030b4cac59821b83ef4d82|ELF64|u:object_r:vendor_file:s0"
    "vendor/lib/mali_symlink.so|049aeccad548f29d1f4a9b246951c69d4a4be6d7d3bc5a4a9e688d194346259b|ELF32|u:object_r:vendor_file:s0"
    "vendor/lib64/mali_symlink.so|9d42468ca6bcc2744ce65424d30a4ae529b403ddc2aa19680aa9ee8c73234ece|ELF64|u:object_r:vendor_file:s0"
)

_T2S_MALI_R38_VERIFY_SOURCE()
{
    local SOURCE="$1"
    local ENTRY REL EXPECTED CLASS LABEL

    for ENTRY in "${MALI_R38_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        _T2S_MALI_R38_FILE_MATCHES "$SOURCE/$REL" "$EXPECTED" || return 1
    done
}

_T2S_MALI_R38_FETCH()
{
    local ENTRY REL EXPECTED CLASS LABEL OUTPUT TEMP

    for ENTRY in "${MALI_R38_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        OUTPUT="$MALI_R38_CACHE_DIR/$REL"
        TEMP="$OUTPUT.download"
        _T2S_MALI_R38_FILE_MATCHES "$OUTPUT" "$EXPECTED" && continue

        LOG "- Downloading $REL from the pinned Galaxy A54 r38p1 donor"
        mkdir -p "$(dirname "$OUTPUT")"
        rm -f "$TEMP"
        DOWNLOAD_FILE "$MALI_R38_BASE_URL/$REL" "$TEMP" || \
            ABORT "Failed to download Mali r38p1 donor file: $REL"
        _T2S_MALI_R38_FILE_MATCHES "$TEMP" "$EXPECTED" || {
            rm -f "$TEMP"
            ABORT "Mali r38p1 donor checksum mismatch: $REL"
        }
        mv -f "$TEMP" "$OUTPUT"
    done
}

_T2S_MALI_R38_VERIFY_ABI()
{
    local ABI_DIR="$TMP_DIR/t2s-mali-r38p1-abi"
    local LIBDIR CLASS TARGET_UMD DONOR_UMD VULKAN SHIM DEP

    case "$ABI_DIR" in
        "$TMP_DIR"/t2s-mali-r38p1-abi) rm -rf "$ABI_DIR" ;;
        *) ABORT "Refusing to clean unexpected Mali ABI path: $ABI_DIR" ;;
    esac
    mkdir -p "$ABI_DIR"

    for LIBDIR in lib lib64; do
        [ "$LIBDIR" = "lib" ] && CLASS="ELF32" || CLASS="ELF64"
        TARGET_UMD="$WORK_DIR/vendor/$LIBDIR/egl/libGLES_mali.so"
        DONOR_UMD="$MALI_R38_SOURCE_DIR/vendor/$LIBDIR/egl/libGLES_mali.so"
        VULKAN="$MALI_R38_SOURCE_DIR/vendor/$LIBDIR/hw/vulkan.mali.so"
        SHIM="$MALI_R38_SOURCE_DIR/vendor/$LIBDIR/mali_symlink.so"

        [ -f "$TARGET_UMD" ] || ABORT "Target Mali UMD is missing: $TARGET_UMD"
        readelf -h "$DONOR_UMD" | grep "Class:.*$CLASS" >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR UMD has the wrong ELF class"
        strings "$DONOR_UMD" | grep -F 'U:r38p1-01eac0' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR UMD has the wrong release"
        strings "$DONOR_UMD" | grep -F 'Mali-G78' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR UMD does not advertise Mali-G78 support"
        readelf --dyn-syms --wide "$DONOR_UMD" | grep ' eglGetDisplay$' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR UMD lacks EGL exports"
        readelf --dyn-syms --wide "$DONOR_UMD" | grep ' glGetString$' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR UMD lacks GLES exports"

        cat > "$ABI_DIR/$LIBDIR.expected.needed" <<'EOF'
android.hardware.graphics.mapper@4.0.so
libbase.so
libc++.so
libc.so
libcutils.so
libdl.so
libgralloctypes.so
libhardware.so
libhidlbase.so
libion_exynos.so
liblog.so
libm.so
libnativewindow.so
libutils.so
libz.so
EOF
        readelf -d "$DONOR_UMD" |
            sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' |
            LC_ALL=C sort -u > "$ABI_DIR/$LIBDIR.donor.needed"
        cmp -s "$ABI_DIR/$LIBDIR.expected.needed" "$ABI_DIR/$LIBDIR.donor.needed" || \
            ABORT "Mali r38p1 $LIBDIR UMD changed the pinned Exynos dependency ABI"

        readelf -h "$VULKAN" | grep "Class:.*$CLASS" >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR Vulkan shim has the wrong ELF class"
        readelf -d "$VULKAN" | grep -F '[libGLES_mali.so]' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR Vulkan shim is not paired with libGLES_mali"
        readelf -d "$VULKAN" | grep -F 'Library runpath: [$ORIGIN/../egl]' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR Vulkan shim has an unexpected runpath"
        readelf -h "$SHIM" | grep "Class:.*$CLASS" >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR compatibility shim has the wrong ELF class"
        readelf -d "$SHIM" | grep -F 'Library soname: [mali_symlink.so]' >/dev/null || \
            ABORT "Mali r38p1 $LIBDIR compatibility shim has the wrong SONAME"

        while IFS= read -r DEP; do
            case "$DEP" in
                libc.so|libm.so|libdl.so) ;;
                *)
                    if [ ! -e "$WORK_DIR/vendor/$LIBDIR/$DEP" ] && \
                            [ ! -L "$WORK_DIR/vendor/$LIBDIR/$DEP" ] && \
                            [ ! -e "$WORK_DIR/system/system/$LIBDIR/$DEP" ] && \
                            [ ! -L "$WORK_DIR/system/system/$LIBDIR/$DEP" ]; then
                        ABORT "Target runtime lacks Mali r38p1 $LIBDIR dependency: $DEP"
                    fi
                    ;;
            esac
        done < "$ABI_DIR/$LIBDIR.donor.needed"
    done

    rm -rf "$ABI_DIR"
}

_T2S_MALI_R38_VERIFY_INSTALLED()
{
    local ENTRY REL EXPECTED CLASS LABEL CONTEXT_PATH

    for ENTRY in "${MALI_R38_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        _T2S_MALI_R38_FILE_MATCHES "$WORK_DIR/$REL" "$EXPECTED" || \
            ABORT "Installed Mali r38p1 file differs from its pinned source: $REL"
        grep -qxF "$REL 0 0 644 capabilities=0x0" \
            "$WORK_DIR/configs/fs_config-vendor" || \
            ABORT "Installed $REL has incorrect filesystem metadata"
        CONTEXT_PATH="/${REL//./\\.} $LABEL"
        grep -qxF "$CONTEXT_PATH" "$WORK_DIR/configs/file_context-vendor" || \
            ABORT "Installed $REL has an incorrect SELinux label"
    done
}

LOG_STEP_IN "- Verifying Mali r38p1 kernel/userspace pairing"
_T2S_MALI_R38_VERIFY_KERNEL_PAIRING
LOG "- KMD: r38p1-01eac0, Job Manager UK ABI 11.35"
LOG_STEP_OUT

LOG_STEP_IN "- Preparing Android 13 Mali r38p1 userspace"
if [ -n "${T2S_MALI_R38P1_DONOR_DIR:-}" ]; then
    MALI_R38_SOURCE_DIR="$T2S_MALI_R38P1_DONOR_DIR"
elif [ -d "$MALI_R38_LOCAL_DONOR_DIR/.git" ] && \
        [ "$(git -C "$MALI_R38_LOCAL_DONOR_DIR" rev-parse HEAD 2>/dev/null)" = \
            "$MALI_R38_COMMIT" ] && \
        _T2S_MALI_R38_VERIFY_SOURCE "$MALI_R38_LOCAL_DONOR_DIR"; then
    MALI_R38_SOURCE_DIR="$MALI_R38_LOCAL_DONOR_DIR"
else
    _T2S_MALI_R38_FETCH
    MALI_R38_SOURCE_DIR="$MALI_R38_CACHE_DIR"
fi
_T2S_MALI_R38_VERIFY_SOURCE "$MALI_R38_SOURCE_DIR" || \
    ABORT "Mali r38p1 donor is incomplete or does not match pinned checksums"
LOG "- UMD donor: $MALI_R38_REPOSITORY@$MALI_R38_COMMIT"
LOG_STEP_OUT

LOG_STEP_IN "- Validating Mali r38p1 G78 userspace ABI"
_T2S_MALI_R38_VERIFY_ABI
LOG "- Replacing the Android 11 r38p0 UMD with the Android 13 r38p1 UMD"
LOG_STEP_OUT

MALI_R38_BOOT_HASH_BEFORE="$(sha256sum "$MALI_R38_BOOT_IMAGE" | cut -d ' ' -f 1)"
MALI_R38_VENDOR_BOOT_HASH_BEFORE="$(
    sha256sum "$MALI_R38_VENDOR_BOOT_IMAGE" | cut -d ' ' -f 1
)"

LOG_STEP_IN "- Installing matched Mali r38p1 userspace"
for ENTRY in "${MALI_R38_FILES[@]}"; do
    IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
    ADD_TO_WORK_DIR "$MALI_R38_SOURCE_DIR" \
        "vendor" "${REL#vendor/}" 0 0 644 "$LABEL"
    SET_METADATA "vendor" "${REL#vendor/}" 0 0 644 "$LABEL"
done
LOG_STEP_OUT

LOG_STEP_IN "- Verifying installed Mali r38p1 userspace"
_T2S_MALI_R38_VERIFY_INSTALLED
MALI_R38_BOOT_HASH_AFTER="$(sha256sum "$MALI_R38_BOOT_IMAGE" | cut -d ' ' -f 1)"
MALI_R38_VENDOR_BOOT_HASH_AFTER="$(
    sha256sum "$MALI_R38_VENDOR_BOOT_IMAGE" | cut -d ' ' -f 1
)"
[ "$MALI_R38_BOOT_HASH_AFTER" = "$MALI_R38_BOOT_HASH_BEFORE" ] || \
    ABORT "Mali userspace module unexpectedly changed boot.img"
[ "$MALI_R38_VENDOR_BOOT_HASH_AFTER" = "$MALI_R38_VENDOR_BOOT_HASH_BEFORE" ] || \
    ABORT "Mali userspace module unexpectedly changed vendor_boot.img"
LOG "- Kernel images are byte-for-byte unchanged"
LOG_STEP_OUT

unset T2S_MALI_R38P1_DONOR_DIR
unset MALI_R38_KERNEL_MANIFEST MALI_R38_BOOT_IMAGE MALI_R38_VENDOR_BOOT_IMAGE
unset MALI_R38_REPOSITORY MALI_R38_COMMIT MALI_R38_BASE_URL
unset MALI_R38_CACHE_DIR MALI_R38_LOCAL_DONOR_DIR MALI_R38_SOURCE_DIR
unset MALI_R38_FILES
unset MALI_R38_BOOT_HASH_BEFORE MALI_R38_VENDOR_BOOT_HASH_BEFORE
unset MALI_R38_BOOT_HASH_AFTER MALI_R38_VENDOR_BOOT_HASH_AFTER
unset ENTRY REL EXPECTED CLASS LABEL TOOL
unset -f _T2S_MALI_R38_FILE_MATCHES _T2S_MALI_R38_MANIFEST_VALUE
unset -f _T2S_MALI_R38_VERIFY_KERNEL_PAIRING
unset -f _T2S_MALI_R38_VERIFY_SOURCE _T2S_MALI_R38_FETCH
unset -f _T2S_MALI_R38_VERIFY_ABI _T2S_MALI_R38_VERIFY_INSTALLED
