unit ConfigUtils;

{
   ---------------------------------------------------
   Config Utils

   Author : Widi Satriya Aviantoro
   09 Sept 2013

   Fast Access to ini files
   Read and Write Rutine
   ---------------------------------------------------
}

interface
  uses IniFiles, Classes, Sysutils;

  type
    TRConfig = record
      AName : String;
      AValue: String;
    end;

    TArConfig = Array Of TRConfig;

    TConfig = class
      Config : TMemIniFile;
      constructor Create; Overload;
      constructor Create(const APathToIniFile : String;Ext : String = '.cfg'); Overload;
    private
      ADataConfig : TArConfig;
      AConfigFilePath, AFileExt : String;
      FSection: String;
      IsFileBase: boolean;
      function GetValue(const Name: string): string;
      procedure SetValue(const Name, Value: string);
      procedure SetSection(const Value: String);
      function GetConfig(const AppExeName : String;Ext : String = '.cfg'): TMemIniFile;
    public
      property Section : String read FSection write SetSection;
      property Values[const Name: string]: string read GetValue write SetValue; default;

      procedure ReloadConfig;
      procedure Save();

      function GetConfigDefault(const Name: String; ADefault: String = ''):String;
  end;


implementation

{ TConfig }
constructor TConfig.Create();
begin
  inherited;

  AConfigFilePath := '';
  AFileExt := '';
  FSection := '';
  IsFileBase := false;
end;

constructor TConfig.Create(const APathToIniFile : String;Ext : String = '.cfg');
begin
  AFileExt := Ext;
  IsFileBase := not (AFileExt = '');

  if IsFileBase then
  begin
    AConfigFilePath := ChangeFileExt(APathToIniFile,Ext);
    ReloadConfig;
  end;
end;

procedure TConfig.ReloadConfig;
{
  Khusus untuk file base Data Config
  Ambil Data Config Dari existing File Config
}
var
  SectionList, KeyList: TStringList;
  I: Integer;
  J: Integer;
begin
  ADataConfig := nil;

  SectionList := TStringList.Create;
  KeyList := TStringList.Create;

  Config := GetConfig(AConfigFilePath,AFileExt);
  try
    {
      load settings to Array
      read ini file as file
    }
    Config.ReadSections(SectionList);
    for J := 0 to SectionList.Count-1 do
    begin
      FSection := SectionList[J];
      Config.ReadSection(FSection, KeyList);
      SetLength(ADataConfig,KeyList.Count);

      for I := 0 to KeyList.Count - 1 do
      begin
        ADataConfig[I].AName  := KeyList[I];
        ADataConfig[I].AValue := Config.ReadString(FSection,KeyList[I],'');
      end;
    end;
  finally
    KeyList.Free;
    SectionList.Free;
    Config.Free;
  end;
end;

function TConfig.GetValue(const Name: string): string;
var I : Integer;
    tmpResult : String;
    AFoundKey : boolean;
begin
  {section is always FSection}
  //result := Config.ReadString(FSection,Name,'');
  AFoundKey :=  false;
  tmpResult := '';
  I := Low(ADataConfig);
  while (I <= High(ADataConfig)) AND (not AFoundKey) do
  begin
    if UpperCase(ADataConfig[I].AName) = UpperCase(Name) then
    begin
      AFoundKey := true;
      tmpResult := ADataConfig[I].AValue;
      Continue;
    end
    else
      AFoundKey := false;

    inc(I);
  end;

  if (not AFoundKey) then
  begin
    {do insert Config}
    SetValue(Name,Name);
    tmpResult := Name;
  end;

  Result := tmpResult;
end;

procedure TConfig.SetValue(const Name, Value: string);
var I : Integer;
    FieldFound : Boolean;
begin
  {update ADataConfig}
  FieldFound := false;
  for I := Low(ADataConfig) to High(ADataConfig) do
  begin
    if ADataConfig[I].AName = Name then
    begin
      ADataConfig[I].AValue :=Value;
      FieldFound := True;
    end;
  end;

  if not FieldFound then
  begin
    SetLength(ADataConfig,length(ADataConfig)+1);
    ADataConfig[High(ADataConfig)].AName   := Name;
    ADataConfig[High(ADataConfig)].AValue  := Value;
  end;

  {update File Config}
  if IsFileBase then  
  with GetConfig(AConfigFilePath,AFileExt) do
  try
    WriteString(FSection,Name,Value);
    UpdateFile;
  finally
    Free;
  end;
end;

procedure TConfig.Save;
begin
  Config.UpdateFile;
end;

procedure TConfig.SetSection(const Value: String);
begin
  FSection := Value;
end;

function TConfig.GetConfig(const AppExeName : String;Ext : String = '.cfg'): TMemIniFile;
begin
  result := TMemIniFile.Create(ChangeFileExt(AppExeName, Ext));
end;

function TConfig.GetConfigDefault(const Name: String; ADefault: String = ''): String;
begin
  Result := GetValue(Name);
  if (Result = Name) then
  begin
    SetValue(Name,ADefault);
    Result := ADefault;
  end;
end;

end.
