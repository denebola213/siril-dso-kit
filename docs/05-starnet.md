# 05. StarNet2 で星を抜く

星を抜いて、星雲と星を別々にストレッチするための手順です。

## Siril 1.5 では C コマンドが消えている

1.5.0 で `starnet` / `seqstarnet` の C インターフェースが削除されました
（release note: "Removed original Starnet C interface"）。設定画面の実行ファイル指定もありません。

```
starnet
→ コマンド実行失敗: ファイルが見つからない
```

1.4 / 1.5 で使えるのは Python スクリプト `StarNet.py` だけです。

## 導入

1. StarNet2 の CLI を配布元から取得（`download.starnetastro.com`。旧
   `www.starnetastro.com/wp-content/uploads/...` の URL は死んでいます）
2. `starnet2` を PATH か `/usr/bin` に置く。zip 版はライブラリと同居させたままにすること
3. `StarNet.py` を Siril のスクリプト置き場に置く

```bash
mkdir -p ~/.local/share/siril/scripts
curl -LO https://raw.githubusercontent.com/free-astro/siril-scripts/main/StarNetAstro/StarNet.py
mv StarNet.py ~/.local/share/siril/scripts/
```

GUI なら Scripts → Get Scripts からも入ります。**Siril 本体のインストール先にある
scripts ディレクトリや siril-scripts リポジトリの作業ツリーには置かないでください。**
起動のたびにリセットされます。

## 実行

```
load SHO_linear
pyscript StarNet.py --linear --masks descreen
```

| フラグ | 意味 |
|---|---|
| `--linear` / `--no-linear` | 線形データとして扱う。内部で仮ストレッチし、戻して返す |
| `--sequence` | シーケンス全体に適用 |
| `--stride N` | タイルサイズ（偶数 2–512） |
| `--upsample` | アップサンプルして処理 |
| `--protect-highlights` | ハイライト保護 |
| `--masks <kind>` | マスク／星レイヤーの出力形式 |
| `--exe PATH` | 最終手段。PATH に通っていれば付けない |

`--masks` に取れる値は **`starnet-mask` / `starnet-unscreen` / `descreen` / `subtract` の4つだけ**です。
`--masks starnet` は無効で、`StarNet: unknown mask kind(s): starnet` で中断します。

- `descreen` = `(orig - starless) / (1 - starless)` — スクリーン合成で元に戻せる形
- `subtract` = `orig - starless`
- `starnet-mask` / `starnet-unscreen` は StarNet 本来の出力ですが、`--linear` では
  線形領域で無効なので、スクリプトが subtract / descreen として計算します

## 出力名の実際（2026 年版で実測）

古い記事と挙動が違うので注意してください。

- **星無し画像はファイルに落ちません。** 現在の画像バッファに返るので、直後に `save` します
- **星レイヤーは `descreen_mask_image.fits`** として保存されます。元画像の名前ではなく
  `image` 固定です（`pyscript` に渡る画像名がそれになるため）
- `-i` / `-o` は不要

```
load SHO_linear
pyscript StarNet.py --linear --masks descreen
save SHO_starless            # ← これが無いと星無しが消える
```

`load starless_SHO_linear` のような古い手順は `file not found` になります。ログには
`Saved Siril star layer (descreen) to descreen_mask_image.fits` が出ているはずです。

## 失敗しても気づきにくい

StarNet.py が失敗しても、**Siril のスクリプトは止まりません**。バッファには元画像が
残ったままで `save` が成功するので、星を抜いていない画像が `SHO_starless` として
保存されます。続く `load descreen_mask_image` で初めて `file not found` になります。

ログに次のいずれかが出ていないか確認してください。

```
StarNet exited with status 255
Image size is too small for the window!
```

後者は **512px 未満の画像を処理できない**という制約です（StarNet2 のタイル窓より小さい）。
小さい画像で試すときは 512px 以上にクロップ／リサイズしてください。

## どこに入れるか

**線形の段階**に入れます。SPCC の後、ストレッチの前です。

```
platesolve
spcc ...
pyscript StarNet.py --linear --masks descreen
save SHO_starless
```

ストレッチ後に抜くと、星の芯が飽和した状態で分離することになり、戻したときに不自然になります。

## 星レイヤーの扱い

```
load descreen_mask_image
autostretch -linked -2.8 0.08     # 星雲より弱く伸ばす
satu -1 1                          # ナローバンド由来なら灰色化
save SHO_stars

load SHO_nebula
pm "$SHO_nebula$ + $SHO_stars$ - $SHO_nebula$ * $SHO_stars$"
save SHO_final
```

- 星雲と同じだけ伸ばすと芯が白飛びして団子になります
- 星が硬すぎる／貼り付いて見えるときは `pm` の前に `fmul 0.7–0.9`
- `satu -1 1` はナローバンド合成の星を灰色にするため。広帯域 RGB の星レイヤーなら不要

## ライセンス

**StarNet2 は無料ですが OSS ではありません。** v2 でソースが閉じられ、バイナリのみの配布です
（初代 StarNet は OSS でした）。「OSS のみ」を条件にする構成では使えません。使う場合は
「OSS + 無料の非 OSS バイナリ1本」と明記してください。

代替として `code2k13/starreduction`（MIT）がありますが、開発は止まっています。
有料の BlurXTerminator は OSS の流れには入れないでください。
