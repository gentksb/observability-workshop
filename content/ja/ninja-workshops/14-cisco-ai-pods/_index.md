---
title: Splunk Observability Cloud による Cisco AI Pods の監視
linkTitle: Splunk Observability Cloud による Cisco AI Pods の監視
weight: 14
archetype: chapter
time: 2 minutes
authors: ["Derek Mitchell"]
description: このハンズオンワークショップでは、Splunk Observability Cloud を使用して Cisco AI Pods を監視する方法を説明します。Red Hat OpenShift に OpenTelemetry Collector をデプロイし、Prometheus レシーバーを使用してインフラストラクチャメトリクスを取り込み、Large Language Models (LLMs) と連携する Python サービスを監視するための APM を設定する方法を学びます。
draft: false
hidden: false
---

**Cisco AI-ready PODs** は、ハードウェアとソフトウェアの最高の技術を組み合わせて、多様なニーズに対応する堅牢でスケーラブルかつ効率的な AI 対応インフラストラクチャを構築します。

**Splunk Observability Cloud** は、このインフラストラクチャ全体と、このスタック上で実行されているすべてのアプリケーションコンポーネントに対する包括的な可視性を提供します。

Cisco AI POD 環境向けに Splunk Observability Cloud を設定する手順は完全にドキュメント化されています（詳細は[こちら](https://github.com/signalfx/splunk-opentelemetry-examples/tree/main/collector/cisco-ai-ready-pods)を参照してください）。

ただし、インストール手順を練習するために Cisco AI POD 環境にアクセスできるとは限りません。

このワークショップでは、実際の Cisco AI POD にアクセスすることなく、Splunk Observability Cloud で Cisco AI PODs を監視するために使用されるいくつかの技術をデプロイして操作するハンズオン体験を提供します。以下の内容が含まれます：

* Red Hat OpenShift クラスターに **OpenTelemetry Collector** をデプロイする練習
* インフラストラクチャメトリクスを取り込むためにコレクターに **Prometheus** レシーバーを追加する練習
* クラスターに **Weaviate** ベクトルデータベースをデプロイする練習
* Large Language Models (LLMs) と連携する Python サービスを **OpenTelemetry** で計装する練習
* LLM と連携するアプリケーションのトレースで OpenTelemetry がキャプチャする詳細情報の理解

> 注: ワークショップのセットアップセクションは、ワークショップの主催者のみが実行する必要があります

{{% notice title="Tip" style="primary"  icon="lightbulb" %}}
このワークショップを進める最も簡単な方法は以下を使用することです：

* このページの右上にある左右の矢印（**<** | **>**）
* キーボードの左（◀️）と右（▶️）のカーソルキー
  {{% /notice %}}
