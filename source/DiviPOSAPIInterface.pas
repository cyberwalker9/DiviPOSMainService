unit DiviPOSAPIInterface;

interface

  uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Datasnap.DSClientRest,
  Data.Bind.Components, Data.Bind.ObjectScope, uRESTObjects, Uni,
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

type
  TAPIInterface = class(TComponent)
    RESTClient: TRESTClient;
    DSRestConnection: TDSRestConnection;
    RESTResponse: TRESTResponse;
    RESTRequest: TRESTRequest;
    RESTResponseDataSetAdapter: TRESTResponseDataSetAdapter;

    SimpleAuthenticator: TSimpleAuthenticator;
    HTTPBasicAuthenticator: THTTPBasicAuthenticator;
    OAuth1Authenticator: TOAuth1Authenticator;
    OAuth2Authenticator: TOAuth2Authenticator;


    FRESTParams: TRESTRequestParams;

    FileList: TStringList;

  private
    procedure SetRESTParams(const Value: TRESTRequestParams);
    procedure ConfigureProxyServer;

  public
    constructor Create(AOwner: TComponent); Override;
    destructor Destroy(); Override;

    procedure UpdateComponentProperties;


    procedure SendJson(AJsonString : String);

    procedure GetRESTList();

    property RESTParams : TRESTRequestParams read FRESTParams write SetRESTParams;
  end;

implementation



{ TAPIInterface }

uses dmService, ServiceUtils, uMainService;

procedure TAPIInterface.ConfigureProxyServer;
begin

end;

constructor TAPIInterface.Create(AOwner: TComponent);
begin
  RESTClient := TRESTClient.Create('');
  with RESTClient do
  begin
    Accept := 'application/json, text/plain; q=0.9, text/html;q=0.8,';
    AcceptCharset := 'UTF-8, *;q=0.8';
    AcceptEncoding := 'identity';
  end;

  RESTResponse := TRESTResponse.Create(self);
  with RESTResponse do
  begin
    ContentType := 'application/json';
    ResetToDefaults;
  end;

  RESTRequest := TRESTRequest.Create(self);
  with RESTRequest do
  begin
    Client := RESTClient;
	Response := RESTResponse;
    ResetToDefaults;
  end;

  
  FileList:= TStringList.Create;

  //RESTResponseDataSetAdapter1: TRESTResponseDataSetAdapter;
end;

destructor TAPIInterface.Destroy;
begin
  FileList.Free;
  //
  inherited;
end;


procedure TAPIInterface.GetRESTList;
var
  RestFolder: String;
begin

end;

procedure TAPIInterface.SendJson(AJsonString: String);
begin
  RESTClient.BaseURL := DiviPOSMainService.URLAddress;

end;

procedure TAPIInterface.SetRESTParams(const Value: TRESTRequestParams);
begin
  FRESTParams := Value;
end;

procedure TAPIInterface.UpdateComponentProperties;
begin
  RESTClient.ResetToDefaults;

  RESTClient.BaseURL := RESTParams.URL;
  RESTRequest.Resource := FRESTParams.Resource;

  RESTRequest.Params.Clear;
  RESTRequest.Params.Assign(FRESTParams.CustomParams);

  if FRESTParams.CustomBody.Size > 0 then
  begin
    RESTRequest.AddBody(FRESTParams.CustomBody, ContentTypeFromString(FRESTParams.ContentType));
  end;

  RESTRequest.Method := FRESTParams.Method;

  case FRESTParams.AuthMethod of
    TRESTAuthMethod.amNONE:
      begin
        RESTClient.Authenticator := NIL;
      end;
    TRESTAuthMethod.amSIMPLE:
      begin
        RESTClient.Authenticator := SimpleAuthenticator;
        SimpleAuthenticator.Username := FRESTParams.AuthUsername;
        SimpleAuthenticator.UsernameKey := FRESTParams.AuthUsernameKey;
        SimpleAuthenticator.Password := FRESTParams.AuthPassword;
        SimpleAuthenticator.PasswordKey := FRESTParams.AuthPasswordKey;
      end;
    TRESTAuthMethod.amBASIC:
      begin
        RESTClient.Authenticator := HTTPBasicAuthenticator;
        HTTPBasicAuthenticator.Username := FRESTParams.AuthUsername;
        HTTPBasicAuthenticator.Password := FRESTParams.AuthPassword;
      end;
    TRESTAuthMethod.amOAUTH:
      begin
        RESTClient.Authenticator := OAuth1Authenticator;
        OAuth1Authenticator.ConsumerKey := FRESTParams.ClientID;
        OAuth1Authenticator.ConsumerSecret := FRESTParams.ClientSecret;
        OAuth1Authenticator.AccessToken := FRESTParams.AccessToken;
        OAuth1Authenticator.AccessTokenSecret := FRESTParams.AccessTokenSecret;
      end;
    TRESTAuthMethod.amOAUTH2:
      begin
        RESTClient.Authenticator := OAuth2Authenticator;
        OAuth2Authenticator.AccessToken := FRESTParams.AccessToken;
      end;
  else
    raise ERESTException.Create(sRESTUnsupportedAuthMethod);
  end;

  RESTRequest.Client := RESTClient;
end;

end.
