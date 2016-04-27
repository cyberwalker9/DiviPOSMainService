object DiviPOSMainService: TDiviPOSMainService
  OldCreateOrder = False
  OnDestroy = ServiceDestroy
  DisplayName = 'DiviPOS Backservice'
  AfterInstall = ServiceAfterInstall
  AfterUninstall = ServiceAfterUninstall
  OnShutdown = ServiceShutdown
  OnStart = ServiceStart
  OnStop = ServiceStop
  Height = 266
  Width = 457
  object RESTClient1: TRESTClient
    Accept = 'application/json, text/plain; q=0.9, text/html;q=0.8,'
    AcceptCharset = 'UTF-8, *;q=0.8'
    AcceptEncoding = 'identity'
    BaseURL = 'http://api.myschool.id'
    Params = <>
    HandleRedirects = True
    Left = 32
    Top = 8
  end
  object RESTResponse1: TRESTResponse
    ContentType = 'application/json'
    Left = 160
    Top = 80
  end
  object RESTRequest1: TRESTRequest
    Client = RESTClient1
    Params = <
      item
        Kind = pkURLSEGMENT
        name = 'userid'
        Options = [poAutoCreated]
        Value = '72'
      end
      item
        Kind = pkURLSEGMENT
        name = 'lastfeed'
        Options = [poAutoCreated]
        Value = '0'
      end>
    Resource = 'v1/agendafeed/{userid}/{lastfeed}'
    Response = RESTResponse1
    SynchronizedEvents = False
    Left = 32
    Top = 80
  end
  object RESTResponseDataSetAdapter1: TRESTResponseDataSetAdapter
    FieldDefs = <>
    ResponseJSON = RESTResponse1
    Left = 160
    Top = 16
  end
end
