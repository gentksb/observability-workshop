---
title: EC2 インスタンスへの接続
linkTitle: 1. EC2 インスタンスへの接続
weight: 1
time: 5 minutes
---

## EC2 インスタンスに接続する

各参加者用に AWS/EC2 上に Ubuntu Linux インスタンスを用意しています。

インストラクターから提供された IP アドレスとパスワードを使用して、以下のいずれかの方法で EC2 インスタンスに接続してください：

* Mac OS / Linux
    * ssh splunk@IP address
* Windows 10+
    * OpenSSH クライアントを使用します
* 以前のバージョンの Windows
    * Putty を使用します

## OpenShift CLI のインストール

OpenShift クラスターにアクセスするには、OpenShift CLI をインストールする必要があります。

以下のコマンドを使用して、OpenShift CLI バイナリを EC2 インスタンスに直接ダウンロードできます：

````
curl -L -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
````

内容を展開します：

````
tar -xvzf openshift-client-linux.tar.gz
````

生成されたファイル（`oc` と `kubectl`）をパスに含まれる場所に移動します。例えば：

``` bash
sudo mv oc /usr/local/bin/oc
sudo mv kubectl /usr/local/bin/kubectl
```

## OpenShift クラスターへの接続

Kube config ファイルが splunk ユーザーによって変更可能であることを確認します：

``` bash
chmod 600 /home/splunk/.kube/config
```

ワークショップ主催者から提供されたクラスター API、参加者ユーザー名、およびパスワードを使用して OpenShift クラスターにログインします：

``` bash
oc login https://api.<cluster-domain>:443 -u participant1 -p '<password>'
```

OpenShift クラスターに接続されていることを確認します：

``` bash
oc whoami --show-server
```

以下のような結果が返されるはずです：

````
https://api.***.openshiftapps.com:443
````
