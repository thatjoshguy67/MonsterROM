# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Debloat list for Qualcomm Snapdragon 888 devices (sm8350)
# - Add entries inside the specific partition containing that file (<PARTITION>_DEBLOAT+="")
# - DO NOT add the partition name at the start of any entry (eg. "/system/dpolicy_system")
# - DO NOT add a slash at the start of any entry (eg. "/dpolicy_system")

# Overlays
SYSTEM_DEBLOAT+="
system/app/WifiRROverlayAppQC
"
PRODUCT_DEBLOAT+="
overlay/SoftapOverlay6GHz
overlay/SoftapOverlayDualAp
overlay/SoftapOverlayOWE
overlay/SoftapOverlayQC
"

# mAFPC
SYSTEM_DEBLOAT+="
system/bin/mafpc_write
"

# GameDriver
SYSTEM_DEBLOAT+="
system/priv-app/GameDriver-SM8550
system/priv-app/GameDriver-SM8750
system/priv-app/GameDriver-SM8850
"

# system_ext clean-up
SYSTEM_EXT_DEBLOAT+="
app/QCC
bin/qccsyshal@1.2-service
etc/init/vendor.qti.hardware.qccsyshal@1.2-service.rc
etc/permissions/com.qti.location.sdk.xml
etc/permissions/com.qualcomm.location.xml
etc/permissions/privapp-permissions-com.qualcomm.location.xml
framework/com.qti.location.sdk.jar
lib/libqcc.so
lib/libqcc_file_agent_sys.so
lib/libqccdme.so
lib/libqccfileservice.so
lib/vendor.qti.hardware.qccsyshal@1.0.so
lib/vendor.qti.hardware.qccsyshal@1.1.so
lib/vendor.qti.hardware.qccsyshal@1.2.so
lib/vendor.qti.hardware.qccvndhal@1.0.so
lib/vendor.qti.qccvndhal_aidl-V1-ndk.so
lib64/libqcc.so
lib64/libqcc_file_agent_sys.so
lib64/libqccdme.so
lib64/libqccfileservice.so
lib64/vendor.qti.hardware.qccsyshal@1.0.so
lib64/vendor.qti.hardware.qccsyshal@1.1.so
lib64/vendor.qti.hardware.qccsyshal@1.2-halimpl.so
lib64/vendor.qti.hardware.qccsyshal@1.2.so
lib64/vendor.qti.hardware.qccvndhal@1.0.so
lib64/vendor.qti.qccvndhal_aidl-V1-ndk.so
priv-app/com.qualcomm.location
"
