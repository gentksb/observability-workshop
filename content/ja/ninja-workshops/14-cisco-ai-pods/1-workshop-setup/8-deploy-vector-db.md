---
title: ベクトルデータベースのデプロイ
linkTitle: 8. ベクトルデータベースのデプロイ
weight: 8
time: 10 minutes
---

このステップでは、OpenShift クラスターにベクトルデータベースをデプロイし、ワークショップ参加者が使用するテストデータを投入します。

## ベクトルデータベースのデプロイ

このワークショップでは、[Weaviate](https://weaviate.io/) というオープンソースのベクトルデータベースをデプロイします。

まず、Weaviate helm chart を含む Weaviate helm リポジトリを追加します。

``` bash
helm repo add weaviate https://weaviate.github.io/weaviate-helm
helm repo update
```

`weaviate/weaviate-values.yaml` ファイルには、Weaviate ベクトルデータベースをデプロイするために使用する設定が含まれています。

Weaviate が後で Prometheus receiver でスクレイプできるメトリクスを公開するように、以下の環境変数を `TRUE` に設定しています。

````
  PROMETHEUS_MONITORING_ENABLED: true
  PROMETHEUS_MONITORING_GROUP: true
````

利用可能な追加のカスタマイズオプションについては、[Weaviate documentation](https://docs.weaviate.io/deploy/installation-guides/k8s-installation) を確認してください。

新しい namespace を作成しましょう。

``` bash
oc create namespace weaviate
```

Weaviate が特権コンテナを実行できるようにするために、以下のコマンドを実行します。

> 注意: この方法は本番環境では推奨されません

``` bash
oc adm policy add-scc-to-user privileged -z default -n weaviate
```

次に Weaviate をデプロイします。

``` bash
helm upgrade --install \
  "weaviate" \
  weaviate/weaviate \
  --namespace "weaviate" \
  --values ./weaviate/weaviate-values.yaml
```

## ベクトルデータベースへのデータ投入

Weaviate が起動して実行されたので、ワークショップでカスタムアプリケーションと一緒に使用するデータを追加しましょう。

これを行うために使用されるアプリケーションは、[LangChain Playbook for NeMo Retriever Text Embedding NIM](https://docs.nvidia.com/nim/nemo-retriever/text-embedding/latest/playbook.html#generate-embeddings-with-text-embedding-nim) に基づいています。

`./load-embeddings/k8s-job.yaml` の設定に従って、[NVIDIA H200 Tensor Core GPU のデータシート](https://nvdam.widen.net/content/udc6mzrk7a/original/hpc-datasheet-sc23-h200-datasheet-3002446.pdf)をベクトルデータベースにロードします。

このドキュメントには、大規模言語モデルがトレーニングされていない NVIDIA H200 GPU に関する情報が含まれています。ワークショップの次のパートでは、ベクトルデータベースにロードされるこのドキュメントのコンテキストを使用して、LLM で質問に回答するアプリケーションを構築します。

OpenShift クラスターに Kubernetes Job をデプロイして、埋め込みをロードします。
このプロセスが一度だけ実行されるようにするために、Pod ではなく Kubernetes Job を使用します。

``` bash
oc create namespace llm-app
oc apply -f ./load-embeddings/k8s-job.yaml
```

> 注意: 埋め込みを Weaviate にロードする Python アプリケーションの Docker イメージをビルドするために、以下のコマンドを実行しました：
> ``` bash
> cd workshop/cisco-ai-pods/load-embeddings
> docker build --platform linux/amd64 -t derekmitchell399/load-embeddings:1.0 .
> docker push derekmitchell399/load-embeddings:1.0
> ```
