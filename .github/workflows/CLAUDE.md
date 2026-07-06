# GitHub Actions ワークフロー

このディレクトリには、Splunk Observability Workshopの日本語翻訳を自動化するGitHub Actionsワークフローが含まれています。

ブランチ構成の概要はリポジトリルートの `CLAUDE.md` を参照してください。

## sync-and-translate.yml

upstreamリポジトリの新しいリリースを検出し、日本語に自動翻訳してPRを作成します。

### トリガー

- **スケジュール**: 毎週月曜日9:00 JST (00:00 UTC)
- **手動実行**: `workflow_dispatch`

### 手動実行オプション

実行目的を `run_mode` で1つ選ぶ。boolean の組み合わせは廃止した。

| オプション | 値 / デフォルト | 使いどころ |
| --------- | -------------- | ---------- |
| `run_mode` | `auto`（デフォルト） | 定期実行と同じ。新リリースがあれば同期・翻訳する |
| | `retranslate-latest` | 翻訳品質に問題があったとき、最新リリース分（1つ前の翻訳タグとの差分）を訳し直す。比較ベースは `.last-translated-tag` のgit履歴から自動取得。レジューム復元は行わず全文翻訳する |
| | `fill-missing-translations` | 過去に失敗・スキップした未翻訳ファイル（`content/ja` に存在しないもの）を補完する。差分翻訳は行わない |
| | `cleanup-only` | 翻訳せず、陳腐化PRクローズ・forkブランチ削除だけを実行する |
| `dry_run` | false | 掃除の安全確認。クローズ・削除対象を一覧表示するだけで実行しない |
| `retry_attempt` | 0 | 内部用。タイムアウト自動リトライのカウンタ。手動実行では変更しない |

陳腐化PRの1回あたり処理上限はワークフロー env `CLEANUP_MAX_PRS`（既定 10）にハードコードしている。

### 処理フロー

翻訳ジョブは「機械同期 → 翻訳 → 構造検証」の3フェーズで構成し、LLMが生成するのは本文プローズだけに限定する。これにより英語版と日本語版で本文以外の差分が発生しにくくなる。

1. **新リリースチェック**: upstreamの最新タグを取得し、`.last-translated-tag` と比較
2. **mainブランチ同期**: 新しいタグがあれば、mainをupstreamのタグにリセット
3. **新ワークショップ検出**: 翻訳対象ファイルから新しいワークショップディレクトリを検出
4. **ミラー同期（Phase 1・機械）** (`sync-ja-mirror.sh`): md以外のアセット（画像等）を `content/en` → `content/ja` で常時ミラーし、en側に対応物のない ja側ファイル・ディレクトリ（レガシー資産）を削除。変更一覧はPR本文に記載
5. **翻訳（Phase 2・3段フォールバック）**: 変更されたファイルをClaude Code (Bedrock)で翻訳。マージ済みの既存訳があるファイルは全文再翻訳せず、enの変更hunkだけを反映する（後述）。前回実行が途中で失敗していた場合は、リモートの `translate/{tag}` ブランチから翻訳済みファイルを復元し、未翻訳分のみを翻訳して再開する（レジューム）
6. **構造検証（Phase 3・機械）** (`check-structure-parity.sh`): frontmatterキー・shortcode・見出しレベル・コードフェンス数を en/ja で比較し、不一致をPR本文に警告として記載
7. **PR作成**: upstreamリポジトリにPRを作成（新ワークショップがある場合はドラフトPR）
8. **陳腐化PRクローズ** (`cleanup-stale-prs`): 新PRより番号が小さい open な `translate/*` PR を upstream から自動クローズ。レビュー痕跡や人手コミットのある PR は skip して Slack に通知
9. **forkブランチ掃除** (`cleanup-fork-branches`): upstream PR が closed/merged の `translate/v*` ブランチを fork から削除
10. **タグ記録**: 翻訳したタグを `.last-translated-tag` に記録
11. **失敗時の自動リトライ** (`retry-on-failure`): 翻訳ジョブが失敗（タイムアウト含む）した場合、同一設定で自身を再dispatch（最大2回）。レジュームにより未翻訳分のみ処理される
12. **Slack通知**: ワークフロー実行結果を Slack に通知（新リリースなし・翻訳対象なしの場合も含む）

補助スクリプトは `ja-translation-system` ブランチの `.github/scripts/` で管理し、`Setup translation tools` ステップで translate ブランチの作業ツリーに取得する（indexには乗せないためコミットに混入しない）。

### 翻訳の3段フォールバック

マージ済みの既存訳（タグのコミットと一致し日本語を含む `content/ja` ファイル）がある変更ファイルは、次の順で処理する。新規ファイル・既存訳なし・`retranslate-latest` モードは最初から全文翻訳。

1. **機械パッチ（トークン消費ゼロ）** (`apply-en-patch.sh`): en側の `last_tag..new_tag` diff をhunk単位で ja ファイルに `git apply`。コードブロック・URL・英語のまま維持された箇所への変更（typo修正の大半）はここで反映される
2. **LLM差分翻訳**: 機械適用できなかったhunk（翻訳済みプローズへの変更）だけをdiffとしてLLMに渡し、既存訳への最小Editを生成。既存訳を保持するため訳ブレが減り、全文再翻訳よりトークン消費が大幅に少ない
3. **全文翻訳**: 1・2が失敗した場合のフォールバック（従来方式）

### 翻訳ルールの注入

translate ブランチには `.claude/` のSkillが存在しないため、翻訳ルール（用語集・文体・構造維持）は `ja-translation-system` ブランチの `translation-guide.md` を取得し、全claude呼び出しに `--append-system-prompt` で注入する。翻訳ルールの正本は `.claude/skills/splunk-workshop-ja-translator/references/translation-guide.md` の1ファイルで、ローカルSkill実行とCI実行の両方が同じルールを参照する。

### 陳腐化 PR / fork ブランチの自動整理

upstream のマージが翻訳PR生成より遅いと、古い未マージ翻訳PRが滞留する。これを `cleanup-stale-prs` / `cleanup-fork-branches` ジョブで毎回整理する。

**`cleanup-stale-prs`**:

- upstream の open な `translate/*` PR を fork 所有者で絞り込み
- 新しく作成した PR の番号より小さいものを対象とし、`gh pr view --json commits,reviews` で人手コミット・非PENDINGレビューがあるものは skip
- skip しなかった対象に「Superseded by #N (translation for vX.Y). Closing this PR.」コメントを残してクローズ
- env `CLEANUP_MAX_PRS`（既定 10）件まで処理。`dry_run=true` の場合は対象一覧の echo だけ実行
- `run_mode=cleanup-only` で dispatch すると、新PR作成をスキップして cleanup のみを実行（`needs.create-pr.outputs.pr_number` が空の場合は最新マージ済み翻訳PRを参照値として使用）

**`cleanup-fork-branches`**:

- `git ls-remote --heads origin 'translate/v*'` で fork のブランチ一覧を取得
- 各ブランチの upstream 側 PR 状態を確認し、`MERGED` / `CLOSED` / `NONE` のものを `git push origin --delete` で削除
- 現在進行中の `translate/{NEW_TAG}` は除外
- `dry_run=true` の場合は `[DRY-RUN] would delete ...` を echo するだけ

**レガシー翻訳ファイルの掃除**（`sync-ja-mirror.sh`、翻訳ジョブ内）:

- en側に対応物のない `content/ja` のファイル・ディレクトリを削除し、md以外のアセットを en から常時ミラー
- 削除・更新一覧はPR本文の「Asset sync and orphan cleanup」セクションに記載され、upstream PRレビューが安全弁になる
- upstreamのディレクトリ再編（例: ninja-workshops の番号付き構造→カテゴリ名への変更）にjaが追従していない場合、初回実行では削除が数百ファイル規模になりうる。PR diffを必ず確認すること

**安全装置**:

- env `CLEANUP_MAX_PRS` (default 10) で1回の実行件数を制限し、初回事故時の被害を局所化
- 各操作は `|| true` でループ続行。失敗しても次回実行で再試行可能
- `concurrency: sync-and-translate` グループで並走防止

### AWS認証（OIDC + credential_process）

Bedrockへの認証は `aws-actions/configure-aws-credentials` ではなく、AWS SDK の `credential_process` を使った都度更新方式を採用しています。

**背景**: `configure-aws-credentials` はジョブ冒頭に一度だけ一時クレデンシャルを取得して環境変数に固定するため、翻訳対象が多くジョブがIAMロールの `MaxSessionDuration`（組織ポリシーで延長不可）を超えるとクレデンシャルが失効し、ジョブが失敗していました。

**仕組み**:

1. `Configure refreshable AWS credentials` ステップが `~/.aws/oidc-credential-process.sh` と `~/.aws/config`（default プロファイルに `credential_process` を設定）を生成
2. claude プロセス（AWS SDK）がクレデンシャルを必要とするたびにスクリプトが実行され、GitHub OIDC トークンの再発行 → `AssumeRoleWithWebIdentity` を実行
3. 取得したクレデンシャルは `$RUNNER_TEMP` にキャッシュされ、失効5分前を切ると自動的に再取得

GitHub OIDC トークンは `id-token: write` 権限があればジョブ実行中いつでも再発行できるため、ジョブ全体の実行時間はセッション上限に縛られません（上限はジョブの `timeout-minutes: 300` のみ）。

### 翻訳のレジューム（途中再開）と自動リトライ

翻訳ジョブが途中で失敗・タイムアウトした場合でも、`Push translation branch` まで到達していれば翻訳結果はリモートの `translate/{tag}` ブランチに残ります。同じタグで再実行すると:

1. `Create translation branch` ステップがリモートの同名ブランチから `content/ja/` を復元（`retranslate-latest` モードは「訳し直し」が目的のため復元しない）
2. `Translate files` ステップが「ベースコミット（タグ）と差分があり、かつ日本語を含む」ファイルをスキップ（成功扱い）し、未翻訳分のみを翻訳

mainに既にマージ済みの古い翻訳はベースコミットと一致するため、スキップ対象にならず、既存訳を保持した差分パッチ方式で処理されます。

さらに `retry-on-failure` ジョブが、翻訳ジョブの失敗を検知すると同一の `run_mode` で自身を再dispatchします（`retry_attempt` カウンタで最大2回に制限）。`workflow_dispatch` は `GITHUB_TOKEN` の再帰トリガー制限の例外のため、PATなしで動作します。手動での再実行が必要になるのは、自動リトライ2回でも完了しなかった場合のみです。

### 新ワークショップ検出とドラフトPR

翻訳対象ファイルに新しいワークショップが含まれる場合、PRをドラフト状態で作成し、人間のレビューを促します。

**新ワークショップの判定基準**: 以下の2つのケースで「リリース済み新規ワークショップ」を検出します。

- **ケース1（新規ディレクトリ）**: `content/en/{category}/{workshop-name}/` レベルのディレクトリが前回翻訳タグ時点で存在せず、かつ `_index.md` の frontmatter に `draft: true` / `hidden: true` がない場合
- **ケース2（draft解除）**: 前回翻訳タグ時点で `draft: true` / `hidden: true` だったが、現在は解除または `false` に変更された場合

WorkshopはHugoの `draft: true` で開発を開始し、リリース時に削除または `false` に変更するフローのため、ディレクトリ作成だけでなくdraftステータスの変化もリリース検出の基準としています。

**動作**:

- 新ワークショップ検出時: `--draft` フラグ付きでPRを作成、PR本文に検出されたワークショップ一覧を記載
- 新ワークショップなし: 通常のPRを作成
- 初回実行（前回タグなし）: 検出をスキップし、通常のPRを作成

### Slack通知

`notify-slack` ジョブは `check-new-release` ジョブが成功した場合に常に実行され、ワークフローの実行結果を Slack Webhook に送信します。

**発火条件**: `check-new-release` ジョブが成功した場合（新リリースの有無に関わらず）

**ペイロード**:

| フィールド | 型 | 内容 |
| --------- | -- | ---- |
| `reason` | string | 実行結果の理由（下記参照） |
| `status` | string | `success` または `failure` |
| `hasNewWorkshopTranslation` | string | 新規ワークショップが含まれるか（`yes`/`no`） |
| `translatedMarkdownFileCount` | string | 翻訳成功ファイル数 |
| `failedFileCount` | string | 翻訳失敗ファイル数 |
| `pullRequestNumber` | string | 作成されたPR番号 |
| `staleClosedCount` | string | cleanup でクローズした陳腐化PR数 |
| `staleSkippedCount` | string | レビュー痕跡があり手動対応が必要な陳腐化PR数 |
| `staleSkippedPrs` | string | 手動対応が必要なPR番号一覧（例: `#511 #512`） |
| `forkBranchesDeleted` | string | fork から削除した translate/v* ブランチ数 |

**`reason` フィールドの値**:

| 値 | 意味 |
| -- | ---- |
| `translated` | 新バージョンあり・翻訳ファイルあり（通常フロー） |
| `no_translation_targets` | 新バージョンはあったが翻訳対象ファイルが0件 |
| `no_new_release` | スケジュール実行されたが新バージョンのリリースがなかった |

**必要なシークレット**: `SLACK_WEBHOOK_URL`

### 必要なシークレット

| シークレット | 用途 |
| ---------- | ---- |
| `AWS_ROLE_ARN` | AWS BedrockへのOIDCアクセス用IAMロールARN |
| `FORK_SYNC_PAT` | fork main を upstream タグに同期する push 用 PAT。`GITHUB_TOKEN` は `.github/workflows/` を含む push を拒否するため必要（`Contents: Read and write` + `Workflows: Read and write` を fork リポジトリのみに付与） |
| `UPSTREAM_PAT` | upstreamリポジトリへのPR作成用PAT（`Pull requests: Read and write` 権限が必要） |
| `SLACK_WEBHOOK_URL` | 実行結果通知用 Slack Webhook URL |

### 必要な権限

| 権限 | 用途 |
| --- | ---- |
| `id-token: write` | AWS OIDC認証 |
| `contents: write` | ブランチの作成・プッシュ |
| `pull-requests: write` | PRの作成 |

## 翻訳

- **翻訳モデル**: Claude Opus 4.6 (via AWS Bedrock)
- **翻訳スキル**: `.claude/skills/splunk-workshop-ja-translator/`
- **翻訳対象**: `content/en/**/*.md` → `content/ja/**/*.md`（関連する `img/` も含む）

### PRレビューチェックリスト

- [ ] Markdownが正しくレンダリングされる
- [ ] すべてのリンクが機能する
- [ ] コードブロックが変更されていない
- [ ] 用語が一貫している
- [ ] 太字マークアップが正しく表示される

## セットアップ手順

### 1. ブランチ構成の設定

```bash
git checkout -b ja-translation-system
git checkout main
git remote add upstream https://github.com/splunk/observability-workshop.git
git fetch upstream
git reset --hard upstream/main
git push origin main --force
```

### 2. GitHubリポジトリ設定

1. **デフォルトブランチの変更**: Settings → General → Default branch → `ja-translation-system`
2. **ブランチ保護ルール**: `main` と `ja-translation-system` を保護（`main` はforce pushを許可）

### 3. シークレットの設定

- `AWS_ROLE_ARN`: AWS BedrockへのOIDCアクセス用IAMロールARN
- `FORK_SYNC_PAT`: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
  - Resource owner: fork 所有者（例: `gentksb`）
  - Repository access: `gentksb/observability-workshop` のみ
  - Permissions: `Contents: Read and write`、`Workflows: Read and write`
  - 有効期限: 90日（Splunk enterprise要件）
- `UPSTREAM_PAT`: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
  - Resource owner: `splunk`
  - Repository access: `splunk/observability-workshop`
  - Permissions: `Pull requests: Read and write`

### 4. AWS OIDC設定

GitHub ActionsからAWS Bedrockにアクセスするために、OIDCプロバイダーとIAMロールを設定します。

## トラブルシューティング

| 問題 | 確認事項 |
| ---- | ------- |
| 翻訳が実行されない | upstreamに新しいタグがあるか確認。`.last-translated-tag` の内容を確認。翻訳し直したい場合は `run_mode=retranslate-latest`、未翻訳の穴埋めは `run_mode=fill-missing-translations` で手動実行 |
| 翻訳が失敗する | AWS認証情報の設定を確認。Claude Code CLIのバージョンを確認。ログでエラーメッセージを特定 |
| `ExpiredToken` / 認証エラーで失敗する | `Configure refreshable AWS credentials` ステップの `aws sts get-caller-identity` 検証結果を確認。`AWS_ROLE_ARN` シークレットとIAMロールの信頼ポリシー（OIDCプロバイダー設定）を確認 |
| ジョブがタイムアウトした | `retry-on-failure` ジョブが最大2回まで自動で再dispatchする（レジュームにより未翻訳分のみ処理）。それでも完了しない場合のみ手動で再実行 |
| 翻訳品質に問題があるファイルが混ざった | `run_mode=retranslate-latest` で最新リリース分を全文訳し直す（レジューム復元は行われない） |
| PR本文に Structure parity warnings が出た | 該当ファイルの frontmatter・shortcode・見出し・コードフェンスを en 側と目視比較し、PR上で修正する。恒常的に出る場合は翻訳ルール（translation-guide.md）の強化を検討 |
| PR本文の orphan cleanup で意図しない削除が出た | en側のディレクトリ再編・リネームに追随した削除かをPR diffで確認。ja側に意図的に残すファイルがある場合は仕組み上サポート外（enミラーが正） |
| Bedrockのスロットリングが頻発する | ワークフロー env の `TRANSLATE_PARALLEL_JOBS`（デフォルト4）を下げる |
| upstream へのPR作成失敗 | `UPSTREAM_PAT` の設定・有効期限・権限を確認 |
| `refusing to allow ... without workflows permission` エラー | `FORK_SYNC_PAT` 未設定または `Workflows: Read and write` 権限不足。GitHub の Fine-grained PAT を再発行し fork リポジトリのみに `Contents` + `Workflows` の write を付与 |

## セキュリティ設計

このワークフローはfork内のmainブランチへのforce pushと、upstreamへのPR作成という強い権限を扱います。設計上の前提は `.github/SECURITY-NOTES.md` に詳細を記載しています。設定変更時は以下を遵守してください。

### 禁止事項

- **`pull_request` / `pull_request_target` トリガーの追加禁止**: PR経由で渡されたコードが secrets にアクセスできる経路が開きます。fork からの PR では GitHub が secrets を渡さない仕様で守られていますが、トリガーを追加すると同一リポジトリ内 PR からの攻撃面が広がります。
- **secret の使用箇所拡大の禁止**: `FORK_SYNC_PAT` は `Sync main with upstream` ステップのみ、`UPSTREAM_PAT` は `create-pr` ジョブのみ。他のステップから参照しないでください。
- **`permissions:` の broad 化禁止**: ジョブ単位で必要最小限のキーのみ指定。グローバル `permissions: {}` は維持してください。

### レビュー必須化

`.github/workflows/`、`.github/CODEOWNERS`、`.claude/` への変更は CODEOWNERS により @gentksb のレビューが必須です。`main` および `ja-translation-system` ブランチのブランチ保護で「Require review from Code Owners」を有効化してください。

### PAT ローテーション

`FORK_SYNC_PAT` および `UPSTREAM_PAT` は90日ごとに更新してください（Splunk enterprise要件）。手順は `.github/SECURITY-NOTES.md` を参照。

### 根拠

- [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [Permissions required for fine-grained PATs](https://docs.github.com/en/rest/overview/permissions-required-for-fine-grained-personal-access-tokens)
