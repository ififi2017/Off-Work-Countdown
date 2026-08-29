; GitHub 渠道把 productName 从「Off Work Countdown」改成了 DoneAt。
; Tauri 的 NSIS 把卸载项、默认安装目录和开始菜单快捷方式绑在 productName 上，
; 不绑 identifier。应用内更新带 /UPDATE /P，找不到 Uninstall\DoneAt 就会当成新装，
; 再写一份 %LOCALAPPDATA%\DoneAt，旧开始菜单项还在。两边又抢同一份
; %APPDATA%\com.rainif.offworkcountdown。
;
; 这里不改 identifier，也不改 MAINBINARYNAME（exe 仍是 Off Work Countdown.exe）。
; 官方 installer.nsi 的 .onInit / PageReinstall 读的是新名字，hook 插不进去；
; PREINSTALL 在 File 之前改 $INSTDIR，POSTINSTALL 在写完新卸载项之后清旧键。
; https://github.com/tauri-apps/tauri/issues/14175

!define LEGACY_PRODUCTNAME "Off Work Countdown"
!define LEGACY_UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${LEGACY_PRODUCTNAME}"
!define RUNKEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define STARTUPAPPROVEDKEY "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"

!macro UnquoteNsisPath dest
  Push $R6
  StrCpy $R6 `${dest}` 1
  ${If} $R6 == '"'
    StrCpy `${dest}` `${dest}` "" 1
  ${EndIf}
  StrCpy $R6 `${dest}` 1 -1
  ${If} $R6 == '"'
    StrCpy `${dest}` `${dest}` -1
  ${EndIf}
  Pop $R6
!macroend

!macro ReadLegacyInstallDir dest
  Push $0
  Push $1
  StrCpy $0 ""

  ReadRegStr $0 SHCTX "Software\${MANUFACTURER}\${LEGACY_PRODUCTNAME}" ""

  ${If} $0 == ""
    ReadRegStr $1 SHCTX "${LEGACY_UNINSTKEY}" "InstallLocation"
    ${If} $1 != ""
      !insertmacro UnquoteNsisPath $1
      StrCpy $0 $1
    ${EndIf}
  ${EndIf}

  ${If} $0 == ""
    ReadRegStr $1 SHCTX "${LEGACY_UNINSTKEY}" "UninstallString"
    ${If} $1 != ""
      !insertmacro UnquoteNsisPath $1
      ${GetParent} "$1" $0
    ${EndIf}
  ${EndIf}

  ${If} $0 == ""
    ReadRegStr $0 HKLM "Software\${MANUFACTURER}\${LEGACY_PRODUCTNAME}" ""
  ${EndIf}

  ${If} $0 == ""
    ReadRegStr $1 HKLM "${LEGACY_UNINSTKEY}" "InstallLocation"
    ${If} $1 != ""
      !insertmacro UnquoteNsisPath $1
      StrCpy $0 $1
    ${EndIf}
  ${EndIf}

  ${If} $0 == ""
    ${If} ${FileExists} "$LOCALAPPDATA\${LEGACY_PRODUCTNAME}\${MAINBINARYNAME}.exe"
      StrCpy $0 "$LOCALAPPDATA\${LEGACY_PRODUCTNAME}"
    ${ElseIf} ${FileExists} "$PROGRAMFILES64\${LEGACY_PRODUCTNAME}\${MAINBINARYNAME}.exe"
      StrCpy $0 "$PROGRAMFILES64\${LEGACY_PRODUCTNAME}"
    ${EndIf}
  ${EndIf}

  StrCpy `${dest}` $0
  Pop $1
  Pop $0
!macroend

!macro HasCurrentProductInstall dest
  Push $0
  Push $1
  StrCpy $0 0
  ReadRegStr $1 SHCTX "${UNINSTKEY}" "UninstallString"
  ${If} $1 != ""
    StrCpy $0 1
  ${Else}
    ReadRegStr $1 SHCTX "${MANUPRODUCTKEY}" ""
    ${If} $1 != ""
      StrCpy $0 1
    ${EndIf}
  ${EndIf}
  StrCpy `${dest}` $0
  Pop $1
  Pop $0
!macroend

!macro DeleteLegacyShortcut shortcut
  ${If} ${FileExists} `${shortcut}`
    !insertmacro UnpinShortcut `${shortcut}`
    Delete `${shortcut}`
  ${EndIf}
!macroend

!macro NSIS_HOOK_PREINSTALL
  ${If} "${PRODUCTNAME}" != "${LEGACY_PRODUCTNAME}"
    !insertmacro HasCurrentProductInstall $R7
    ${If} $R7 = 0
      !insertmacro ReadLegacyInstallDir $R8
      ${If} $R8 != ""
        StrCpy $R7 $INSTDIR
        StrCpy $INSTDIR $R8
        SetOutPath $INSTDIR
        ${If} $R7 != $INSTDIR
          RMDir $R7
        ${EndIf}
      ${EndIf}
    ${EndIf}
  ${EndIf}
!macroend

!macro NSIS_HOOK_POSTINSTALL
  ${If} "${PRODUCTNAME}" != "${LEGACY_PRODUCTNAME}"
    DeleteRegKey SHCTX "${LEGACY_UNINSTKEY}"
    DeleteRegKey HKCU "${LEGACY_UNINSTKEY}"
    DeleteRegKey HKLM "${LEGACY_UNINSTKEY}"
    DeleteRegKey SHCTX "Software\${MANUFACTURER}\${LEGACY_PRODUCTNAME}"
    DeleteRegKey HKCU "Software\${MANUFACTURER}\${LEGACY_PRODUCTNAME}"
    DeleteRegKey HKLM "Software\${MANUFACTURER}\${LEGACY_PRODUCTNAME}"

    !insertmacro DeleteLegacyShortcut "$SMPROGRAMS\${LEGACY_PRODUCTNAME}.lnk"
    !insertmacro DeleteLegacyShortcut "$SMPROGRAMS\$AppStartMenuFolder\${LEGACY_PRODUCTNAME}.lnk"

    ${If} ${FileExists} "$DESKTOP\${LEGACY_PRODUCTNAME}.lnk"
      !insertmacro UnpinShortcut "$DESKTOP\${LEGACY_PRODUCTNAME}.lnk"
      Delete "$DESKTOP\${LEGACY_PRODUCTNAME}.lnk"
      ${If} $NoShortcutMode != 1
        CreateShortcut "$DESKTOP\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
        !insertmacro SetLnkAppUserModelId "$DESKTOP\${PRODUCTNAME}.lnk"
      ${EndIf}
    ${EndIf}

    ${If} $NoShortcutMode != 1
      StrCpy $R7 "$SMPROGRAMS\${PRODUCTNAME}.lnk"
      ${If} $AppStartMenuFolder != ""
        StrCpy $R7 "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk"
      ${EndIf}
      ${IfNot} ${FileExists} "$R7"
        ${If} $AppStartMenuFolder != ""
          CreateDirectory "$SMPROGRAMS\$AppStartMenuFolder"
        ${EndIf}
        CreateShortcut "$R7" "$INSTDIR\${MAINBINARYNAME}.exe"
        !insertmacro SetLnkAppUserModelId "$R7"
      ${EndIf}
    ${EndIf}

    ReadRegStr $R7 HKCU "${RUNKEY}" "${LEGACY_PRODUCTNAME}"
    ${If} $R7 != ""
      WriteRegStr HKCU "${RUNKEY}" "${PRODUCTNAME}" $R7
      DeleteRegValue HKCU "${RUNKEY}" "${LEGACY_PRODUCTNAME}"
    ${EndIf}
    ReadRegBin $R7 HKCU "${STARTUPAPPROVEDKEY}" "${LEGACY_PRODUCTNAME}"
    ${If} $R7 != ""
      WriteRegBin HKCU "${STARTUPAPPROVEDKEY}" "${PRODUCTNAME}" $R7
      DeleteRegValue HKCU "${STARTUPAPPROVEDKEY}" "${LEGACY_PRODUCTNAME}"
    ${EndIf}
  ${EndIf}
!macroend
