---
title: LLM アプリケーションのデプロイ
linkTitle: 5. LLM アプリケーションのデプロイ
weight: 5
time: 10 minutes
---

このワークショップの最終ステップでは、NVIDIA NIM オペレーターを使用して先ほどデプロイした instruct モデルと embeddings モデルを使用するアプリケーションを OpenShift クラスターにデプロイします。

## アプリケーションの概要

LLM と対話するほとんどのアプリケーションと同様に、このアプリケーションは Python で書かれています。また、LLM を活用したアプリケーションの開発を簡素化するオープンソースのオーケストレーションフレームワークである [LangChain](https://www.langchain.com/) も使用しています。

アプリケーションは、使用する2つの LLM に接続することから始まります：

* `meta/llama-3.2-1b-instruct`：ユーザーのプロンプトに応答するために使用
* `nvidia/llama-3.2-nv-embedqa-1b-v2`：埋め込みを計算するために使用

``` python
# connect to a LLM NIM at the specified endpoint, specifying a specific model
llm = ChatNVIDIA(base_url=INSTRUCT_MODEL_URL, model="meta/llama-3.2-1b-instruct")

# Initialize and connect to a NeMo Retriever Text Embedding NIM (nvidia/llama-3.2-nv-embedqa-1b-v2)
embeddings_model = NVIDIAEmbeddings(model="nvidia/llama-3.2-nv-embedqa-1b-v2",
                                   base_url=EMBEDDINGS_MODEL_URL)
```

両方の LLM に使用される URL は `k8s-manifest.yaml` ファイルで定義されています：

``` yaml
    - name: INSTRUCT_MODEL_URL
      value: "http://meta-llama-3-2-1b-instruct.nim-service:8000/v1"
    - name: EMBEDDINGS_MODEL_URL
      value: "http://llama-32-nv-embedqa-1b-v2.nim-service:8000/v1"
```

次に、アプリケーションは LLM とのインタラクションで使用されるプロンプトテンプレートを定義します：

``` python
prompt = ChatPromptTemplate.from_messages([
    ("system",
        "You are a helpful and friendly AI!"
        "Your responses should be concise and no longer than two sentences."
        "Do not hallucinate. Say you don't know if you don't have this information."
        "Answer the question using only the context"
        "\n\nQuestion: {question}\n\nContext: {context}"
    ),
    ("user", "{question}")
])
```

> LLM に対して、回答がわからない場合はわからないと言うよう明示的に指示していることに注目してください。これにより、ハルシネーションを最小限に抑えることができます。また、LLM が質問に回答するために使用できるコンテキストを提供するためのプレースホルダーもあります。

アプリケーションは Flask を使用し、エンドユーザーからの質問に応答するために `/askquestion` という単一のエンドポイントを定義しています。このエンドポイントを実装するために、アプリケーションは Weaviate ベクトルデータベースに接続し、ユーザーの質問を受け取り、それを埋め込みに変換し、ベクトルデータベースで類似のドキュメントを検索するチェーン（LangChain を使用）を呼び出します。その後、ユーザーの質問を関連ドキュメントと共に LLM に送信し、LLM のレスポンスを返します。

``` python
   # connect with the vector store that was populated earlier
    vector_store = WeaviateVectorStore(
        client=weaviate_client,
        embedding=embeddings_model,
        index_name="CustomDocs",
        text_key="page_content"
    )

    chain = (
        {
            "context": vector_store.as_retriever(),
            "question": RunnablePassthrough()
        }
        | prompt
        | llm
        | StrOutputParser()
    )

    response = chain.invoke(question)
```

## OpenTelemetry でアプリケーションを計装する

アプリケーションからメトリクス、トレース、ログをキャプチャするために、OpenTelemetry で計装しました。これには、`requirements.txt` ファイルに以下のパッケージを追加する必要がありました（最終的に `pip install` でインストールされます）：

````
splunk-opentelemetry==2.7.0
````

また、このアプリケーションのコンテナイメージをビルドするために使用される `Dockerfile` に以下を追加して、追加の OpenTelemetry 計装パッケージをインストールしました：

``` dockerfile
# Add additional OpenTelemetry instrumentation packages
RUN opentelemetry-bootstrap --action=install
```

次に、アプリケーション実行時に `opentelemetry-instrument` を呼び出すように `Dockerfile` の `ENTRYPOINT` を変更しました：

``` dockerfile
ENTRYPOINT ["opentelemetry-instrument", "flask", "run", "-p", "8080", "--host", "0.0.0.0"]
```

最後に、OpenTelemetry で収集されるトレースとメトリクスを強化するために、[OpenLIT](https://openlit.io/) というパッケージを `requirements.txt` ファイルに追加しました：

````
openlit==1.35.4
````

OpenLIT は LangChain をサポートしており、計装時にトレースにリクエストの処理に使用されたトークン数やプロンプトとレスポンスの内容などの追加コンテキストを追加します。

OpenLIT を初期化するために、アプリケーションコードに以下を追加しました：

``` python
import openlit
...
openlit.init(environment="llm-app")
```

## LLM アプリケーションのデプロイ

以下のコマンドを使用して、このアプリケーションを OpenShift クラスターにデプロイします：

``` bash
oc apply -f ./llm-app/k8s-manifest.yaml
```

> 注：この Python アプリケーションの Docker イメージをビルドするために、以下のコマンドを実行しました：
> ``` bash
> cd workshop/cisco-ai-pods/llm-app
> docker build --platform linux/amd64 -t derekmitchell399/llm-app:1.0 .
> docker push derekmitchell399/llm-app:1.0
> ```

## LLM アプリケーションのテスト

アプリケーションが期待どおりに動作していることを確認しましょう。

curl コマンドにアクセスできる Pod を起動します：

``` bash
oc run --rm -it curl --image=curlimages/curl:latest -- sh
```

次に、以下のコマンドを実行して LLM に質問を送信します：

{{< tabs >}}
{{% tab title="Script" %}}

``` bash
curl -X "POST" \
 'http://llm-app:8080/askquestion' \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "question": "How much memory does the NVIDIA H200 have?"
  }'
```

{{% /tab %}}
{{% tab title="Example Output" %}}

``` bash
The NVIDIA H200 has 141GB of HBM3e memory, which is twice the capacity of the NVIDIA H100 Tensor Core GPU with 1.4X more memory bandwidth.
```

{{% /tab %}}
{{< /tabs >}}

## Splunk Observability Cloud でトレースデータを表示する

Splunk Observability Cloud で `APM` に移動し、`Service Map` を選択します。環境名が選択されていることを確認してください（例：`rosa-workshop-participant-1`）。以下のようなサービスマップが表示されるはずです：

![Service Map](../../images/ServiceMap.png)

右側のメニューで `Traces` をクリックします。次に、実行時間の長いトレースの1つを選択します。以下の例のように表示されるはずです：

![Trace](../../images/Trace.png)

このトレースは、ユーザーの質問（例：「How much memory does the NVIDIA H200 have?」）に回答するためにアプリケーションが実行したすべてのインタラクションを示しています。

たとえば、アプリケーションが Weaviate ベクトルデータベースで質問に関連するドキュメントを検索するために類似性検索を実行した箇所を確認できます：

![Document Retrieval](../../images/DocumentRetrieval.png)

また、ベクトルデータベースから取得したコンテキストを含めて、アプリケーションが LLM に送信するプロンプトを作成した方法も確認できます：

![Prompt Template](../../images/PromptTemplate.png)

最後に、LLM からのレスポンス、所要時間、使用された入出力トークン数を確認できます：

![LLM Response](../../images/LLMResponse.png)
