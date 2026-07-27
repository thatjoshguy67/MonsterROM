# Smali method signatures below contain '$' (inner-class separator) inside
# single quotes, which shellcheck flags as SC2016; that is intentional here.
# shellcheck disable=SC2016
APPLY_PATCH "system" "system/framework/framework.jar" \
    "$MODPATH/framework.jar/0001-Introduce-PlayIntegrityHooks.patch"
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali/android/app/Instrumentation.smali" "replace" \
    'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;' \
    'return-object p0' \
    '    invoke-static {p1}, Lio/mesalabs/unica/PlayIntegrityHooks;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
    > /dev/null
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali/android/app/Instrumentation.smali" "replace" \
    'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;' \
    'return-object p0' \
    '    invoke-static {p3}, Lio/mesalabs/unica/PlayIntegrityHooks;->setProps(Landroid/content/Context;)V\n\n    return-object p0' \
    > /dev/null
# services.jar: skip ActivityTaskManagerService's task-permission checks when
# PlayIntegrityHooks asks to. Done as content-anchored SMALI_PATCH instead of
# the upstream positional git-apply patch: that patch injected a :cond_0 label
# which collided with existing labels, forcing brittle label-renumbering hunks
# that break on every firmware recompile (they did, on the One UI 9 source).
# Anchoring on the stable enforceTaskPermission call and using a unique bypass
# label is register- and line-independent, so it survives recompiles.
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/wm/ActivityTaskManagerService.smali" "replace" \
    'getFocusedRootTaskInfo()Landroid/app/ActivityTaskManager$RootTaskInfo;' \
    '->enforceTaskPermission(Ljava/lang/String;)V' \
    '    iget-object v0, p0, Lcom/android/server/wm/ActivityTaskManagerService;->mContext:Landroid/content/Context;\n\n    invoke-static {v0}, Lio/mesalabs/unica/PlayIntegrityHooks;->shouldBypassTaskPermission(Landroid/content/Context;)Z\n\n    move-result v0\n\n    if-nez v0, :pif_bypass_getfocusedroottaskinfo\n\n    const-string/jumbo v0, "getFocusedRootTaskInfo()"\n\n    invoke-static {v0}, Lcom/android/server/wm/ActivityTaskManagerService;->enforceTaskPermission(Ljava/lang/String;)V\n\n    :pif_bypass_getfocusedroottaskinfo' \
    > /dev/null
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/wm/ActivityTaskManagerService.smali" "replace" \
    'registerTaskStackListener(Landroid/app/ITaskStackListener;)V' \
    '->enforceTaskPermission(Ljava/lang/String;)V' \
    '    iget-object v0, p0, Lcom/android/server/wm/ActivityTaskManagerService;->mContext:Landroid/content/Context;\n\n    invoke-static {v0}, Lio/mesalabs/unica/PlayIntegrityHooks;->shouldBypassTaskPermission(Landroid/content/Context;)Z\n\n    move-result v0\n\n    if-nez v0, :pif_bypass_registertaskstacklistener\n\n    const-string/jumbo v0, "registerTaskStackListener()"\n\n    invoke-static {v0}, Lcom/android/server/wm/ActivityTaskManagerService;->enforceTaskPermission(Ljava/lang/String;)V\n\n    :pif_bypass_registertaskstacklistener' \
    > /dev/null

if [ ! -f "$APKTOOL_DIR/system/framework/framework.jar/smali_classes6/io/mesalabs/unica/KeyboxImitationHooks.smali" ]; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/io/mesalabs/unica/PlayIntegrityHooks.smali" "return" \
        'shouldBlockKeyAttestation()Z' 'true'
fi
