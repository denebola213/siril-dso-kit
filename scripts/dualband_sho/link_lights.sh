#!/usr/bin/env bash
# =============================================================================
# link_lights.sh -- Ekos などが付けたファイル名（例: NGC_6992_Light_001.fits）を、
#                  01/02 が前提とする light_0001.fits の連番にリンクする。
#
#   Siril はファイル名の basename からシーケンス名を作る。3桁連番だと語尾に
#   区切りが残り、calibrate light が見つけられない。ここで名前を揃える。
#
#   実体はコピーしない（同一 FS 内のシンボリックリンク）。
#   既存のリンクは「消してから作る」のではなく上書きする。先に全部消す方式だと、
#   ディレクトリの中身がリンクだけだった場合に実体ごと失われる。
#
#   使い方: ./link_lights.sh <ライトのディレクトリ> [glob]
#           ./link_lights.sh /data/NGC6992/HaO3 'NGC_6992_Light_*.fits'
#
#   前提: ext4 / xfs / btrfs（exFAT・NTFS ではシンボリックリンクが作れない）
# =============================================================================
set -euo pipefail
shopt -s nullglob

dir=${1:?usage: link_lights.sh <dir> [glob]}
pattern=${2:-*.fits}
[ -d "$dir" ] || { echo "ディレクトリがありません: $dir" >&2; exit 1; }
cd "$dir"

# Siril は <名前>.seq があるとディレクトリを再スキャンしない。light 側だけ消す
# （.seq は再生成できるメタデータ。ただし register 後は登録結果を含むので消さない）
rm -f light.seq light_.seq

i=0
for f in $pattern; do
  [ -f "$f" ] || continue
  case "$f" in light_*.fits|light_*.fts|light_*.fit) continue ;; esac
  i=$((i + 1))
  target=$(printf 'light_%04d.fits' "$i")
  [ "$f" = "$target" ] && continue          # 自分自身へのリンクは作らない
  ln -sfn "$f" "$target"
done

if [ "$i" -eq 0 ]; then
  n=0
  for l in light_*.fits light_*.fit light_*.fts; do
    if [ -e "$l" ] || [ -L "$l" ]; then n=$((n + 1)); fi
  done
  if [ "$n" -gt 0 ]; then
    echo "既に light_*.{fits,fit,fts} が $n 個あります（リンク不要）"
    exit 0
  fi
  echo "ライトが見つかりません（pattern: $pattern, dir: $dir）" >&2
  echo "  第2引数でパターンを指定してください（例: 'NGC_6992_Light_*.fits'）" >&2
  exit 1
fi

# 前回のリンクが今回の枚数より多い場合、余った分だけ消す（-L のみ。実ファイルは触らない）
for ((k = i + 1; k <= i + 500; k++)); do
  for ext in fits fit fts; do
    stale=$(printf 'light_%04d.%s' "$k" "$ext")
    if [ -L "$stale" ]; then rm -f "$stale"; fi
  done
done

echo "${i} 個を light_0001.fits ... にリンクしました"
ls -l light_*.fits | head -3
echo "..."
ls -l light_*.fits | tail -1
