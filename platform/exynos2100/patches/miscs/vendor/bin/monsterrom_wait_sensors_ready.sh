#!/system/bin/sh
# shellcheck disable=SC2015

TRY=0

log_msg()
{
    echo "monsterrom_wait_sensors_ready: $*" > /dev/kmsg 2>/dev/null || true
}

mount_hidden_hole_sensor_overlay()
{
    BASE="/dev/monsterrom_hidden_hole_sensors"
    VIEW="$BASE/sensors"

    if [ -e /sys/class/sensors/hidden_hole/hh_check_coef ] \
        && [ -e /sys/class/sensors/grip_notifier ] \
        && [ -e /sys/class/sensors/grip_sensor/country_code ]; then
        return 0
    fi
    [ -d /sys/class/sensors ] || return 0

    if grep -q " /sys/class/sensors " /proc/mounts 2>/dev/null; then
        return 0
    fi

    rm -rf "$BASE" 2>/dev/null || true
    mkdir -p "$VIEW/hidden_hole" 2>/dev/null || return 0

    for SENSOR in /sys/class/sensors/*; do
        [ -e "$SENSOR" ] || continue
        NAME="${SENSOR##*/}"
        TARGET="$(readlink -f "$SENSOR" 2>/dev/null || true)"
        [ -n "$TARGET" ] && [ -e "$TARGET" ] || continue
        ln -s "$TARGET" "$VIEW/$NAME" 2>/dev/null || true
    done

    TARGET="$(readlink -f /sys/devices/virtual/sensors/grip_sensor 2>/dev/null || true)"
    if [ -n "$TARGET" ] && [ -d "$TARGET" ]; then
        rm -f "$VIEW/grip_sensor" 2>/dev/null || true
        mkdir -p "$VIEW/grip_sensor" 2>/dev/null || true
        for SENSOR in "$TARGET"/*; do
            [ -e "$SENSOR" ] || continue
            ln -s "$SENSOR" "$VIEW/grip_sensor/${SENSOR##*/}" 2>/dev/null || true
        done
        echo "EEA" > "$VIEW/grip_sensor/country_code" 2>/dev/null || true
        chown -R system:radio "$VIEW/grip_sensor" 2>/dev/null || true
        chmod 0755 "$VIEW/grip_sensor" 2>/dev/null || true
        chmod 0664 "$VIEW/grip_sensor/country_code" 2>/dev/null || true
    fi

    TARGET="$(readlink -f /sys/devices/virtual/sensor_event/symlink/grip_notifier 2>/dev/null || true)"
    if [ -n "$TARGET" ] && [ -e "$TARGET" ]; then
        ln -s "$TARGET" "$VIEW/grip_notifier" 2>/dev/null || true
    fi

    echo "hidden_hole" > "$VIEW/hidden_hole/name" 2>/dev/null || true
    echo "SAMSUNG" > "$VIEW/hidden_hole/vendor" 2>/dev/null || true
    echo "0" > "$VIEW/hidden_hole/hh_check_coef" 2>/dev/null || true
    echo "0" > "$VIEW/hidden_hole/raw_data" 2>/dev/null || true
    chown -R system:radio "$VIEW/hidden_hole" 2>/dev/null || true
    chmod 0755 "$VIEW" "$VIEW/hidden_hole" 2>/dev/null || true
    chmod 0664 "$VIEW/hidden_hole/"* 2>/dev/null || true
    chcon -h u:object_r:sysfs:s0 "$VIEW" "$VIEW/grip_sensor" "$VIEW/grip_sensor/"* \
        "$VIEW/grip_notifier" "$VIEW/hidden_hole" "$VIEW/hidden_hole/"* 2>/dev/null || true

    mount -o bind "$VIEW" /sys/class/sensors 2>/dev/null || {
        log_msg "hidden_hole sensor overlay bind failed"
        return 0
    }

    log_msg "hidden_hole sensor overlay mounted"
}

while [ "$TRY" -lt 24 ]; do
    dmesg 2>/dev/null | grep -q "Sensors of MCU are ready" && break
    TRY=$((TRY + 1))
    sleep 1
done

mount_hidden_hole_sensor_overlay
setprop vendor.monsterrom.sensors_ready 1
