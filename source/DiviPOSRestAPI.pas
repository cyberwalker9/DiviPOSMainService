unit DiviPOSRestAPI;

interface
  uses
  System.Classes,
  SysUtils,
  REST.Authenticator.OAuth,
  REST.Authenticator.Basic,
  REST.Authenticator.Simple,
  REST.Response.Adapter,
  REST.Client,
  REST.Exception,
  REST.Consts,
  REST.Json,
  REST.Types,
  REST.Utils;

  function PostJson(const AResources: String; const AJSonString : String):boolean;
  function GetResponse(aRESTResponse: TRESTResponse):boolean;
  function GetJson(const AResources: String):TJson;

implementation

uses uMainService;

function GetResponse(aRESTResponse: TRESTResponse):boolean;
var
  tmpResult: Boolean;
begin
  tmpResult := false;
  with DiviPOSMainService do
  begin
    {init RESTResponse}
    with aRESTResponse do
    begin
      if StatusCode >= 300 then
      begin
        UpdateStatus := 'Request Failed :('+StatusCode.ToString()+') '+#13#10+
                                            StatusText+' '+ErrorMessage;
      end
      else
      begin
        UpdateStatus := 'Request Success';
        tmpResult := true;
      end;
      UpdateStatus := '[Debug] '+Content;
    end;
  end;
  Result := tmpResult;
end;

function PostJson(const AResources: String; const AJSonString : String):boolean;
var
  RESTClient: TRESTClient;
  RESTRequest: TRESTRequest;
  RESTResponse: TRESTResponse;
  tmpResult: Boolean;
begin
  tmpResult := false;
  with DiviPOSMainService do
  begin
    {init REST Client}
    if URLAddress = '' then
    begin
      UpdateStatus := '[Error] URL is Empty ';
      Exit(false);
    end;

    UpdateStatus := 'PostJson to : '+(URLAddress)+AResources;
    UpdateStatus := '[Debug] '+AJSonString;
    RESTClient:= TRESTClient.Create(URLAddress);
    RESTResponse := TRESTResponse.Create(DiviPOSMainService);

    {init REST Request}
    RESTRequest := TRESTRequest.Create(DiviPOSMainService);
    with RESTRequest do
    try
      Client := RESTClient;
      Response := RESTResponse;
      Method := rmPOST;
      AddBody(AJSonString, ctAPPLICATION_JSON);
      Resource := AResources;

      try
        Execute;
      except
        on E: TRESTResponseDataSetAdapter.EJSONValueError do
        begin
          UpdateStatus := E.Message;
        end;
        on E: TRESTResponse.EJSONValueError do
        begin
          UpdateStatus := E.Message;
        end
        else
          raise;
        Exit(false);
      end;
      tmpResult := GetResponse(RESTResponse);
    finally
      RESTClient.Free;
      RESTRequest.Free;
      RESTResponse.Free;
    end;
  end;
  Result := tmpResult;
end;

end.
