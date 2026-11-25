# 00. セットアップ

Siril 1.5 と GraXpert 3.x、必要なら StarNet2 を用意します。ここでは Linux を前提にします。
Windows / macOS も概ね同じですが、パスの書き方は読み替えてください。

## 1. Siril 1.5

### Arch Linux

公式リポジトリにはありません。

```bash
# AUR: 1.5 開発版（gtk4）。ビルドには base-devel が必要（yay は自動で入れない）
sudo pacman -S --needed base-devel meson cmake ninja
yay -S siril-git

# check() だけがテストのタイムアウトで落ちる場合はテストを飛ばす
makepkg -si --nocheck

# 安定版 1.4.4 が欲しい場合（本リポジトリのスクリプトは 1.5 前提）
yay -S siril
```

`siril-git` のビルドで `streaks_test` / `unbanding_test` が 30 秒でタイムアウトして
`Fail: 0, Timeout: 2` になることがあります。コンパイル自体は成功しているので、
テストを飛ばして先に進んで構いません。

### Flatpak

```bash
flatpak install flathub org.siril.Siril
```

Flatpak 版はサンドボックス内なので、StarNet2 などの外部バイナリを呼ぶには
`~/.var/app/org.siril.Siril/` の中に置く必要があります。本リポジトリの手順は
ネイティブ実行を前提に書いています。

### 確認

```bash
siril-cli --version
# siril 1.5.0-<hash>  のように出れば OK（1.4 系なら scripts は動きません）
```

ヘッドレス実行は `siril-cli` を使います。作業ディレクトリは `-d` で渡します。

```bash
siril-cli -d /path/to/work -s script.ssf
```

## 2. GraXpert 3.x

GPL-3.0。GitHub Releases から Linux 版のアーカイブを展開するだけです（インストーラなし）。

```bash
mkdir -p ~/opt/graxpert && tar -xf GraXpert-linux-*.tar.gz -C ~/opt/graxpert
~/opt/graxpert/GraXpert-linux/GraXpert -cli -cmd --help    # ヘルプが出れば OK

# PATH に通すか、環境変数で渡す
export GRAXPERT=~/opt/graxpert/GraXpert-linux/GraXpert
```

- `-cli` を付けないと GUI が開きます。
- 初回実行で BGE の AI モデル（約数百 MB）を `~/.local/share/GraXpert/` にダウンロードします。
  回線が細いと数分待ちます。以降はオフラインでも動きます。
- CUDA 12 のランタイム（libcublas / libcudnn8）が無い環境では CPU にフォールバックします。
  無害な `libcublasLt.so.12` の警告が出ますが、`-gpu false` を付ければ黙ります。

## 3. StarNet2（任意・非 OSS）

星を抜いて別レイヤーにする場合だけ必要です。v2 はソース非公開の無料バイナリなので、
「OSS だけで完結」を条件にするなら使えません。使う場合は構成をそう明記してください。

```bash
# 配布元は download.starnetastro.com（旧 www.starnetastro.com の URL は死んでいます）
# .deb を展開すると /usr/bin/starnet2 と /usr/lib/starnet2/ に入ります
sudo dpkg -i StarNet2_linux_*.deb     # Debian/Ubuntu 系
starnet2 --version
```

- CLI の zip 版は `starnet2` とライブラリが同じディレクトリにあります。**バイナリだけ移動しないでください。**
- 2.6 系は ONNX Runtime ベースです（libtensorflow は不要）。
- CUDA が無くても CPU で動きます（12MP で数分）。

## 4. Python（QC 用）

`scripts/flatless/qc_flatless.py` は numpy だけで FITS を読みます。

```bash
python3 -c "import numpy; print(numpy.__version__)"
```

無ければ `pip install numpy`（または `pacman -S python-numpy`）。

## 5. データの置き方

スクリプトは「作業ディレクトリにライトが連番で並んでいる」ことを前提にします。

```
work/
├── light_0001.fits
├── light_0002.fits
└── ...
```

Ekos などが付ける名前（`NGC_6992_Light_001.fits`）のままでは `calibrate light` が通りません。
理由は [01-siril-15-gotchas.md](01-siril-15-gotchas.md#シーケンス名はファイル名の-basename) を参照。
`scripts/dualband_sho/link_lights.sh` でリンクすれば実体をコピーせずに揃えられます
（ext4 / xfs / btrfs のみ。exFAT / NTFS では名前の変更で対応してください）。
