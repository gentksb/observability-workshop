---
title: Demo-in-a-Box の実行
weight: 3
description: Demo-in-a-Box を使用して、使いやすいウェブインターフェースでデモと otel collector を管理する方法を学びます。
draft: true
---

**Demo-in-a-box** は、ウェブインターフェースを使用してデモアプリを簡単に実行する方法です。

以下の機能を提供します：

* デモアプリとその状態を素早くデプロイする方法
* otel collector の設定を簡単に変更し、ログを確認する方法
* Pod のステータスや Pod ログなどを取得する機能

multipass を使用してローカルで利用するには：

* [local hosting for multipass](../multipass) の手順に従ってください
  * `terraform.tfvars` ファイルで、`splunk_diab` を `true` に設定し、**他のすべて**のオプションが `false` に設定されていることを確認してください
  * 次に、必要なトークンや URL を設定してください
  * その後、terraform のステップを実行してください
* インスタンスが起動したら、ブラウザで `http://<IP>:8083` にアクセスしてください
  * `terraform.tfvars` ファイルでは、`wsversion` はデフォルトでワークショップの現在のバージョン（例：`4.64`）に設定されています：
    * 最新の開発版を使用するには、`wsversion` を `main` に変更してください
    * ワークショップは3つのバージョンのみがメンテナンスされています：開発版（`main`）、現行版（例：`4.64`）、および前のバージョン（例：`4.63`）
    * 変更後、`terraform apply` を実行して変更を適用してください
* これでどのデモでもデプロイできます。デプロイの一部として collector も一緒にデプロイされます
