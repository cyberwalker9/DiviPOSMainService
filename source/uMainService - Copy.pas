unit uMainService;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.SvcMgr, Vcl.Dialogs, Registry, System.Threading;

type
  TDiviPOSMainService = class(TService)
    procedure ServiceAfterInstall(Sender: TService);
    procedure ServiceExecute(Sender: TService);
    procedure ServiceStart(Sender: TService; var Started: Boolean);
  private
    FDebugMode: boolean;

    FUpdateStatus: String;
    procedure SetUpdateStatus(const Value: String);
    { Private declarations }
  public
    CriticalSection: TRTLCriticalSection;

    function GetServiceController: TServiceController; override;
    function ServiceStopOrShutdown: boolean;
    { Public declarations }
    procedure UpdateLog(OnlyDebugMode : boolean = false);

    property UpdateStatus : String read FUpdateStatus write SetUpdateStatus;
    property DebugMode : Boolean read FDebugMode write FDebugMode;
  end;

var
  DiviPOSMainService: TDiviPOSMainService;

implementation

{$R *.dfm}

uses ServiceUtils;

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  DiviPOSMainService.Controller(CtrlCode);
end;

function TDiviPOSMainService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TDiviPOSMainService.ServiceAfterInstall(Sender: TService);
var
  Reg: TRegistry;
begin
  UpdateStatus := 'DiviPOS Backservice After Install';
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKey('\SYSTEM\CurrentControlSet\Services\' + Name, false) then
    begin
      Reg.WriteString('Description', 'Datadigi DiviPOS Backservice Application. Provide support for DiviPOS Application to Connect to Main Web Service');
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure TDiviPOSMainService.ServiceExecute(Sender: TService);
var
  Start: Integer;
  DBConnected : Boolean;
begin
  {
  Start := GetTickCount;
  While not Terminated Do
  Begin
    UpdateStatus := 'DiviPOS Service Execute ';
    if (GetTickCount-Start) > 10000 then
    begin
  }
      {
      if not Assigned(dmdService) then
        dmdService := TdmdService.Create(self);

      if not DBConnected then
      begin
        DBConnected := dmdService.ConnectMaster;
        if DBConnected then
        begin
          UpdateStatus := 'Database connected successfully ';
          //LoadParameter;
        end
        else
        begin
          UpdateStatus := 'Database Failed to Connect, please check settings ';
        end;
        sleep(10000);
      end;

      if DBConnected then
      begin
        UpdateStatus := 'Ready to Run Task';
        UpdateStatus := 'No Task';
      end;
      }
      {
      Start := GetTickCount;
    end;
    ServiceThread.ProcessRequests(false);
  End;
      }
end;

procedure TDiviPOSMainService.ServiceStart(Sender: TService;
  var Started: Boolean);
begin
  //InitializeCriticalSection(CriticalSection);
end;

function TDiviPOSMainService.ServiceStopOrShutdown: boolean;
begin
  UpdateStatus := 'DiviPOS Backservice Stop';
  Result := true;
end;

procedure TDiviPOSMainService.SetUpdateStatus(const Value: String);
var
  debugOnly: Boolean;
begin
  FUpdateStatus := Value;
  debugOnly := Pos('[Debug]',Value) > 0;
  UpdateLog(debugOnly);
end;

procedure TDiviPOSMainService.UpdateLog(OnlyDebugMode: boolean);
var
  tmpMsg : String;
begin
  if AllocConsole then
  try
    Writeln;
    writeln(FUpdateStatus);
  finally
    FreeConsole;
  end;

  if ((Not DiviPOSMainService.DebugMode) AND (OnlyDebugMode)) then Exit;

  EnterCriticalSection(DiviPOSMainService.CriticalSection);
  while IsWritingLog do sleep(100);
  CreateLogPerDay('[Import] '+FUpdateStatus);
  LeaveCriticalSection(DiviPOSMainService.CriticalSection);
end;

end.
