#!/usr/bin/env bash
# 英語ソースの変更diffを、hunk単位で日本語訳ファイルへ機械適用する。
#
# 日本語訳ファイルのうち、翻訳されていない領域（コードブロック・CLIコマンド・URL・
# 英語のまま維持された機能名など）は英語原文と一致するため、その領域への変更は
# git apply でトークン消費ゼロで反映できる。翻訳済みプローズへの変更hunkは
# コンテキストが一致せず適用に失敗するので、OUT_DIFF に書き出して呼び出し側の
# LLM差分翻訳へ回す。
#
# 使い方: apply-en-patch.sh EN_FILE JA_FILE BASE_REF HEAD_REF OUT_DIFF
# 終了コード:
#   0  = 反映完了（en変更なし、または全hunk機械適用済み。OUT_DIFFは削除される）
#   10 = 未適用hunkあり（OUT_DIFF にja側パスのunified diffとして出力）
#   1  = 引数エラー等
set -euo pipefail

if [ $# -ne 5 ]; then
  echo "Usage: $0 EN_FILE JA_FILE BASE_REF HEAD_REF OUT_DIFF" >&2
  exit 1
fi

EN_FILE="$1"
JA_FILE="$2"
BASE_REF="$3"
HEAD_REF="$4"
OUT_DIFF="$5"

if [ ! -f "$JA_FILE" ]; then
  echo "ERROR: Japanese file not found: ${JA_FILE}" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

git diff "${BASE_REF}..${HEAD_REF}" -- "$EN_FILE" > "$WORK_DIR/en.diff"

if [ ! -s "$WORK_DIR/en.diff" ]; then
  echo "No English changes between ${BASE_REF} and ${HEAD_REF} for ${EN_FILE}"
  rm -f "$OUT_DIFF"
  exit 0
fi

# diffヘッダのパスをja側に書き換える（LLMフォールバック時もja側パスのdiffとして渡す）
sed -e "s|a/${EN_FILE}|a/${JA_FILE}|g" -e "s|b/${EN_FILE}|b/${JA_FILE}|g" \
  "$WORK_DIR/en.diff" > "$WORK_DIR/ja.diff"

# ヘッダ（最初の @@ より前）を抽出
sed -n '1,/^@@/p' "$WORK_DIR/ja.diff" | sed '$d' > "$WORK_DIR/header"

# hunkごとに「ヘッダ + 単一hunk」の独立したdiffファイルへ分割
awk -v dir="$WORK_DIR" '
  /^@@/ {
    n++
    hunk = sprintf("%s/hunk_%04d.diff", dir, n)
    printf "%s", header > hunk
  }
  {
    if (n > 0) { print >> hunk }
    else { header = header $0 "\n" }
  }
' "$WORK_DIR/ja.diff"

APPLIED=0
FAILED=0
: > "$WORK_DIR/failed_hunks"

for hunk in "$WORK_DIR"/hunk_*.diff; do
  [ -e "$hunk" ] || break
  if git apply "$hunk" 2>/dev/null; then
    APPLIED=$((APPLIED + 1))
  else
    FAILED=$((FAILED + 1))
    # 失敗hunkの @@ 以降のみを蓄積（ヘッダは最後に1回だけ付ける）
    sed -n '/^@@/,$p' "$hunk" >> "$WORK_DIR/failed_hunks"
  fi
done

echo "Hunks applied mechanically: ${APPLIED}, remaining: ${FAILED} (${JA_FILE})"

if [ "$FAILED" -eq 0 ]; then
  rm -f "$OUT_DIFF"
  exit 0
fi

mkdir -p "$(dirname "$OUT_DIFF")"
cat "$WORK_DIR/header" "$WORK_DIR/failed_hunks" > "$OUT_DIFF"
exit 10
