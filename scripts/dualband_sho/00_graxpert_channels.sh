#!/usr/bin/env bash
# =============================================================================
# 00: 分離済み4チャンネルに GraXpert BGE → denoise をかける（線形のまま）
#   入力: Ha.fits / OIII_ha.fits / SII.fits / OIII_s2.fits
#   出力: Ha_gx.fits / OIII_ha_gx.fits / SII_gx.fits / OIII_s2_gx.fits
#   03_merge_compose.ssf はこの4つの _gx.fits を前提にしている。
# =============================================================================
set -euo pipefail

GRAXPERT=${GRAXPERT:-GraXpert-linux}   # PATH が通っていればこれでOK
DIR=${1:-.}
cd "$DIR"

# GraXpert の入力は「位置引数」（-input というフラグは無い）。-output は
# ディレクトリ無し・拡張子無しの裸の名前。出力は入力の隣に <名前>.fits で出る。
run_bge() {   # $1=入力名(拡張子なし)
  "$GRAXPERT" "$1.fits" -cli -cmd background-extraction \
    -output "$1_bge" \
    -correction Subtraction -smoothing 0.25 -gpu false
}
run_dn() {    # $1=入力名(拡張子なし)  $2=出力名(拡張子なし)
  "$GRAXPERT" "$1.fits" -cli -cmd denoising \
    -output "$2" \
    -strength 0.50 -gpu false
}

for ch in Ha OIII_ha SII OIII_s2; do
  echo "== BGE: $ch"
  run_bge "$ch"
done

# OIII は2本のフィルタ平均で最も弱い。SII も Ha より暗い。
# ここで各チャンネルを個別に均しておくと、合成後の1回デノイズで色が濁らない。
run_dn Ha_bge      Ha_gx
run_dn OIII_ha_bge OIII_ha_gx
run_dn SII_bge     SII_gx
run_dn OIII_s2_bge OIII_s2_gx

ls -l *_gx.fits
