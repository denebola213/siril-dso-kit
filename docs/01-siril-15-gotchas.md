# 01. Siril 1.5 の罠（実測にもとづく）

1.5 の CLI で詰まった点を、症状 → 原因 → 対処の順にまとめます。ここに書いてあることは
すべて実際に踏んだものです。踏むと原因が分からないまま時間が溶けるものから並べています。

## `requires` 行が無いと何も実行されない

`.ssf` の1行目は `requires 1.5.0` でなければなりません。

```
requires 1.5.0
setext fits
...
```

無いと Siril は `Script execution finished successfully` を出して **5ms で終わります**。
エラーになりません。ファイルが1つもできていないのに成功と表示されるので、最初は
「出力先が違うのか」と探し回ることになります。

## `setext` を書かないと `calibrate` が落ちる

Siril の FITS 拡張子の既定は `.fit` です。Ekos や多くの撮影ソフトは `.fits` を書きます。
そのため、目の前に `light_0001.fits` があっても Siril からは見えません。

```
No sequence found, verify working directory or change FITS extension in settings (current is .fit)
No sequence `light' found
無効な入力シーケンス
```

対処は `setext fits` を `requires` の次（2行目）に置くことです。`setext` が取る値は
`fit` / `fits` / `fts` の3つだけです。

**この1行はシーケンスの構成にも `load` / `save` の拡張子にも効きます。** 段階ごとに別の
`.ssf` を走らせるとき、全部同じ値にしないと次段が前段の出力を見つけられません。
ただし `-dark=` `-flat=` `-extref=` のような**明示パスには効きません**。実拡張子を書いてください。

## シーケンス名はファイル名の basename

`calibrate light` は `light_0001.fits` という名前を要求します。Siril はファイル名から
シーケンス名を自動で決めるので、`NGC_6992_Light_001.fits` なら basename は
`NGC_6992_Light_`（**末尾の区切り込み**）になり、`light.seq` は作られません。

まずディレクトリの `.seq` を見てください。Siril がどの basename を検出したかは、そこに書いてあります。

```bash
ls *.seq            # 例: NGC_6992_Light_.seq ができていたら、それが実際の名前
```

対処はシンボリックリンクで `light_0001.fits` 連番を用意することです（実体はコピーしない）。

```bash
for f in *.fits; do ln -sfn "$f" "$(printf 'light_%04d.fits' $i)"; i=$((i+1)); done
```

`scripts/dualband_sho/link_lights.sh` がこれをやります。シンボリックリンクは
ext4 / xfs / btrfs でのみ作れます。exFAT / NTFS では名前を変更してください（容量は増えません）。

## 失敗の3パターンはログで区別できる

シーケンス関連の失敗は見た目が似ていますが、ログで切り分けられます。

| ログ | 原因 | 対処 |
|---|---|---|
| `Checking sequences in the directory` ＋ `No sequence found ... (current is .fit)` | 拡張子違い。1枚もマッチしていない | `setext fits` を追加 |
| `Checking sequences in the directory` はあるが `No sequence found` が無く、`Loading sequence 'X' failed.` | ファイルはあるが**別名**。別 basename の `.seq` が作られ、要求した `X.seq` が存在しない | `link_lights.sh` で名前を揃える |
| `Checking sequences` 行すら出ない | `X.seq` が既にあり、再スキャンせず読みに行って失敗 | `rm -f X.seq`（登録結果も消えるので `register` 前のみ） |

3番目は本当の理由が STDERR にしか出ません。GUI では隠れるので、`siril-cli` を端末で走らせてください。

## `register` の後は `seqapplyreg` を挟む

1.5 では `register` は変換を計算するだけで、`r_` 付きの画像を作りません。

```
register pp_light -2pass
seqapplyreg pp_light        # ここで r_pp_light ができる
stack r_pp_light rej 3 3 -norm=addscale -out=result
```

`register` の直後に `stack` すると、変換が shift 以外のときに拒否されます。

```
detected registration data on layer 0 with more than simple shifts
```

`register` の既定は相似変換／ホモグラフィを含むフィットなので、`-2pass` でなくても
この拒否は起こります。`seqapplyreg` を挟めば解消します。

## CFA を保ったままの整列は成立しない（実測）

`calibrate -cfa` ＋ `extract_HaOIII` というルートは、1.5 の CLI では使えません。
ベイヤーモザイクを保ったまま整列できないからです。実データで測った値：

| 段階 | 2x2 サイトのコントラスト | 1px 高周波エネルギー |
|---|---|---|
| 較正直後 | 70% | 1.0 |
| `seqapplyreg` 後 | 34% | 1/4 |
| `stack` 後 | 19% | — |

`seqapplyreg` はバイリニア補間し、`stack` がさらにリサンプルします。`src/stacking/stacking.c`
にベイヤー処理はありません。`register -transf=shift -interp=none` は**登録段階**の補間を
止めるだけで、変換自体がサブピクセルを含むため `stack` が補間します。

**採用する経路**：`calibrate light -debayer` → `register` → `seqapplyreg` → `stack` →
`split` で Ha/OIII を取り出す。情報量は `extract_HaOIII` と同等です（あちらも Ha は
補間された R 画素から作られます）。

## 引数の個数が決まっているコマンド

```
split Ha G B        # 3つの出力名が必須（引数なしでは動かない）
savepng result      # 出力名が必須。引数なしは invalid number of arguments
```

`stack` の出力は `-out=`、`split` は位置引数、`pm` は `-out=` を持たない、と不揃いです。
下表は混同しやすいものの整理です。

| コマンド | 結果の行き先 |
|---|---|
| `stack seq ... -out=name` | ファイル `name` |
| `split a b c` | ファイル `a` `b` `c` |
| `pm "式"` | **現在の画像バッファ**（`-out=` は無い） |
| `pyscript StarNet.py` | 星無しは**現在の画像バッファ**、星レイヤーはファイル |

## 算術コマンドの名前が直感に反する

| コマンド | 意味 |
|---|---|
| `fmul 0.5` | 定数を掛ける（**f**loat multiply） |
| `imul file` | 画像を掛ける（**i**mage multiply） |
| `iadd file` / `isub file` | 画像を足す / 引く |
| `linear_match ref low high` | `[low, high]` の画素だけを使って参照画像に合わせる |

チャンネル合成は `pm` より `fmul` / `iadd` / `linear_match` の方が挙動が読みやすいです。
`pm` は `$name$` 記法が必要で、結果の扱いも独特なので、スクリーン合成など限られた用途に向きます。

## `linear_match` の窓は背景だけにする

```
linear_match Ha_gx 0.0 0.01
```

0.0–0.01 は 16bit で 0–655 ADU、つまり背景だけを拾う窓です。0.0–0.10 にすると星が混ざって
ゲインの推定が狂います。

**そして `linear_match` の後に重みを掛けないでください。** 重みは背景も一緒に持ち上げるので、
画面全体がその色に転びます（SII に 1.5 を掛けたら合成が真っ赤になったのを実測）。
重みを掛けるなら背景を引いた後、あるいは 1.0 のまま合成して弱い線の扱いは別にする。

## `autostretch` の引数は位置引数

```
autostretch -linked -2.8 0.15
```

`-2.8` が shadowsclip、`0.15` が targetbg で、**名前付き引数ではありません**。
色校正の後は必ず `-linked` を付けてください。アンリンクだとホワイトバランスが壊れます。

targetbg を下げると背景が暗くなり色ムラが目立たなくなりますが、これは**見た目だけ**の話です。
クロマノイズは背景レベルに比例するので、ノイズ対背景の比は変わりません（実測 0.42 → 0.45）。
効くのはデノイズ強度か積算時間です。

## `spcc` の文字列は丸ごと引用する

```
spcc "-oscsensor=Sony IMX571" "-oscfilter=No filter"
```

`-oscsensor="Sony IMX571"` の形は `invalid arguments` になります。スペースを含む値は
**トークン全体**を引用してください。

受け付ける文字列は `spcc_list` で確認できます（ログに出力されます）。

```
spcc_list oscsensor
spcc_list oscfilter
spcc_list monosensor
spcc_list whiteref
```

`spcc -oscfilter=` は 1.5.0 のビルドで**値を受け付けるが結果に効かない**現象を確認しています。
`No filter` / `SIGHTRON Comet BP` / `Baader UV/IR Cut` の3つで K0/K1/K2 が
1.000/0.669/0.777 の同一値、出力もビット一致でした。フィルタ間の色差を語る前に、
K が実際に変わっているか確認してください。

## `pm` は `$name$` で画像を参照する

```
load SHO_nebula
pm "$SHO_nebula$ + $SHO_stars$ - $SHO_nebula$ * $SHO_stars$"
save SHO_final
```

`$name$` は作業ディレクトリの画像 basename です（最大10個）。結果は現在の画像に入るので
`save` が要ります。`pm` に `-out=` はありません。

## `siril-cli` の作業ディレクトリ

`siril-cli -s file.ssf` は自分の設定上の CWD から始まります。シェルの CWD ではありません。

```bash
siril-cli -d /path/to/work -s /path/to/script.ssf
```

`-s` のスクリプトパスも**この CWD から解決されます**。`-d /path/work -s script.ssf` は
`/path/work/script.ssf` を探しに行き、こう落ちます。

```
File [script.ssf] does not exist (from CWD, use absolute path?)
```

スクリプトは常に絶対パスで渡してください。

**スクリプトの中に `cd` を書かないでください。** `cd` 以降の行が捨てられます。

## 10枚未満のスタック

```
stack r_pp_light rej 3 3 -norm=addscale -out=result
```

`rej 3 3`（Winsorized sigma clip）は枚数が少ないと失敗します。目安は10枚未満で `med` に落とすこと。

## 32bit float で 0..1 に正規化される

`siril-cli` の出力 FITS は 32bit float、値域 0..1 です。ADU で診断するときは
65535 を掛けて読み替えてください。外部ツールと数値を突き合わせるときの定番の落とし穴です。
