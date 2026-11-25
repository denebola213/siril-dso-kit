# flatless — フラット無しで仕上げる

フラットを撮っていないライト列を、ダーク（またはバイアス）だけで仕上げるためのキット。
使うのは OSS のみ（Siril 1.5 = GPL-3.0 / GraXpert 3.x = GPL-3.0 / Python + numpy）。

```
qc_flatless.py        1枚から「フラットレスで行けるか」を実測判定する
flatless_pipeline.sh  本処理（較正→整列→スタック→クロップ→BGE→デノイズ→SPCC→ストレッチ）
```

**フラットがあるなら使ってください。** これは「無い場合の最善」であって、上位互換ではありません。

## 1. まず QC（1分）

```bash
python3 qc_flatless.py light_0001.fits --pedestal 500
```

`--pedestal` はカメラのオフセット値（ADU）。分からなければ `--bias master_bias.fit`。
省略すると減光を**過小評価**するので、必ず指定してください（未指定なら警告が出ます）。

| 最も暗い隅（中心比） | 判定 | 次の行動 |
|---|---|---|
| > 0.95 | 可 | そのまま本処理（`--crop 2` 程度） |
| 0.85 – 0.95 | 条件付き可 | `--crop 5` |
| < 0.85 | 不可寄り | `--crop 8` 以上、またはフラットを撮る |
| 非対称性 > 1.10 | 危険 | ダスト/傾き。モデルでは消えない → クロップかフラット |

`--json` で機械可読、`--dims` で `幅 高さ` だけを出します（パイプラインが利用）。

数値で分からないもの：**ダストモート**。1枚を `autostretch` して、背景の円形の暗いシミを
目視してください。

## 2. 本処理

```bash
./flatless_pipeline.sh \
  --workdir /path/to/lights \
  --lights "light_*.fit" \
  --dark master_dark.fit \
  --sensor "Sony IMX571" \
  --filter "None" \
  --crop 3
```

実行計画だけ確認する場合（ファイルを書きません）：

```bash
./flatless_pipeline.sh --workdir . --dark master_dark.fit --dry-run
```

### 主なオプション

| オプション | 既定 | 意味 |
|---|---|---|
| `--workdir DIR` | カレント | ライトのあるディレクトリ |
| `--lights GLOB` | `light_*.fit` | ライトのパターン。`light_0001.fit` → シーケンス名 `light` を自動推定 |
| `--seq NAME` | 自動 | シーケンス名を明示 |
| `--dark FILE` | — | マスターダーク（`-cc=dark 3 3` も有効化） |
| `--bias FILE` | — | マスターバイアス |
| `--mono` | off | モノクロカメラ（`-debayer` を付けない） |
| `--crop PCT` | 3 | 各辺を削る割合[%]。0 で無効 |
| `--smoothing V` | 0.35 | GraXpert BGE。**0.5 超は外殻を食う** |
| `--targetbg V` | 0.25 | `autostretch` の背景値（0.15 で色ムラが目立たなくなるが、これは見た目だけ） |
| `--denoise V` | 0.5 | GraXpert デノイズ強度。0 でスキップ |
| `--sensor` / `--filter` | — | SPCC 用。`spcc_list oscsensor` で正確な文字列を確認 |
| `--narrowband` | off | SPCC をナローバンド扱い |
| `--skip-spcc` / `--skip-solve` | off | 該当ステップを飛ばす |
| `--out NAME` | `target` | 出力名の接頭辞 |
| `--stage all\|1\|2\|3` | all | 途中から再実行 |
| `--dry-run` | off | `.ssf` を生成して表示するだけ |
| `--siril` / `--graxpert` | `siril` / `graxpert` | 実行ファイルを差し替え |

FITS の拡張子はライトから自動判定し、生成する `.ssf` に `setext` を入れます。
`--siril siril-cli` を渡すか、`siril` が PATH にある前提です。

## 3. ステージ構成

| ステージ | 実体 | 生成物 |
|---|---|---|
| 1 | `_flatless_stage1.ssf`（Siril） | `pp_light*` / `r_pp_light*` / `<out>_stack.fits` |
| 2a | `_flatless_stage2.ssf`（Siril） | `<out>_crop.fits` |
| 2b | GraXpert BGE（**Division**） | `bge.fits` |
| 2c | GraXpert denoise | `dn.fits` |
| 3 | `_flatless_stage3.ssf`（Siril） | `<out>_final.tif` / `<out>_final_stretched.fits` |

**この順序である理由**

- 背景除去は**線形**で行う（ストレッチ後では物理的に意味がない）
- デノイズも線形で1パス
- クロップは BGE の**前**。外周の極端な減光を残すとモデルが引っ張られる
- `autostretch` は `spcc` の**後**、かつ `-linked`（アンリンクは色バランスを壊す）

## 4. 結果の確認（必須）

1. `bge.fits` を開いて `autostretch` → **対象の形が背景モデルに写っていないか**
2. 補正前後で外縁が「増えても減ってもいない」か
3. 背景が中心から隅まで単調か（リング状の山谷が無いか）

淡い外殻（球状星団の潮汐構造など）を主張する画像では `--smoothing` を 0.3 以下にし、
BGE を2パスにしないでください。

## 5. つまずきやすい点

| 症状 | 原因 / 対処 |
|---|---|
| `スタック結果が見つかりません` | 出力拡張子が `.fits` の可能性。`--out` を変えて再実行 |
| `spcc` で落ちる | センサー/フィルタ名が違う。`spcc_list oscsensor` で確認。オフラインなら `--skip-solve --skip-spcc` |
| `graxpert が見つかりません` | `--graxpert /path/to/graxpert` |
| `FileNotFoundError: out/out/...` | `-output` にディレクトリを渡している。スクリプトは裸名を渡すので通常は起きない |
| 背景がまだリング状 | `--crop` を増やす → `--smoothing` を 0.3 に下げる → それでも駄目ならフラット |
| 色が転ぶ | `autostretch` に `-linked` が付いているか確認（スクリプトは常に付与） |

## 6. 制約

- **ダストモートは消えません。** クロップで外すか、フラットを撮る以外に手段がありません。
- 減光が15%超の光学系では、「捨てる」か「諦めて撮り直す」に収束します。
- M33 のような低表面輝度・画面充填型の対象には向きません（クロップが効かず、BGE が腕を食う）。

## 検証状況

合成データ（Bayer 768px、8枚）でステージ1〜3 を通し実行済み。`platesolve` と `spcc` は
合成画像ではプレートソルブが成立しないため `--skip-solve --skip-spcc` で実行し、未検証です。
`--dry-run` の生成内容、QC の判定値、エラー経路も確認しています。詳細は
[docs/07-verification.md](../../docs/07-verification.md)。
