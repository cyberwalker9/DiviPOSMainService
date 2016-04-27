unit AppUtils.Tools;

interface

  uses SysUtils, Classes, Windows, Vcl.Menus, stdCtrls, StrUtils,
  controls, RzEdit, RzCmboBx, DB, Uni, forms, zlib, shellapi, IOUtils,
  winAPI.Messages, dToast, dProgressMsg, Math, Graphics;

  Type
     TExec = procedure of object;
     TExecS = procedure;

     FileInfoPtr = ^FileInfoRec;
     FileInfoRec = record
       fName    : string;
       typ      : byte;
       Modified : TDateTime;
     end;

     TProgressRead = class
     private
       FMsgtext: string;
       FTotalRead: Cardinal;
       FOnProgress: TExec;
       FPercentProgress: cardinal;
       FMaxProgress: cardinal;
       procedure SetMsgtext(const Value: string);
       procedure SetReadProgress(const Value: Cardinal);
       procedure SetOnProgress(const Value: TExec);
       procedure SetPercentProgress(const Value: cardinal);
       procedure SetMaxProgress(const Value: cardinal);
     public
       property MaxProgress : cardinal read FMaxProgress write SetMaxProgress;
       property OnProgress: TExec read FOnProgress write SetOnProgress;
       property Msgtext : string read FMsgtext write SetMsgtext;
       property TotalRead : Cardinal read FTotalRead;
       property ReadProgress : Cardinal write SetReadProgress;
       property PercentProgress : cardinal read FPercentProgress write SetPercentProgress;
     end;

     {Filtering }
     TFieldFilter = packed record
       FieldName : String;
       Caption   : String;
       FieldType : TFieldType;
     end;
     TArFieldFilter = array of TFieldFilter;

     TRegisteredComp = class
     private
        fControl: TControl;
        fowndproc: TWndMethod;

        FOnChange: TExec;
        procedure HookWndProc(var Message: TMessage);
        procedure SetOnChange(const Value: TExec);
        procedure DoOnChange;
     public
        constructor Create( c: TControl );
        destructor Destroy; override;
     published
        property OnChangeSender:TExec read FOnChange write SetOnChange;
     end;

     TFocusObserver = class
     private
        l: TList;
        FOnChange: TExec;
        procedure SetOnChange(const Value: TExec);
        procedure DoOnChange;
     public
       constructor Create;
       destructor Destroy; override;
       procedure reg( c: TControl );
     published
        property OnChangeSender:TExec read FOnChange write SetOnChange;
     end;

     TToastUtils = class(TThread)
     private
        DToast : TdlgToast;
        FAMsg: String;
        procedure SetAMsg(const Value: String);
     public
        constructor Create(CreateSuspended:Boolean);
        procedure Execute; override;
        property AMsg : String read FAMsg write SetAMsg;
        procedure ToastNow(AMsg : String);
     end;

  const
     FL_FOLDER      = 1;
     FL_FILE        = FL_FOLDER + 1;

     { File Date Types   }
     FD_CREATED     = 1;
     FD_ACCESSED    = FD_CREATED + 1;
     FD_MODIFIED    = FD_ACCESSED + 1;

     cNL = #13#10;

     DBBackUpExt = '.zBAK';
     DBUpdateExt = '.up';

     cHTMLMenuBtn      = '<BODY Background="%s"><p>';
     cHTMLNewLine      =  '<br>';
     cHTMLSoldOut      =  '<IND x="75"><FONT Color="clRed"><b>Sold Out</b></font><br>';
     cHTMLCount        =  '<IND x="75"><FONT Color="clRed"><b>%s left</b></font><br>';
     cHTMLMenuName     =  '<IND x="75"><b>%s</b><br>';
     cHTMLStrikePrice  =  '<IND x="75"><b><font color="#FF8000"><s>%s</s></font></b><br>';
     cHTMLPrice        =  '<IND x="75"><b><font color="#FF8000">%s</font></b><br>';
     cHTMLMenuBtnEnd   = '</p>';


  procedure CreateFolderPath(APathFolder : String);
  procedure GetDirList(const dir : String;var AStringList : TStringList;const recursive : Boolean;const AExt : String = '.bzip');
  procedure SetLangPopUp(APopupMenu : TPopupMenu);
  function GetLangSelected():String;
  procedure LangPopup_Click(Sender: TObject);

  {Form Utils}
  procedure SetComboField(ACb : TRzComboBox;AList : TArFieldFilter);
  procedure CBChange(ACB : TRzComboBox; AList : TArFieldFilter; AQQuery : TUniQuery;AText : TRzEdit; ADate : TRzDateTimeEdit; ANum : TRzNumericEdit);
  procedure GetLookupID(LookupClassName:String; var AID, ADescr : String; var AModalResult : TModalResult);
  {console utils}
  procedure GetDosOutput(var AString :TProgressRead; CommandLine: string; Work: string = 'C:\');
  procedure ShellOpenFile(FilePathName : String; AParameter : String = ''; AWorkDir : String = '';AShowCmd : Boolean = true);
  function GetHardDiskSerial(const DriveLetter: Char): string;
  function GetFileTimes(FileName : String; typ : byte; var fDate : TDateTime) : Boolean;

  {Compression Utils}
  function CompressZIP(AFileSource : String):string;
  function DecompressZIP(AFileSource : String):string;

  {System Info Utils}
  function SetOnCorectPath(ASource: string; ATarget: string):string;
  function Is64BitWindows: boolean;

  function GetMenuCaption(ABackground, AMenuName, AOriPrice :string; ADiscPrice : string = ''; AServeCount:integer = 99):string;
  procedure Toast(AToastMsg : string);

  {ACR120 Utils}
  function ErrDef(ErrorCode:smallint):string;
  Function StrHEX_Dec(StrHex: char) : Integer;
  Function Hex_Dec(val: TEdit): Byte;
  function GetTagType1(GetTagTypeA: Byte):string;


  var
    sto: Longint;
    LogType: Byte;
    acrHandle: smallint;
    retcode: smallint;
    SID: Byte;
    Sec:smallint;
    pKey: array[0..5] of Byte;
    dataRead: array[0..15] of Byte;
    dout: array[0..15] of byte;
    str: String;
    BLCK: Byte;
    ReadAsc: boolean;
    WriteAsc: boolean;
    PhysicalSector: smallint;


implementation

uses AppUtils, fMain, ImageUtils;

procedure CreateFolderPath(APathFolder : String);
begin
  if not DirectoryExists(APathFolder) then
  if not CreateDir(APathFolder) then
  raise EAppException.CreateFmt(LangRes['CannotCreateFolder'],[APathFolder]);
end;

function GetFileTimes(FileName : String; typ : byte; var fDate : TDateTime) : Boolean;
var
  fHandle : Integer;
  fTimeC,
  fTimeA,
  fTimeM : TFileTime;
  lTime  : TFileTime;
  sTime  : TSystemTime;
begin { GetFileTimes }
  fHandle := FileOpen(FileName, fmShareDenyNone);
  fDate := 0.0;
  result := (fHandle >= 0);
  if result
  then begin GetFileTime(fHandle, @fTimeC, @fTimeA, @fTimeM);
             FileClose(fHandle);
             case typ of
              FD_CREATED  : FileTimeToLocalFileTime(fTimeC, lTime);
              FD_ACCESSED : FileTimeToLocalFileTime(fTimeA, lTime);
              FD_MODIFIED : FileTimeToLocalFileTime(fTimeM, lTime);
             end;
             if FileTimeToSystemTime(lTime, sTime)
              then fDate := EncodeDate(sTime.wYear, sTime.wMonth, sTime.wDay) + EncodeTime(sTime.wHour, sTime.wMinute, sTime.wSecond, sTime.wMilliSeconds);
       end;
end; { of GetFileTimes }

procedure GetDirList(const dir : String;var AStringList : TStringList;const recursive : Boolean;const AExt : String = '.bzip');
var
  fsRec : TSearchRec;
  //fIPtr : FileInfoPtr;
begin { GetDirList }
  if (dir = '')
    then Exit;
  try
    try
       if (FindFirst(IncludeTrailingPathDelimiter(dir) + '*.*', faAnyFile, fsRec) = 0) then
       repeat
          if (fsRec.Name <> '') AND (fsRec.Name <> '.') AND (fsRec.Name <> '..') then
          begin
            //fIPtr := AllocMem(SizeOf(FileInfoRec));
            //fIPtr^.fName := dir + fsRec.Name;
            //GetFileTimes(dir + fsRec.Name, FD_MODIFIED, fIPtr^.Modified);
            if ((fsRec.Attr AND faDirectory) = faDirectory) then
            begin
              //fIPtr^.typ := FL_FOLDER;
              //List.Insert(0, fIPtr);
              if recursive then
                GetDirList(IncludeTrailingPathDelimiter(dir) + fsRec.Name, AStringList, TRUE);
            end;
            //else
            //begin
              //fIPtr^.typ := FL_FILE;
              //List.Add(fIPtr);
            //end;
            if ExtractFileExt(fsRec.Name) = AExt then
               AStringList.Add(fsRec.Name);
          end;
       until (FindNext(fsRec) <> 0);
       SysUtils.FindClose(fsRec);
    except

    end;
  finally
    //FreeMem(fIPtr);
    {if Assigned(fIPtr) then
      FreeAndNil(fIPtr);}
  end;
end; { of GetDirList }

procedure LangPopup_Click(Sender: TObject);
begin
  if Sender.ClassType = TMenuItem then
  begin
    frmMain.btnLang.Caption := TMenuItem(Sender).Caption;
    { TODO -cLanguange :
      1. save lang used,
      2. Refresh form change text
      identifier TMenuItem(Sender).tag and langlist
     }
  end;
end;

function ParseLangName(ALangFileName : String):String;
begin
  result := ReplaceStr(ReplaceStr(ALangFileName,'.lang',''),'_',' ');
end;

function GetLangSelected():String;
begin
  Result := 'Bahasa Indonesia';
  if AppMgmt.LangList.IndexOf(AppConfig['lang']) > -1 then
    Result := ParseLangName(AppMgmt.LangList[AppMgmt.LangList.IndexOf(AppConfig['lang'])]);
end;

procedure SetLangPopUp(APopupMenu : TPopupMenu);
var I : Integer;
    AMenu : TMenuItem;
begin
  if Assigned(APopupMenu.Items) then APopupMenu.Items.Clear;
  for I := 0 to AppMgmt.LangList.Count-1 do
  begin
    AMenu := TMenuItem.Create(APopupMenu);
    AMenu.Name := 'langlist'+inttostr(I);
    AMenu.Caption := ParseLangName(AppMgmt.LangList[I]);
    AMenu.OnClick := frmMain.LangPopup_Click;
    AMenu.Tag := I;
    APopupMenu.Items.Add(AMenu);
  end;
end;

procedure SetComboField(ACb : TRzComboBox;AList : TArFieldFilter);
var I : Integer;
begin
  with ACb do
  begin
    ACb.Clear;
    ACb.Items.Add('');
    for I := 0 to Length(Alist)-1 do
    begin
      ACb.Items.Add(AList[I].Caption);
    end;
  end;
end;

procedure CBChange(ACB : TRzComboBox; AList : TArFieldFilter; AQQuery : TUniQuery;AText : TRzEdit; ADate : TRzDateTimeEdit; ANum : TRzNumericEdit);
var I : Integer;
    TmpFieldName : String;
begin

  if ACB.Text <> '' then
  begin
    AText.Visible := false;
    ANum.Visible := false;
    ADate.Visible := false;

    ADate.Date := now;

    // find Grid FieldName By Captioned
    I := 0;
    while I < Length(Alist)-1 do
    begin
      if AList[I].Caption = ACB.Text then
      begin
         TmpFieldName := AList[I].FieldName;
      end;
      INC(I);
    end;
    //

    if AQQuery.Fields.FieldByName(AList[ACB.itemIndex-1].FieldName).DataType in [ftDate, ftTime, ftDateTime] then
    begin
      ADate.Visible := true;
      ADate.Date := now;
    end
    else
    if AQQuery.Fields.FieldByName(AList[ACB.itemIndex-1].FieldName).DataType in [ftSmallint,ftInteger,ftWord,ftFloat,ftCurrency] then
    begin
      ANum.Visible := true;
    end
    else
    begin
      AText.Visible := true;
    end;
  end;
end;

procedure GetLookupID(LookupClassName:String; var AID, ADescr : String; var AModalResult : TModalResult);
var
  AClass : TClass;
begin

end;

procedure GetDosOutput(var AString :TProgressRead; CommandLine: string; Work: string = 'C:\');
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  StdOutPipeRead, StdOutPipeWrite: THandle;
  WasOK: Boolean;
  Buffer: array[0..255] of AnsiChar;
  BytesRead: Cardinal;
  WorkDir: string;
  Handle: Boolean;
begin
  with SA do begin
    nLength := SizeOf(SA);
    bInheritHandle := True;
    lpSecurityDescriptor := nil;
  end;
  CreatePipe(StdOutPipeRead, StdOutPipeWrite, @SA, 0);
  try
    with SI do
    begin
      FillChar(SI, SizeOf(SI), 0);
      cb := SizeOf(SI);
      dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
      wShowWindow := SW_HIDE;
      hStdInput := GetStdHandle(STD_INPUT_HANDLE); // don't redirect stdin
      hStdOutput := StdOutPipeWrite;
      hStdError := StdOutPipeWrite;
    end;
    WorkDir := Work;
    Handle := CreateProcess(nil, PChar('cmd.exe /C ' + CommandLine),
                            nil, nil, True, 0, nil,
                            PChar(WorkDir), SI, PI);
    CloseHandle(StdOutPipeWrite);
    if Handle then
      try
        repeat
          WasOK := ReadFile(StdOutPipeRead, Buffer, 255, BytesRead, nil);
          if BytesRead > 0 then
          begin
            Buffer[BytesRead] := #0;
            AString.Msgtext := Buffer;
            AString.ReadProgress := BytesRead;
            Application.ProcessMessages;
          end;
        until not WasOK or (BytesRead = 0);
        WaitForSingleObject(PI.hProcess, INFINITE);
      finally
        CloseHandle(PI.hThread);
        CloseHandle(PI.hProcess);
      end;
  finally
    CloseHandle(StdOutPipeRead);
  end;
  AString.FMsgtext := 'Done.';
end;


function CompressZIP(AFileSource : String):string;
var
  ATargetFile: String;
  LInput, LOutput: TFileStream;
  LZip: TZCompressionStream;
begin
  if FileExists(AFileSource) then
  begin
    { Create the Input, Output, and Compressed streams. }
    ATargetFile := AFileSource + DBBackUpExt;
    LInput := TFileStream.Create(AFileSource, fmOpenRead);
    LOutput := TFileStream.Create(ATargetFile, fmCreate);
    LZip := TZCompressionStream.Create(LOutput);
    try
      { Compress data. }
      LZip.CopyFrom(LInput, LInput.Size);
    finally
      { Free the streams. }
      LZip.Free;
      LInput.Free;
      LOutput.Free;

      DeleteFile(PChar(AFileSource));
    end;
    Result := ATargetFile;
  end;
end;

function DecompressZIP(AFileSource : String):string;
var
  LInput, LOutput: TFileStream;
  LUnZip: TZDecompressionStream;
  ATargetFile: String;
begin
  { Create the Input, Output, and Decompressed streams. }
  ATargetFile := ChangeFileExt(AFileSource, '');
  LInput := TFileStream.Create(AFileSource, fmOpenRead);
  LOutput := TFileStream.Create(ATargetFile, fmCreate);
  LUnZip := TZDecompressionStream.Create(LInput);
  try
    { Decompress data. }
    LOutput.CopyFrom(LUnZip, 0);
  finally
    { Free the streams. }
    LUnZip.Free;
    LInput.Free;
    LOutput.Free;
  end;
  Result := ATargetFile;
end;


procedure ShellOpenFile(FilePathName : String; AParameter : String = ''; AWorkDir : String = '';AShowCmd : Boolean = true);
var errorcode : Integer;
    AParPointer : Pointer;
    AWorkDirPointer : Pointer;
    AShowCmdInt : Integer;
begin
   if AParameter = '' then
     AParPointer := nil
   else
     AParPointer := PCHAR(AParameter);

   if AWorkDir = '' then
     AWorkDirPointer := nil
   else
     AWorkDirPointer := PCHAR(AWorkDir);

   if AShowCmd then
     AShowCmdInt := SW_NORMAL
   else
     AShowCmdInt := SW_HIDE;

   errorcode := ShellExecute(0,'open',PCHAR(FilePathName),AParPointer,AWorkDirPointer,AShowCmdInt);
   case errorcode of
    2: AppMgmt.ShowInfoMsg('file not found');
    3: AppMgmt.ShowInfoMsg('path not found');
    5: AppMgmt.ShowInfoMsg('access denied');
    8: AppMgmt.ShowInfoMsg('not enough memory');
    32: AppMgmt.ShowInfoMsg('dynamic-link library not found');
    26: AppMgmt.ShowInfoMsg('sharing violation');
    27: AppMgmt.ShowInfoMsg('filename association incomplete or invalid');
    28: AppMgmt.ShowInfoMsg('DDE request timed out');
    29: AppMgmt.ShowInfoMsg('DDE transaction failed');
    30: AppMgmt.ShowInfoMsg('DDE busy');
    31: AppMgmt.ShowInfoMsg('no application associated with the given filename extension');
   end;
end;

function GetHardDiskSerial(const DriveLetter: Char): string;
var
  NotUsed:     DWORD;
  VolumeFlags: DWORD;
  VolumeInfo:  array[0..MAX_PATH] of Char;
  VolumeSerialNumber: DWORD;
begin
  GetVolumeInformation(PChar(DriveLetter + ':\'),
    nil, SizeOf(VolumeInfo), @VolumeSerialNumber, NotUsed,
    VolumeFlags, nil, 0);
  Result := Format('%8.8X', [VolumeSerialNumber])
end;

function IsOnCorectPath(ASource: string; ATarget: string):boolean;
var
  ExpandedPath : string;
  ExpandedTarget : string;
begin
  ExpandedPath := ExtractFilePath(ExpandUNCFileName(ASource));
  ExpandedTarget := ExtractFilePath(ExpandUNCFileName(ATarget));
  Result := CompareText(LeftStr(ExpandedPath,Length(ExpandedTarget)),ExpandedTarget) = 0;
end;

function SetOnCorectPath(ASource: string; ATarget: string):string;
{
  return new Corect Path + filename
}
var
  AFileName : String;
begin
  AFileName := ExtractFileName(ASource);
  if not IsOnCorectPath(ASource,ATarget) then
  begin
    AFileName := ExtractFileName(ASource);
    {copy folder to ATargetFolder}
    try
      if FileExists(ATarget+AFileName) then
        AppMgmt.ShowInfoMsg(LangRes['FileExists']);

      if not FileExists(ATarget+AFileName) then
      begin
        //TFile.Copy(ASource,ATarget+AFileName,false);
        ResizeBitmap2(ASource,ATarget+AFileName,72,72,True);
        {  //ResizeImage(ASource,ATarget+AFileName,72,72,clWhite,itBMP);
        if (ExtractFileExt(ASource) = '.jpg') OR (ExtractFileExt(ASource) = '.jpeg') then
        begin
          ResizeBitmap2(ATarget+AFileName,ATarget+AFileName,72,72,True);

          ResizeImage(ASource,ATarget+AFileName,72,72,clWhite,itJPG);

        end;
        if ExtractFileExt(ASource) = '.png' then
          ResizeImage(ASource,ATarget+AFileName,72,72,clWhite,itPNG);
          }
      end;
    finally
      //AppMgmt.ShowInfoMsg('Gagal Copy File, Pastikan Folder tujuan dapat di akses!');
    end;
  end;
  AFileName := ChangeFileExt(AFileName,'.bmp');
  Result := ATarget+AFileName;
end;

function Is64BitWindows: boolean;
type
  TIsWow64Process = function(hProcess: THandle; var Wow64Process: BOOL): BOOL;
    stdcall;
var
  DLLHandle: THandle;
  pIsWow64Process: TIsWow64Process;
  WasCalled: BOOL;
  IsWow64: BOOL;
begin
  IsWow64 := false;
  if not WasCalled then begin
    DllHandle := LoadLibrary('kernel32.dll');
    if DLLHandle <> 0 then begin
      pIsWow64Process := GetProcAddress(DLLHandle, 'IsWow64Process');
      if Assigned(pIsWow64Process) then
        pIsWow64Process(GetCurrentProcess, IsWow64);
      WasCalled := True;
      FreeLibrary(DLLHandle);
    end;
  end;
  Result := IsWow64;
end;

{}

constructor TFocusObserver.Create;
begin
  l := TList.Create;
end;

destructor TFocusObserver.Destroy;
var i: integer;
begin
  for i := 0 to l.Count - 1 do
    TRegisteredComp(l[i]).Free;
  l.Free;
  inherited;
end;

procedure TFocusObserver.reg( c: TControl );
var
  rc: TRegisteredComp;
begin
  rc := TRegisteredComp.Create( c );
  rc.OnChangeSender := FOnChange;
  l.Add( rc );
end;

constructor TRegisteredComp.Create(c: TControl);
begin
  fControl := c;
  fowndproc := c.WindowProc;
  c.WindowProc := HookWndProc;
end;

destructor TRegisteredComp.Destroy;
begin
  fControl.WindowProc := fowndproc;
  inherited;
end;

procedure TRegisteredComp.DoOnChange;
begin
  if assigned(FOnChange) then
    FOnChange;
end;

procedure TFocusObserver.DoOnChange;
begin
  if Assigned(OnChangeSender) then
    OnChangeSender;
end;

procedure TRegisteredComp.HookWndProc(var Message: TMessage);
begin
  if ( Message.Msg = CM_FOCUSCHANGED ) and
    ( TControl(Message.LParam) = fControl ) then
    begin
      wcGlobalActive := fControl;
    end;
  fowndproc( Message );
end;

procedure TRegisteredComp.SetOnChange(const Value: TExec);
begin
  FOnChange := Value;
end;

procedure TFocusObserver.SetOnChange(const Value: TExec);
begin
  FOnChange := Value;
end;


{ TProgressRead }

procedure TProgressRead.SetMaxProgress(const Value: cardinal);
begin
  FMaxProgress := Value;
end;

procedure TProgressRead.SetMsgtext(const Value: string);
begin
  FMsgtext := Value;
  if assigned(OnProgress) then
    OnProgress;
end;

procedure TProgressRead.SetOnProgress(const Value: TExec);
begin
  FOnProgress := Value;
end;

procedure TProgressRead.SetPercentProgress(const Value: cardinal);
begin
  FPercentProgress := Value;
end;

procedure TProgressRead.SetReadProgress(const Value: Cardinal);
begin
  FTotalRead := FTotalRead + Value;
  if MaxProgress > 0 then
    PercentProgress :=  round((FTotalRead / MaxProgress) * 100);
end;

function GetMenuCaption(ABackground, AMenuName, AOriPrice :string; ADiscPrice : string = ''; AServeCount:integer = 99):string;
var
  tmpMenuName : String;
begin
  Result := Format(cHTMLMenuBtn,[ABackground]);
  {soldout / Count}
  if AServeCount >= 99 then
  Result := Result + cHTMLNewLine
  else
  if AServeCount <= 0 then
  Result := Result + cHTMLSoldOut
  else
  Result := Result + Format(cHTMLCount,[IntToStr(AServeCount)]);
  {menuname}

  tmpMenuName := WrapText(AMenuName,'|',[' '],15);
  tmpMenuName := ReplaceStr(tmpMenuName,'|','<br><IND x="75"><b>');
  Result := Result + Format(cHTMLMenuName,[tmpMenuName]);

  {price}
  if ADiscPrice = AOriPrice then
  Result := Result + Format(cHTMLPrice,[AOriPrice]) else
  Result := Result + Format(cHTMLStrikePrice,[AOriPrice])
            + Format(cHTMLPrice,[ADiscPrice]);
end;

procedure Toast(AToastMsg : string);
begin
  AppMgmt.ShowInfoMsg(AToastMsg);
  //frmMain.HintsPanel.Caption := AToastMsg;
  {with TToastUtils.Create(True) do
  try
    AMsg := AToastMsg;
    Resume;
  except
    //Free;
  end;}
end;

{ TToastUtils }

constructor TToastUtils.Create(CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);
  Self.FreeOnTerminate := True;
end;

procedure TToastUtils.Execute;
begin
  inherited;
  DToast := TdlgToast.Create(Application);
  ToastNow(AMsg);
end;

procedure TToastUtils.SetAMsg(const Value: String);
begin
  FAMsg := Value;
end;

procedure TToastUtils.ToastNow(AMsg: String);
var
  I : Integer;
begin
  with DToast do
  try
    Height := 40;
    ToastMsg := AMsg;
    AlphaBlendValue := 0;
    Show;
    Top := Screen.Height - Height - 55;
    Left := Ceil((Screen.Width - Width)/2);
    for I := 1 to 50 do
    begin
      if Assigned(DToast) then
        AlphaBlendValue := AlphaBlendValue + 5;
      Sleep(10);
      Application.ProcessMessages;
    end;
  finally
    UpMoment := Time;
    while ((Moment-UpMoment)*86400<2) do
    begin
      Moment := Time;
      Application.ProcessMessages;
    end;
    for I := 1 to 50 do
    begin
      if Assigned(DToast) then
        AlphaBlendValue := AlphaBlendValue - 5;
      Sleep(10);
      Application.ProcessMessages;
    end;
    if Assigned(DToast) then
      AlphaBlendValue := 0;
    //Close;
    if Assigned(DToast) then
    try
      FreeAndNil(DToast);
      Application.ProcessMessages;
    except

    end;
  end;
end;

{ACR120 Utils}

function ErrDef(ErrorCode:smallint):string;

begin

     case ErrorCode of
          -1000: ErrDef := '( X ) Unexpected Internal Library Error : -1000';
          -2000: ErrDef := '( X ) Invalid Port : -2000';
          -2010: ErrDef := '( X ) Port Occupied by Another Application : -2010';
          -2020: ErrDef := '( X ) Invalid Handle : -2020';
          -2030: ErrDef := '( X ) Incorrect Parameter : -2030';
          -3000: ErrDef := '( X ) No TAG Selected or in Reachable Range : -3000';
          -3010: ErrDef := '( X ) Read Failed after Operation : -3010';
          -3020: ErrDef := '( X ) Block does not contain value : -3020';
          -3030: ErrDef := '( X ) Operation Failed : -3030';
          -3040: ErrDef := '( X ) Unknown Reader Error : -3040';
          -4010: ErrDef := '( X ) Invalid stored key format in login process : -4010';
          -4020: ErrDef := '( X ) Reader cannot read after write operation : -4020';
          -4030: ErrDef := '( X ) Decrement Failure (Empty) : -4030';
     end;

end;


//'======================================================
//'  Routine for converting Hex Significant Byte value
//'  to it's Decimal value.
//'======================================================
Function StrHEX_Dec(StrHex: char) : Integer;
begin

      Case ord(StrHex) of
        ord('0'):  StrHEX_Dec := 0;
        ord('1'):  StrHEX_Dec := 1;
        ord('2'):  StrHEX_Dec := 2;
        ord('3'):  StrHEX_Dec := 3;
        ord('4'):  StrHEX_Dec := 4;
        ord('5'):  StrHEX_Dec := 5;
        ord('6'):  StrHEX_Dec := 6;
        ord('7'):  StrHEX_Dec := 7;
        ord('8'):  StrHEX_Dec := 8;
        ord('9'):  StrHEX_Dec := 9;
        ord('A'):  StrHEX_Dec := 10;
        ord('B'):  StrHEX_Dec := 11;
        ord('C'):  StrHEX_Dec := 12;
        ord('D'):  StrHEX_Dec := 13;
        ord('E'):  StrHEX_Dec := 14;
        ord('F'):  StrHEX_Dec := 15;
      end;

End;




Function GetTagType1(GetTagTypeA: Byte) : string;

begin

      //Function that explains the value of the TAGTYPE of the Card.
      Case GetTagTypeA of
         1: GetTagType1 := 'Mifare Light';
         2: GetTagType1 := 'Mifare 1K';
         3: GetTagType1 := 'Mifare 4K';
         4: GetTagType1 := 'Mifare DESFire';
         5: GetTagType1 := 'Mifare Ultralight';
         6: GetTagType1 := 'JCOP30';
         7: GetTagType1 := 'Shanghai Transport';
         8: GetTagType1 := 'MPCOS Combi';
         128: GetTagType1 := 'ISO Type B, Calypso';

    end;

End;



//'======================================================
//'  Routine for converting Hex to Decimal value.
//'======================================================

Function Hex_Dec(val: TEdit): Byte;
var
MSB: Byte;
LSB: Byte;
Fbyte: Byte;
begin
              Fbyte := 0;
              MSB := 0;
              LSB := 0;

              MSB := StrHEX_Dec(val.Text[1]);
              LSB := StrHEX_Dec(val.Text[2]);
              Fbyte := (MSB * 16) + LSB;

Hex_Dec := Fbyte;

End;


end.
