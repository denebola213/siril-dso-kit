#!/usr/bin/env python3
"""qc_flatless.py -- フラットレス可否を実測で判定する（FITS 直読み / numpy のみ）

使い方:
  python3 qc_flatless.py --dims  light_00001.fit      # -> "幅 高さ"
  python3 qc_flatless.py light_00001.fit --pedestal 32768
  python3 qc_flatless.py light_00001.fit --bias master_bias.fit
  python3 qc_flatless.py light_00001.fit --box 256

ペデスタル（バイアス/オフセット）について:
  減光の比を正しく出すには、空の信号からオフセットを引く必要がある。
  引かないと比は 1 に寄り、減光を**過小評価**する（危険側）。
  指定が無ければヘッダの PEDESTAL / OFFSET / BLACKLEV を探し、
  それも無ければ 0 として「過小評価である」と警告する。

判定の目安:
  四隅比 > 0.95        -> フラットレスで実用可
  0.85 - 0.95          -> クロップ or 乗算モデル(subsky -mode=divide)が必要
  < 0.85               -> 周辺を捨てるか、フラットを撮る
  隅の非対称性 > 1.10  -> ダスト/傾き/非対称ムラ。モデルでは消えない可能性大
"""
import sys
import os
import argparse

import numpy as np

_DT = {8: "u1", 16: ">i2", 32: ">i4", -32: ">f4", -64: ">f8"}
_PED_KEYS = ("PEDESTAL", "OFFSET", "BLACKLEV", "BIAS")


def read_header_and_shape(path):
    """FITS ヘッダを素朴に読み、カード辞書とヘッダ長(バイト)を返す。"""
    nblk = 0
    buf = b""
    with open(path, "rb") as f:
        while True:
            blk = f.read(2880)
            if len(blk) < 2880:
                raise ValueError("ヘッダが途中で終わっています: %s" % path)
            buf += blk
            nblk += 1
            if b"END" in blk:
                break
            if nblk > 200:
                raise ValueError("ヘッダに END が見つかりません: %s" % path)

    cards = {}
    for i in range(0, len(buf), 80):
        card = buf[i:i + 80].decode("ascii", "ignore")
        if card.startswith("END"):
            break
        key = card[:8].strip()
        if card[8:10] != "= ":
            continue
        val = card[10:].split("/")[0].strip()
        cards[key] = val.strip("'").strip()
    return cards, nblk * 2880


def read_fits(path):
    """2D/3D の FITS を float32 で読む。BAYER 生は 2D のまま返る。"""
    cards, off = read_header_and_shape(path)
    bitpix = int(cards["BITPIX"])
    if bitpix not in _DT:
        raise ValueError("未対応の BITPIX %s" % bitpix)
    n1 = int(cards["NAXIS1"])
    n2 = int(cards["NAXIS2"])
    n3 = int(cards.get("NAXIS3", 1)) if int(cards.get("NAXIS", 2)) >= 3 else 1
    bzero = float(cards.get("BZERO", 0.0))
    bscale = float(cards.get("BSCALE", 1.0))

    d = np.fromfile(path, dtype=_DT[bitpix], count=n1 * n2 * n3, offset=off)
    if d.size != n1 * n2 * n3:
        raise ValueError("データ部が不足しています（壊れた FITS?）: %s" % path)
    d = d.astype(np.float32) * bscale + bzero
    if n3 > 1:
        d = d.reshape(n3, n2, n1)
    else:
        d = d.reshape(n2, n1)
    return d, cards


def luminance(d):
    """3D ならプレーン平均で 2D に落とす。"""
    if d.ndim == 2:
        return d
    return d.mean(axis=0)


def box_median(a, y, x, s):
    h, w = a.shape
    half = s // 2
    y0, y1 = max(0, y - half), min(h, y + half)
    x0, x1 = max(0, x - half), min(w, x + half)
    if y1 <= y0 or x1 <= x0:
        raise ValueError("測定窓が画像外です")
    return float(np.median(a[y0:y1, x0:x1]))


def guess_pedestal(cards):
    for k in _PED_KEYS:
        if k in cards:
            try:
                return float(cards[k]), "header:%s" % k
            except ValueError:
                continue
    return None, None


def main():
    ap = argparse.ArgumentParser(description="フラットレス可否の実測判定")
    ap.add_argument("fits", nargs="?", help="判定する FITS（ライト1枚）")
    ap.add_argument("--dims", action="store_true", help="幅と高さだけ出力")
    ap.add_argument("--box", type=int, default=128, help="測定窓の一辺[px] (既定128)")
    ap.add_argument("--pedestal", type=float, default=None,
                    help="バイアス/オフセット値[ADU]。減光比の基準")
    ap.add_argument("--bias", help="マスターバイアス FITS（中央値をペデスタルに使う）")
    ap.add_argument("--json", action="store_true", help="JSON で出力")
    args = ap.parse_args()

    if not args.fits:
        ap.error("FITS を指定してください")

    d, cards = read_fits(args.fits)
    if args.dims:
        print(int(cards["NAXIS1"]), int(cards["NAXIS2"]))
        return 0

    a = luminance(d)
    h, w = a.shape
    s = args.box

    # --- ペデスタルの決定 ---------------------------------------------------
    ped, ped_src = args.pedestal, "--pedestal"
    if ped is None and args.bias:
        b, _ = read_fits(args.bias)
        ped, ped_src = float(np.median(luminance(b))), "--bias"
    if ped is None:
        ped, ped_src = guess_pedestal(cards)
    warned = False
    if ped is None:
        ped, ped_src, warned = 0.0, "未指定", True
    a = a - ped

    c = box_median(a, h // 2, w // 2, s)
    if c <= 0:
        print("中央の信号が 0 以下です。--pedestal を確認してください。", file=sys.stderr)
        return 1

    pos = {
        "TL": (h // 8, w // 8),
        "TR": (h // 8, 7 * w // 8),
        "BL": (7 * h // 8, w // 8),
        "BR": (7 * h // 8, 7 * w // 8),
        "T":  (h // 8, w // 2),
        "B":  (7 * h // 8, w // 2),
        "L":  (h // 2, w // 8),
        "R":  (h // 2, 7 * w // 8),
    }
    r = {k: box_median(a, y, x, s) / c for k, (y, x) in pos.items()}

    corners = [r["TL"], r["TR"], r["BL"], r["BR"]]
    worst = min(corners)
    best = max(corners)
    asym = (best / worst) if worst > 0 else float("inf")

    if args.json:
        import json
        print(json.dumps({
            "file": args.fits, "width": w, "height": h,
            "pedestal": ped, "pedestal_source": ped_src,
            "ratios": {k: round(v, 4) for k, v in r.items()},
            "worst_corner": round(worst, 4),
            "asymmetry": None if worst <= 0 else round(asym, 3),
        }, ensure_ascii=False, indent=2))
        return 0

    print("=" * 64)
    print("フラットレス判定 :", os.path.basename(args.fits))
    print("  画像サイズ      : %d x %d  (測定窓 %d px)" % (w, h, s))
    print("  ペデスタル      : %.1f ADU (%s)" % (ped, ped_src))
    print("  中央の信号      : %.1f ADU" % c)
    print("-" * 64)
    print("  中央比 (=1.000 基準)")
    print("    TL %.3f   T %.3f   TR %.3f" % (r["TL"], r["T"], r["TR"]))
    print("    L  %.3f   C 1.000   R  %.3f" % (r["L"], r["R"]))
    print("    BL %.3f   B %.3f   BR %.3f" % (r["BL"], r["B"], r["BR"]))
    print("-" * 64)
    print("  最も暗い隅      : %.3f" % worst)
    if worst > 0:
        print("  隅の非対称性    : %.3f  (max/min)" % asym)
    else:
        print("  隅の非対称性    : 測定不能（負値）")

    print("-" * 64)
    if worst > 0.95:
        print("  判定: 【可】四隅の減光 5% 未満。クロップ＋軽い背景除去で十分。")
    elif worst > 0.85:
        print("  判定: 【条件付き可】減光が 5-15%。クロップを増やすか")
        print("        subsky -auto -mode=divide で乗算モデルを当てる。")
    else:
        print("  判定: 【不可寄り】減光 15% 超。外周を捨てるか、フラットを撮る。")

    if worst > 0 and asym > 1.10:
        print("  警告: 隅の明るさが 10% 以上ばらついています（非対称ムラ）。")
        print("        ダスト・センサー傾き・照明ムラの可能性。乗算モデルでは消えません。")
        print("        → 外周を捨てるか、フラットを撮ってください。")
    elif worst > 0:
        print("  非対称ムラ: 目立たず（中心対称の減光と判断できる）")

    if warned:
        print("-" * 64)
        print("  注意: ペデスタル未指定のため減光を過小評価しています（比が 1 に寄る）。")
        print("        正確に測るには --pedestal <オフセット[ADU]> か --bias <master_bias> を指定。")
        print("        この値は「これより悪いことはない」という下限として読んでください。")

    print("  目視確認    : autostretch して背景に円形の暗いシミ（ダストモート）が")
    print("                無いか必ず確認してください。数値では検出できません。")
    print("=" * 64)
    return 0


if __name__ == "__main__":
    sys.exit(main())
