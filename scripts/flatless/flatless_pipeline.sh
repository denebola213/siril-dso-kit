#!/usr/bin/env bash
# =============================================================================
# flatless_pipeline.sh -- フラット無しのライト列を仕上げるパイプライン (全 OSS)
#
#   Siril 1.5 (GPL-3.0) + GraXpert 3.x (GPL-3.0) のみで完結する。
#   フラットを撮っていないライト列を、ダーク較正だけで仕上げる。
#
#   流れ:  ダーク較正 -> 整列(-2pass) -> σクリップスタック -> 外周クロップ
#          -> GraXpert BGE(除算) -> GraXpert デノイズ
#          -> プレートソルブ -> SPCC -> autostretch -> TIFF/FITS 保存
#
#   想定:  球状星団のように「画角に対して小さく、背景が一様」な対象。
#          周辺を捨てても情報損失が小さいことが前提。
#          フラットがあるなら使うこと。これは「無い場合の最善」で上位互換ではない。
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QC="${SELF_DIR}/qc_flatless.py"
PY="${PYTHON:-python3}"

# ---- 既定値 ----------------------------------------------------------------
WORKDIR="$PWD"
LIGHTS="light_*.fit"
SEQ=""                    # 空なら LIGHTS から自動推定
DARK=""
BIAS=""
MONO=0                    # 1 で -cfa を付けない（モノクロカメラ）
CROP_PCT=3                # 各辺を何% 削るか。0 で無効
SMOOTH="0.35"             # GraXpert BGE の smoothing
TARGETBG="0.25"           # autostretch の背景持ち上げ量 (0.15 に下げると色ムラが目立たない)
STRENGTH="0.5"            # GraXpert denoising の strength
SENSOR=""                 # 例: "Sony IMX571"
OSCFILTER=""              # 例: "None" / "IDAS LPS-D3" / "Optolong L-eXtreme"
NARROWBAND=0              # 1 で spcc -narrowband
SKIP_SPCC=0
SKIP_SOLVE=0
DRY=0
STAGE="all"               # all | 1 | 2 | 3
OUTNAME="target"
SIRIL_BIN="${SIRIL_BIN:-siril}"
GRAXPERT_BIN="${GRAXPERT_BIN:-graxpert}"

usage() {
cat <<'EOF'
使い方:
  ./flatless_pipeline.sh [options]

必須ではないが、ほぼ必ず指定するもの:
  --workdir DIR        ライトがあるディレクトリ (既定: カレント)
  --lights GLOB        ライトのパターン (既定: light_*.fit)
                       ファイル名は「連番の前まで」が Siril のシーケンス名になる
                       例) light_00001.fit -> --seq light が自動推定される
  --sensor NAME        SPCC 用のセンサー名 (例: "Sony IMX571")
  --filter NAME        SPCC 用のフィルター名 (例: "None", "IDAS LPS-D3")

較正:
  --dark FILE          マスターダーク (指定時は -cc=dark 3 3 も有効化)
  --bias FILE          マスターバイアス
  --mono               モノクロカメラ (-cfa を付けない)

調整:
  --crop PCT           各辺を削る割合[%] (既定 3 / 0 で無効)
  --smoothing V        GraXpert BGE smoothing (既定 0.35)
  --targetbg V         autostretch の背景値 (既定 0.25 / 色ムラが気になるなら 0.15)
  --denoise V          GraXpert denoising strength (既定 0.5)
  --narrowband         SPCC をナローバンドとして実行
  --skip-spcc          SPCC を実行しない
  --skip-solve         プレートソルブを実行しない
  --out NAME           出力名の接頭辞 (既定 target)

実行制御:
  --dry-run            .ssf を生成して表示するだけ（実行しない）
  --stage all|1|2|3    指定ステージだけ実行
  --siril PATH         siril 実行ファイル (既定: siril / siril-cli も可)
  --graxpert PATH      graxpert 実行ファイル

例:
  ./flatless_pipeline.sh --lights "light_*.fit" --dark master_dark.fit \
      --sensor "Sony IMX571" --filter "None"
EOF
}

die() { echo "エラー: $*" >&2; exit 1; }
log() { echo "[$(date +%H:%M:%S)] $*"; }

# ---- 引数解析 --------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir)     WORKDIR="$2"; shift 2;;
    --lights)      LIGHTS="$2"; shift 2;;
    --seq)         SEQ="$2"; shift 2;;
    --dark)        DARK="$2"; shift 2;;
    --bias)        BIAS="$2"; shift 2;;
    --mono)        MONO=1; shift;;
    --crop)        CROP_PCT="$2"; shift 2;;
    --smoothing)   SMOOTH="$2"; shift 2;;
    --targetbg)    TARGETBG="$2"; shift 2;;
    --denoise)     STRENGTH="$2"; shift 2;;
    --sensor)      SENSOR="$2"; shift 2;;
    --filter)      OSCFILTER="$2"; shift 2;;
    --narrowband)  NARROWBAND=1; shift;;
    --skip-spcc)   SKIP_SPCC=1; shift;;
    --skip-solve)  SKIP_SOLVE=1; shift;;
    --out)         OUTNAME="$2"; shift 2;;
    --dry-run)     DRY=1; shift;;
    --stage)       STAGE="$2"; shift 2;;
    --siril)       SIRIL_BIN="$2"; shift 2;;
    --graxpert)    GRAXPERT_BIN="$2"; shift 2;;
    -h|--help)     usage; exit 0;;
    *)             die "不明な引数: $1（--help 参照）";;
  esac
done

[ -d "$WORKDIR" ] || die "作業ディレクトリがありません: $WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
cd "$WORKDIR"

# ---- ライト列の確認 --------------------------------------------------------
shopt -s nullglob nocaseglob
FRAMES=( $LIGHTS )
shopt -u nocaseglob
N=${#FRAMES[@]}
[ "$N" -gt 0 ] || die "ライトが見つかりません: $WORKDIR/$LIGHTS"
[ "$N" -ge 3 ] || die "ライトが $N 枚しかありません（最低3枚、推奨20枚以上）"

FIRST="${FRAMES[0]}"
[ -n "$SEQ" ] || SEQ="${LIGHTS%%_*}"
[ -n "$SEQ" ] || die "--seq を指定してください"

# FITS の拡張子はライトから決める。setext を書かないと Siril の既定 (.fit) で
# シーケンスを探し、.fits のライトを見つけられずに calibrate が落ちる。
EXT="$(printf '%s' "${FIRST##*.}" | tr 'A-Z' 'a-z')"
case "$EXT" in
  fit|fits|fts) ;;
  *) die "ライトが FITS ではありません（拡張子: $EXT）: $FIRST" ;;
esac

DIMS="$("$PY" "$QC" --dims "$FIRST")" || die "FITS を読めません: $FIRST"
read -r W H <<< "$DIMS"
[ -n "${W:-}" ] && [ -n "${H:-}" ] || die "画像サイズを取得できませんでした: $FIRST"

log "作業ディレクトリ : $WORKDIR"
log "ライト          : $N 枚 / シーケンス名 '$SEQ' / 拡張子 .$EXT"
log "画像サイズ      : ${W} x ${H}"

# 枚数でリジェクション方式を切り替える（10枚未満は rej 3 3 が効かない）
if [ "$N" -ge 10 ]; then REJ="rej 3 3"; else REJ="med"; fi
log "リジェクション  : $REJ"

# ---- 較正オプションの組み立て ----------------------------------------------
CAL_OPTS=""
if [ -n "$BIAS" ]; then CAL_OPTS="$CAL_OPTS -bias=$BIAS"; fi
if [ -n "$DARK" ]; then CAL_OPTS="$CAL_OPTS -dark=$DARK -cc=dark 3 3"; fi
if [ "$MONO" -eq 0 ]; then CAL_OPTS="$CAL_OPTS -debayer"; fi
if [ -z "$DARK" ] && [ -z "$BIAS" ]; then
  die "較正データがありません（--dark か --bias は必須。-cfa だけでは較正できません）"
fi

if [ -n "$DARK" ] && [ ! -f "$DARK" ]; then die "ダークがありません: $DARK"; fi
if [ -n "$BIAS" ] && [ ! -f "$BIAS" ]; then die "バイアスがありません: $BIAS"; fi

# ---- クロップ量 ------------------------------------------------------------
if [ "$CROP_PCT" -gt 0 ]; then
  CX=$(( W * CROP_PCT / 100 )); CY=$(( H * CROP_PCT / 100 ))
  CW=$(( W - 2 * CX ));         CH=$(( H - 2 * CY ))
  CROP_CMD="crop ${CX} ${CY} ${CW} ${CH}"
else
  CROP_CMD="# クロップ無効 (--crop 0)"
fi

# ---- ステージ 1: 較正 + 整列 + スタック ------------------------------------
SSF1="${WORKDIR}/_flatless_stage1.ssf"
{
  echo "requires 1.5.0"
  echo "setext $EXT"
  echo "# auto-generated by flatless_pipeline.sh"
  echo "calibrate $SEQ$CAL_OPTS"
  echo "register pp_$SEQ -2pass"
  echo "seqapplyreg pp_$SEQ"
  echo "stack r_pp_$SEQ $REJ -norm=addscale -out=${OUTNAME}_stack"
  echo "exit"
} > "$SSF1"

if [ "$STAGE" = "all" ] || [ "$STAGE" = "1" ]; then
  if [ "$DRY" -eq 1 ]; then
    echo "===== $SSF1 ====="; cat "$SSF1"
  else
    log "ステージ1: 較正・整列・スタック"
    "$SIRIL_BIN" -d "$WORKDIR" -s "$SSF1"
  fi
fi

# スタック結果の実ファイル名を解決（.fit / .fits の差を吸収）
STACKF=""
if [ "$STAGE" = "all" ] || [ "$STAGE" = "1" ] || [ "$STAGE" = "2" ]; then
  for ext in fit fits; do
    if [ -f "${OUTNAME}_stack.$ext" ]; then STACKF="${OUTNAME}_stack.$ext"; break; fi
  done
  if [ -z "$STACKF" ]; then
    if [ "$DRY" -eq 1 ]; then
      STACKF="${OUTNAME}_stack.fit"      # ドライラン用のダミー名
    else
      die "スタック結果が見つかりません (${OUTNAME}_stack.fit*)。--stage 3 ならスタック不要です"
    fi
  fi
fi

# ---- ステージ 2: クロップ + 背景除去 + デノイズ ----------------------------
SSF2="${WORKDIR}/_flatless_stage2.ssf"
CROPF="${OUTNAME}_crop.${EXT}"
if [ "$STAGE" = "all" ] || [ "$STAGE" = "2" ]; then
  {
    echo "requires 1.5.0"
    echo "setext $EXT"
    echo "# auto-generated by flatless_pipeline.sh"
    echo "load \"$STACKF\""
    echo "$CROP_CMD"
    echo "save $CROPF"
    echo "exit"
  } > "$SSF2"

  if [ "$DRY" -eq 1 ]; then
    echo "===== $SSF2 ====="; cat "$SSF2"
  else
    log "ステージ2: 外周クロップ (${CROP_PCT}%/辺)"
    "$SIRIL_BIN" -d "$WORKDIR" -s "$SSF2"
  fi
fi

GX1=()
GX2=()
if [ "$STAGE" = "all" ] || [ "$STAGE" = "2" ]; then
  # GraXpert の -output は拡張子なしの裸名。入力と同じ場所に <name>.fits で出る。
  GX1=("$GRAXPERT_BIN" -cli -cmd background-extraction
       -correction Division -smoothing "$SMOOTH" -gpu false
       -output bge "$CROPF")
  # デノイズは BGE 後（linear のまま）に適用する
  GX2=("$GRAXPERT_BIN" -cli -cmd denoising
       -strength "$STRENGTH" -gpu false
       -output dn bge.fits)

  if [ "$DRY" -eq 1 ]; then
    echo "===== GraXpert 1 ====="; printf '%q ' "${GX1[@]}"; echo
    echo "===== GraXpert 2 ====="; printf '%q ' "${GX2[@]}"; echo
  else
    command -v "$GRAXPERT_BIN" >/dev/null 2>&1 || die "graxpert が見つかりません（--graxpert で指定）"
    log "ステージ2: 背景除去 (Division, smoothing=$SMOOTH)"
    "${GX1[@]}"
    [ -f bge.fits ] || die "GraXpert の出力 bge.fits がありません"
    if [ "$STRENGTH" = "0" ]; then
      log "ステージ2: デノイズはスキップ (--denoise 0)"
    else
      log "ステージ2: デノイズ (strength=$STRENGTH)"
      "${GX2[@]}"
      [ -f dn.fits ] || die "GraXpert の出力 dn.fits がありません"
    fi
  fi
fi

# ---- ステージ 3: ソルブ + SPCC + ストレッチ --------------------------------
SSF3="${WORKDIR}/_flatless_stage3.ssf"
{
  echo "requires 1.5.0"
  # ここから先の入力は GraXpert が書いた .fits
  echo "setext fits"
  echo "# auto-generated by flatless_pipeline.sh"
  if [ -f "$WORKDIR/dn.fits" ]; then echo "load dn.fits"; else echo "load bge.fits"; fi
  if [ "$SKIP_SOLVE" -eq 0 ]; then echo "platesolve"; fi
  if [ "$SKIP_SPCC" -eq 0 ]; then
    SPCC_LINE="spcc"
    if [ -n "$SENSOR" ]; then SPCC_LINE="$SPCC_LINE \"-oscsensor=$SENSOR\""; fi
    if [ -n "$OSCFILTER" ]; then SPCC_LINE="$SPCC_LINE \"-oscfilter=$OSCFILTER\""; fi
    if [ "$NARROWBAND" -eq 1 ]; then SPCC_LINE="$SPCC_LINE -narrowband"; fi
    echo "$SPCC_LINE"
  fi
  echo "autostretch -linked -2.8 $TARGETBG"
  echo "savetif32 ${OUTNAME}_final"
  echo "save ${OUTNAME}_final_stretched"
  echo "exit"
} > "$SSF3"

if [ "$DRY" -eq 1 ]; then
  echo "===== $SSF3 ====="; cat "$SSF3"
  echo "（--dry-run のため実行していません）"
  exit 0
fi

if [ "$STAGE" = "all" ] || [ "$STAGE" = "3" ]; then
  log "ステージ3: プレートソルブ / SPCC / ストレッチ"
  "$SIRIL_BIN" -d "$WORKDIR" -s "$SSF3"
fi

# ---- 結果 ------------------------------------------------------------------
echo
echo "===== 生成物 ====="
for f in "${OUTNAME}_stack".fit* "${OUTNAME}_crop".fit* bge.fits dn.fits \
         "${OUTNAME}_final.tif" "${OUTNAME}_final_stretched".fit*; do
  if [ -f "$f" ]; then printf "  %-32s %s\n" "$f" "$(du -h "$f" | cut -f1)"; fi
done
echo
echo "確認事項:"
echo "  1) bge.fits を autostretch して、対象の形が背景モデルに写っていないか"
echo "  2) 補正前後で外縁が『増えても減ってもいない』か"
echo "  3) 背景が中心から隅まで単調か（リング状の山谷が無いか）"
