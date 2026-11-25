# 06. 症状別トラブルシュート

上から順に、出会う頻度の高いものから並べています。

## スクリプトが一瞬で終わる

| 症状 | 原因 |
|---|---|
| `Script execution finished successfully` が数ミリ秒で出て、何も起きない | `requires 1.5.0` 行が無い |
| `No sequence found ... (current is .fit)` | `setext fits` が無い（Ekos は `.fits` を書く） |
| `Loading sequence 'light' failed.`（`No sequence found` は出ない） | ファイル名が違う。別 basename の `.seq` ができている |
| 何もログが出ない | `X.seq` が壊れている。`rm -f X.seq`。本当の理由は STDERR のみ |

詳しくは [01-siril-15-gotchas.md](01-siril-15-gotchas.md)。

## 較正がおかしい

**まずペデスタルを疑ってください。** ライトとダーク／バイアスを別の offset で撮っていると、
数百 ADU の差が全画素を負にして空を潰します。較正の前に中央値を見ます。

```python
# 1枚ずつの中央値を比べる（FITS は numpy で読めます）
```

ライト / ダーク / バイアスの中央値が大きくずれている場合の対処：

```
# バイアスを引いたダークを作り、それを -dark= に渡す（-bias= は付けない）
calibrate dark -bias=master_bias
stack pp_dark -nonorm -out=master_dark_bs
```

ホットピクセルの超過分はペデスタルに依存しないので、補正は正しいまま offset のずれが消えます。

| 症状 | 原因 |
|---|---|
| 空が真っ黒に潰れる / 星が欠ける | offset 0 で撮っている。取得側の欠陥。次の夜に offset を上げる |
| アンプグローが残る | 露出・温度が一致したダークを使う。**`-opt`（ダーク最適化）は使わない**。グローは露光に線形比例しない |
| ザラザラしたノイズが残る | ホットピクセルのショットノイズ。コスメティック補正＋ディザ＋σクリップで積算する。ダークの精度を上げても解決しない |

## スタックで拒否される

```
detected registration data on layer 0 with more than simple shifts
```

`register` の後に `seqapplyreg` を挟んでください。`r_` 付きシーケンスが作られ、
`stack r_pp_light ...` で通ります。`-2pass` の有無に関係なく起こります。

```
rej 3 3 で落ちる
```

枚数不足です。10枚未満なら `med` に落とします。

## 色が転ぶ・色が出ない

| 症状 | 原因 / 対処 |
|---|---|
| 合成が特定の色に転ぶ | チャンネル間の背景レベル差。`linear_match ref 0.0 0.01` で背景を揃えてから合成 |
| 重みを掛けたら画面全体がその色になった | `linear_match` の後に重みを掛けている。重みは背景も持ち上げる。1.0 のまま合成する |
| ストレッチ後に色バランスが崩れた | `autostretch` に `-linked` が無い |
| マゼンタ／紫の背景 | R と B が G より高い。`rmgreen` ではなく R/B のバランスを取る |
| SPCC でフィルタを変えても結果が同じ | 1.5.0 の既知の挙動（K が変わらない）。色差を語る前に K0/K1/K2 を確認 |
| SPCC が `invalid arguments` | スペースを含む値をトークン全体で引用していない。`"-oscsensor=Sony IMX571"` |

## StarNet で詰まる

| 症状 | 原因 |
|---|---|
| `コマンド実行失敗: ファイルが見つからない`（`starnet`） | 1.5 で C インターフェースが削除済み。`StarNet.py` を使う |
| `StarNet: unknown mask kind(s): starnet` | `--masks` は `descreen` / `subtract` / `starnet-mask` / `starnet-unscreen` のみ |
| StarNet 成功後に `file not found` | 星無しはバッファに返る。`save` を書く。星レイヤーは `descreen_mask_image.fits` 固定 |
| `StarNet executable is not valid`（GUI から指定） | Wayland のファイル選択が portal のパスを返す。`GTK_USE_PORTAL=0 siril` で起動する |
| 星が貼り付いたように見える | 星レイヤーの伸ばしすぎ。`-2.8 0.08` 程度に下げ、`pm` の前に `fmul 0.8` |

## 背景がムラになる（ストレッチ後）

ムラは多くの場合、大きなスケールの**輝度**残差で、きれいな勾配ではありません。いきなり
BGE を強くするのではなく、原因を切り分けてください。

1. **GraXpert の `-smoothing` を上げる**（0.15 → 0.25–0.40）。低いとモデルが構造を追って
   ムラが残り、高すぎると淡い星雲を食います。ここが最大の調整点
2. `-correction Division` と `Subtraction` を比べる
3. 強い1パス → 弱い1パス、の2段
4. `subsky -rbf=<n> -samples=<n>` でサンプル位置を自分で置く（Siril は制約できる）
5. GHT の黒点で背景を沈める
6. 取得側：ディザと積算時間

対象が画面いっぱい（ベール星雲など）だと、きれいな空の画素が足りずモデルが不足します。
ムラの一部は本物の淡い Hα / OIII / IFN です。消しすぎに注意してください。

**本物かアーティファクトかの判定**：露出やサブセットを変えて再スタックし、
同じ場所に残るなら実信号かフラット／ダークの欠陥です。背景モデルのせいではありません。

**ディザを「見た目」で判断しないでください。** 位相相関で測ると、10px 程度のばらつきが
あれば σクリップ積算でセンサー固定パターンを除去できます。ディザがあるのに色ムラを
ディザのせいにすると、対処が全部外れます。

## GraXpert が落ちる

| 症状 | 原因 |
|---|---|
| GUI が開く | `-cli` が無い |
| `FileNotFoundError: out/out/x.fits` | `-output` にディレクトリを渡した。裸の名前のみ |
| `libcublasLt.so.12` の警告 | CUDA ランタイムが無い。CPU で動く。`-gpu false` で黙る |
| 入力が見つからない | 入力は位置引数。`-input` は存在しない |
| 出力が入力と同じ場所に出る | 仕様。`os.path.join(dirname(input), output + ".fits")` で書かれる |

## フラットが無い

[docs/03-flatless.md](03-flatless.md)。判定 → クロップ → Division の BGE → デノイズ。
ダストモートだけは消えません。
