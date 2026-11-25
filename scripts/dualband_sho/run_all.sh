#!/usr/bin/env bash
# =============================================================================
# run_all.sh -- dualband_sho の 01 -> 04 を順に回す薄いラッパー
#
#   各段の .ssf はそのまま使う。02 の -extref だけは 01 の出力を指すように
#   一時ファイルへ差し替える（.ssf に変数は無いため）。
#
#   使い方:
#     ./run_all.sh --hao3 DIR --s2o3 DIR --ch DIR [--graxpert PATH] [--skip-starnet]
#
#   --hao3 / --s2o3 はライトが入ったディレクトリ、--ch は出力と合成の作業場所。
#   フラット・ダークがある夜は 01/02 の calibrate 行を直接書き換えること。
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIRIL="${SIRIL:-siril-cli}"
GRAXPERT="${GRAXPERT:-graxpert}"
HAO3=""; S2O3=""; CH=""; SKIP_STARNET=0
GLOB="*.fits"

usage() {
cat <<'EOF'
使い方:
  ./run_all.sh --hao3 DIR --s2o3 DIR --ch DIR [options]

必須:
  --hao3 DIR       Hα+OIII のライトがあるディレクトリ
  --s2o3 DIR       SII+OIII のライトがあるディレクトリ
  --ch DIR         チャンネル作業ディレクトリ（無ければ作る）

任意:
  --glob PATTERN   ライトのパターン (既定 *.fits)
  --siril PATH     siril 実行ファイル (既定 siril-cli)
  --graxpert PATH  GraXpert 実行ファイル (既定 graxpert)
  --skip-starnet   04 を飛ばす（StarNet2 が無い場合）
  -h, --help       これ
EOF
}

die() { echo "エラー: $*" >&2; exit 1; }
log() { echo "[$(date +%H:%M:%S)] $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --hao3)        HAO3="$2"; shift 2;;
    --s2o3)        S2O3="$2"; shift 2;;
    --ch)          CH="$2"; shift 2;;
    --glob)        GLOB="$2"; shift 2;;
    --siril)       SIRIL="$2"; shift 2;;
    --graxpert)    GRAXPERT="$2"; shift 2;;
    --skip-starnet) SKIP_STARNET=1; shift;;
    -h|--help)     usage; exit 0;;
    *)             die "不明な引数: $1（--help 参照）";;
  esac
done

[ -n "$HAO3" ] || die "--hao3 がありません"
[ -n "$S2O3" ] || die "--s2o3 がありません"
[ -n "$CH" ]   || die "--ch がありません"
[ -d "$HAO3" ] || die "ディレクトリがありません: $HAO3"
[ -d "$S2O3" ] || die "ディレクトリがありません: $S2O3"
HAO3="$(cd "$HAO3" && pwd)"
S2O3="$(cd "$S2O3" && pwd)"
mkdir -p "$CH"
CH="$(cd "$CH" && pwd)"

command -v "$SIRIL" >/dev/null 2>&1 || [ -x "$SIRIL" ] || die "siril が見つかりません: $SIRIL"

# ---- 0) ファイル名を light_0001.fits 連番に揃える -------------------------
log "ライトをリンクしています"
"$SELF_DIR/link_lights.sh" "$HAO3" "$GLOB"
"$SELF_DIR/link_lights.sh" "$S2O3" "$GLOB"

# ---- 1) Hα+OIII: 較正・整列・スタック・分離 -------------------------------
log "01: Ha+OIII を処理しています"
"$SIRIL" -d "$HAO3" -s "$SELF_DIR/01_stack_hao3.ssf"

REF="$HAO3/HaO3_color.fits"
[ -f "$REF" ] || die "01 の出力が見つかりません: $REF"

# ---- 2) SII+OIII: -extref を 01 のスタックに差し替えて実行 ----------------
TMP02="$S2O3/_02_extref.ssf"
sed "s|-extref=[^ ]*|-extref=$REF|" "$SELF_DIR/02_stack_s2o3.ssf" > "$TMP02"
grep -q -- "-extref=$REF" "$TMP02" || die "-extref の差し替えに失敗しました（02_stack_s2o3.ssf を確認）"
log "02: SII+OIII を処理しています（参照: $REF）"
"$SIRIL" -d "$S2O3" -s "$TMP02"

# ---- 3) 4チャンネルを集めて GraXpert ------------------------------------
for f in "$HAO3/Ha.fits" "$HAO3/OIII_ha.fits" "$S2O3/SII.fits" "$S2O3/OIII_s2.fits"; do
  [ -f "$f" ] || die "分離結果がありません: $f"
done
ln -sfn "$HAO3/Ha.fits"      "$CH/Ha.fits"
ln -sfn "$HAO3/OIII_ha.fits" "$CH/OIII_ha.fits"
ln -sfn "$S2O3/SII.fits"     "$CH/SII.fits"
ln -sfn "$S2O3/OIII_s2.fits" "$CH/OIII_s2.fits"

GRAXPERT="$GRAXPERT" "$SELF_DIR/00_graxpert_channels.sh" "$CH"

# ---- 4) OIII 統合 → SHO 合成 --------------------------------------------
log "03: OIII 統合と SHO 合成"
"$SIRIL" -d "$CH" -s "$SELF_DIR/03_merge_compose.ssf"

# ---- 5) 星抜きと仕上げ ---------------------------------------------------
if [ "$SKIP_STARNET" -eq 1 ]; then
  log "04 をスキップしました（--skip-starnet）。SHO_linear.fits まで完成"
else
  log "04: StarNet2 とスクリーン合成"
  "$SIRIL" -d "$CH" -s "$SELF_DIR/04_finish_starnet.ssf"
fi

echo
echo "===== 生成物 ($CH) ====="
for f in Ha.fits OIII_ha.fits SII.fits OIII_s2.fits SHO_linear.fits \
         SHO_nebula.fits SHO_stars.fits SHO_final.fits; do
  [ -f "$CH/$f" ] && printf "  %-20s %s\n" "$f" "$(du -h "$CH/$f" | cut -f1)"
done
