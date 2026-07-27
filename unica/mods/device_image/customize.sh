DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || return 1

_DEVICE_IMAGE_DIR="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"
_DEVICE_IMAGE_SMALI="$(find "$_DEVICE_IMAGE_DIR" -type f \
    -path '*/com/samsung/android/settings/deviceinfo/aboutphone/DeviceImageManager$1.smali')"
if [ -z "$_DEVICE_IMAGE_SMALI" ] || \
        [ "$(printf "%s\n" "$_DEVICE_IMAGE_SMALI" | wc -l)" -ne 1 ]; then
    LOGE "Failed to resolve DeviceImageManager\$1.smali in SecSettings.apk"
    return 1
fi

LOG "- Replacing the device image product code in /system/system/priv-app/SecSettings/SecSettings.apk"
python3 - "$_DEVICE_IMAGE_SMALI" << 'PYEOF' || return 1
import re
import sys

path = sys.argv[1]
with open(path) as stream:
    lines = stream.readlines()

markers = [
    index for index, line in enumerate(lines)
    if re.match(
        r'\s*const-string(?:/jumbo)?\s+[vp]\d+,\s+"ril\.product_code"\s*$',
        line,
    )
]
if len(markers) != 1:
    print(f"Expected one ril.product_code lookup, found {len(markers)}", file=sys.stderr)
    sys.exit(1)

start = markers[0]
invoke = next(
    (
        index for index in range(start + 1, min(len(lines), start + 10))
        if "SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;" in lines[index]
    ),
    None,
)
if invoke is None:
    print("SystemProperties.get call not found after ril.product_code", file=sys.stderr)
    sys.exit(1)

result = None
end = None
for index in range(invoke + 1, min(len(lines), invoke + 6)):
    match = re.match(r"\s*move-result-object\s+([vp]\d+)\s*$", lines[index])
    if match:
        result = match.group(1)
        end = index
        break

if result is None or end is None:
    print("Product code result register not found", file=sys.stderr)
    sys.exit(1)

indent = re.match(r"\s*", lines[start]).group(0)
lines[start:end + 1] = [f'{indent}const-string {result}, "SM-S948BZDGEUX"\n']
with open(path, "w") as stream:
    stream.writelines(lines)
PYEOF

unset _DEVICE_IMAGE_DIR _DEVICE_IMAGE_SMALI
