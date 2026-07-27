# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/smali_utils.sh"
# ]

# ABORT <message>
# Stops the build process, additionally prints a log message if supplied.
ABORT()
{
    if [ "$1" ]; then
        LOGE "$1"
    fi
    return 1
}

# APPLY_PATCH <partition> <apk/jar> <patch>
# Applies a unified diff patch to the provided APK/JAR decoded directory.
_RESOLVE_PATCH_SMALI_PATHS()
{
    local TARGET_DIR="$1"
    local PATCH="$2"
    local OUTPUT="$3"
    local CHANGED=false

    cp "$PATCH" "$OUTPUT" || return 1

    while IFS= read -r PATCH_PATH; do
        if [ -f "$TARGET_DIR/$PATCH_PATH" ] || [[ "$PATCH_PATH" != smali*/* ]]; then
            continue
        fi

        local SMALI_SUFFIX="${PATCH_PATH#*/}"
        local MATCHES
        MATCHES="$(find "$TARGET_DIR" -type f -path "*/$SMALI_SUFFIX")"

        if [ -n "$MATCHES" ] && [ "$(printf "%s\n" "$MATCHES" | wc -l)" -eq 1 ]; then
            local RESOLVED_PATH="${MATCHES#"$TARGET_DIR"/}"
            local OUTPUT_TMP="$OUTPUT.tmp"

            awk -v OLD="$PATCH_PATH" -v NEW="$RESOLVED_PATH" '
                function replace_literal(line, old, new, index_at, result) {
                    result = ""
                    while ((index_at = index(line, old)) > 0) {
                        result = result substr(line, 1, index_at - 1) new
                        line = substr(line, index_at + length(old))
                    }
                    return result line
                }
                { print replace_literal($0, OLD, NEW) }
            ' "$OUTPUT" > "$OUTPUT_TMP" && mv "$OUTPUT_TMP" "$OUTPUT" || return 1

            LOG "- Resolved patch path \"$PATCH_PATH\" to \"$RESOLVED_PATH\""
            CHANGED=true
        fi
    done < <(
        awk '/^(---|\+\+\+) [ab]\// {
            path = $2
            sub(/^[ab]\//, "", path)
            print path
        }' "$PATCH" | LC_ALL=C sort -u
    )

    $CHANGED
}

APPLY_PATCH()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "PATCH" "$3" || return 1

    local PARTITION="$1"
    local FILE="$2"
    local PATCH="$3"

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    if [ ! -f "$PATCH" ]; then
        LOGE "File not found: ${PATCH//$SRC_DIR\//}"
        return 1
    fi

    while [[ "${FILE:0:1}" == "/" ]]; do
        FILE="${FILE:1}"
    done

    DECODE_APK "$PARTITION" "$FILE" || return 1

    local TARGET_DIR="$APKTOOL_DIR/$PARTITION/${FILE//system\//}"
    local PATCH_TO_APPLY="$PATCH"
    local RESOLVED_PATCH

    LOG "- Applying \"$(grep "^Subject:" "$PATCH" | sed "s/.*PATCH] //")\" to /$PARTITION/$FILE"
    if ! LC_ALL=C git apply --check --directory="$TARGET_DIR" --unsafe-paths "$PATCH" &> /dev/null; then
        RESOLVED_PATCH="$(mktemp)"
        if _RESOLVE_PATCH_SMALI_PATHS "$TARGET_DIR" "$PATCH" "$RESOLVED_PATCH"; then
            PATCH_TO_APPLY="$RESOLVED_PATCH"
        else
            rm -f "$RESOLVED_PATCH"
            RESOLVED_PATCH=""
        fi

        if ! LC_ALL=C git apply --check --directory="$TARGET_DIR" --unsafe-paths "$PATCH_TO_APPLY" &> /dev/null; then
            case "$PATCH" in
                *"/audio/virtual_vib/SecSettings.apk/0001-Disable-virtual-vibration-support.patch")
                    LOG "- Skipping obsolete SecSettings virtual-vibration patch"
                    [ -n "$RESOLVED_PATCH" ] && rm -f "$RESOLVED_PATCH"
                    return 0
                    ;;
            esac
        fi
    fi

    if ! EVAL "LC_ALL=C git apply --directory=\"$TARGET_DIR\" --verbose --unsafe-paths \"$PATCH_TO_APPLY\""; then
        [ -n "$RESOLVED_PATCH" ] && rm -f "$RESOLVED_PATCH"
        return 1
    fi

    [ -n "$RESOLVED_PATCH" ] && rm -f "$RESOLVED_PATCH"
    return 0
}

# DECODE_APK <partition> <apk/jar>
# Same usage as `run_cmd apktool d <partition> <apk/jar>`.
DECODE_APK()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1

    if [ ! -d "$APKTOOL_DIR/$1/${2//system\/}" ]; then
        "$SRC_DIR/scripts/apktool.sh" d "$1" "$2"
        return $?
    fi

    return 0
}

# GET_GALAXY_STORE_DOWNLOAD_URL "<package name/id>"
# Returns a URL to download the desired app from Samsung servers.
GET_GALAXY_STORE_DOWNLOAD_URL()
{
    _CHECK_NON_EMPTY_PARAM "PACKAGE" "$1" || return 1

    local PACKAGE="$1"
    local DEVICES
    local OS
    local ONEUI
    local PROTOCOL

    # Galaxy Z Fold8 Ultra EUR_OPENX
    DEVICES=("SM-F976B")

    OS="$(GET_PROP "system" "ro.build.version.sdk")"
    ONEUI="$(GET_PROP "system" "ro.build.version.oneui")"

    if [ ! "$OS" ]; then
        # Fallback to Android 17
        OS="37"
    fi
    if [ ! "$ONEUI" ]; then
        # Fallback to One UI 9.0
        ONEUI="90000"
    fi

    PROTOCOL+="<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>"
    PROTOCOL+="<SamsungProtocol networkType=\"0\" openApiVersion=\"$OS\" deviceModel=\"DEVICE\""
    PROTOCOL+=" mcc=\"262\" mnc=\"01\" csc=\"EUX\" version=\"7.7\""
    PROTOCOL+=" deviceFeature=\"locale=en_GB||abi32=armeabi-v7a:armeabi||abi64=arm64-v8a||oneUiVersion=$ONEUI\">"
    PROTOCOL+="<request id=\"2303\" numParam=\"2\">"
    PROTOCOL+="<param name=\"stduk\">0</param>"
    PROTOCOL+="<param name=\"productID\">PRODUCTID</param>"
    PROTOCOL+="</request>"
    PROTOCOL+="</SamsungProtocol>"

    local OUT
    local REQUEST
    for i in "${DEVICES[@]}"; do
        if [[ "$PACKAGE" =~ ^[+-]?[0-9]+$ ]]; then
            OUT="$PACKAGE"
        else
            OUT="$(curl -L -s "https://vas.samsungapps.com/stub/stubUpdateCheck.as?appId=$PACKAGE&versionCode=0&deviceId=$i&mcc=262&mnc=01&csc=EUX&sdkVer=$OS&oneUiVersion=$ONEUI&systemId=0")"
            OUT="$(grep -o -P "(?<=<productId>)[^<]+" <<< "$OUT")"
            if [ ! "$OUT" ]; then
                continue
            fi
        fi

        REQUEST="$PROTOCOL"
        REQUEST="${REQUEST//DEVICE/$i}"
        REQUEST="${REQUEST//PRODUCTID/$OUT}"

        OUT="$(curl -L -s "https://uk-odc.samsungapps.com/ods.as" -H "Content-Type: text/plain" -d "$REQUEST")"
        OUT="$(grep -o -P "(?<=<value name=\"downLoadURI\">)[^<]+" <<< "$OUT")"
        if [ "$OUT" ]; then
            echo "${OUT//amp;/}"
            return 0
        fi
    done

    LOGE "No download URI found for app \"$PACKAGE\""
    return 1
}

# DOWNLOAD_GALAXY_STORE_APP "<package name/id>" "<dest apk path>"
# Downloads an app from the Galaxy Store into <dest apk path>. A missing
# store entry or a failed download is non-fatal: it logs a warning and
# returns 0. An optional preloaded app must not abort the whole ROM build
# when Samsung's store has no match for the spoofed device/region/SDK.
DOWNLOAD_GALAXY_STORE_APP()
{
    _CHECK_NON_EMPTY_PARAM "PACKAGE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "DEST" "$2" || return 1

    local PACKAGE="$1"
    local DEST="$2"
    local URL

    URL="$(GET_GALAXY_STORE_DOWNLOAD_URL "$PACKAGE")" || URL=""
    if [ -z "$URL" ]; then
        LOGW "No Galaxy Store download for \"$PACKAGE\"; skipping"
        return 0
    fi

    if ! DOWNLOAD_FILE "$URL" "$DEST"; then
        LOGW "Download of \"$PACKAGE\" failed; skipping"
        rm -f "$DEST"
    fi

    return 0
}

# GET_FLOATING_FEATURE_CONFIG "<file>" "<config>"
# Returns the supplied config value, file can be omitted.
GET_FLOATING_FEATURE_CONFIG()
{
    local FILE
    if [ "$2" ]; then
        FILE="$1"
        shift
    else
        FILE="$WORK_DIR/system/system/etc/floating_feature.xml"
    fi

    _CHECK_NON_EMPTY_PARAM "CONFIG" "$1" || return 1

    local CONFIG="$1"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    grep -o -P "(?<=<$CONFIG>)[^<]+" "$FILE" 2> /dev/null || true
}

# HEX_PATCH "<file>" "<old pattern>" "<new pattern>"
# Applies the supplied hex patch to the desired file.
HEX_PATCH()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FROM" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "TO" "$3" || return 1

    local FILE="$1"
    local FROM="$2"
    local TO="$3"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    FROM="${FROM// /}"
    TO="${TO// /}"

    FROM="$(tr "[:upper:]" "[:lower:]" <<< "$FROM")"
    TO="$(tr "[:upper:]" "[:lower:]" <<< "$TO")"

    if ! xxd -p -c 0 "$FILE" | grep -q "$FROM"; then
        LOGE "No \"$FROM\" match in ${FILE//$WORK_DIR/}"
        return 1
    fi

    if [[ "$(echo -n "$FROM" | wc -c)" != "$(echo -n "$TO" | wc -c)" ]]; then
        LOGE "Byte strings length must be equal"
        return 1
    fi

    LOG "- Patching \"$FROM\" to \"$TO\" in ${FILE//$WORK_DIR/}"
    xxd -p -c 0 "$FILE" | sed "s/$FROM/$TO/" | xxd -r -p > "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"

    return 0
}

# SET_FLOATING_FEATURE_CONFIG "<config>" "<value>"
# Sets the supplied config to the desired value.
# "-d" or "--delete" can be passed as value to delete the config.
SET_FLOATING_FEATURE_CONFIG()
{
    _CHECK_NON_EMPTY_PARAM "CONFIG" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "VALUE" "$2" || return 1

    local CONFIG="$1"
    local VALUE="$2"
    local FILE="$WORK_DIR/system/system/etc/floating_feature.xml"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    if grep -q "$CONFIG" "$FILE"; then
        if [[ "$VALUE" == "-d" ]] || [[ "$VALUE" == "--delete" ]]; then
            LOG "- Deleting \"$CONFIG\" config in /system/system/etc/floating_feature.xml"
            sed -i "/<$CONFIG>/d" "$FILE"
        else
            LOG "- Replacing \"$CONFIG\" config with \"$VALUE\" in /system/system/etc/floating_feature.xml"
            sed -i "$(sed -n "/<${CONFIG}>/=" "$FILE") c\ \ \ \ <${CONFIG}>${VALUE}</${CONFIG}>" "$FILE"
        fi
    elif [[ "$VALUE" != "-d" ]] && [[ "$VALUE" != "--delete" ]]; then
        LOG "- Adding \"$CONFIG\" config with \"$VALUE\" in /system/system/etc/floating_feature.xml"
        sed -i "/<\/SecFloatingFeatureSet>/d" "$FILE"
        if ! grep -q "Added by scripts" "$FILE"; then
            echo "    <!-- Added by scripts/utils/module_utils.sh -->" >> "$FILE"
        fi
        echo "    <${CONFIG}>${VALUE}</${CONFIG}>" >> "$FILE"
        echo "</SecFloatingFeatureSet>" >> "$FILE"
    fi

    return 0
}

# SET_PROP_IF_DIFF "<partition>" "<prop>" "<value>"
# Calls SET_PROP if the current prop value does not match, partition name CANNOT be omitted.
SET_PROP_IF_DIFF()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "PROP" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "EXPECTED" "$3" || return 1

    local PARTITION="$1"
    local PROP="$2"
    local EXPECTED="$3"

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    local CURRENT
    CURRENT="$(GET_PROP "$PARTITION" "$PROP")"
    [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || SET_PROP "$PARTITION" "$PROP" "$EXPECTED"
}
