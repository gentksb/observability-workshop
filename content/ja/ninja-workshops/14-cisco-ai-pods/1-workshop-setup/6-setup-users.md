---
title: ユーザーのセットアップ
linkTitle: 6. ユーザーのセットアップ
weight: 6
time: 5 minutes
---

このセクションでは、ワークショップ参加者ごとにユーザーを作成し、それぞれに namespace とリソースクォータを割り当てます。

## ユーザーの Namespace とリソースクォータの作成

``` bash
cd user-setup
./create-namespaces.sh
```

## ユーザーの作成

参加者の認証情報を含む HTPasswd ファイルを作成し、ROSA 管理の HTPasswd IdP をカスタムのものに置き換えます:

``` bash
./create-users.sh
```

## cluster-admin ユーザーの再作成と再ログイン

cluster-admin ユーザーを再作成し、再度ログインします:

``` bash
rosa create admin -c rosa-test
oc login <Cluster API URL> --username cluster-admin --password <cluster admin password>
```

## ユーザーへのロール追加

各ユーザーに自分の namespace のみへのアクセス権を付与します:

``` bash
./add-role-to-users.sh
```


## ログインのテスト

### OpenShift CLI のインストール

ローカルマシンからログインをテストするには、OpenShift CLI をインストールする必要があります。

MacOS の場合、Homebrew パッケージマネージャーを使用して OpenShift CLI をインストールできます:

``` bash
brew install openshift-cli
```

その他のインストールオプションについては、[OpenShift documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.8/html/cli_tools/openshift-cli-oc) を参照してください。

### ワークショップユーザーとしてログイン

ローカルマシンからワークショップユーザーの一人としてログインを試みます:

``` bash
oc login https://api.<cluster-domain>:443 -u participant1 -p 'TempPass123!'
```

以下のようなメッセージが表示されるはずです:

````
Login successful.

You have one project on this server: "workshop-participant-1"
````

### LLM へのアクセス確認

ワークショップユーザーアカウントから LLM にアクセスできることを確認しましょう。

curl コマンドにアクセスできる Pod を起動します:

``` bash
oc run --rm -it curl --image=curlimages/curl:latest -- sh
```

次に、以下のコマンドを実行して LLM にプロンプトを送信します:

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
curl -X "POST" \
 'http://meta-llama-3-2-1b-instruct.nim-service:8000/v1/chat/completions' \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
        "model": "meta/llama-3.2-1b-instruct",
        "messages": [
        {
          "content":"What is the capital of Canada?",
          "role": "user"
        }],
        "top_p": 1,
        "n": 1,
        "max_tokens": 1024,
        "stream": false,
        "frequency_penalty": 0.0,
        "stop": ["STOP"]
      }'
```

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
{
  "id": "chatcmpl-2ccfcd75a0214518aab0ef0375f8ca21",
  "object": "chat.completion",
  "created": 1758919002,
  "model": "meta/llama-3.2-1b-instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "reasoning_content": null,
        "content": "The capital of Canada is Ottawa.",
        "tool_calls": []
      },
      "logprobs": null,
      "finish_reason": "stop",
      "stop_reason": null
    }
  ],
  "usage": {
    "prompt_tokens": 42,
    "total_tokens": 50,
    "completion_tokens": 8,
    "prompt_tokens_details": null
  },
  "prompt_logprobs": null
}
```

{{% /tab %}}
{{< /tabs >}}
