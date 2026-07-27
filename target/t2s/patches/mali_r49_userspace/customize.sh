# shellcheck disable=SC2016,SC2034
SKIPUNZIP=1

if [ "${T2S_ENABLE_EXPERIMENTAL_MALI_R49:-0}" != "1" ]; then
    LOGW "Mali r49p0 userspace is disabled because its UK ABI does not match r38p1"
    LOG "- Keeping the Android 13 r38p1 userspace paired with Floppy's r38p1 KMD"
    return 0
fi

# This module deliberately swaps only vendor userspace. Hashing both packaged
# kernel images makes that boundary enforceable instead of relying on convention.
MALI_R49_BOOT_IMAGE="$WORK_DIR/kernel/boot.img"
MALI_R49_VENDOR_BOOT_IMAGE="$WORK_DIR/kernel/vendor_boot.img"
[ -f "$MALI_R49_BOOT_IMAGE" ] || ABORT "Installed boot.img is missing"
[ -f "$MALI_R49_VENDOR_BOOT_IMAGE" ] || ABORT "Installed vendor_boot.img is missing"
MALI_R49_BOOT_HASH_BEFORE="$(sha256sum "$MALI_R49_BOOT_IMAGE" | cut -d ' ' -f 1)"
MALI_R49_VENDOR_BOOT_HASH_BEFORE="$(
    sha256sum "$MALI_R49_VENDOR_BOOT_IMAGE" | cut -d ' ' -f 1
)"

for TOOL in curl cut debugfs grep patchelf readelf sed sha256sum stat strings; do
    command -v "$TOOL" >/dev/null ||
        ABORT "Required Mali r49 userspace tool is missing: $TOOL"
done

_T2S_MALI_FILE_MATCHES()
{
    local FILE="$1"
    local EXPECTED="$2"

    [ -f "$FILE" ] && [ "$(sha256sum "$FILE" | cut -d ' ' -f 1)" = "$EXPECTED" ]
}

# Pixel 6 Android 15 QPR1 Beta 1 is the last official G78/Job Manager image
# carrying the exact r49p0 userspace release. Extract only vendor.img from the
# immutable factory ZIP, then pin every installed file by digest.
MALI_R49_FACTORY_URL="https://dl.google.com/developers/android/vic/images/factory/oriole_beta-ap41.240726.009-factory-05406aad.zip"
MALI_R49_FACTORY_VENDOR_RANGE="594610965-858370220"
MALI_R49_FACTORY_VENDOR_COMPRESSED_SIZE="263759256"
MALI_R49_FACTORY_VENDOR_SIZE="595206144"
MALI_R49_FACTORY_VENDOR_SHA256="4f1269dd6921bc8e3cbda24a223cefa755d7167a0d728411e328e1e69b3eebe5"
MALI_R49_CACHE_DIR="$SRC_DIR/out/gpu-cache/oriole-ap41.240726.009-r49p0"
MALI_R49_LOCAL_DONOR_DIR="$SRC_DIR/out/gpu-donors/pixel-oriole-r49p0-ap41"
MALI_R49_PRIVATE_CACHE_DIR="$SRC_DIR/out/gpu-cache/oriole-ap41.240726.009-r49p0-private"

# relative destination|sha256|SELinux label
MALI_R49_DRIVER_FILES=(
    "vendor/lib/egl/libGLES_mali.so|0875f4194d1bb04f612b5c41afd77b7faa0ba3a92853b95b2d927266a4f73a97|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/egl/libGLES_mali.so|650814353861e1916981034f65dc3fed39eba8e846d8404f8946aafa44d8ad0b|u:object_r:same_process_hal_file:s0"
    "vendor/lib/hw/vulkan.mali.so|37cdd47abeb440fb6431f2bb6edcf497f08820844f11590ee54c08d97bec0ecb|u:object_r:vendor_file:s0"
    "vendor/lib64/hw/vulkan.mali.so|1f53d8bc7fe7eff0ebf4c005d2938c97cddeebc874a54cdc0d31f162bef1e155|u:object_r:vendor_file:s0"
)

# relative destination|sha256|ELF class|SELinux label
MALI_R49_RUNTIME_FILES=(
    "vendor/lib/android.hardware.common-V2-ndk.so|5e2ba5b94f88c0d605c48f1285b00a8b9153479c6586dedef10ba98837a9f5a7|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/android.hardware.graphics.allocator-V2-ndk.so|f1522a3bc820966e1552e0aad5ba44776b627c4a8ef2513e913e53db75f7faf3|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/android.hardware.graphics.common-V5-ndk.so|bb8d455fbbfe50118d5277702d097ded7e1160be9911e3f96bd0026ba3983318|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/libdmabufheap.so|f52ce6cededbed04d68a5aa2683805bb6ab7a1e4a9a77bdba6ca5c7d75f2e124|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/libdrm.so|27f1f456344a4366967123384c5a2b7ac44115aef6b655da34e87f3a6cd2babf|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/android.hardware.common-V2-ndk.so|49522b6082eb8a6e46a03d0f061e6ccc88a0a3ab4399ecbb4b5768448da41585|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/android.hardware.graphics.allocator-V2-ndk.so|ebb6121276aea9830ced81878a60d4cde37886d26f39239cf93a807ec7b44204|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/android.hardware.graphics.common-V5-ndk.so|021114549e807febccb38eba361164e806284f19ca2f5f07c54afb763f20c886|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libdmabufheap.so|f78818076768143ce5d1ecc5e50ee0f2c8650d22be957719d8e3a1f3af0a7783|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libdrm.so|234e1f719354f75ab89addaa47a123e9bf63c375df065882fe85bd1ba215f356|ELF64|u:object_r:same_process_hal_file:s0"
)

# Patchelf output is deterministic. These hashes pin the isolated closure that
# is actually installed, not only the untouched Pixel donor inputs.
MALI_R49_PRIVATE_DRIVER_FILES=(
    "vendor/lib/egl/libGLES_mali.so|843c8f1c4cdd5deaf96df91fba22cf53664cf29b0dcad3c0e4a1b7cccfcdcd4a|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/egl/libGLES_mali.so|df642a18f6685267fd4525a648e3593b6c28ab1d02b455be39016ec3e03ae5f1|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib/hw/vulkan.mali.so|37cdd47abeb440fb6431f2bb6edcf497f08820844f11590ee54c08d97bec0ecb|ELF32|u:object_r:vendor_file:s0"
    "vendor/lib64/hw/vulkan.mali.so|1f53d8bc7fe7eff0ebf4c005d2938c97cddeebc874a54cdc0d31f162bef1e155|ELF64|u:object_r:vendor_file:s0"
)

MALI_R49_PRIVATE_RUNTIME_FILES=(
    "vendor/lib/libmali_r49_common_ndk.so|3b4979abe23dda47eb10eb5ce7c5602efe144f40727d041e5e6da0e2985209be|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/libmali_r49_allocator_ndk.so|7b9e026d2013e1a9de9e8c733f7a01b36dfc8d75b32fe6c53dc8e03fc71a27a3|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/libmali_r49_graphics_common_ndk.so|b934aa65488b3644fdc968bc1b057cac0761764699b4a6adee67c0630a287ac6|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/libmali_r49_dmabufheap.so|078f92e285bf437a8b04646ba8b01a37fd1cf377d60c5d8628de84aeedb8d303|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib/libmali_r49_drm.so|923400e21903710e67f18f797dcb86fbef74b55111f18a603364006a14b2e7f5|ELF32|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libmali_r49_common_ndk.so|651c08fa189bf65e0e23dd6a0c6dc39a9350c3d95178a270c92a6b353cacd103|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libmali_r49_allocator_ndk.so|f11b6cdc9385193e575126df76a2777ac6b1422e9ef215908f340c3f96d16696|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libmali_r49_graphics_common_ndk.so|e473831702647b0e08e5bac8b148fead14dcbbe6510a8227366851b39bcb25e8|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libmali_r49_dmabufheap.so|2a4c2ac5597a3eb084122f2f56f6cd7af2e9d7274fa13578659ce7a068fefc4c|ELF64|u:object_r:same_process_hal_file:s0"
    "vendor/lib64/libmali_r49_drm.so|76ad853df016c78e7f84347eb0a2d965fbd63ae72b20cd762ac10f0c1ca3a627|ELF64|u:object_r:same_process_hal_file:s0"
)

_T2S_MALI_VERIFY_R49_SOURCE()
{
    local SOURCE="$1"
    local ENTRY REL EXPECTED CLASS LABEL

    for ENTRY in "${MALI_R49_DRIVER_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED LABEL <<< "$ENTRY"
        _T2S_MALI_FILE_MATCHES "$SOURCE/$REL" "$EXPECTED" || return 1
    done
    for ENTRY in "${MALI_R49_RUNTIME_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        _T2S_MALI_FILE_MATCHES "$SOURCE/$REL" "$EXPECTED" || return 1
    done
}

_T2S_MALI_FETCH_R49()
{
    local PAYLOAD="$MALI_R49_CACHE_DIR/vendor.img.deflate.download"
    local IMAGE="$MALI_R49_CACHE_DIR/vendor.img.download"
    local ENTRY REL EXPECTED CLASS LABEL OUTPUT TEMP TOOL

    _T2S_MALI_VERIFY_R49_SOURCE "$MALI_R49_CACHE_DIR" && return 0

    for TOOL in curl debugfs python3 stat; do
        command -v "$TOOL" >/dev/null || \
            ABORT "Required Pixel r49 factory extraction tool is missing: $TOOL"
    done

    mkdir -p "$MALI_R49_CACHE_DIR"
    rm -f "$PAYLOAD" "$IMAGE"
    LOG "- Range-downloading Pixel 6 AP41.240726.009 vendor.img"
    if ! curl --fail --location --retry 3 --retry-delay 2 \
            --max-filesize "$MALI_R49_FACTORY_VENDOR_COMPRESSED_SIZE" \
            --range "$MALI_R49_FACTORY_VENDOR_RANGE" \
            --output "$PAYLOAD" "$MALI_R49_FACTORY_URL"; then
        rm -f "$PAYLOAD" "$IMAGE"
        ABORT "Failed to download the pinned Pixel r49 vendor.img range"
    fi
    if [ "$(stat -c '%s' "$PAYLOAD")" != "$MALI_R49_FACTORY_VENDOR_COMPRESSED_SIZE" ]; then
        rm -f "$PAYLOAD" "$IMAGE"
        ABORT "Pixel r49 vendor.img compressed range has an unexpected size"
    fi

    LOG "- Inflating and verifying the pinned Pixel r49 vendor.img"
    if python3 - "$PAYLOAD" "$IMAGE" <<'PY'
import sys
import zlib

source, target = sys.argv[1:]
decoder = zlib.decompressobj(-zlib.MAX_WBITS)
with open(source, "rb") as src, open(target, "wb") as dst:
    while chunk := src.read(8 * 1024 * 1024):
        dst.write(decoder.decompress(chunk))
    dst.write(decoder.flush())
if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
    raise SystemExit("incomplete or trailing raw DEFLATE stream")
PY
    then
        :
    else
        rm -f "$PAYLOAD" "$IMAGE"
        ABORT "Failed to inflate the pinned Pixel r49 vendor.img"
    fi
    rm -f "$PAYLOAD"
    if [ "$(stat -c '%s' "$IMAGE")" != "$MALI_R49_FACTORY_VENDOR_SIZE" ] || \
            ! _T2S_MALI_FILE_MATCHES "$IMAGE" "$MALI_R49_FACTORY_VENDOR_SHA256"; then
        rm -f "$IMAGE"
        ABORT "Pixel r49 vendor.img checksum or size mismatch"
    fi

    for ENTRY in "${MALI_R49_DRIVER_FILES[@]}" "${MALI_R49_RUNTIME_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        OUTPUT="$MALI_R49_CACHE_DIR/$REL"
        TEMP="$OUTPUT.download"
        mkdir -p "$(dirname "$OUTPUT")"
        rm -f "$TEMP"
        if ! debugfs -R "dump /${REL#vendor/} $TEMP" "$IMAGE" >/dev/null 2>&1; then
            rm -f "$TEMP" "$IMAGE"
            ABORT "Failed to extract $REL from the pinned Pixel r49 vendor.img"
        fi
        _T2S_MALI_FILE_MATCHES "$TEMP" "$EXPECTED" || {
            rm -f "$TEMP" "$IMAGE"
            ABORT "Pixel r49 factory checksum mismatch: $REL"
        }
        mv -f "$TEMP" "$OUTPUT"
    done
    rm -f "$IMAGE"

    _T2S_MALI_VERIFY_R49_SOURCE "$MALI_R49_CACHE_DIR" || \
        ABORT "Extracted Pixel r49 userspace failed checksum validation"
}

_T2S_MALI_VERIFY_R49_PRIVATE_SOURCE()
{
    local SOURCE="$1"
    local ENTRY REL EXPECTED CLASS LABEL

    for ENTRY in \
            "${MALI_R49_PRIVATE_DRIVER_FILES[@]}" \
            "${MALI_R49_PRIVATE_RUNTIME_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        _T2S_MALI_FILE_MATCHES "$SOURCE/$REL" "$EXPECTED" || return 1
    done
}

_T2S_MALI_BUILD_R49_PRIVATE_CLOSURE()
{
    local TEMP="${MALI_R49_PRIVATE_CACHE_DIR}.tmp"
    local LIBDIR SOURCE_DIR OUTPUT_DIR

    _T2S_MALI_VERIFY_R49_PRIVATE_SOURCE "$MALI_R49_PRIVATE_CACHE_DIR" &&
        return 0

    case "$TEMP" in
        "$SRC_DIR"/out/gpu-cache/*) rm -rf "$TEMP" ;;
        *) ABORT "Refusing to clean unexpected Mali cache path: $TEMP" ;;
    esac
    mkdir -p "$TEMP"

    for LIBDIR in lib lib64; do
        SOURCE_DIR="$MALI_R49_SOURCE_DIR/vendor/$LIBDIR"
        OUTPUT_DIR="$TEMP/vendor/$LIBDIR"
        mkdir -p "$OUTPUT_DIR/egl" "$OUTPUT_DIR/hw"

        cp -a "$SOURCE_DIR/egl/libGLES_mali.so" \
            "$OUTPUT_DIR/egl/libGLES_mali.so"
        cp -a "$SOURCE_DIR/hw/vulkan.mali.so" \
            "$OUTPUT_DIR/hw/vulkan.mali.so"
        cp -a "$SOURCE_DIR/android.hardware.common-V2-ndk.so" \
            "$OUTPUT_DIR/libmali_r49_common_ndk.so"
        cp -a "$SOURCE_DIR/android.hardware.graphics.allocator-V2-ndk.so" \
            "$OUTPUT_DIR/libmali_r49_allocator_ndk.so"
        cp -a "$SOURCE_DIR/android.hardware.graphics.common-V5-ndk.so" \
            "$OUTPUT_DIR/libmali_r49_graphics_common_ndk.so"
        cp -a "$SOURCE_DIR/libdmabufheap.so" \
            "$OUTPUT_DIR/libmali_r49_dmabufheap.so"
        cp -a "$SOURCE_DIR/libdrm.so" \
            "$OUTPUT_DIR/libmali_r49_drm.so"

        patchelf \
            --replace-needed android.hardware.graphics.allocator-V2-ndk.so \
                libmali_r49_allocator_ndk.so \
            --replace-needed android.hardware.graphics.common-V5-ndk.so \
                libmali_r49_graphics_common_ndk.so \
            --replace-needed libdmabufheap.so libmali_r49_dmabufheap.so \
            --replace-needed libdrm.so libmali_r49_drm.so \
            "$OUTPUT_DIR/egl/libGLES_mali.so"

        patchelf \
            --set-soname libmali_r49_allocator_ndk.so \
            --replace-needed android.hardware.graphics.common-V5-ndk.so \
                libmali_r49_graphics_common_ndk.so \
            "$OUTPUT_DIR/libmali_r49_allocator_ndk.so"
        patchelf \
            --set-soname libmali_r49_graphics_common_ndk.so \
            --replace-needed android.hardware.common-V2-ndk.so \
                libmali_r49_common_ndk.so \
            "$OUTPUT_DIR/libmali_r49_graphics_common_ndk.so"
        patchelf --set-soname libmali_r49_common_ndk.so \
            "$OUTPUT_DIR/libmali_r49_common_ndk.so"
        patchelf --set-soname libmali_r49_dmabufheap.so \
            "$OUTPUT_DIR/libmali_r49_dmabufheap.so"
        patchelf --set-soname libmali_r49_drm.so \
            "$OUTPUT_DIR/libmali_r49_drm.so"
    done

    _T2S_MALI_VERIFY_R49_PRIVATE_SOURCE "$TEMP" ||
        ABORT "Generated Mali r49 private closure differs from pinned output"

    case "$MALI_R49_PRIVATE_CACHE_DIR" in
        "$SRC_DIR"/out/gpu-cache/*) rm -rf "$MALI_R49_PRIVATE_CACHE_DIR" ;;
        *) ABORT "Refusing to replace unexpected Mali cache path" ;;
    esac
    mv "$TEMP" "$MALI_R49_PRIVATE_CACHE_DIR"
}

_T2S_MALI_VERIFY_R49_ABI()
{
    local LIBDIR UMD VULKAN CLASS DEP FILE SONAME

    if ! grep -qF '<name>android.hardware.graphics.allocator</name>' \
            "$WORK_DIR/vendor/etc/vintf/manifest.xml" || \
            ! grep -qF '@4.0::IAllocator/default' \
            "$WORK_DIR/vendor/etc/vintf/manifest.xml"; then
        ABORT "Target HIDL graphics allocator 4.0 service is not declared"
    fi

    for LIBDIR in lib lib64; do
        UMD="$MALI_R49_PRIVATE_CACHE_DIR/vendor/$LIBDIR/egl/libGLES_mali.so"
        VULKAN="$MALI_R49_PRIVATE_CACHE_DIR/vendor/$LIBDIR/hw/vulkan.mali.so"
        [ "$LIBDIR" = "lib" ] && CLASS="ELF32" || CLASS="ELF64"

        readelf -h "$UMD" | grep "Class:.*$CLASS" >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD has the wrong ELF class"
        strings "$UMD" | grep -F 'r49p0-00eac0' >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD has the wrong release"
        strings "$UMD" | grep -F 'Mali-G78' >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD does not advertise Mali-G78 support"
        for DEP in \
            libmali_r49_allocator_ndk.so \
            libmali_r49_graphics_common_ndk.so \
            libmali_r49_drm.so libmali_r49_dmabufheap.so \
            libvndksupport.so; do
            readelf -d "$UMD" | grep -F "[$DEP]" >/dev/null || \
                ABORT "Mali r49 $LIBDIR UMD lacks dependency: $DEP"
        done
        for DEP in \
            android.hardware.graphics.allocator-V2-ndk.so \
            android.hardware.graphics.common-V5-ndk.so \
            libdrm.so libdmabufheap.so; do
            if readelf -d "$UMD" | grep -F "[$DEP]" >/dev/null; then
                ABORT "Mali r49 $LIBDIR UMD still overrides global dependency: $DEP"
            fi
        done
        readelf --dyn-syms --wide "$UMD" | grep ' AServiceManager_checkService@' >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD lacks the optional AIDL allocator probe"
        readelf --dyn-syms --wide "$UMD" | grep 'IMapper10getService' >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD lacks the HIDL Mapper 4 fallback"
        readelf --dyn-syms --wide "$UMD" | grep ' eglGetDisplay$' >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD lacks EGL exports"
        readelf --dyn-syms --wide "$UMD" | grep ' glGetString$' >/dev/null || \
            ABORT "Mali r49 $LIBDIR UMD lacks GLES exports"

        readelf -h "$VULKAN" | grep "Class:.*$CLASS" >/dev/null || \
            ABORT "Mali r49 $LIBDIR Vulkan shim has the wrong ELF class"
        readelf -d "$VULKAN" | grep -F '[libGLES_mali.so]' >/dev/null || \
            ABORT "Mali r49 $LIBDIR Vulkan shim is not paired with libGLES_mali"
        readelf -d "$VULKAN" | grep -F 'Library runpath: [$ORIGIN/../egl]' >/dev/null || \
            ABORT "Mali r49 $LIBDIR Vulkan shim has an unexpected runpath"

        for FILE in \
            libmali_r49_common_ndk.so \
            libmali_r49_allocator_ndk.so \
            libmali_r49_graphics_common_ndk.so \
            libmali_r49_dmabufheap.so libmali_r49_drm.so; do
            readelf -h "$MALI_R49_PRIVATE_CACHE_DIR/vendor/$LIBDIR/$FILE" | \
                grep "Class:.*$CLASS" >/dev/null || \
                ABORT "Private Mali r49 $LIBDIR/$FILE has the wrong ELF class"
            SONAME="$(readelf -d \
                "$MALI_R49_PRIVATE_CACHE_DIR/vendor/$LIBDIR/$FILE" | \
                sed -n 's/.*Library soname: \[\(.*\)\]/\1/p')"
            [ "$SONAME" = "$FILE" ] || \
                ABORT "Private Mali r49 $LIBDIR/$FILE has the wrong SONAME"
        done

        for DEP in \
            libbinder_ndk.so libnativewindow.so libutils.so \
            android.hardware.graphics.mapper@4.0.so liblog.so \
            libgralloctypes.so libhidlbase.so libvndksupport.so \
            libcutils.so libhardware.so libbase.so libz.so \
            libc++.so libc.so libm.so libdl.so; do
            if [ ! -e "$WORK_DIR/vendor/$LIBDIR/$DEP" ] && \
                    [ ! -L "$WORK_DIR/vendor/$LIBDIR/$DEP" ] && \
                    [ ! -e "$WORK_DIR/system/system/$LIBDIR/$DEP" ] && \
                    [ ! -L "$WORK_DIR/system/system/$LIBDIR/$DEP" ]; then
                ABORT "Target $LIBDIR runtime lacks Mali r49 dependency: $DEP"
            fi
        done

        readelf -d \
            "$MALI_R49_PRIVATE_CACHE_DIR/vendor/$LIBDIR/libmali_r49_allocator_ndk.so" | \
            grep -F '[libmali_r49_graphics_common_ndk.so]' >/dev/null || \
            ABORT "Private Mali r49 $LIBDIR allocator closure is incomplete"
        readelf -d \
            "$MALI_R49_PRIVATE_CACHE_DIR/vendor/$LIBDIR/libmali_r49_graphics_common_ndk.so" | \
            grep -F '[libmali_r49_common_ndk.so]' >/dev/null || \
            ABORT "Private Mali r49 $LIBDIR graphics-common closure is incomplete"
    done
}

_T2S_MALI_VERIFY_R49_INSTALLED_CLOSURE()
{
    local LIBDIR FILE DEP ENTRY REL EXPECTED CLASS LABEL CONTEXT_PATH
    local -a FILES

    for ENTRY in "${MALI_R49_PRIVATE_DRIVER_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        _T2S_MALI_FILE_MATCHES "$WORK_DIR/$REL" "$EXPECTED" || \
            ABORT "Installed Mali r49 driver differs from pinned output: $REL"
        grep -qxF "$REL 0 0 644 capabilities=0x0" \
            "$WORK_DIR/configs/fs_config-vendor" || \
            ABORT "Installed $REL has incorrect filesystem metadata"
        CONTEXT_PATH="/${REL//./\\.} $LABEL"
        grep -qxF "$CONTEXT_PATH" "$WORK_DIR/configs/file_context-vendor" || \
            ABORT "Installed $REL has the wrong SELinux label"
    done
    for ENTRY in "${MALI_R49_PRIVATE_RUNTIME_FILES[@]}"; do
        IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
        _T2S_MALI_FILE_MATCHES "$WORK_DIR/$REL" "$EXPECTED" || \
            ABORT "Installed private r49 runtime differs from pinned output: $REL"
        grep -qxF "$REL 0 0 644 capabilities=0x0" \
            "$WORK_DIR/configs/fs_config-vendor" || \
            ABORT "Installed $REL has incorrect filesystem metadata"
        CONTEXT_PATH="/${REL//./\\.} $LABEL"
        grep -qxF "$CONTEXT_PATH" "$WORK_DIR/configs/file_context-vendor" || \
            ABORT "Installed $REL is not labeled as an SP-HAL library"
    done

    for LIBDIR in lib lib64; do
        FILES=(
            "$WORK_DIR/vendor/$LIBDIR/egl/libGLES_mali.so"
            "$WORK_DIR/vendor/$LIBDIR/hw/vulkan.mali.so"
            "$WORK_DIR/vendor/$LIBDIR/libmali_r49_common_ndk.so"
            "$WORK_DIR/vendor/$LIBDIR/libmali_r49_allocator_ndk.so"
            "$WORK_DIR/vendor/$LIBDIR/libmali_r49_graphics_common_ndk.so"
            "$WORK_DIR/vendor/$LIBDIR/libmali_r49_dmabufheap.so"
            "$WORK_DIR/vendor/$LIBDIR/libmali_r49_drm.so"
        )
        for FILE in "${FILES[@]}"; do
            [ -f "$FILE" ] || \
                ABORT "Installed Mali r49 closure file is missing: ${FILE//$WORK_DIR\//}"
            while IFS= read -r DEP; do
                case "$DEP" in
                    libGLES_mali.so)
                        [ -f "$WORK_DIR/vendor/$LIBDIR/egl/$DEP" ] || \
                            ABORT "Mali r49 $LIBDIR Vulkan dependency is unresolved: $DEP"
                        ;;
                    libmali_r49_drm.so|libmali_r49_dmabufheap.so|\
                    libmali_r49_common_ndk.so|libmali_r49_allocator_ndk.so|\
                    libmali_r49_graphics_common_ndk.so)
                        [ -f "$WORK_DIR/vendor/$LIBDIR/$DEP" ] || \
                            ABORT "Private Mali r49 $LIBDIR dependency is unresolved: $DEP"
                        ;;
                    *)
                        if [ ! -e "$WORK_DIR/vendor/$LIBDIR/$DEP" ] && \
                                [ ! -L "$WORK_DIR/vendor/$LIBDIR/$DEP" ] && \
                                [ ! -e "$WORK_DIR/system/system/$LIBDIR/$DEP" ] && \
                                [ ! -L "$WORK_DIR/system/system/$LIBDIR/$DEP" ]; then
                            ABORT "Mali r49 $LIBDIR dependency is unresolved: $DEP"
                        fi
                        ;;
                esac
            done < <(readelf -d "$FILE" | \
                sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | LC_ALL=C sort -u)
        done
    done
}

LOG_STEP_IN "- Preparing Pixel 6 Mali r49p0 userspace-only backport"
if [ -n "${T2S_MALI_R49P0_DONOR_DIR:-}" ]; then
    MALI_R49_SOURCE_DIR="$T2S_MALI_R49P0_DONOR_DIR"
elif [ -d "$MALI_R49_LOCAL_DONOR_DIR" ] && \
        _T2S_MALI_VERIFY_R49_SOURCE "$MALI_R49_LOCAL_DONOR_DIR"; then
    MALI_R49_SOURCE_DIR="$MALI_R49_LOCAL_DONOR_DIR"
else
    _T2S_MALI_FETCH_R49
    MALI_R49_SOURCE_DIR="$MALI_R49_CACHE_DIR"
fi
_T2S_MALI_VERIFY_R49_SOURCE "$MALI_R49_SOURCE_DIR" || \
    ABORT "Mali r49 donor is incomplete or does not match pinned checksums"
LOG "- UMD donor: Pixel 6 AP41.240726.009 factory vendor image"
LOG "- Generating isolated libmali_r49 dependency closure"
_T2S_MALI_BUILD_R49_PRIVATE_CLOSURE
LOGW "Mali r49p0 UMD is experimental with the unchanged r38p1 kernel driver"
LOG_STEP_OUT

LOG_STEP_IN "- Validating Mali r49p0 G78/HIDL/SP-HAL compatibility"
_T2S_MALI_VERIFY_R49_ABI
LOG "- Target HIDL Mapper 4 fallback is present"
LOG "- One UI 9 global graphics libraries remain untouched"
LOG_STEP_OUT

LOG_STEP_IN "- Installing Mali r49p0 userspace with its private runtime closure"
for ENTRY in "${MALI_R49_PRIVATE_RUNTIME_FILES[@]}"; do
    IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
    ADD_TO_WORK_DIR "$MALI_R49_PRIVATE_CACHE_DIR" \
        "vendor" "${REL#vendor/}" 0 0 644 "$LABEL"
    SET_METADATA "vendor" "${REL#vendor/}" 0 0 644 "$LABEL"
done
for ENTRY in "${MALI_R49_PRIVATE_DRIVER_FILES[@]}"; do
    IFS="|" read -r REL EXPECTED CLASS LABEL <<< "$ENTRY"
    ADD_TO_WORK_DIR "$MALI_R49_PRIVATE_CACHE_DIR" \
        "vendor" "${REL#vendor/}" 0 0 644 "$LABEL"
    SET_METADATA "vendor" "${REL#vendor/}" 0 0 644 "$LABEL"
done
ADD_TO_WORK_DIR "$MODPATH" "vendor" \
    "etc/permissions/android.hardware.vulkan.version.xml" \
    0 0 644 "u:object_r:vendor_configs_file:s0"
SET_METADATA "vendor" "etc/permissions/android.hardware.vulkan.version.xml" \
    0 0 644 "u:object_r:vendor_configs_file:s0"
LOG_STEP_OUT

LOG_STEP_IN "- Verifying installed Mali r49p0 vendor/SP-HAL closure"
_T2S_MALI_VERIFY_R49_INSTALLED_CLOSURE
MALI_R49_BOOT_HASH_AFTER="$(sha256sum "$MALI_R49_BOOT_IMAGE" | cut -d ' ' -f 1)"
MALI_R49_VENDOR_BOOT_HASH_AFTER="$(
    sha256sum "$MALI_R49_VENDOR_BOOT_IMAGE" | cut -d ' ' -f 1
)"
[ "$MALI_R49_BOOT_HASH_AFTER" = "$MALI_R49_BOOT_HASH_BEFORE" ] || \
    ABORT "Mali userspace module unexpectedly changed boot.img"
[ "$MALI_R49_VENDOR_BOOT_HASH_AFTER" = "$MALI_R49_VENDOR_BOOT_HASH_BEFORE" ] || \
    ABORT "Mali userspace module unexpectedly changed vendor_boot.img"
LOG "- Kernel images are byte-for-byte unchanged"
LOG_STEP_OUT

unset T2S_MALI_R49P0_DONOR_DIR
unset MALI_R49_FACTORY_URL MALI_R49_FACTORY_VENDOR_RANGE
unset MALI_R49_FACTORY_VENDOR_COMPRESSED_SIZE MALI_R49_FACTORY_VENDOR_SIZE
unset MALI_R49_FACTORY_VENDOR_SHA256 MALI_R49_CACHE_DIR
unset MALI_R49_LOCAL_DONOR_DIR MALI_R49_SOURCE_DIR MALI_R49_PRIVATE_CACHE_DIR
unset MALI_R49_DRIVER_FILES MALI_R49_RUNTIME_FILES
unset MALI_R49_PRIVATE_DRIVER_FILES MALI_R49_PRIVATE_RUNTIME_FILES
unset MALI_R49_BOOT_IMAGE MALI_R49_VENDOR_BOOT_IMAGE
unset MALI_R49_BOOT_HASH_BEFORE MALI_R49_VENDOR_BOOT_HASH_BEFORE
unset MALI_R49_BOOT_HASH_AFTER MALI_R49_VENDOR_BOOT_HASH_AFTER
unset ENTRY REL EXPECTED CLASS LABEL TOOL
unset -f _T2S_MALI_FILE_MATCHES
unset -f _T2S_MALI_VERIFY_R49_SOURCE _T2S_MALI_FETCH_R49
unset -f _T2S_MALI_VERIFY_R49_PRIVATE_SOURCE
unset -f _T2S_MALI_BUILD_R49_PRIVATE_CLOSURE
unset -f _T2S_MALI_VERIFY_R49_ABI _T2S_MALI_VERIFY_R49_INSTALLED_CLOSURE
