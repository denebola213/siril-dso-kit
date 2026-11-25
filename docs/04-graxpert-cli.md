# 04. GraXpert 3.x の CLI

GraXpert は GUI が主役ですが、CLI も揃っています。ここは実際に叩いて確認した仕様だけを書きます。

## 基本形

```bash
GraXpert-linux IMAGE.fits -cli -cmd <command> [options]
```

- `-cli` を付けないと GUI が開きます。
- **入力画像は位置引数**です。`-input` というフラグはありません。
- `-cmd` は `background-extraction` / `denoising` / `deconv-obj` / `deconv-stellar`。

## `-output` のルール（最重要）

```
-output <bare-name>
```

- ディレクトリを渡してはいけません
- 拡張子も付けてはいけません

GraXpert は `os.path.join(dirname(input), output + ".fits")` で書きます。`out/xxx` のように
ディレクトリを渡すと二重結合されて `FileNotFoundError: out/out/xxx.fits` になります。
**出力は必ず入力と同じディレクトリに出ます。** 絶対パスは許されます。

## 背景除去（BGE）

```bash
GraXpert-linux stack.fits -cli -cmd background-extraction \
  -output bge -correction Division -smoothing 0.25 -gpu false
```

| オプション | 値 | 意味 |
|---|---|---|
| `-correction` | `Subtraction` / `Division` | 勾配なら Subtraction、減光なら Division |
| `-smoothing` | 0.0–1.0 | **最大の調整点**。低いとモデルが構造を追ってムラが残り、高いと淡い星雲を食う |
| `-bg` | フラグ | `<output>_background.fits` を出力（モデルの確認用） |

迷ったら 0.2–0.35。淡い外殻を主張する画像では 0.3 以下。`-bg` で出したモデルを
`autostretch` して、対象の形が写っていないか必ず見てください。

線形データに対してかけます。ストレッチ後では意味がありません。

## デノイズ

```bash
GraXpert-linux bge.fits -cli -cmd denoising -output dn -strength 0.5 -gpu false
```

| オプション | 値 | 意味 |
|---|---|---|
| `-strength` | 0.0–1.0 | 既定 0.5。0.5 を1パスが安全 |
| `-batch_size` | 1–32 | GPU メモリが足りないとき下げる |

線形でもストレッチ後でも動きます。線形1パスが基本。CPU だと 12MP で約17分かかります。

## デコンボリューション（3.1 以上）

3.0.x には BGE とデノイズしかありません。3.1.0-RC2 以降で2モードが入りました。

```bash
GraXpert-linux linear.fits -cli -cmd deconv-obj    -strength 0.25 -psfsize 3.2 -output deconv
GraXpert-linux linear.fits -cli -cmd deconv-stellar -strength 0.25 -psfsize 3.2 -output deconv
```

| モード | 対象 |
|---|---|
| `deconv-obj` | 星雲・銀河（広がった構造） |
| `deconv-stellar` | 星 |

- 引数は `Strength 0.0–1.0` と `Image FWHM` の2つだけ。まず Strength 0.2–0.3 から。
- **`psfsize` はピクセル単位**で、秒角ではありません。Siril の Dynamic PSF で測った FWHM(px)
  を入れてください。0 で最小効果。
- デコンボリューションはノイズを増幅します。**必ずデノイズより前に**かけて、
  デノイズに回収させてください。
- 星が緑・紫に転ぶ場合は Strength を下げるか、SPCC との順序を入れ替えて比較します。

## Siril から呼ぶ場合

GraXpert は Siril の `pyscript GraXpert-AI.py` からも呼べます。

```
pyscript GraXpert-AI.py -deconv_obj -strength 0.3 -psfsize 3.2
```

パスや出力名の解決はスクリプト側がやるので、CLI の `-output` の罠は踏みません。
ただしバッチ処理を自分で組みたい場合は CLI の方が見通しが良いです。

## GPU

Linux で CUDA を使うには CUDA 12 のランタイム（libcublas / libcudnn8）が必要です。
無いと CUDA の実行プロバイダが失敗し、`libcublasLt.so.12` の警告を出して CPU に落ちます。
警告が煩わしければ `-gpu false` を付けてください（動作は同じ）。

## ライセンス

GraXpert は GPL-3.0（`Steffenhir/GraXpert`）。商用のデコンボリューションツール
（BlurXTerminator など）は有料の独自製品なので、OSS の流れに混ぜないでください。
OSS でデコンボリューションを代替するなら GraXpert 3.1 以降の上記2モードです。
