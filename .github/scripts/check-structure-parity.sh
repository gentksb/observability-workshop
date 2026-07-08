#!/usr/bin/env bash
# en/jaファイル間で「本文以外の構造」が一致しているかを検査する。
#
# 比較項目:
#   - frontmatter のキー集合（値は翻訳されるためキーのみ）
#   - Hugo shortcode の名前と出現数（開始/終了タグを区別）
#   - 見出しレベルの並び（見出しテキストは翻訳されるためレベルのみ）
#   - コードフェンス数
#
# 使い方: check-structure-parity.sh EN_FILE JA_FILE
# 出力:   不一致項目を "PARITY <ja_file>: <詳細>" 形式でstdoutへ1行ずつ出力
# 終了コード: 0 = 一致、1 = 不一致あり
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 EN_FILE JA_FILE" >&2
  exit 2
fi

EN_FILE="$1"
JA_FILE="$2"

extract_frontmatter_keys() {
  awk '
    /^---[ \t]*$/ { c++; next }
    c >= 2 { exit }
    c == 1 && /^[A-Za-z0-9_-]+:/ { sub(/:.*/, ""); print }
  ' "$1" | sort -u
}

extract_shortcodes() {
  # {{< name >}} / {{% name %}} / {{< /name >}} の名前を抽出して集計
  grep -oE '\{\{[<%][[:space:]]*/?[A-Za-z0-9_-]+' "$1" 2>/dev/null \
    | sed -E 's/\{\{[<%][[:space:]]*//' \
    | sort | uniq -c | sed 's/^ *//' || true
}

extract_heading_levels() {
  # コードフェンス内の # コメントを見出しと誤認しないようフェンス外のみ対象
  awk '
    /^[ \t]*(```|~~~)/ { f = !f; next }
    !f && /^#/ {
      match($0, /^#+/)
      if (RLENGTH <= 6 && substr($0, RLENGTH + 1, 1) == " ") print RLENGTH
    }
  ' "$1"
}

count_code_fences() {
  awk '/^[ \t]*(```|~~~)/ { c++ } END { print c + 0 }' "$1"
}

FAIL=0

if [ "$(extract_frontmatter_keys "$EN_FILE")" != "$(extract_frontmatter_keys "$JA_FILE")" ]; then
  echo "PARITY ${JA_FILE}: frontmatter keys differ from English source"
  FAIL=1
fi

if [ "$(extract_shortcodes "$EN_FILE")" != "$(extract_shortcodes "$JA_FILE")" ]; then
  echo "PARITY ${JA_FILE}: Hugo shortcode set differs from English source"
  FAIL=1
fi

if [ "$(extract_heading_levels "$EN_FILE")" != "$(extract_heading_levels "$JA_FILE")" ]; then
  echo "PARITY ${JA_FILE}: heading structure differs from English source"
  FAIL=1
fi

EN_FENCES=$(count_code_fences "$EN_FILE")
JA_FENCES=$(count_code_fences "$JA_FILE")
if [ "$EN_FENCES" != "$JA_FENCES" ]; then
  echo "PARITY ${JA_FILE}: code fence count differs (en=${EN_FENCES} ja=${JA_FENCES})"
  FAIL=1
fi

exit "$FAIL"
