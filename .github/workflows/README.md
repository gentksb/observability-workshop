# GitHub Actions ワークフロー

このディレクトリには、Splunk Observability Workshopの日本語翻訳を自動化するGitHub Actionsワークフローが含まれています。

## アーキテクチャ

```
フォークリポジトリ
├── main                    ← upstreamと完全同期（翻訳システムファイルなし）
├── ja-translation-system   ← 翻訳ワークフロー、.claude/などを管理（デフォルトブランチ）
└── translate/*             ← upstreamへのPR用ブランチ（content/ja/のみ）
```

### ブランチの役割

| ブランチ | 役割 |
|---------|------|
| `main` | upstreamリポジトリと完全に同期。翻訳システムのファイルは含まない |
| `ja-translation-system` | 翻訳ワークフロー、Claude Codeスキル、設定ファイルを管理。デフォルトブランチとして設定 |
| `translate/*` | 翻訳結果をupstreamにPRするためのブランチ。`content/ja/`のみを含む |

## ワークフロー

### Sync Upstream and Translate (`sync-and-translate.yml`)

upstreamリポジトリの新しいリリースを検出し、日本語に自動翻訳してPRを作成します。

#### トリガー

- **スケジュール**: 毎週月曜日 9:00 JST (00:00 UTC)
- **手動実行**: `workflow_dispatch`

#### 手動実行オプション

実行目的を `run_mode` で1つ選択します。

| オプション | 説明 | デフォルト |
| --------- | ---- | --------- |
| `run_mode` | `auto`（定期実行と同じ） / `retranslate-latest`（最新リリース分の訳し直し） / `fill-missing-translations`（未翻訳ファイルの補完） / `cleanup-only`（PR・ブランチ掃除のみ） | `auto` |
| `dry_run` | 掃除のクローズ・削除対象を一覧表示するだけで実行しない | false |
| `retry_attempt` | 内部用（タイムアウト自動リトライのカウンタ）。手動実行では変更しない | 0 |

#### 処理フロー

1. **新リリースチェック**: upstreamの最新タグを取得し、前回翻訳したタグと比較
2. **mainブランチ同期**: 新しいタグがあれば、mainをupstreamのタグにリセット
3. **ミラー同期**: md以外のアセットを `content/en` → `content/ja` でミラーし、en側に対応物のないja側ファイルを削除
4. **翻訳**: 変更されたファイルをClaude Code (Bedrock)で翻訳。既存訳のあるファイルは変更hunkだけを反映（機械パッチ → LLM差分翻訳 → 全文翻訳の3段フォールバック）
5. **構造検証**: frontmatter・shortcode・見出し・コードフェンスを en/ja で比較し、不一致をPR本文に警告
6. **PR作成**: upstreamリポジトリにPRを作成（新ワークショップ検出時はドラフトPR）
7. **タグ記録**: 翻訳したタグを`.last-translated-tag`に記録

各フェーズの詳細・cleanupジョブ・自動リトライは [CLAUDE.md](./CLAUDE.md) を参照してください。

#### 必要なシークレット

- `AWS_ROLE_ARN`: AWS BedrockへのアクセスにOIDCで使用するIAMロールARN
- `UPSTREAM_PAT`: upstreamリポジトリへのPR作成に使用するPersonal Access Token（Fine-grained PAT推奨、`Pull requests: Read and write`権限が必要）

#### 必要な権限

- `id-token: write` - AWS OIDC認証
- `contents: write` - ブランチの作成・プッシュ
- `pull-requests: write` - PRの作成

## 翻訳について

### 翻訳の仕組み

翻訳は[Claude Code CLI](https://github.com/anthropics/claude-code)とAWS Bedrockを使用して自動的に行われます。

- **翻訳モデル**: Claude Opus 4.6 (via AWS Bedrock)
- **翻訳スキル**: `.claude/skills/splunk-workshop-ja-translator/`
- **翻訳ガイドライン**: [translation-guide.md](../../.claude/skills/splunk-workshop-ja-translator/references/translation-guide.md)

### 翻訳対象

- `content/en/**/*.md` → `content/ja/**/*.md`
- 関連する画像ファイル (`img/` ディレクトリ)

### 翻訳されないもの

- コードブロック内のコード
- CLIコマンド
- ファイルパス、URL
- 製品名 (Splunk, Kubernetes, Docker など)

### 翻訳結果の確認

翻訳が完了すると、upstreamリポジトリにドラフトPRが自動的に作成されます。レビュー後、以下を確認してください：

- [ ] Markdownが正しくレンダリングされる
- [ ] すべてのリンクが機能する
- [ ] コードブロックが変更されていない
- [ ] 用語が一貫している
- [ ] 太字マークアップが正しく表示される

## セットアップ手順

### 1. ブランチ構成の設定

```bash
# ja-translation-systemブランチを作成（現在のブランチから）
git checkout -b ja-translation-system

# mainブランチをupstreamと同期
git checkout main
git remote add upstream https://github.com/splunk/observability-workshop.git
git fetch upstream
git reset --hard upstream/main
git push origin main --force
```

### 2. GitHubリポジトリ設定

1. **デフォルトブランチの変更**:
   - Settings → General → Default branch
   - `ja-translation-system`に変更

2. **ブランチ保護ルール**:
   - `main`ブランチを保護（force pushを許可）
   - `ja-translation-system`ブランチを保護

### 3. シークレットの設定

- `AWS_ROLE_ARN`: AWS BedrockへのアクセスにOIDCで使用するIAMロールARN
- `UPSTREAM_PAT`: upstreamリポジトリへのPR作成用Personal Access Token
  - GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
  - Resource owner: `splunk`
  - Repository access: `splunk/observability-workshop`
  - Permissions: `Pull requests: Read and write`

### 4. AWS OIDC設定

GitHub ActionsからAWS Bedrockにアクセスするために、OIDCプロバイダーとIAMロールを設定します。

認証はAWS SDKの `credential_process` を使った都度更新方式です。Bedrock呼び出しのたびにGitHub OIDCトークンを再発行して `AssumeRoleWithWebIdentity` を実行するため、IAMロールの `MaxSessionDuration` を延長しなくても長時間の翻訳ジョブを実行できます。詳細は [CLAUDE.md](./CLAUDE.md) の「AWS認証」を参照してください。

## トラブルシューティング

### 翻訳が実行されない

- upstreamに新しいタグがあるか確認
- 訳し直しは `run_mode=retranslate-latest`、未翻訳の穴埋めは `run_mode=fill-missing-translations` で手動実行
- `.last-translated-tag`ファイルの内容を確認

### 翻訳が失敗する

- AWS認証情報が正しく設定されているか確認
- Claude Code CLIが最新バージョンか確認
- ログを確認し、エラーメッセージを特定

### 翻訳ジョブが途中で失敗・タイムアウトした

- `retry-on-failure` ジョブが最大2回まで自動で再dispatchする
- 翻訳済みファイルはリモートの `translate/{tag}` ブランチから復元・スキップされ、未翻訳分のみが翻訳される（レジューム）
- 自動リトライでも完了しない場合のみ、同じ設定で手動再実行する

### upstream へのPRが作成できない

- `UPSTREAM_PAT`シークレットが正しく設定されているか確認
- PATの有効期限が切れていないか確認
- PATに`Pull requests: Read and write`権限があるか確認
- upstreamリポジトリへのPR作成権限を確認

## フォーク元との関係

このリポジトリはupstream (`splunk/observability-workshop`) からフォークされています。

- **フォーク元**: https://github.com/splunk/observability-workshop
- **同期方針**: upstreamの新リリース時にmainブランチを同期
- **翻訳方針**: 翻訳結果はupstreamリポジトリにPRとして提出

## 参考リンク

- [Claude Code](https://claude.ai/claude-code)
- [Splunk Observability Workshop](https://splunk.github.io/observability-workshop/)
- [Hugo Documentation](https://gohugo.io/documentation/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
