#!/usr/bin/env bash
# content/ja を content/en の構造にミラーし、本文md以外の差分を排除する。
#
# 処理内容:
#   1. orphanディレクトリ削除: en側に対応ディレクトリのない ja側ディレクトリを削除
#   2. orphanファイル削除:     en側に対応ファイルのない ja側ファイル（md含む）を削除
#   3. アセットミラー:         ja側に存在するディレクトリ限定で、md以外のファイルを
#                              en側から常時コピー（en側の更新・削除に追従）
#
# 未翻訳ディレクトリ（ja側に存在しないもの）にはファイルを持ち込まない。
#
# 使い方: sync-ja-mirror.sh [--dry-run]
# 出力:   実行した操作を1行1件で出力（DELETE / UPDATE / ADD プレフィックス）
set -euo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

EN_ROOT="content/en"
JA_ROOT="content/ja"

if [ ! -d "$EN_ROOT" ]; then
  echo "ERROR: ${EN_ROOT} not found. Run this script from the repository root." >&2
  exit 1
fi

if [ ! -d "$JA_ROOT" ]; then
  echo "No ${JA_ROOT} directory; nothing to mirror"
  exit 0
fi

run() {
  if [ "$DRY_RUN" = "true" ]; then
    return 0
  fi
  "$@"
}

# 1. orphanディレクトリの削除（子から先に消すため深い順に処理）
while IFS= read -r ja_dir; do
  en_dir="${EN_ROOT}${ja_dir#"$JA_ROOT"}"
  if [ ! -d "$en_dir" ]; then
    echo "DELETE (orphan dir) ${ja_dir}"
    run rm -rf "$ja_dir"
  fi
done < <(find "$JA_ROOT" -mindepth 1 -type d | sort -r)

# 2. orphanファイルの削除（en側に対応物のないファイルは翻訳mdも含めて削除）
while IFS= read -r ja_file; do
  [ -f "$ja_file" ] || continue  # 1.で削除済みディレクトリ配下はスキップ
  en_file="${EN_ROOT}${ja_file#"$JA_ROOT"}"
  if [ ! -f "$en_file" ]; then
    echo "DELETE (orphan file) ${ja_file}"
    run rm -f "$ja_file"
  fi
done < <(find "$JA_ROOT" -type f | sort)

# 3. アセットミラー: ja側に存在するディレクトリのmd以外ファイルをen側からコピー
while IFS= read -r en_file; do
  rel="${en_file#"$EN_ROOT"/}"
  ja_file="${JA_ROOT}/${rel}"
  ja_dir=$(dirname "$ja_file")
  # 未翻訳ディレクトリには持ち込まない
  [ -d "$ja_dir" ] || continue
  if [ ! -f "$ja_file" ]; then
    echo "ADD ${ja_file}"
    run cp "$en_file" "$ja_file"
  elif ! cmp -s "$en_file" "$ja_file"; then
    echo "UPDATE ${ja_file}"
    run cp "$en_file" "$ja_file"
  fi
done < <(find "$EN_ROOT" -type f ! -name '*.md' | sort)

echo "Mirror sync complete (dry_run=${DRY_RUN})"
