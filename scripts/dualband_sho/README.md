# dualband_sho — デュアルナローバンド2枚から SHO

Hα+OIII と SII+OIII のライト列から、Hα / SII / OIII を分離して SHO 合成します。
手順の背景説明は [docs/02-dualband-sho.md](../../docs/02-dualband-sho.md)。

## ファイル

| ファイル | 役割 | 実行場所 |
|---|---|---|
| `run_all.sh` | 01→04 を順に回す薄いラッパー | どこからでも |
| `link_lights.sh` | Ekos 名を `light_0001.fits` にリンク | ライトのディレクトリ |
| `01_stack_hao3.ssf` | Ha+OIII: 較正 → 整列 → スタック → Ha/OIII 分離 | HaO3 の作業ディレクトリ |
| `02_stack_s2o3.ssf` | SII+OIII: 同上。`-extref` で 01 のスタックに位置合わせ | S2O3 の作業ディレクトリ |
| `00_graxpert_channels.sh` | 4チャンネルに BGE → denoise（線形のまま） | `ch/` |
| `03_merge_compose.ssf` | OIII の統合 → SHO 合成（線形のまま） | `ch/` |
| `04_finish_starnet.ssf` | StarNet2 → 別ストレッチ → スクリーン合成 | `ch/` |

## まとめて回す

```bash
scripts/dualband_sho/run_all.sh \
  --hao3 /path/work/HaO3 \
  --s2o3 /path/work/S2O3 \
  --ch   /path/work/ch \
  --graxpert /opt/graxpert/GraXpert-linux/GraXpert \
  --skip-starnet        # StarNet2 が無い場合
```

`--siril` で実行ファイルを差し替えられます（既定 `siril-cli`）。
StarNet2 を入れたら `--skip-starnet` を外してください。

## 個別に回す

```bash
scripts/dualband_sho/link_lights.sh /path/work/HaO3
scripts/dualband_sho/link_lights.sh /path/work/S2O3

siril-cli -d /path/work/HaO3 -s scripts/dualband_sho/01_stack_hao3.ssf
siril-cli -d /path/work/S2O3 -s scripts/dualband_sho/02_stack_s2o3.ssf   # -extref を書き換える

mkdir -p /path/work/ch && cd /path/work/ch
ln -sf ../HaO3/Ha.fits ../HaO3/OIII_ha.fits ../S2O3/SII.fits ../S2O3/OIII_s2.fits .
GRAXPERT=/opt/graxpert/GraXpert-linux/GraXpert scripts/dualband_sho/00_graxpert_channels.sh .

siril-cli -d /path/work/ch -s scripts/dualband_sho/03_merge_compose.ssf
siril-cli -d /path/work/ch -s scripts/dualband_sho/04_finish_starnet.ssf
```

## 書き換える箇所

| ファイル | 箇所 |
|---|---|
| 01 / 02 | `calibrate` のオプション（フラット・ダークがある夜のみ） |
| 02 | `-extref=` のパス（絶対パス・拡張子込み） |
| 03 | `linear_match` の窓（既定 0.0–0.01）、露出が違う場合の `fmul` 比 |
| 04 | 星が硬い場合、`pm` の前に星レイヤーへ `fmul 0.8` |

## 前提と出力

- 各フィルタのライトが `light_0001.fits` の連番で並んでいること
- `.fits` 前提（各 `.ssf` の `setext fits` がこれを成立させている）
- マスターダークは露出・温度・offset がライトと一致するものだけ

| 出力 | 内容 |
|---|---|
| `HaO3_color.fits` / `S2O3_color.fits` | 較正済みカラースタック |
| `Ha.fits` / `SII.fits` | R 画素から取り出した Hα / SII |
| `OIII_ha.fits` / `OIII_s2.fits` | (G+B)/2 |
| `*_gx.fits` | GraXpert 適用後 |
| `SHO_linear.fits` | 線形 SHO 合成 |
| `SHO_nebula.fits` / `SHO_stars.fits` / `SHO_final.fits` | 星無し / 星 / 合成 |

## 検証状況

NGC 6992 の実データ（Ha+OIII 13枚 / SII+OIII 12枚、フラット・ダークなし）で
01 → 02 → 00 → 03 まで完走。04 は StarNet2 を導入していない環境だったため未実行でしたが、
合成データ（Bayer 768px、8枚）で StarNet2 2.6.2 を使って 04 まで完走し、
星レイヤーが `descreen_mask_image.fits` として出ることを確認しています。
詳細は [docs/07-verification.md](../../docs/07-verification.md)。

## 注意

- `linear_match` の後に重みを掛けると背景ごと持ち上がり、画面全体がその色に転びます（実測）。
- 02 の `-extref` を通さないと2つのスタックが別グリッドに載り、OIII の平均が二重像になります。
- 失敗の切り分けは [docs/01-siril-15-gotchas.md](../../docs/01-siril-15-gotchas.md) の
  3パターン表を見てください。
