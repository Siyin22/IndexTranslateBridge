Option Explicit

Dim shell, fso, projectDir, autoStartScript
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
projectDir = fso.GetParentFolderName(WScript.ScriptFullName)
autoStartScript = projectDir & "\scripts\autostart.ps1"

' The PowerShell helper finds py.exe or python.exe and starts the bridge silently.
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & autoStartScript & """", 0, False
