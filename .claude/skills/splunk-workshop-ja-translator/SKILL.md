---
name: splunk-workshop-ja-translator
description: Splunk Observability Workshopの英日翻訳・ローカライゼーション。Hugoベースの技術ドキュメントを日本語に翻訳する際に使用。翻訳依頼、日本語化、ローカライズ、i18n作業時にトリガーされる。Markdown構文を維持しながら、コードブロックや製品名を保持し、日本の開発者向けに自然な表現に変換する。
context: fork
hooks:
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: 'if echo "$CLAUDE_FILE_PATH" | grep -qE "\.md$"; then npx markdownlint-cli --fix "$CLAUDE_FILE_PATH" 2>/dev/null || true; fi'
        - type: command
          command: 'if echo "$CLAUDE_FILE_PATH" | grep -qE "\.md$" && [ -f "$CLAUDE_PROJECT_DIR/.textlintrc" ]; then npx textlint -c "$CLAUDE_PROJECT_DIR/.textlintrc" --rulesdir "$CLAUDE_PROJECT_DIR/.claude/skills/splunk-workshop-ja-translator/textlint-rules" --fix "$CLAUDE_FILE_PATH" 2>/dev/null || true; fi'
  Stop:
    - hooks:
        - type: command
          command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/check-translation-coverage.sh'
          timeout: 30
---

# Splunk Workshop 日本語翻訳スキル

## 概要

Splunk Observability Workshop を英語から日本語に翻訳するためのガイドライン。単なる翻訳ではなく、日本の開発者向けにローカライズする。

## ディレクトリ構造

- ソース: `/content/en/` (最新版)
- 出力先: `/content/ja/` (同じ構造をミラーリング)

## 翻訳ワークフロー

1. 対象セクションのファイルを `/content/en/` から `/content/ja/` にコピー。対象セクションが不明な場合、Skill 利用者に確認すること
   1. Markdown ファイルだけでなく、リンクされている画像もコピーする必要があります。通常`./img/`に配置されていますが、セクション配下を丸ごとコピーすることを推奨します
2. `/content/ja/` で未翻訳ファイルを確認
3. 翻訳ルールに従って翻訳
4. `hugo serve` でプレビュー確認 (`http://localhost:1313/`)

## 自動翻訳ワークフロー（CI/CD用）

GitHub Actions からの自動実行時:

1. 翻訳対象ファイルのパスが引数として渡される
2. 対象ファイルを読み込み、翻訳ルールに従って翻訳
3. 翻訳結果を同じファイルに上書き保存
4. 処理完了を報告

### 重要: ターン数の節約戦略（Write一発上書き）

CI 実行時は `--max-turns` によるターン数制限がある。複数回の Edit を繰り返すとターンを使い切って失敗する。次のフローを厳守する。

1. **Read を1回**: 翻訳対象ファイル（`content/ja/...`）を最初に1回だけ読む
2. **翻訳結果を頭の中で組み立てる**: ファイル全体の翻訳結果を1つのテキストとして用意する
3. **Write を1回**: ファイル全体を `Write` で**一括上書き**する（部分的な `Edit` を繰り返さない）
4. **検証は最小限**: 翻訳後の Read による再確認は省略する（PostToolUse hook が markdownlint/textlint を実行するため）

`Edit` を細切れに使うと、見出しごと・段落ごとに1ターンずつ消費し、長いファイルでは10ターンに収まらない。**1ファイル = 1 Read + 1 Write** を原則とする。

## 翻訳ルール

翻訳ルールの正本は [references/translation-guide.md](references/translation-guide.md)。翻訳前に必ず読むこと。要点:

- 翻訳しない: コードブロック、CLIコマンド、ファイルパス、URL、製品名（Splunk, Kubernetes 等）
- 文体: です/ます形（丁寧語）。行末コロンは除去
- 太字: 機能名・UI要素の単語は英語を維持、文章は翻訳。強調ブロック内に役物を含む場合は前後に半角スペース
- Markdown構文・frontmatterキー・Hugoショートコードは原文の構造を維持

## 品質チェックリスト

翻訳完了後、以下を確認:

- [ ] Markdown が正しくレンダリングされる
- [ ] すべてのリンクが機能する
- [ ] コードブロックが変更されていない
- [ ] 用語が一貫している
- [ ] 太字マークアップが正しく表示される
- [ ] Markdownlint, Prettier などのフォーマッターを実行した
- [ ] textlint (ja-spacing) を実行した
- [ ] `/content/ja/` の全ファイルが翻訳済み（日本語テキストを含む）

## よくある翻訳パターン

詳細な翻訳パターンと用語集は [references/translation-guide.md](references/translation-guide.md) を参照。
