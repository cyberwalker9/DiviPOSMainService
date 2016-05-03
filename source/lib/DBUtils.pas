unit DBUtils;



interface

  uses dmService, Uni, UniDacVcl, StrUtils, SysUtils, Vcl.Controls,
       System.Classes, Vcl.Forms, Math, System.JSON, Data.DB, Datasnap.DBClient;

  function ValidateDatabase: Boolean;
  function GetDBServerVersion(): Integer;
  function UpdateDBServiceVersion(var AVersion: Integer): boolean;

  function InitDBConnection(AOwner: TComponent): Integer;
  function SendPOSTransaction(): boolean;
  function ImportFromServer():boolean;

  function GetTokenFromServer():String;
  function GetKitchen(AToken: String):Boolean;
  function GetLocations(AToken: String):Boolean;
  function GetTables(AToken: String):Boolean;
  function GetEDCs(AToken: String):Boolean;
  function GetJabatan(AToken: String):Boolean;
  function GetStaff(AToken: String):Boolean;
  function GetCustomer(AToken: String):Boolean;

  function FinishImport:boolean;

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
  DiviPOSMainService.isExportRun := true;
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
      DiviPOSMainService.UpdateStatus := '[Debug] '+AQuery;
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
      isPOSTSuccess := PostJson('post_pos',JsonString);

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
      DiviPOSMainService.isExportRun := false;
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

function ImportFromServer():boolean;
var
  LJsonObj   : TJSONObject;
  LJsonArray : TJSONArray;
  LJsonValue : TJSONValue;
  Litem      : TJSONValue;
  AJsonValue : string;
  aToken: string;
begin
  //Start Transaction Get Token
  DiviPOSMainService.isImportRun := true;
  try
    try
      aToken := GetTokenFromServer();
      DiviPOSMainService.UpdateStatus := 'Token : '+aToken;
      if aToken = '' then Exit(false);

      if not GetKitchen(aToken) then Exit(false);
      if not GetLocations(aToken) then Exit(false);
      if not GetTables(aToken) then Exit(false);
      if not GetEDCs(aToken) then Exit(false);
      if not GetJabatan(aToken) then Exit(false);
      if not GetStaff(aToken) then Exit(false);
      if not GetCustomer(aToken) then Exit(false);
      FinishImport();

    finally
      DiviPOSMainService.isImportRun := false;
    end;
  except on E: Exception do
    DiviPOSMainService.UpdateStatus := '[Error] ImportFromServer: '+E.Message;
  end;
end;

function GetTokenFromServer():String;
var
  AJsonValue: string;
  aToken: string;
  LJsonObj: TJSONObject;
begin
  aToken := '';
  try
    DiviPOSMainService.UpdateStatus := 'Start Import ';
    AJsonValue := GetJson('start_export/'+DiviPOSMainService.BranchID);
    DiviPOSMainService.UpdateStatus := '[Debug] '+AJsonValue;

    if not (AJsonValue = '') then
    begin
      LJsonObj := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONObject;
      aToken := LJsonObj.Get('hbe_exportedtoken').JsonValue.Value;
    end;
  except on E: Exception do
    DiviPOSMainService.UpdateStatus := '[Error] GetToken: '+E.Message;
  end;
  Result := aToken;
end;

function GetKitchen(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  mkc_code: string;
  mkc_name: string;

  KitchenDataset : TClientDataSet;
  AQuery: String;
begin
  {get kitchen}
  try
    AJsonValue := GetJson('get_kitchens/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] Kitchen : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        KitchenDataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(KitchenDataset, ftString, 'mkc_code',20);
        NewDataSetField(KitchenDataset, ftString, 'mkc_name',50);

        KitchenDataset.DataSetField := nil;
        KitchenDataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(KitchenDataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          AQuery := '';
          with KitchenDataset do
          begin
            First;
            while not Eof do
            begin
              mkc_code := FieldByName('mkc_code').AsString;
              mkc_name := FieldByName('mkc_name').AsString;
              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[mkc_code, mkc_name]);

              AQuery := 'INSERT INTO m_kitchen SET '+
                        ' kitchenid = '+QuotedStr(mkc_code)+', '+
                        ' kitchenname = '+QuotedStr(mkc_name)+' '+
                        ' ON DUPLICATE KEY UPDATE kitchenname = '+QuotedStr(mkc_name);
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;
        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert Kitchen: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetKitchen: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;

function GetLocations(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  mlo_code: string;
  mlo_name: string;
  mlo_seqno: integer;

  LocationsDataset : TClientDataSet;
  AQuery: String;
begin
  {get Lantai}
  try
    AJsonValue := GetJson('get_locations/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] Locations : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        LocationsDataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(LocationsDataset, ftString, 'mlo_code',20);
        NewDataSetField(LocationsDataset, ftString, 'mlo_name',50);
        NewDataSetField(LocationsDataset, ftInteger, 'mlo_seqno');

        LocationsDataset.DataSetField := nil;
        LocationsDataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(LocationsDataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          // truncate old data?
          // tidak karena yang di kirim hanya yang perubahan saja

          with LocationsDataset do
          begin
            First;
            while not Eof do
            begin
              mlo_code := FieldByName('mlo_code').AsString;
              mlo_name := FieldByName('mlo_name').AsString;
              mlo_seqno := FieldByName('mlo_seqno').AsInteger;

              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[mlo_code, mlo_name]);

              AQuery := 'INSERT INTO m_lantai SET '+
                        ' lantaiid = '+QuotedStr(mlo_code)+', '+
                        ' lantainame = '+QuotedStr(mlo_name)+', '+
                        ' seqno = '+QuotedStr(mlo_seqno.ToString)+' '+
                        ' ON DUPLICATE KEY UPDATE lantainame = '+QuotedStr(mlo_name)+', seqno = '+QuotedStr(mlo_seqno.ToString);
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;
        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert Lantai: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetLantai: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;

function GetTables(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  mta_code    : string;
  mta_name    : string;
  mta_location: string;

  TablesDataset : TClientDataSet;
  AQuery: String;
begin
  {get Tables}
  try
    AJsonValue := GetJson('get_tables/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] Tables : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        TablesDataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(TablesDataset, ftString, 'mta_code',20);
        NewDataSetField(TablesDataset, ftString, 'mta_name',50);
        NewDataSetField(TablesDataset, ftString, 'mta_location',20);

        TablesDataset.DataSetField := nil;
        TablesDataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(TablesDataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          AQuery := '';
          //truncate old data?
          //AQuery := 'TRUNCATE m_tables';
          //dmdService.ExecQuery(AQuery);

          with TablesDataset do
          begin
            First;
            while not Eof do
            begin
              mta_code := FieldByName('mta_code').AsString;
              mta_name := FieldByName('mta_name').AsString;
              mta_location := FieldByName('mta_location').AsString;

              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[mta_code, mta_name]);

              AQuery := 'INSERT INTO m_table SET '+
                        ' tableid = '+QuotedStr(mta_code)+', '+
                        ' tablename = '+QuotedStr(mta_name)+', '+
                        ' location = '+QuotedStr(mta_location)+' '+
                        ' ON DUPLICATE KEY UPDATE '+
                        ' tablename = '+QuotedStr(mta_name)+
                        ', location = '+QuotedStr(mta_location);
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;
        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert Tables: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetTables: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;

function GetEDCs(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  med_code    : string;
  med_name    : string;
  med_pcharge : Double;

  TablesDataset : TClientDataSet;
  AQuery: String;

  QCheck : TUniQuery;
  DefaultEDC: String;
  defaultQuery: String;
  gotDefault: boolean;
  CodefirstData: String;
begin
  {get EDC}
  try
    AJsonValue := GetJson('get_edcs/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] EDCs : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        TablesDataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(TablesDataset, ftString, 'med_code',20);
        NewDataSetField(TablesDataset, ftString, 'med_name',50);
        NewDataSetField(TablesDataset, ftFloat, 'med_pcharge');

        TablesDataset.DataSetField := nil;
        TablesDataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(TablesDataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          QCheck := TUniQuery.Create(dmdService);
          AQuery := 'SELECT * FROM m_edc WHERE isDefault = 1 ';
          QCheck.OpenQuery(AQuery);

          gotDefault := false;
          DefaultEDC := '';
          if not QCheck.Eof then
            DefaultEDC := QCheck.FieldByName('edc').AsString;

          //truncate old data?
          //AQuery := 'TRUNCATE m_tables';
          //dmdService.ExecQuery(AQuery);

          with TablesDataset do
          begin
            First;
            while not Eof do
            begin
              med_code := FieldByName('med_code').AsString;
              med_name := FieldByName('med_name').AsString;
              med_pcharge := FieldByName('med_pcharge').AsFloat;

              if CodefirstData = '' then
                 CodefirstData := med_code;

              defaultQuery := '';
              if DefaultEDC.Equals(med_code) then
              begin
                gotDefault := true;
                defaultQuery := ' ,isDefault = 1 ';
              end;

              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[med_code, med_name]);

              AQuery := 'INSERT INTO m_edc SET '+
                        ' edc = '+QuotedStr(med_code)+', '+
                        ' keterangan = '+QuotedStr(med_name)+', '+
                        ' cardcharge = '+QuotedStr(FloatToStr(med_pcharge))+' '+
                        defaultQuery+
                        ' ON DUPLICATE KEY UPDATE '+
                        ' keterangan = '+QuotedStr(med_name)+
                        ', cardcharge = '+QuotedStr(FloatToStr(med_pcharge));
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;

          if (not gotDefault) AND (CodefirstData <> '') then
          begin
            AQuery := 'UPDATE m_edc SET isDefault = 1 WHERE edc = '+QuotedStr(CodefirstData);
            dmdService.ExecQuery(AQuery);
          end;

        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert EDCs: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetEDCs: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;

function FinishImport:boolean;
var
  AJsonValue: string;
begin
  AJsonValue := '';
  DiviPOSMainService.UpdateStatus := 'Finish Import ';
  try
    AJsonValue := GetJson('finish_export/'+DiviPOSMainService.BranchID);
  except on E: Exception do
    DiviPOSMainService.UpdateStatus := 'Finish Import '+E.Message;
  end;
  Result := not (AJsonValue = '[ERROR]');
end;

function GetJabatan(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  mpo_code: string;
  mpo_name: string;

  ADataset : TClientDataSet;
  AQuery: String;
begin
  {get Jabatan}
  try
    AJsonValue := GetJson('get_positions/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] Jabatan : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        ADataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(ADataset, ftString, 'mpo_code',20);
        NewDataSetField(ADataset, ftString, 'mpo_name',50);

        ADataset.DataSetField := nil;
        ADataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(ADataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          AQuery := '';
          with ADataset do
          begin
            First;
            while not Eof do
            begin
              mpo_code := FieldByName('mpo_code').AsString;
              mpo_name := FieldByName('mpo_name').AsString;
              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[mpo_code, mpo_name]);

              AQuery := 'INSERT INTO m_jabatan SET '+
                        ' jabatanid = '+QuotedStr(mpo_code)+', '+
                        ' jabatanname = '+QuotedStr(mpo_name)+' '+
                        ' ON DUPLICATE KEY UPDATE jabatanname = '+QuotedStr(mpo_name);
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;
        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert Jabatan: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetJabatan: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;

function GetStaff(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  mpo_code: string;
  mpo_name: string;

  ADataset : TClientDataSet;
  AQuery: String;

const
  AFields : array[1..16] of string = (
    'mst_code',
    'mst_name',
    'mst_pic',
    'mst_address1',
    'mst_address2',
    'mst_address3',
    'mst_phone',
    'mst_fax',
    'mst_hp',
    'mst_email',
    'mst_birthdate',
    'mst_idcard',
    'mst_idtax',
    'mst_position',
    'mst_gender',
    'mst_active');

begin
  {get Staff}
  try
    AJsonValue := GetJson('get_staffs/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] Kru/Karyawan : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        ADataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(ADataset, ftString, AFields[1],20);
        NewDataSetField(ADataset, ftString, AFields[2],50);
        NewDataSetField(ADataset, ftString, AFields[3],50);
        NewDataSetField(ADataset, ftString, AFields[4],50);
        NewDataSetField(ADataset, ftString, AFields[5],50);
        NewDataSetField(ADataset, ftString, AFields[6],50);
        NewDataSetField(ADataset, ftString, AFields[7],50);
        NewDataSetField(ADataset, ftString, AFields[8],50);
        NewDataSetField(ADataset, ftString, AFields[9],50);
        NewDataSetField(ADataset, ftString, AFields[10],50);
        NewDataSetField(ADataset, ftDate, AFields[11]);
        NewDataSetField(ADataset, ftString, AFields[12],20);
        NewDataSetField(ADataset, ftString, AFields[13],20);
        NewDataSetField(ADataset, ftString, AFields[14],20);
        NewDataSetField(ADataset, ftInteger, AFields[15]);
        NewDataSetField(ADataset, ftInteger, AFields[16]);

        ADataset.DataSetField := nil;
        ADataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(ADataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          AQuery := '';
          with ADataset do
          begin
            First;
            while not Eof do
            begin
              //mpo_code := FieldByName('mpo_code').AsString;
              //mpo_name := FieldByName('mpo_name').AsString;
              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[FieldByName(AFields[1]).AsString, FieldByName(AFields[2]).AsString]);

              AQuery := 'INSERT INTO `m_kru` SET '
                       +'`kruid`='+QuotedStr(FieldByName(AFields[1]).AsString)
                       +',`jabatanid`='+QuotedStr(FieldByName(AFields[14]).AsString)
                       +',`kruname`='+QuotedStr(FieldByName(AFields[2]).AsString)
                       +',`birthdate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[11]).AsDateTime))
                       +',`address`='+QuotedStr(FieldByName(AFields[4]).AsString+FieldByName(AFields[5]).AsString+FieldByName(AFields[6]).AsString)
                       +',`gender`='+QuotedStr(FieldByName(AFields[15]).AsString)
                       +',`ktp`='+QuotedStr(FieldByName(AFields[12]).AsString)
                       +',`npwp`='+QuotedStr(FieldByName(AFields[15]).AsString)
                       +',`phone`='+QuotedStr(FieldByName(AFields[7]).AsString)
                       //+',`joindate`='+QuotedStr(FieldByName(AFields[0]).AsString)
                       //+',`Remarks`='+QuotedStr(FieldByName(AFields[0]).AsString)
                       +',`email`='+QuotedStr(FieldByName(AFields[10]).AsString)
                       +',`handphone`='+QuotedStr(FieldByName(AFields[9]).AsString)
                       +',`statusaktif`='+QuotedStr(FieldByName(AFields[16]).AsString)
                       //+',`create_userid`='+QuotedStr(FieldByName(AFields[0]).AsString)
                       +' '+
                        ' ON DUPLICATE KEY UPDATE '
                       +'`kruname`='+QuotedStr(FieldByName(AFields[2]).AsString)
                       +',`jabatanid`='+QuotedStr(FieldByName(AFields[14]).AsString)
                       +',`address`='+QuotedStr(FieldByName(AFields[4]).AsString+FieldByName(AFields[5]).AsString+FieldByName(AFields[6]).AsString)
                       +',`gender`='+QuotedStr(FieldByName(AFields[15]).AsString)
                       +',`ktp`='+QuotedStr(FieldByName(AFields[12]).AsString)
                       +',`npwp`='+QuotedStr(FieldByName(AFields[15]).AsString)
                       +',`phone`='+QuotedStr(FieldByName(AFields[7]).AsString)
                       +',`email`='+QuotedStr(FieldByName(AFields[10]).AsString)
                       +',`handphone`='+QuotedStr(FieldByName(AFields[9]).AsString)
                       +',`statusaktif`='+QuotedStr(FieldByName(AFields[16]).AsString)
                       ;
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;
        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert Kru/Karyawan: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetStaff: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;

function GetCustomer(AToken: String):Boolean;
var
  AJsonValue: string;
  LJsonArray: TJSONArray;
  LJsonValue: TJSONValue;
  LItem: TJSONValue;
  LJsonObj: TJSONObject;
  
  ADataset : TClientDataSet;
  AQuery: String;

const
  AFields : array[1..20] of string = (
    'mcu_code',
    'mcu_name',
    'mcu_pic',
    'mcu_address1',
    'mcu_address2',
    'mcu_address3',
    'mcu_phone',
    'mcu_fax',
    'mcu_hp',
    'mcu_email',
    'mcu_birthdate',
    'mcu_begindate',
    'mcu_enddate',
    'mcu_oldcode',
    'mcu_idcard',
    'mcu_idtax',
    'mcu_plafond',
    'mcu_type',
    'mcu_gender',
    'mcu_active');

begin
  {get Member}
  try
    AJsonValue := GetJson('get_customers/'+AToken);
    DiviPOSMainService.UpdateStatus := '[Debug] Customer/member : '+AJsonValue;
    if (AJsonValue <> '') then
    begin
      try
        LJsonArray := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(AJsonValue),0) as TJSONArray;
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Parse error : '+E.Message;
          Exit(false);
        end;
      end;

      try
        ADataset := TClientDataSet.Create(DiviPOSMainService);
        NewDataSetField(ADataset, ftString, AFields[1],20);
        NewDataSetField(ADataset, ftString, AFields[2],50);
        NewDataSetField(ADataset, ftString, AFields[3],50);
        NewDataSetField(ADataset, ftString, AFields[4],50);
        NewDataSetField(ADataset, ftString, AFields[5],50);
        NewDataSetField(ADataset, ftString, AFields[6],50);
        NewDataSetField(ADataset, ftString, AFields[7],50);
        NewDataSetField(ADataset, ftString, AFields[8],50);
        NewDataSetField(ADataset, ftString, AFields[9],50);
        NewDataSetField(ADataset, ftString, AFields[10],50);
        NewDataSetField(ADataset, ftDate, AFields[11]);
        NewDataSetField(ADataset, ftDate, AFields[12]);
        NewDataSetField(ADataset, ftDate, AFields[13]);
        NewDataSetField(ADataset, ftString, AFields[14],20);
        NewDataSetField(ADataset, ftString, AFields[15],20);
        NewDataSetField(ADataset, ftString, AFields[16],20);
        NewDataSetField(ADataset, ftFloat, AFields[17]);
        NewDataSetField(ADataset, ftString, AFields[18],20);
        NewDataSetField(ADataset, ftInteger, AFields[19]);
        NewDataSetField(ADataset, ftInteger, AFields[20]);

        ADataset.DataSetField := nil;
        ADataset.CreateDataSet;
        Converter.JSON.Source(LJsonArray).ToDataSet(ADataset);
      except on E: Exception do
        begin
          DiviPOSMainService.UpdateStatus := 'Convert error : '+E.Message;
          Exit(false);
        end;
      end;

      {loop and insert to database}
      //dmdService.StartTrans;
      try
        try
          AQuery := '';
          with ADataset do
          begin
            First;
            while not Eof do
            begin
              //mpo_code := FieldByName('mpo_code').AsString;
              //mpo_name := FieldByName('mpo_name').AsString;
              DiviPOSMainService.UpdateStatus := '[Debug] '+Format('%s : %s',[FieldByName(AFields[1]).AsString, FieldByName(AFields[2]).AsString]);

              AQuery := 'INSERT INTO `m_member` SET '
                       +'`memberid`='+QuotedStr(FieldByName(AFields[1]).AsString)
                       +',`membername`='+QuotedStr(FieldByName(AFields[2]).AsString)
                       +',`address1`='+QuotedStr(FieldByName(AFields[4]).AsString)
                       +',`address2`='+QuotedStr(FieldByName(AFields[5]).AsString)
                       +',`address3`='+QuotedStr(FieldByName(AFields[6]).AsString)
                       +',`phone`='+QuotedStr(FieldByName(AFields[7]).AsString)
                       +',`hp`='+QuotedStr(FieldByName(AFields[9]).AsString)
                       +',`email`='+QuotedStr(FieldByName(AFields[10]).AsString)
                       +',`birthdate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[11]).AsDateTime))
                       +',`joindate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[12]).AsDateTime))
                       +',`enddate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[13]).AsDateTime))
                       +',`old_memberid`='+QuotedStr(FieldByName(AFields[14]).AsString)
                       +',`ktp`='+QuotedStr(FieldByName(AFields[15]).AsString)
                       +',`npwp`='+QuotedStr(FieldByName(AFields[16]).AsString)
                       +',`plafond`='+QuotedStr(FieldByName(AFields[17]).AsString)
                       +',`membertypeid`='+QuotedStr(FieldByName(AFields[18]).AsString)
                       +',`gender`='+QuotedStr(FieldByName(AFields[19]).AsString)
                       +',`statusaktif`='+QuotedStr(FieldByName(AFields[20]).AsString)
                       //+',`create_userid`='+QuotedStr(FieldByName(AFields[0]).AsString)
                       +' '
                       +' ON DUPLICATE KEY UPDATE '
                       +' `membername`='+QuotedStr(FieldByName(AFields[2]).AsString)
                       +',`address1`='+QuotedStr(FieldByName(AFields[4]).AsString)
                       +',`address2`='+QuotedStr(FieldByName(AFields[5]).AsString)
                       +',`address3`='+QuotedStr(FieldByName(AFields[6]).AsString)
                       +',`phone`='+QuotedStr(FieldByName(AFields[7]).AsString)
                       +',`hp`='+QuotedStr(FieldByName(AFields[9]).AsString)
                       +',`email`='+QuotedStr(FieldByName(AFields[10]).AsString)
                       +',`birthdate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[11]).AsDateTime))
                       +',`joindate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[12]).AsDateTime))
                       +',`enddate`='+QuotedStr(FormatDateTime('yyyy-mm-dd',FieldByName(AFields[13]).AsDateTime))
                       +',`old_memberid`='+QuotedStr(FieldByName(AFields[14]).AsString)
                       +',`ktp`='+QuotedStr(FieldByName(AFields[15]).AsString)
                       +',`npwp`='+QuotedStr(FieldByName(AFields[16]).AsString)
                       +',`plafond`='+QuotedStr(FieldByName(AFields[17]).AsString)
                       +',`membertypeid`='+QuotedStr(FieldByName(AFields[18]).AsString)
                       +',`gender`='+QuotedStr(FieldByName(AFields[19]).AsString)
                       +',`statusaktif`='+QuotedStr(FieldByName(AFields[20]).AsString)
                       ;
              dmdService.ExecQuery(AQuery);
              Next;
            end;
          end;
        except on E: Exception do
          begin
            DiviPOSMainService.UpdateStatus := '[Error] Insert Member: '+E.Message;
            Exit(false);
          end;
          //dmdService.RollbackTrans;
        end;
      finally
        //dmdService.CommitTrans;
      end;
    end;
  except on E: Exception do
    begin
      DiviPOSMainService.UpdateStatus := '[Error] GetMember: '+E.Message;
      Exit(false);
    end;
  end;
  Result := True;
end;


end.
