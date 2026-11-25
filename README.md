# siril-dso-kit

Siril 1.5 で天体画像（DSO）を仕上げるための `.ssf` スクリプトと、その使い方の日本語ドキュメント。

「動いた」と言い切れるものだけを置いています。各スクリプトには、実際にどこまで検証したかを
README に明記してあります。推測で書いたコマンドは入れていません。

English: Battle-tested Siril 1.5 `.ssf` scripts with Japanese usage docs — dual-band
(Hα+OIII / SII+OIII) SHO composition, a flatless pipeline, and GraXpert / StarNet CLI recipes.
Verified on Siril 1.5.0 (Linux, `siril-cli`). All paths in the docs assume 16-bit FITS.

## 収録内容

| ディレクトリ | 内容 | 検証状況 |
|---|---|---|
| `scripts/dualband_sho/` | Hα+OIII と SII+OIII の2枚から SHO を合成する 4 本の `.ssf` ＋ ファイル名整形 | 実データ（NGC 6992）で 01→03、合成データで 01→04（StarNet2 込み）まで完走 |
| `scripts/flatless/` | フラット無しのライト列を仕上げるパイプラインと、1枚から可否を測る QC | 合成データでステージ1〜3 を完走（platesolve / SPCC は未検証） |
| `scripts/flat_panel_qc/` | フラット光源のムラを回転差分で測る | 合成データで動作確認 |
| `docs/` | セットアップ、Siril 1.5 の罠、各ワークフロー、GraXpert / StarNet の CLI 仕様、症状別トラブルシュート、検証記録 | — |

## 前提

| ソフト | 必要なバージョン | 備考 |
|---|---|---|
| Siril | **1.5 系**（1.5.0 で検証） | コマンド名と挙動が 1.4 以前と違う。`requires 1.5.0` 行は削らない |
| GraXpert | 3.0 以上（deconvolution は 3.1 以上） | GPL-3.0。`-cli` 必須 |
| StarNet2 | CLI 2.5.0–2.6.2 | 無料だが**非 OSS**（v2 でソース非公開）。使う場合は構成をそう書く |
| Python 3 + numpy | QC 用 | `pip install numpy` |

Linux（Arch / Fedora / Flatpak）での導入手順は [docs/00-setup.md](docs/00-setup.md)。

## クイックスタート

```bash
git clone https://github.com/denebola213/siril-dso-kit.git
cd siril-dso-kit

# 1) ライトのファイル名を light_0001.fits 連番に揃える（Ekos 名のままだと calibrate が通らない）
scripts/dualband_sho/link_lights.sh /path/to/work/HaO3

# 2) 較正 → 整列 → スタック → Ha/OIII 分離
siril-cli -d /path/to/work/HaO3 -s scripts/dualband_sho/01_stack_hao3.ssf
```

詳細は [docs/02-dualband-sho.md](docs/02-dualband-sho.md)。

## 最初に読むべき1本

[docs/01-siril-15-gotchas.md](docs/01-siril-15-gotchas.md) — `setext` を書かないと
「`Script execution finished successfully` と出て 5ms で終わる」、シーケンス名はファイル名の
basename そのもの、CFA を保ったままの整列は 1.5 の CLI では成立しない、など。
ここを踏むと原因が分からないまま数時間溶けます。

## ドキュメント

| ファイル | 内容 |
|---|---|
| [docs/00-setup.md](docs/00-setup.md) | Siril 1.5 / GraXpert / StarNet2 / Python の導入 |
| [docs/01-siril-15-gotchas.md](docs/01-siril-15-gotchas.md) | 1.5 の罠（`setext`、basename、CFA、`pm`、`spcc`、`linear_match`） |
| [docs/02-dualband-sho.md](docs/02-dualband-sho.md) | デュアルバンド2枚からの SHO |
| [docs/03-flatless.md](docs/03-flatless.md) | フラット無しの判定と本処理 |
| [docs/04-graxpert-cli.md](docs/04-graxpert-cli.md) | GraXpert 3.x の CLI 仕様 |
| [docs/05-starnet.md](docs/05-starnet.md) | StarNet2 の導入と挙動 |
| [docs/06-troubleshooting.md](docs/06-troubleshooting.md) | 症状別の切り分け |
| [docs/07-verification.md](docs/07-verification.md) | 何をどこまで検証したか |

## 設計方針

- **失敗の原因をログで特定できる形にする。** エラーが出たら何が起きたかを docs に書いてある。
- **数値は実測。** 「補間で 2x2 コントラストが 70% → 34% → 19% に落ちる」は実データの測定値で、
  仕様の推測ではない。測定していないことは「未検証」と書く。
- **OSS の範囲を明示する。** Siril と GraXpert は GPL-3.0。StarNet2 は無料だが非 OSS なので、
  使った構成を「OSS + 無料の非 OSS バイナリ1本」と書く。

## 注意

- 座標・撮影地・個人環境のパスは含めていません。スクリプトはすべて相対パスか引数で受け取ります。
- `.ssf` は Siril のバージョンに強く依存します。1.4 系では動きません。
- 未検証の組み合わせ（Flatpak のサンドボックス内から外部バイナリを呼ぶ等）は該当 docs に注記しています。

## ライセンス

スクリプトとドキュメント: MIT（[LICENSE](LICENSE)）。
ただし StarNet2 は独自ライセンスのバイナリで、本リポジトリには含みません。
