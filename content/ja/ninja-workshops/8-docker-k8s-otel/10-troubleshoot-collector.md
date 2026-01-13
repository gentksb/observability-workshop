---
title: OpenTelemetry Collector の問題をトラブルシュートする
linkTitle: 10. OpenTelemetry Collector の問題をトラブルシュートする
weight: 10
time: 20 minutes
---

前のセクションでは、コレクター設定に debug エクスポーターを追加し、トレースとログのパイプラインの一部としました。期待通り、エージェントコレクターのログにデバッグ出力が書き込まれています。

しかし、トレースが o11y cloud に送信されなくなりました。原因を調べて修正しましょう。

## コレクター設定を確認する

`values.yaml` ファイルでコレクター設定を変更した場合は、config map を確認してコレクターに適用された実際の設定を確認すると便利です。

``` bash
kubectl describe cm splunk-otel-collector-otel-agent
```

エージェントコレクター設定のログとトレースのパイプラインを確認しましょう。次のようになっているはずです。

``` yaml
  pipelines:
    logs:
      exporters:
      - debug
      processors:
      - memory_limiter
      - k8sattributes
      - filter/logs
      - batch
      - resourcedetection
      - resource
      - resource/logs
      - resource/add_environment
      receivers:
      - filelog
      - otlp
    ...
    traces:
      exporters:
      - debug
      processors:
      - memory_limiter
      - k8sattributes
      - batch
      - resourcedetection
      - resource
      - resource/add_environment
      receivers:
      - otlp
      - jaeger
      - zipkin
```

問題がわかりますか？トレースとログのパイプラインには debug エクスポーターしか含まれていません。以前トレースパイプライン設定に存在していた `otlphttp` と `signalfx` エクスポーターがなくなっています。これが o11y cloud でトレースが表示されなくなった理由です。また、ログパイプラインでは `splunk_hec/platform_logs` エクスポーターが削除されています。

> 以前どのエクスポーターが含まれていたかをどうやって知ることができたのでしょうか？それを調べるには、以前のカスタマイズを元に戻してから config map を確認し、元々トレースパイプラインに何が含まれていたかを確認する方法があります。または、[GitHub repo for splunk-otel-collector-chart](https://github.com/signalfx/splunk-otel-collector-chart/blob/main/examples/default/rendered_manifests/configmap-agent.yaml) の例を参照して、Helm chart で使用されるデフォルトのエージェント設定を確認することもできます。

## これらのエクスポーターはどのように削除されたのか

`values.yaml` ファイルに追加したカスタマイズを確認しましょう。

``` yaml
logsEngine: otel
splunkObservability:
  infrastructureMonitoringEventsEnabled: true
agent:
  config:
    receivers:
     ...
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        traces:
          exporters:
            - debug
        logs:
          exporters:
            - debug
```

`helm upgrade` を使用して `values.yaml` ファイルをコレクターに適用すると、カスタム設定が以前のコレクター設定とマージされます。この際、パイプラインセクションのエクスポーターのリストのように、リストを含む `yaml` 設定のセクションは、`values.yaml` ファイルに含めた内容（debug エクスポーターのみ）に置き換えられます。

## 問題を修正しましょう

したがって、既存のパイプラインをカスタマイズする場合は、設定のその部分を完全に再定義する必要があります。`values.yaml` ファイルは次のように更新する必要があります。

``` yaml
logsEngine: otel
splunkObservability:
  infrastructureMonitoringEventsEnabled: true
agent:
  config:
    receivers:
     ...
    exporters:
      debug:
        verbosity: detailed
    service:
      pipelines:
        traces:
          exporters:
            - otlphttp
            - signalfx
            - debug
        logs:
          exporters:
            - splunk_hec/platform_logs
            - debug
```

変更を適用しましょう。

``` bash
helm upgrade splunk-otel-collector \
  --set="splunkObservability.realm=$REALM" \
  --set="splunkObservability.accessToken=$ACCESS_TOKEN" \
  --set="clusterName=$INSTANCE-cluster" \
  --set="environment=otel-$INSTANCE" \
  --set="splunkPlatform.token=$HEC_TOKEN" \
  --set="splunkPlatform.endpoint=$HEC_URL" \
  --set="splunkPlatform.index=splunk4rookies-workshop" \
  -f values.yaml \
splunk-otel-collector-chart/splunk-otel-collector
```

次に、エージェントの config map を確認します。

``` bash
kubectl describe cm splunk-otel-collector-otel-agent
```

今回は、ログとトレースの両方で完全に定義されたエクスポーターパイプラインが表示されるはずです。

``` bash
  pipelines:
    logs:
      exporters:
      - splunk_hec/platform_logs
      - debug
      processors:
      ...
    traces:
      exporters:
      - otlphttp
      - signalfx
      - debug
      processors:
      ...
```

## ログ出力を確認する

**Splunk Distribution of OpenTelemetry .NET** は、`Microsoft.Extensions.Logging` をロギングに使用するアプリケーション（サンプルアプリもこれを使用しています）から、トレースコンテキストでエンリッチされたログを自動的にエクスポートします。

アプリケーションログはトレースメタデータでエンリッチされ、OTLP 形式でローカルの OpenTelemetry Collector インスタンスにエクスポートされます。

debug エクスポーターでキャプチャされたログを詳しく見て、それが行われているか確認しましょう。コレクターログを tail するには、次のコマンドを使用します。

``` bash
kubectl logs -l component=otel-collector-agent -f
```

ログを tail している間に、curl を使用してトラフィックを生成できます。すると、次のような出力が表示されるはずです。

````
2024-12-20T21:56:30.858Z	info	Logs	{"kind": "exporter", "data_type": "logs", "name": "debug", "resource logs": 1, "log records": 1}
2024-12-20T21:56:30.858Z	info	ResourceLog #0
Resource SchemaURL: https://opentelemetry.io/schemas/1.6.1
Resource attributes:
     -> splunk.distro.version: Str(1.8.0)
     -> telemetry.distro.name: Str(splunk-otel-dotnet)
     -> telemetry.distro.version: Str(1.8.0)
     -> os.type: Str(linux)
     -> os.description: Str(Debian GNU/Linux 12 (bookworm))
     -> os.build_id: Str(6.8.0-1021-aws)
     -> os.name: Str(Debian GNU/Linux)
     -> os.version: Str(12)
     -> host.name: Str(derek-1)
     -> process.owner: Str(app)
     -> process.pid: Int(1)
     -> process.runtime.description: Str(.NET 8.0.11)
     -> process.runtime.name: Str(.NET)
     -> process.runtime.version: Str(8.0.11)
     -> container.id: Str(5bee5b8f56f4b29f230ffdd183d0367c050872fefd9049822c1ab2aa662ba242)
     -> telemetry.sdk.name: Str(opentelemetry)
     -> telemetry.sdk.language: Str(dotnet)
     -> telemetry.sdk.version: Str(1.9.0)
     -> service.name: Str(helloworld)
     -> deployment.environment: Str(otel-derek-1)
     -> k8s.node.name: Str(derek-1)
     -> k8s.cluster.name: Str(derek-1-cluster)
ScopeLogs #0
ScopeLogs SchemaURL:
InstrumentationScope HelloWorldController
LogRecord #0
ObservedTimestamp: 2024-12-20 21:56:28.486804 +0000 UTC
Timestamp: 2024-12-20 21:56:28.486804 +0000 UTC
SeverityText: Information
SeverityNumber: Info(9)
Body: Str(/hello endpoint invoked by {name})
Attributes:
     -> name: Str(Kubernetes)
Trace ID: 78db97a12b942c0252d7438d6b045447
Span ID: 5e9158aa42f96db3
Flags: 1
	{"kind": "exporter", "data_type": "logs", "name": "debug"}
````

この例では、OpenTelemetry .NET インストルメンテーションによって Trace ID と Span ID がログ出力に自動的に書き込まれていることがわかります。これにより、Splunk Observability Cloud でログとトレースを関連付けることができます。

ただし、Helm を使用して K8s クラスターに OpenTelemetry collector をデプロイし、ログ収集オプションを含めた場合、OpenTelemetry collector は File Log receiver を使用してコンテナログを自動的にキャプチャすることを覚えているかもしれません。

これにより、アプリケーションのログが重複してキャプチャされることになります。例えば、次のスクリーンショットでは、サービスへの各リクエストに対して 2 つのログエントリがあることがわかります。

![Duplicate Log Entries](../images/duplicate_logs.png)

これを回避するにはどうすればよいでしょうか？

## K8s での重複ログを回避する

重複ログのキャプチャを回避するには、`OTEL_LOGS_EXPORTER` 環境変数を `none` に設定して、Splunk Distribution of OpenTelemetry .NET が OTLP を使用してコレクターにログをエクスポートしないようにします。これは、`deployment.yaml` ファイルに `OTEL_LOGS_EXPORTER` 環境変数を追加することで実現できます。

``` yaml
          env:
            - name: PORT
              value: "8080"
            - name: NODE_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://$(NODE_IP):4318"
            - name: OTEL_SERVICE_NAME
              value: "helloworld"
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "deployment.environment=otel-$INSTANCE"
            - name: OTEL_LOGS_EXPORTER
              value: "none"
```

そして次を実行します。

``` bash
# update the deployment
kubectl apply -f deployment.yaml
```

`OTEL_LOGS_EXPORTER` 環境変数を `none` に設定するのは簡単です。しかし、アプリケーションが生成する stdout ログには Trace ID と Span ID が書き込まれないため、ログとトレースを関連付けることができなくなります。

これを解決するには、`/home/splunk/workshop/docker-k8s-otel/helloworld/SplunkTelemetryConfigurator.cs` で定義されている例のようなカスタムロガーを定義する必要があります。

`Program.cs` ファイルを次のように更新することで、これをアプリケーションに含めることができます。

``` cs
using SplunkTelemetry;
using Microsoft.Extensions.Logging.Console;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

SplunkTelemetryConfigurator.ConfigureLogger(builder.Logging);

var app = builder.Build();

app.MapControllers();

app.Run();
```

次に、カスタムロギング設定を含む新しい Docker イメージをビルドします。

``` bash
cd /home/splunk/workshop/docker-k8s-otel/helloworld

docker build -t helloworld:1.3 .
```

そして、更新したイメージをローカルコンテナリポジトリにインポートします。

``` bash
cd /home/splunk

# Tag the image
docker tag helloworld:1.3 localhost:9999/helloworld:1.3

# Import the image into our local container repo
docker push localhost:9999/helloworld:1.3
```

最後に、コンテナイメージの 1.3 バージョンを使用するように `deployment.yaml` ファイルを更新する必要があります。

``` yaml
    spec:
      containers:
        - name: helloworld
          image: localhost:9999/helloworld:1.3
```

そして変更を適用します。

``` bash
# update the deployment
kubectl apply -f deployment.yaml
```

これで、重複したログエントリが削除されたことがわかります。残りのログエントリは JSON 形式でフォーマットされ、span ID と trace ID が含まれています。

![JSON Format Logs](../images/logs_json_format.png)
