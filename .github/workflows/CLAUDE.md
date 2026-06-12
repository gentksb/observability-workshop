# GitHub Actions ワークフロー

このディレクトリには、Splunk Observability Workshopの日本語翻訳を自動化するGitHub Actionsワークフローが含まれています。

ブランチ構成の概要はリポジトリルートの `CLAUDE.md` を参照してください。

## sync-and-translate.yml

upstreamリポジトリの新しいリリースを検出し、日本語に自動翻訳してPRを作成します。

### トリガー

- **スケジュール**: 毎週月曜日9:00 JST (00:00 UTC)
- **手動実行**: `workflow_dispatch`

### 手動実行オプション

| オプション | 説明 | デフォルト |
| --------- | ---- | --------- |
| `force_translate` | 新しいタグがなくても翻訳を実行 | false |
| `translate_all_untranslated` | すべての未翻訳コンテンツも翻訳 | false |
| `cleanup_only` | sync/translate/PR作成をスキップし、cleanup ジョブだけを実行 | false |
| `cleanup_dry_run` | cleanup の対象一覧を出力するだけで close/delete を実行しない | false |
| `cleanup_max_prs` | 1回の実行で処理する陳腐化PRの上限（安全装置） | 10 |

### 処理フロー

1. **新リリースチェック**: upstreamの最新タグを取得し、`.last-translated-tag` と比較
2. **mainブランチ同期**: 新しいタグがあれば、mainをupstreamのタグにリセット
3. **新ワークショップ検出**: 翻訳対象ファイルから新しいワークショップディレクトリを検出
4. **翻訳**: 変更されたファイルをClaude Code (Bedrock)で翻訳。前回実行が途中で失敗していた場合は、リモートの `translate/{tag}` ブランチから翻訳済みファイルを復元し、未翻訳分のみを翻訳して再開する（レジューム）
5. **PR作成**: upstreamリポジトリにPRを作成（新ワークショップがある場合はドラフトPR）
6. **陳腐化PRクローズ** (`cleanup-stale-prs`): 新PRより番号が小さい open な `translate/*` PR を upstream から自動クローズ。レビュー痕跡や人手コミットのある PR は skip して Slack に通知
7. **forkブランチ掃除** (`cleanup-fork-branches`): upstream PR が closed/merged の `translate/v*` ブランチを fork から削除
8. **タグ記録**: 翻訳したタグを `.last-translated-tag` に記録
9. **Slack通知**: ワークフロー実行結果を Slack に通知（新リリースなし・翻訳対象なしの場合も含む）

### 陳腐化 PR / fork ブランチの自動整理

upstream のマージが翻訳PR生成より遅いと、古い未マージ翻訳PRが滞留する。これを `cleanup-stale-prs` / `cleanup-fork-branches` ジョブで毎回整理する。

**`cleanup-stale-prs`**:

- upstream の open な `translate/*` PR を fork 所有者で絞り込み
- 新しく作成した PR の番号より小さいものを対象とし、`gh pr view --json commits,reviews` で人手コミット・非PENDINGレビューがあるものは skip
- skip しなかった対象に「Superseded by #N (translation for vX.Y). Closing this PR.」コメントを残してクローズ
- `cleanup_max_prs` 件まで処理。`cleanup_dry_run=true` の場合は対象一覧の echo だけ実行
- `cleanup_only=true` で dispatch すると、新PR作成をスキップして cleanup のみを実行（`needs.create-pr.outputs.pr_number` が空の場合は最新マージ済み翻訳PRを参照値として使用）

**`cleanup-fork-branches`**:

- `git ls-remote --heads origin 'translate/v*'` で fork のブランチ一覧を取得
- 各ブランチの upstream 側 PR 状態を確認し、`MERGED` / `CLOSED` / `NONE` のものを `git push origin --delete` で削除
- 現在進行中の `translate/{NEW_TAG}` は除外
- `cleanup_dry_run=true` の場合は `[DRY-RUN] would delete ...` を echo するだけ

**安全装置**:

- `cleanup_max_prs` (default 10) で1回の実行件数を制限し、初回事故時の被害を局所化
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

### 翻訳のレジューム（途中再開）

翻訳ジョブが途中で失敗・タイムアウトした場合でも、`Push translation branch` まで到達していれば翻訳結果はリモートの `translate/{tag}` ブランチに残ります。同じタグで再実行すると:

1. `Create translation branch` ステップがリモートの同名ブランチから `content/ja/` を復元
2. `Translate files` ステップが「ベースコミット（タグ）と差分があり、かつ日本語を含む」ファイルをスキップ（成功扱い）し、未翻訳分のみを翻訳

mainに既にマージ済みの古い翻訳はベースコミットと一致するため、スキップ対象にならず正しく再翻訳されます。

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
| 翻訳が実行されない | upstreamに新しいタグがあるか確認。手動実行で `force_translate` を有効化。`.last-translated-tag` の内容を確認 |
| 翻訳が失敗する | AWS認証情報の設定を確認。Claude Code CLIのバージョンを確認。ログでエラーメッセージを特定 |
| `ExpiredToken` / 認証エラーで失敗する | `Configure refreshable AWS credentials` ステップの `aws sts get-caller-identity` 検証結果を確認。`AWS_ROLE_ARN` シークレットとIAMロールの信頼ポリシー（OIDCプロバイダー設定）を確認 |
| ジョブがタイムアウトした | 同じタグでワークフローを再実行する。翻訳済みファイルはリモートの `translate/{tag}` ブランチから復元・スキップされ、未翻訳分のみ翻訳される |
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
