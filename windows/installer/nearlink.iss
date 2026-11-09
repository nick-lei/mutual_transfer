#ifndef AppVersion
  #error AppVersion must be supplied by build_installer.ps1
#endif
#ifndef PackageDirectory
  #error PackageDirectory must be supplied by build_installer.ps1
#endif
#ifndef OutputDirectory
  #error OutputDirectory must be supplied by build_installer.ps1
#endif

#ifndef AppName
  #define AppName "邻传 NearLink"
#endif
#define AppExe "mutual_transfer.exe"
#ifndef AppGuid
  #define AppGuid "{1E9AC935-47A2-47F0-99F4-F85723139C8B}"
#endif
#ifndef AppMenuName
  #define AppMenuName "NearLink"
#endif

[Setup]
AppId={{#AppGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=NearLink
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}.0
VersionInfoDescription=NearLink Installer
DefaultDirName={localappdata}\Programs\NearLink
DefaultGroupName={#AppMenuName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern dynamic
WizardSizePercent=110
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
AppMutex=Local\NearLink.InstallationGuard
CloseApplications=no
RestartApplications=no
SetupLogging=yes
Compression=lzma2
SolidCompression=yes
OutputDir={#OutputDirectory}
OutputBaseFilename=NearLink-{#AppVersion}-windows-x64-Setup

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
chinesesimplified.SetupAppRunningError=邻传仍在运行。%n%n请在任务托盘中右键邻传图标，选择“退出邻传”，再点击“确定”继续安装。
chinesesimplified.UninstallAppRunningError=邻传仍在运行。%n%n请在任务托盘中右键邻传图标，选择“退出邻传”，再点击“确定”继续卸载。
english.SetupAppRunningError=NearLink is still running.%n%nRight-click its system tray icon and choose Exit, then click OK to continue installing.
english.UninstallAppRunningError=NearLink is still running.%n%nRight-click its system tray icon and choose Exit, then click OK to continue uninstalling.

[CustomMessages]
chinesesimplified.LaunchNearLink=运行邻传
chinesesimplified.UninstallNearLink=卸载邻传
english.LaunchNearLink=Launch NearLink
english.UninstallNearLink=Uninstall NearLink
chinesesimplified.RunningTitle=邻传正在运行
chinesesimplified.RunningInfo=继续操作前需要关闭邻传。安装程序会先请求正常退出，旧版或无响应的实例将被强制停止。正在进行的传输会中断，未保存的内容可能丢失。
chinesesimplified.CloseAndContinue=关闭邻传并继续
chinesesimplified.CancelOperation=取消
chinesesimplified.CloseFailed=无法关闭部分邻传实例，可能是权限不足或程序仍在退出。请退出邻传后重试，详细原因已记录在安装日志中。
chinesesimplified.CloseCancelled=操作已取消，邻传仍保持运行。
english.RunningTitle=NearLink is running
english.RunningInfo=NearLink must close before continuing. Setup will first request a normal exit, then force stop older or unresponsive instances. Active transfers will be interrupted and unsaved content may be lost.
english.CloseAndContinue=Close NearLink and continue
english.CancelOperation=Cancel
english.CloseFailed=Some NearLink instances could not be closed, possibly because of insufficient permissions. Exit NearLink and retry. See the setup log for details.
english.CloseCancelled=The operation was cancelled. NearLink is still running.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#PackageDirectory}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb"

[Icons]
Name: "{autoprograms}\{#AppMenuName}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; AppUserModelID: "NearLink.Desktop"
Name: "{autoprograms}\{#AppMenuName}\{cm:UninstallNearLink}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon; AppUserModelID: "NearLink.Desktop"

[Run]
Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Description: "{cm:LaunchNearLink}"; Flags: nowait postinstall skipifsilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  ApprovedKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  InstallationGuard = 'Local\NearLink.InstallationGuard';

type
  TProcessIds = array of Integer;

var
  ShutdownCancelled: Boolean;
  ShutdownFiles: TArrayOfString;

function InstallerProcessId: LongWord;
  external 'GetCurrentProcessId@kernel32.dll stdcall';
function FindNextAppWindow(Parent, After: HWND; ClassName: String; Title: NativeInt): HWND;
  external 'FindWindowExW@user32.dll stdcall';
function WindowProcessId(Window: HWND; var ProcessId: LongWord): LongWord;
  external 'GetWindowThreadProcessId@user32.dll stdcall';
function RegisterExitMessage(Name: String): LongWord;
  external 'RegisterWindowMessageW@user32.dll stdcall';
function OpenTargetProcess(Access: LongWord; Inherit: Boolean; ProcessId: LongWord): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForTarget(Handle: THandle; Milliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseTargetHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function OpenShutdownFile(Name: String; Access, Sharing: LongWord;
  Security: NativeInt; Creation, Flags: LongWord; Template: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';

function QuietOperation: Boolean;
begin
  if IsUninstaller then Result := UninstallSilent
  else Result := WizardSilent;
end;

function FindNearLinkProcesses(Service: Variant; const Sid: String;
  Session: Integer): TProcessIds;
var
  Items, Item, Owner, FileInfo: Variant;
  Index, Count, FileIndex: Integer;
  KnownFile: Boolean;
  FileName, EscapedName, Company: String;
begin
  SetArrayLength(Result, 0);
  Items := Service.ExecQuery('SELECT * FROM Win32_Process WHERE Name = ''{#AppExe}''');
  for Index := 0 to Items.Count - 1 do begin
    Item := Items.ItemIndex(Index);
    if Item.Properties_.Item('SessionId').Value = Session then begin
      try
        Owner := Item.ExecMethod_('GetOwnerSid');
        if (Owner.Properties_.Item('ReturnValue').Value = 0) and
           (Owner.Properties_.Item('Sid').Value = Sid) then begin
          FileName := Item.Properties_.Item('ExecutablePath').Value;
          EscapedName := FileName;
          StringChangeEx(EscapedName, '\', '\\', True);
          StringChangeEx(EscapedName, '"', '\"', True);
          FileInfo := Service.Get('CIM_DataFile.Name="' + EscapedName + '"');
          Company := FileInfo.Properties_.Item('Manufacturer').Value;
          // Match the app identity as well as its name, user and session.
          if Company = 'com.nearlink' then begin
            Count := GetArrayLength(Result);
            SetArrayLength(Result, Count + 1);
            Result[Count] := Item.Properties_.Item('ProcessId').Value;
            KnownFile := False;
            for FileIndex := 0 to GetArrayLength(ShutdownFiles) - 1 do
              if CompareText(ShutdownFiles[FileIndex], FileName) = 0 then KnownFile := True;
            if not KnownFile then begin
              FileIndex := GetArrayLength(ShutdownFiles);
              SetArrayLength(ShutdownFiles, FileIndex + 1);
              ShutdownFiles[FileIndex] := FileName;
            end;
            Log(Format('NearLink shutdown target: PID %d, %s', [Result[Count], FileName]));
          end;
        end;
      except
        Log('Could not inspect a NearLink candidate: ' + GetExceptionMessage);
      end;
    end;
  end;
end;

procedure RequestNormalExit(const Targets: TProcessIds);
var
  Window: HWND;
  ProcessId, MessageId: LongWord;
  Index: Integer;
begin
  MessageId := RegisterExitMessage('NearLink.ExitForUpdate');
  Window := FindNextAppWindow(0, 0, 'FLUTTER_RUNNER_WIN32_WINDOW', 0);
  while Window <> 0 do begin
    WindowProcessId(Window, ProcessId);
    for Index := 0 to GetArrayLength(Targets) - 1 do
      if ProcessId = LongWord(Targets[Index]) then begin
        PostMessage(Window, MessageId, 0, 0);
        Log(Format('Requested normal NearLink exit: PID %d', [Targets[Index]]));
      end;
    Window := FindNextAppWindow(0, Window, 'FLUTTER_RUNNER_WIN32_WINDOW', 0);
  end;
end;

function AnyTargetRunning(const Targets: TProcessIds): Boolean;
var
  Index: Integer;
  Handle: THandle;
begin
  Result := False;
  for Index := 0 to GetArrayLength(Targets) - 1 do begin
    Handle := OpenTargetProcess($00100000, False, Targets[Index]);
    if Handle <> 0 then begin
      try
        if WaitForTarget(Handle, 0) <> 0 then Result := True;
      finally
        CloseTargetHandle(Handle);
      end;
    end;
  end;
end;

function ShutdownFilesReleased: Boolean;
var
  Index: Integer;
  Handle: THandle;
begin
  Result := True;
  for Index := 0 to GetArrayLength(ShutdownFiles) - 1 do
    if FileExists(ShutdownFiles[Index]) then begin
      // Process termination can precede release of its executable image.
      Handle := OpenShutdownFile(ShutdownFiles[Index], $40000000, 7, 0, 3, 0, 0);
      if Handle = THandle(-1) then begin
        Result := False;
        Exit;
      end;
      CloseTargetHandle(Handle);
    end;
end;

function EnsureNearLinkStopped: Boolean;
var
  Locator, Service, Self, Owner, Item, Status, Parameters: Variant;
  Sid: String;
  Session, Index, Attempt: Integer;
  Targets: TProcessIds;
  Forced: Boolean;
begin
  Result := False;
  ShutdownCancelled := False;
  SetArrayLength(ShutdownFiles, 0);
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Self := Service.Get(Format('Win32_Process.Handle="%d"', [InstallerProcessId]));
    Owner := Self.ExecMethod_('GetOwnerSid');
    Sid := Owner.Properties_.Item('Sid').Value;
    if (Owner.Properties_.Item('ReturnValue').Value <> 0) or (Sid = '') then
      RaiseException('Could not determine the installer user SID');
    Session := Self.Properties_.Item('SessionId').Value;
    Targets := FindNearLinkProcesses(Service, Sid, Session);
    if GetArrayLength(Targets) = 0 then begin
      Result := not CheckForMutexes(InstallationGuard);
      Exit;
    end;
    Forced := ExpandConstant('{param:FORCECLOSENEARLINK|0}') = '1';
    if not Forced then begin
      if QuietOperation then begin
        Log('NearLink is running; silent shutdown requires /FORCECLOSENEARLINK=1');
        Exit;
      end;
      if TaskDialogMsgBox(CustomMessage('RunningTitle'),
         CustomMessage('RunningInfo'), mbConfirmation, MB_OKCANCEL, [
         CustomMessage('CloseAndContinue'), CustomMessage('CancelOperation')], 0) <> IDOK then begin
        ShutdownCancelled := True;
        Exit;
      end;
    end;
    RequestNormalExit(Targets);
    for Attempt := 1 to 20 do begin
      Sleep(200);
      if not AnyTargetRunning(Targets) then Break;
    end;
    Targets := FindNearLinkProcesses(Service, Sid, Session);
    for Index := 0 to GetArrayLength(Targets) - 1 do begin
      try
        Item := Service.Get(Format('Win32_Process.Handle="%d"', [Targets[Index]]));
        Parameters := Item.Methods_.Item('Terminate').InParameters.SpawnInstance_;
        Parameters.Properties_.Item('Reason').Value := 0;
        Status := Item.ExecMethod_('Terminate', Parameters);
        Log(Format('Forced NearLink exit: PID %d, result %d', [
          Targets[Index], Integer(Status.Properties_.Item('ReturnValue').Value)]));
      except
        Log('Could not stop a NearLink instance: ' + GetExceptionMessage);
      end;
    end;
    for Attempt := 1 to 50 do begin
      Sleep(200);
      if not AnyTargetRunning(Targets) and not CheckForMutexes(InstallationGuard) and
         ShutdownFilesReleased then begin
        Targets := FindNearLinkProcesses(Service, Sid, Session);
        if GetArrayLength(Targets) <> 0 then Break;
        Log('NearLink shutdown completed; installation guard and executable files released');
        Result := True;
        Exit;
      end;
    end;
  except
    Log('NearLink shutdown failed: ' + GetExceptionMessage);
  end;
end;

function InitializeSetup: Boolean;
begin
  Result := EnsureNearLinkStopped;
  if not Result and not QuietOperation and not ShutdownCancelled then
    SuppressibleMsgBox(CustomMessage('CloseFailed'), mbError, MB_OK, IDOK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  if EnsureNearLinkStopped then Result := ''
  else if ShutdownCancelled then Result := CustomMessage('CloseCancelled')
  else Result := CustomMessage('CloseFailed');
end;

function StartupCommand: String;
begin
  Result := '"' + ExpandConstant('{app}\{#AppExe}') + '" --autostart';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Existing: String;
begin
  if CurStep = ssPostInstall then begin
    // Preserve the user's existing startup choice when moving or upgrading.
    if RegQueryStringValue(HKCU, RunKey, 'NearLink', Existing) and
       (Pos(Lowercase('{#AppExe}'), Lowercase(Existing)) > 0) then begin
      if not RegWriteStringValue(HKCU, RunKey, 'NearLink', StartupCommand) then
        Log('Could not update the existing NearLink startup path');
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Existing: String;
begin
  if CurUninstallStep = usAppMutexCheck then
    if not EnsureNearLinkStopped then begin
      if ShutdownCancelled then Abort;
      RaiseException(CustomMessage('CloseFailed'));
    end;
  if CurUninstallStep = usPostUninstall then begin
    // A portable copy may have taken over startup after installation.
    if RegQueryStringValue(HKCU, RunKey, 'NearLink', Existing) and
       (CompareText(Existing, StartupCommand) = 0) then begin
      RegDeleteValue(HKCU, RunKey, 'NearLink');
      RegDeleteValue(HKCU, ApprovedKey, 'NearLink');
    end;
  end;
end;
