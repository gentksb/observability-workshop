---
title: OpenTelemetry Collector 設定のカスタマイズ
linkTitle: 9. OpenTelemetry Collector 設定のカスタマイズ
weight: 9
time: 20 minutes
---

K8s クラスターにデフォルト設定で Splunk Distribution of the OpenTelemetry Collector をデプロイしました。このセクションでは、Collector の設定をカスタマイズする方法をいくつかの例を通じて説明します。

## Collector 設定の取得

Collector の設定をカスタマイズする前に、現在の設定がどのようになっているかを確認する方法を見てみましょう。

Kubernetes 環境では、Collector の設定は Config Map を使用して保存されます。

以下のコマンドでクラスター内に存在する config map を確認できます:

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
kubectl get cm -l app=splunk-otel-collector
```

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
NAME                                                 DATA   AGE
splunk-otel-collector-otel-k8s-cluster-receiver   1      3h37m
splunk-otel-collector-otel-agent                  1      3h37m
```

{{% /tab %}}
{{< /tabs >}}

> なぜ2つの config map があるのでしょうか？

次に、Collector agent の config map を以下のように確認できます:

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
kubectl describe cm splunk-otel-collector-otel-agent
```

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
Name:         splunk-otel-collector-otel-agent
Namespace:    default
Labels:       app=splunk-otel-collector
              app.kubernetes.io/instance=splunk-otel-collector
              app.kubernetes.io/managed-by=Helm
              app.kubernetes.io/name=splunk-otel-collector
              app.kubernetes.io/version=0.136.1
              chart=splunk-otel-collector-0.136.0
              helm.sh/chart=splunk-otel-collector-0.136.0
              release=splunk-otel-collector
Annotations:  meta.helm.sh/release-name: splunk-otel-collector
              meta.helm.sh/release-namespace: default

Data
====
relay:
----
exporters:
  otlphttp:
    auth:
      authenticator: headers_setter
    metrics_endpoint: https://ingest.us1.signalfx.com/v2/datapoint/otlp
    traces_endpoint: https://ingest.us1.signalfx.com/v2/trace/otlp
    (followed by the rest of the collector config in yaml format)
```

{{% /tab %}}
{{< /tabs >}}


## K8s での Collector 設定の更新方法

以前の Linux インスタンスで Collector を実行した例では、Collector の設定は `/etc/otel/collector/agent_config.yaml` ファイルにありました。その場合、Collector の設定を変更する必要があれば、このファイルを編集して保存し、Collector を再起動するだけでした。

K8s では、少し異なる方法で動作します。`agent_config.yaml` を直接変更する代わりに、helm chart のデプロイに使用する `values.yaml` ファイルを変更することで Collector の設定をカスタマイズします。

[GitHub](https://github.com/signalfx/splunk-otel-collector-chart/blob/main/helm-charts/splunk-otel-collector/values.yaml) にある values.yaml ファイルで、利用可能なカスタマイズオプションが説明されています。

例を見てみましょう。

## インフラストラクチャイベント監視の追加

最初の例として、K8s クラスターのインフラストラクチャイベント監視を有効にしましょう。

> これにより、チャートの Events Feed セクションで Kubernetes イベントを確認できるようになります。
> cluster receiver は、カスタムイベントを送信するために kubernetes-events monitor を使用した Smart Agent receiver で設定されます。詳細は [Collect Kubernetes events](https://docs.splunk.com/observability/en/gdi/opentelemetry/collector-kubernetes/kubernetes-config-logs.html#collect-kubernetes-events) を参照してください。

これは `values.yaml` ファイルに以下の行を追加することで行います:

> ヒント: vi でファイルを開いて保存する手順は、前のステップにあります。

``` yaml
logsEngine: otel
splunkObservability:
  infrastructureMonitoringEventsEnabled: true
agent:
...
```

ファイルを保存したら、以下のコマンドで変更を適用できます:

{{< tabs >}}
{{% tab title="Script" %}}

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

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
Release "splunk-otel-collector" has been upgraded. Happy Helming!
NAME: splunk-otel-collector
LAST DEPLOYED: Fri Dec 20 01:17:03 2024
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None
NOTES:
Splunk OpenTelemetry Collector is installed and configured to send data to Splunk Observability realm us1.
```

{{% /tab %}}
{{< /tabs >}}

次に、config map を確認して変更が適用されたことを確認できます:

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
kubectl describe cm splunk-otel-collector-otel-k8s-cluster-receiver
```

{{% /tab %}}
{{% tab title="Example Output" %}}

`smartagent/kubernetes-events` が agent の設定に含まれていることを確認してください:

``` bash
  smartagent/kubernetes-events:
    alwaysClusterReporter: true
    type: kubernetes-events
    whitelistedEvents:
    - involvedObjectKind: Pod
      reason: Created
    - involvedObjectKind: Pod
      reason: Unhealthy
    - involvedObjectKind: Pod
      reason: Failed
    - involvedObjectKind: Job
      reason: FailedCreate
```

{{% /tab %}}
{{< /tabs >}}

> この特定の変更が適用される場所であるため、cluster receiver の config map を指定したことに注意してください。

## Debug Exporter の追加

Collector に送信されるトレースとログを確認して、Splunk に送信する前に検査したい場合があります。debug exporter を使用すると、OpenTelemetry 関連の問題のトラブルシューティングに役立ちます。

values.yaml ファイルの末尾に debug exporter を以下のように追加しましょう:

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

ファイルを保存したら、以下のコマンドで変更を適用できます:

{{< tabs >}}
{{% tab title="Script" %}}

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

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
Release "splunk-otel-collector" has been upgraded. Happy Helming!
NAME: splunk-otel-collector
LAST DEPLOYED: Fri Dec 20 01:32:03 2024
NAMESPACE: default
STATUS: deployed
REVISION: 3
TEST SUITE: None
NOTES:
Splunk OpenTelemetry Collector is installed and configured to send data to Splunk Observability realm us1.
```

{{% /tab %}}
{{< /tabs >}}

curl を使用してアプリケーションを数回実行し、以下のコマンドで agent collector のログを tail します:

``` bash
kubectl logs -l component=otel-collector-agent -f
```

以下のようなトレースが agent collector のログに出力されるはずです:

````
2024-12-20T01:43:52.929Z	info	Traces	{"kind": "exporter", "data_type": "traces", "name": "debug", "resource spans": 1, "spans": 2}
2024-12-20T01:43:52.929Z	info	ResourceSpans #0
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
     -> container.id: Str(78b452a43bbaa3354a3cb474010efd6ae2367165a1356f4b4000be031b10c5aa)
     -> telemetry.sdk.name: Str(opentelemetry)
     -> telemetry.sdk.language: Str(dotnet)
     -> telemetry.sdk.version: Str(1.9.0)
     -> service.name: Str(helloworld)
     -> deployment.environment: Str(otel-derek-1)
     -> k8s.pod.ip: Str(10.42.0.15)
     -> k8s.pod.labels.app: Str(helloworld)
     -> k8s.pod.name: Str(helloworld-84865965d9-nkqsx)
     -> k8s.namespace.name: Str(default)
     -> k8s.pod.uid: Str(38d39bc6-1309-4022-a569-8acceef50942)
     -> k8s.node.name: Str(derek-1)
     -> k8s.cluster.name: Str(derek-1-cluster)
````

また、以下のようなログエントリも表示されます:

````
2024-12-20T01:43:53.215Z	info	Logs	{"kind": "exporter", "data_type": "logs", "name": "debug", "resource logs": 1, "log records": 2}
2024-12-20T01:43:53.215Z	info	ResourceLog #0
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
     -> container.id: Str(78b452a43bbaa3354a3cb474010efd6ae2367165a1356f4b4000be031b10c5aa)
     -> telemetry.sdk.name: Str(opentelemetry)
     -> telemetry.sdk.language: Str(dotnet)
     -> telemetry.sdk.version: Str(1.9.0)
     -> service.name: Str(helloworld)
     -> deployment.environment: Str(otel-derek-1)
     -> k8s.node.name: Str(derek-1)
     -> k8s.cluster.name: Str(derek-1-cluster)
````

ただし、Splunk Observability Cloud に戻ると、アプリケーションからトレースとログが送信されなくなっていることに気づくでしょう。

なぜそうなるのでしょうか？次のセクションで探ってみましょう。
