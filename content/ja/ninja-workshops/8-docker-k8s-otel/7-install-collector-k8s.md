---
title: K8s への OpenTelemetry Collector のインストール
linkTitle: 7. K8s への OpenTelemetry Collector のインストール
weight: 7
time: 15 minutes
---

## ワークショップ Part 1 の振り返り

ワークショップのここまでで、以下を完了しました:

* Linux ホストに Splunk distribution of the OpenTelemetry Collector をデプロイしました
* トレースとメトリクスを Splunk Observability Cloud に送信するように設定しました
* .NET アプリケーションをデプロイし、OpenTelemetry で計装しました
* .NET アプリケーションを Docker 化し、トレースが o11y cloud に送信されていることを確認しました

上記の手順を**まだ完了していない**場合は、ワークショップの残りの部分に進む前に、以下のコマンドを実行してください:

``` bash
cp /home/splunk/workshop/docker-k8s-otel/docker/Dockerfile /home/splunk/workshop/docker-k8s-otel/helloworld/
cp /home/splunk/workshop/docker-k8s-otel/docker/entrypoint.sh /home/splunk/workshop/docker-k8s-otel/helloworld/
````

> **重要** これらのファイルをコピーしたら、エディタで `/home/splunk/workshop/docker-k8s-otel/helloworld/Dockerfile` を開き、
> Dockerfile 内の `$INSTANCE` をインスタンス名に置き換えてください。
> インスタンス名は `echo $INSTANCE` を実行して確認できます。

## ワークショップ Part 2 の紹介

ワークショップの次のパートでは、アプリケーションを Kubernetes で実行したいので、
Kubernetes クラスターに Splunk distribution of the OpenTelemetry Collector を
デプロイする必要があります。

まず、いくつかの重要な用語を定義しましょう。

### 重要な用語

#### Kubernetes とは？

_「Kubernetes は、コンテナ化されたワークロードやサービスを管理するための、
ポータブルで拡張可能なオープンソースプラットフォームであり、宣言的な設定と自動化の両方を促進します。」_

出典:  https://kubernetes.io/docs/concepts/overview/

Dockerfile に小さな変更を加えた後、先ほどアプリケーション用に作成した Docker イメージを
Kubernetes クラスターにデプロイします。

#### Helm とは？

Helm は Kubernetes のパッケージマネージャーです。

_「最も複雑な Kubernetes アプリケーションでも、定義、インストール、アップグレードを支援します。」_

出典:  https://helm.sh/

Helm を使用して、K8s クラスターに OpenTelemetry collector をデプロイします。

#### Helm の利点

* 複雑さの管理
  * 数十のマニフェストファイルではなく、単一の values.yaml ファイルで対応
* 簡単なアップデート
  * インプレースアップグレード
* ロールバックサポート
  * helm rollback を使用するだけで、リリースの古いバージョンにロールバック可能

## ホスト Collector のアンインストール

先に進む前に、先ほど Linux ホストにインストールした collector を削除しましょう:

``` bash
curl -sSL https://dl.signalfx.com/splunk-otel-collector.sh > /tmp/splunk-otel-collector.sh;
sudo sh /tmp/splunk-otel-collector.sh --uninstall
```

## Helm を使用した Collector のインストール

製品内ウィザードではなく、コマンドラインを使用して独自の
`helm` コマンドを作成し、collector をインストールしましょう。

まず、helm リポジトリを追加する必要があります:

``` bash
helm repo add splunk-otel-collector-chart https://signalfx.github.io/splunk-otel-collector-chart
```

そして、リポジトリが最新であることを確認します:

``` bash
helm repo update
```

helm chart のデプロイを設定するために、
`/home/splunk` ディレクトリに `values.yaml` という名前の新しいファイルを作成しましょう:

``` bash
# /home/splunk ディレクトリに移動
cd /home/splunk
# vi で values.yaml ファイルを作成
vi values.yaml
```
> 以下のテキストを貼り付ける前に、vi で 'i' を押して挿入モードに入ってください。

次に、以下の内容を貼り付けます:

``` yaml
logsEngine: otel
agent:
  config:
    receivers:
      hostmetrics:
        collection_interval: 10s
        root_path: /hostfs
        scrapers:
          cpu: null
          disk: null
          filesystem:
            exclude_mount_points:
              match_type: regexp
              mount_points:
              - /var/*
              - /snap/*
              - /boot/*
              - /boot
              - /opt/orbstack/*
              - /mnt/machines/*
              - /Users/*
          load: null
          memory: null
          network: null
          paging: null
          processes: null
```

> vi で変更を保存するには、`esc` キーを押してコマンドモードに入り、`:wq!` と入力してから `enter/return` キーを押します。

これで、以下のコマンドを使用して collector をインストールできます:

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
  helm install splunk-otel-collector --version {{< otel-version >}} \
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
NAME: splunk-otel-collector
LAST DEPLOYED: Fri Dec 20 01:01:43 2024
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Splunk OpenTelemetry Collector is installed and configured to send data to Splunk Observability realm us1.
```

{{% /tab %}}
{{< /tabs >}}

## Collector が実行中であることを確認する

以下のコマンドで collector が実行中かどうかを確認できます:

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
kubectl get pods
```

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
NAME                                                         READY   STATUS    RESTARTS   AGE
splunk-otel-collector-agent-dkn88                            1/1     Running   0          53s
splunk-otel-collector-agent-ksmh4                            1/1     Running   0          53s
splunk-otel-collector-agent-lc2lf                            1/1     Running   0          53s
splunk-otel-collector-k8s-cluster-receiver-dbf64995b-xgm9b   1/1     Running   0          53s
```

{{% /tab %}}
{{< /tabs >}}

## K8s クラスターが O11y Cloud に表示されていることを確認する

Splunk Observability Cloud で、**Infrastructure** -> **Kubernetes** -> **Kubernetes Clusters** に移動し、
クラスター名（`$INSTANCE-cluster`）を検索します:

![Kubernetes node](../images/k8snode.png)
