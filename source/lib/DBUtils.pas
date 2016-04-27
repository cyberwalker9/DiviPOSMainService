unit DBUtils;



interface

  uses dmService, Uni, UniDacVcl, StrUtils, SysUtils, Vcl.Controls,
       System.Classes, Vcl.Forms, Math, System.JSON;

  function ValidateDatabase: Boolean;
  function GetDBServerVersion(): Integer;
  function UpdateDBServiceVersion(var AVersion: Integer): boolean;

  function InitDBConnection(AOwner: TComponent): Integer;
  function SendPOSTransaction(): boolean;

  procedure LoadParameter();
Const
  AppDBVersion    = 1;
  AppName = 'DiviPOS Backservice';


implementation

uses uMainService, DataSetJSONConverter4D, DiviPOSRestAPI;


function ValidateDatabase: Boolean;
var QInfo : TUniQuery;
    AQuery : String;
begin
  if dmdService.LogConnected then
  begin
    QInfo := TUniQuery.Create(dmdService);
    with QInfo do
    try
      AQuery:= 'SHOW TABLES like ''m_activity'' ';
      OpenLogQuery(AQuery);
      if Eof then
        Exit(false);

      {
      AQuery := 'SELECT app_name FROM z_appparam WHERE app_name = '+QuotedStr(AppName)+'';
      OpenQuery(AQuery);
      if Eof then
        Exit(false);
      }

    finally
      Free;
    end;
    Result := True;
  end;
end;


function GetDBServerVersion(): Integer;
var
  AQuery: string;
  QInfo: TUniQuery;
begin
  QInfo := TUniQuery.Create(nil);
  with QInfo do
  try
    if not dmdService.LogConnected then
    begin
      DiviPOSMainService.UpdateStatus := 'Error Log DB Not Connected';
      Exit(-1);
    end;

    AQuery:= 'SHOW TABLES like ''z_serviceparam'' ';
    OpenLogQuery(AQuery);
    if Eof then
      Exit(0);

    AQuery := 'SELECT app_name FROM z_serviceparam WHERE app_name = '+QuotedStr(AppName)+'';
    OpenLogQuery(AQuery);
    if Eof then
    begin
      AQuery := 'INSERT IGNORE INTO `z_serviceparam` SET '
                   +'`appid`=''DVBackSvc'','
                   +'`app_name`='+QuotedStr(AppName)+','
                   +'`dbversion`=0; ';
      dmdService.ExecLog(AQuery);
    end;

    Result := 0;
    AQuery := 'SELECT dbversion FROM z_serviceparam ' +
              'WHERE app_name = ' + QuotedStr(AppName);
    OpenLogQuery(AQuery);
    if not eof then
      Result := fieldByName('dbversion').asInteger;

  finally
    Free;
  end;

end;

function UpdateDBServiceVersion(var AVersion: Integer): boolean;
var
  AQuery: String;
begin
  case AVersion of
    0:  begin
          AQuery := 'CREATE TABLE IF NOT EXISTS `z_serviceparam` ( '
                   +'  `appid` varchar(20) NOT NULL DEFAULT '''',  '
                   +'  `app_name` varchar(255) NOT NULL DEFAULT ''Next App'', '
                   +'  `dbversion` int(11) unsigned NOT NULL DEFAULT ''0'',  '
                   +'  PRIMARY KEY (`appid`) '
                   +'); ';
          dmdService.ExecLog(AQuery);

          AQuery := 'INSERT IGNORE INTO `z_serviceparam` SET '
                   +'`appid`=''DVBackSvc'','
                   +'`app_name`='+QuotedStr(AppName)+','
                   +'`dbversion`=0; ';
          dmdService.ExecLog(AQuery);

          AQuery := 'CREATE TABLE IF NOT EXISTS `m_resttask` ( '
                   +'  `taskid` varchar(10) COLLATE latin1_swedish_ci NOT NULL DEFAULT '''', '
                   +'  `taskname` varchar(100) COLLATE latin1_swedish_ci NULL DEFAULT NULL, '
                   +'  `direction` tinyint(3) unsigned NOT NULL DEFAULT 0 COMMENT ''0 download 1 upload'', '
                   +'  `restfilename` varchar(255) COLLATE latin1_swedish_ci NULL DEFAULT NULL, '
                   +'  `status` tinyint(3) unsigned NULL DEFAULT 0, '
                   +'  PRIMARY KEY (`taskid`(10)) '
                   +');';
          dmdService.ExecLog(AQuery);
        end;
  end;

  if AppDBVersion > AVersion then
  begin
    AVersion := AVersion + 1;
    AQuery := 'UPDATE z_serviceparam SET dbversion = ' +
      QuotedStr(IntToStr(AVersion));
    dmdService.ExecLog(AQuery);

    //Application.ProcessMessages;
    Result := true;
  end;

end;

function InitDBConnection(AOwner: TComponent): Integer;
var
  ConfigPath : String;
  AMsg: string;
  ConfigExists: Boolean;
  CurrDBVersion: Integer;
  RunAPP: Boolean;
begin
  //detecting

  ConfigPath := DiviPOSMainService.PAppPath + 'Shogun.dbs';

  ConfigExists := FileExists(ConfigPath);
  AMsg := '';
  if not ConfigExists then
    AMsg := ' not';

  DiviPOSMainService.UpdateStatus := 'Config Path :'+ConfigPath+AMsg+' Found';

  if not ConfigExists then exit(1);

  if not Assigned(dmdService) then
  try
    dmdService := TdmdService.Create(AOwner);
  except
    on e : Exception do
    DiviPOSMainService.UpdateStatus := 'Error '+e.Message;
  end;

  dmdService.PathToConfig := ConfigPath;

  if not dmdService.ConnectMaster then
  begin
    DiviPOSMainService.UpdateStatus := 'Connect Master Failed';
    exit(2);
  end;

  if not dmdService.ConnectLog then
  begin
    DiviPOSMainService.UpdateStatus := 'Connect Log Failed';
    exit(3);
  end;

  DiviPOSMainService.UpdateStatus := 'Database Successfull connected';

  if not ValidateDatabase then exit(4);

  RunAPP := true;
  CurrDBVersion := GetDBServerVersion;
  DiviPOSMainService.UpdateStatus := 'Database Version is '+CurrDBVersion.ToString;
  while (AppDBVersion > CurrDBVersion) AND RunAPP do
  begin
    DiviPOSMainService.UpdateStatus := 'Updating database ver.'+CurrDBVersion.ToString;
    RunApp := UpdateDBServiceVersion(CurrDBVersion);
    CurrDBVersion := GetDBServerVersion;
  end;
  DiviPOSMainService.UpdateStatus := 'Current Database Version is '+CurrDBVersion.ToString;

  Result := ifthen(runAPP,0,5);
end;

function SendPOSTransaction():boolean;
var
  AQuery: string;
  QTableLog: TUniQuery;
  QTableYPOS, QTableYPOSDetail: TUniQuery;
  strQuery: String;
  vJSONArray: TJSONArray;
  JSonMaster, JSonDetail : String;
  capturedTime : String;
  isPOSTSuccess: Boolean;
  TableList: TStringList;
  I: integer;
  JsonString: String;
  JSonCardDetail: string;
const
  ASelectQuery = 'SELECT %s as branchid, kassa, refdoc  FROM %s '
                +' WHERE stasend = 0 '
                +' AND transid = 20 '
                +' AND log_timestamp < %s ';

  AUpdateQuery = ' UPDATE %s '
                +' SET stasend = 1 '
                +' WHERE stasend = 0 '
                +' AND transid = 20 '
                +' AND log_timestamp < %s ';
begin
  try
    capturedTime := DateTimeToStr(now);
    DiviPOSMainService.UpdateStatus := '[Debug] Captured Time : ' + capturedTime;


    QTableLog         := TUniQuery.Create(dmdService);
    with QTableLog do
    try
      AQuery := 'SHOW TABLES '
               +' WHERE Tables_in_divipos_log >= CONCAT(''userlog_'',YEAR(DATE_SUB(NOW(), INTERVAL 1 MONTH)), RIGHT(LPAD(MONTH(DATE_SUB(NOW(), INTERVAL 1 MONTH)),2,''0''),2)) '
               +' AND Tables_in_divipos_log like ''userlog%''  ';
      OpenLogQuery(AQuery);

      if RecordCount <= 0 then Exit;

      TableList := TStringList.Create;
      strQuery := '';
      while not Eof do
      begin
        TableList.Add(Fields[0].AsString);
        if not strQuery.IsEmpty then
          strQuery := strQuery + ' UNION ';
        strQuery := strQuery + format(ASelectQuery,[QuotedStr(DiviPOSMainService.BranchID), dmdService.DBLogName+'.'+Fields[0].AsString, QuotedStr(capturedTime)]);
        Next;
      end;

      {Query Master y_pos}
      AQuery := 'SELECT * FROM '+dmdService.DBName+'.y_pos WHERE (branchid, kassa, strukno) in '
               +'('
               +strQuery
               +') ORDER BY branchid, kassa, strukno, strukdate ';
      OpenLogQuery(AQuery);
      DiviPOSMainService.UpdateStatus := '[Debug] Selected Record : ' + QTableLog.RecordCount.ToString();

      if QTableLog.Eof then Exit(false);

      vJSONArray := Converter.DataSet(QTableLog).AsJSONArray;

      //DiviPOSMainService.UpdateStatus := vJSONArray.ToString;
      JSonMaster := vJSONArray.ToString;

      {Query detail y_pos_detail}
      AQuery := 'SELECT * FROM '+dmdService.DBName+'.y_pos_detail WHERE (branchid, kassa, strukno) in '
               +'('
               +strQuery
               +') ORDER BY branchid, kassa, strukno ';
      OpenLogQuery(AQuery);
      DiviPOSMainService.UpdateStatus := '[Debug] Selected Record : ' + QTableLog.RecordCount.ToString();

      JSonDetail := '';
      if not QTableLog.Eof then
      begin
        vJSONArray := Converter.DataSet(QTableLog).AsJSONArray;
        JSonDetail := vJSONArray.ToString;
      end;

      {Query detail y_poscard_detail}
      AQuery := 'SELECT * FROM '+dmdService.DBName+'.y_poscard_detail WHERE (branchid, kassa, strukno) in '
               +'('
               +strQuery
               +') ORDER BY branchid, kassa, strukno ';
      OpenLogQuery(AQuery);
      DiviPOSMainService.UpdateStatus := '[Debug] Selected Record : ' + QTableLog.RecordCount.ToString();

      JSonCardDetail := '';
      if not QTableLog.Eof then
      begin
        vJSONArray := Converter.DataSet(QTableLog).AsJSONArray;
        JSonCardDetail := vJSONArray.ToString;
        if not JSonCardDetail.IsEmpty then
          JSonCardDetail := ', "y_poscard_detail":'+JSonCardDetail;

      end;



      DiviPOSMainService.UpdateStatus := '[Debug] '+JSonMaster;
      DiviPOSMainService.UpdateStatus := '[Debug] '+JSonDetail;
      DiviPOSMainService.UpdateStatus := '[Debug] '+JSonCardDetail;

      JsonString := '{"y_pos":'+JSonMaster+', "y_pos_detail":'+JSonDetail+''+JSonCardDetail+'}';

      //call API Interface to Web Server
      isPOSTSuccess := PostJson('post_postest',JsonString);

      DiviPOSMainService.UpdateStatus := '[Debug] PostTest Return : '+isPOSTSuccess.ToString();
      {Update stasend}
      if isPOSTSuccess then
      for I := 0 to TableList.Count-1 do
      begin
        DiviPOSMainService.UpdateStatus := '[Debug] '+Format(AUpdateQuery,[TableList[I], QuotedStr(capturedTime)]);
        dmdService.ExecLog(Format(AUpdateQuery,[TableList[I], QuotedStr(capturedTime)]));
      end;

    finally
      TableList.Free;
      Free;
    end;
  except
    on e : exception do
      DiviPOSMainService.UpdateStatus := e.Message;
  end;
end;

procedure LoadParameter();
var
  AQuery: string;
  QParameter: TUniQuery;
begin
  try
    DiviPOSMainService.UpdateStatus := 'Load parameter';
    QParameter := TUniQuery.Create(dmdService);
    with QParameter do
    try
      AQuery := 'SELECT shopid, web_host FROM m_setupparameter ';
      OpenQuery(AQuery);

      if not Eof then
        with DiviPOSMainService do
        begin
          BranchID := FieldByName('shopid').AsString;
          URLAddress := FieldByName('web_host').AsString;
          DiviPOSMainService.UpdateStatus := 'Load parameter Success : Branchid = '+BranchID+' URLAddress = '+URLAddress;
        end;

    finally
      free;
    end;
  except on E: Exception do
    DiviPOSMainService.UpdateStatus := e.Message;
  end;

end;

end.