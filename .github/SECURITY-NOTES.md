# Security Notes: 翻訳自動化ワークフローの脅威モデル

このドキュメントは `sync-and-translate.yml` ワークフローのセキュリティ設計判断を将来の保守者向けに残すものです。設定変更時は、ここに記載された前提が崩れていないか確認してください。

## 背景: 2026-05 v6.69 push 失敗事象

### 発生事象

2026-05-12 のスケジュール実行で、upstream の v6.69 を fork main に同期する `git push origin main --force` が以下のエラーで失敗しました。

```text
HEAD is now at 6bcbfd5ab Releasing v6.69
! [remote rejected]     main -> main
  (refusing to allow a GitHub App to create or update workflow
   .github/workflows/deploy-workshop.yml without `workflows` permission)
```

### 原因

upstream `splunk/observability-workshop` の v6.69 で `.github/workflows/deploy-workshop.yml` が更新されました。GitHub Actions の `GITHUB_TOKEN` は、`contents: write` を持っていても **`.github/workflows/` 配下のファイル変更を含む push を拒否する**仕様です（GitHub Actions の安全装置）。

`permissions:` ブロックに `workflows` というキーは存在しません（workflow syntax の公式仕様）。`actions: write` は workflow run の操作（cancel/rerun）を許可するもので、workflow ファイル自体の書き換え権限ではありません。

### 採用した解決策

**Fine-grained PAT（`FORK_SYNC_PAT`）を新規発行し、`Sync main with upstream` ステップでのみ使用**することにしました。

| 項目 | 内容 |
|------|------|
| Resource owner | `gentksb`（fork 所有者） |
| Repository access | `gentksb/observability-workshop` のみ |
| Permissions | `Contents: Read and write`、`Workflows: Read and write` |
| 有効期限 | 90 日（Splunk enterprise 要件） |
| 使用箇所 | `sync-and-translate` ジョブの `Sync main with upstream` ステップのみ |

## 脅威モデルと現状の防御線

### 想定された懸念

「workflow 自己更新を許す権限を導入すると、PR 経由で workflow を書き換える攻撃コードを送り込まれ、`UPSTREAM_PAT` などの secret が漏えいするのではないか」

### 防御線の検証

現状の `sync-and-translate.yml` の設計では、この直接攻撃経路は構造的に閉じています。

| 防御線 | 内容 | 該当箇所 |
|--------|------|----------|
| PR トリガー不在 | `pull_request` / `pull_request_target` トリガーが存在せず、`schedule` + `workflow_dispatch` のみ | `sync-and-translate.yml` line 3-18 |
| Fork PR の secret 隔離 | GitHub の仕様上、fork からの `pull_request` イベントでは secrets が渡されない | GitHub Actions Security Hardening 公式ガイド |
| Secret の使用箇所限定 | `FORK_SYNC_PAT` は sync-step のみ、`UPSTREAM_PAT` は create-pr ジョブのみ | line 141, line 621 |
| CODEOWNERS による事前レビュー | `.github/workflows/`、`.github/CODEOWNERS`、`.claude/` への変更は @gentksb のレビュー必須 | `.github/CODEOWNERS` |
| Translate ブランチでのコミット保護 | `translate/*` ブランチでの `.claude/` 変更を pre-commit hook が拒否 | `.claude/hooks/validate-commit.sh` |

### 残存リスクと緩和策

| リスク | 緩和策 |
|--------|--------|
| `FORK_SYNC_PAT` 漏えい時、fork 内の任意 workflow が書き換え可能 | リソース所有者を fork に限定 / 90 日ローテーション / GitHub の secret scanning を有効化 |
| 悪意ある PR がレビューをすり抜けてマージされ、次回スケジュール実行で動く | CODEOWNERS による必須レビュー / ブランチ保護で「Require review from Code Owners」を有効化 |
| 将来 `pull_request` トリガーが追加されると secret 露出経路が開く | `.github/workflows/CLAUDE.md` に追加禁止を明記 / CODEOWNERS で workflow 変更を統制 |
| Claude Code 翻訳ジョブが誤って `.github/workflows/` を編集する | `--allowedTools "Edit,Read,Write"` で制限済み / `git add content/ja/` のみコミット（line 572） |

## 設定変更時のチェックリスト

`.github/workflows/` 配下を変更する PR をレビューする際は、以下を確認してください。

- [ ] `pull_request` / `pull_request_target` トリガーが追加されていないか
- [ ] `FORK_SYNC_PAT` が `Sync main with upstream` ステップ以外から参照されていないか
- [ ] `UPSTREAM_PAT` が `create-pr` ジョブ以外から参照されていないか
- [ ] `permissions:` ブロックが最小権限になっているか（ジョブ単位での絞り込み）
- [ ] 新しい secret を追加する場合、CODEOWNERS で参照箇所がレビュー対象になっているか

## PAT ローテーション手順

1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens から新しいトークンを発行
2. リポジトリの Settings → Secrets and variables → Actions で該当 secret を更新
3. `workflow_dispatch` で `force_translate=true` を指定して手動実行し、成功を確認

## 参考文献

- [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [Automatic token authentication (GITHUB_TOKEN permissions)](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication)
- [Workflow syntax for GitHub Actions (permissions)](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#permissions)
- [Permissions required for fine-grained PATs](https://docs.github.com/en/rest/overview/permissions-required-for-fine-grained-personal-access-tokens)
