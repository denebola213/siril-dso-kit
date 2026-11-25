# 07. 検証記録

「動いた」の根拠を残しておきます。書いていないものは検証していません。

## 環境

| 項目 | 値 |
|---|---|
| Siril | 1.5.0-712e3766f（Linux x86_64、`siril-cli`） |
| GraXpert | 3.x（CLI、CPU 実行 `-gpu false`） |
| StarNet2 | 2.6.2（ONNX Runtime、`/usr/bin/starnet2`） |
| StarNet.py | free-astro/siril-scripts の 2026 年版 |
| Python | 3.12 + numpy |
| データ | 合成 FITS（Bayer RGGB モザイク 768×768、周辺減光 30%、シフト付き 8 枚）と、実データ（NGC 6992、下記） |

## 実データで確認したこと

NGC 6992（2026-11、Ha+OIII 13枚 / SII+OIII 12枚、フラット・ダークなし）で
`01_stack_hao3.ssf` → `02_stack_s2o3.ssf` → `00_graxpert_channels.sh` →
`03_merge_compose.ssf` を完走。Ha / SII / OIII の分離と SHO 合成まで到達。
`04_finish_starnet.ssf` は StarNet2 未導入の環境だったため、この実データでは未実行。

## 合成データで確認したこと（公開前に再実行）

| 対象 | 結果 |
|---|---|
| `01_stack_hao3.ssf` | `calibrate -debayer` → `register` → `seqapplyreg` → `stack` → `split` が通り、`Ha.fits` / `OIII_ha.fits` を生成 |
| `02_stack_s2o3.ssf` | `-extref=` を 01 の出力に差し替えて実行、`SII.fits` / `OIII_s2.fits` を生成 |
| `00_graxpert_channels.sh` | 4チャンネルの BGE → denoise が完走（CPU） |
| `03_merge_compose.ssf` | OIII 統合 → `rgbcomp` で `SHO_linear.fits` を生成 |
| `04_finish_starnet.ssf` | StarNet2 で星を分離。`descreen_mask_image.fits` が生成され、`SHO_nebula` / `SHO_stars` / `SHO_final` まで完走 |
| `run_all.sh` | 上記 01→04 を 1 コマンドで完走 |
| `flatless_pipeline.sh` | ステージ1（較正・整列・スタック）、2（クロップ・BGE Division・denoise）、3（autostretch・`savetif32`・save）を完走。`--skip-solve --skip-spcc` で実行 |
| `qc_flatless.py` | 周辺減光 30% の合成画像で四隅比 0.662 を出力（設計値と一致）。`--dims` / `--json` / ペデスタル未指定の警告も確認 |
| `flat_panel_qc.py` | 180 度回した合成パネル画像で、仕込んだ非対称成分を検出（約 2 倍の偏差として出る） |
| `link_lights.sh` | Ekos 名（`NGC_6992_Light_001.fits`）からリンクを作成。リンク無しでは `Loading sequence 'light' failed.`、リンク後は完走 |

## 失敗経路も確認したこと

- `requires` 無し → 5ms で「成功」して何も起きない
- Ekos 名のまま → `Loading sequence 'light' failed.`
- `-s` に相対パス → `File [...] does not exist (from CWD, use absolute path?)`
- StarNet2 に 512px 未満 → `Image size is too small for the window!` / status 255、
  しかも `save` は通り、星を抜いていない画像が保存される
- 較正データ無しで `flatless_pipeline.sh` → 明示エラーで停止
- GraXpert が PATH に無い → `エラー: graxpert が見つかりません（--graxpert で指定）`

## 未検証

- `platesolve` / `spcc`（合成データではプレートソルブが成立しないため、両方スキップして実行）
- Flatpak 版 Siril のサンドボックス内から外部バイナリを呼ぶ構成
- Windows / macOS
- GraXpert の deconvolution（3.0.x には存在しない。3.1 以降で未実行）
- exFAT / NTFS 上での `link_lights.sh`（シンボリックリンクが作れないため、名前の変更で代替）
