#!/usr/bin/env python3
"""flat_panel_qc.py — フラット光源（パネル／拡散板）のムラを回転差分で実測する。

使い方:
    python3 flat_panel_qc.py A.fit B.fit [--pedestal N] [--grid 8] [--smooth 64]

A.fit と B.fit は「同じ光学系・同じフォーカス・同じフィルタ」で、
光源（パネル）だけを 180 度回転（または大きく平行移動）させて撮ったスタック済みフラット。
光学系の減光（周辺減光・ダスト）は両者で同一、光源ムラだけが回るので、
比の平滑成分が 1 からどれだけズレるか＝光源ムラの実効量になる。

出力:
    ratio の平滑成分の標準偏差・最大偏差（％）と、グリッドごとの比（％）。
    目安: |max| < 0.5% 良好 / 0.5-1% 実用 / >2% 拡散不足（紙を足す・距離を詰める）

FITS は BITPIX 8/16/32/-32/-64, NAXIS=2 の主 HDU のみ対応（astropy 不要）。
"""
import argparse
import sys

import numpy as np


def read_fits(path):
    with open(path, "rb") as f:
        cards = []
        while True:
            block = f.read(2880)
            if len(block) < 2880:
                raise ValueError(f"{path}: header truncated")
            for i in range(0, 2880, 80):
                card = block[i:i + 80].decode("ascii", "replace")
                cards.append(card)
                if card.startswith("END"):
                    break
            else:
                continue
            break
        hdr = {}
        for c in cards:
            key = c[:8].strip()
            if key in ("", "COMMENT", "HISTORY", "END"):
                continue
            val = c[10:].split("/")[0].strip()
            hdr[key] = val
        bitpix = int(hdr["BITPIX"])
        naxis = int(hdr.get("NAXIS", 0))
        if naxis != 2:
            raise ValueError(f"{path}: NAXIS={naxis} は未対応（2次元のみ）")
        w = int(hdr["NAXIS1"])
        h = int(hdr["NAXIS2"])
        dtype = {8: ">u1", 16: ">i2", 32: ">i4", -32: ">f4", -64: ">f8"}[bitpix]
        raw = np.frombuffer(f.read(w * h * abs(bitpix) // 8), dtype=dtype)
        bzero = int(hdr.get("BZERO", 0))
        data = raw.reshape(h, w).astype(np.float64) + bzero
    return data, hdr


def box_smooth(a, size):
    """cumsum による boxcar 平滑（端は縮小窓で平均）。size は奇数推奨。"""
    size = max(3, int(size) | 1)
    pad = size // 2
    p = np.pad(a, pad, mode="reflect")
    cs = np.cumsum(np.cumsum(p, axis=0), axis=1)
    cs = np.pad(cs, ((1, 0), (1, 0)), mode="constant")
    s = (cs[size:, size:] - cs[:-size, size:] - cs[size:, :-size] + cs[:-size, :-size])
    return s / (size * size)


def normalize(img, pedestal):
    d = img - pedestal
    med = np.median(d)
    if med <= 0:
        raise ValueError("中央値が 0 以下。--pedestal を見直してください")
    return d / med


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--pedestal", type=float, default=0.0,
                    help="バイアス/オフセット（ADU）。バイアス減算済みなら 0（既定）。"
                         "未減算ならカメラの offset 値か master bias の中央値を渡す")
    ap.add_argument("--smooth", type=int, default=64, help="比を平滑する窓 [px]")
    ap.add_argument("--grid", type=int, default=8, help="表示グリッド数")
    args = ap.parse_args()

    a, ha = read_fits(args.a)
    b, hb = read_fits(args.b)
    if a.shape != b.shape:
        sys.exit(f"サイズ不一致: {a.shape} vs {b.shape}")

    pa = pb = args.pedestal
    na = normalize(a, pa)
    nb = normalize(b, pb)

    with np.errstate(divide="ignore", invalid="ignore"):
        ratio = na / nb
    bad = ~np.isfinite(ratio) | (ratio <= 0)
    if bad.mean() > 0.2:
        sys.exit(f"比の {bad.mean()*100:.1f}% が無効です。--pedestal を見直してください")
    ratio = np.where(bad, 1.0, ratio)
    sm = box_smooth(ratio, args.smooth)
    # 平滑成分を 1 中心の相対偏差（％）に
    dev = (sm - 1.0) * 100.0

    print(f"A: {args.a}  median={np.median(a):.1f}  pedestal={pa:.1f}")
    print(f"B: {args.b}  median={np.median(b):.1f}  pedestal={pb:.1f}")
    print(f"平滑窓: {args.smooth}px   サイズ: {a.shape[1]}x{a.shape[0]}")
    print(f"比の平滑成分: mean={dev.mean():+.3f}%  std={dev.std():.3f}%  "
          f"max={dev.max():+.3f}%  min={dev.min():+.3f}%")

    verdict = ("良好（±0.5%以内）" if max(abs(dev.max()), abs(dev.min())) < 0.5 else
               "実用（±1%以内）" if max(abs(dev.max()), abs(dev.min())) < 1.0 else
               "拡散不足の疑い: 紙を1枚追加するかパネルを近づける")
    print(f"判定: {verdict}")

    g = args.grid
    h, w = dev.shape
    print(f"\nグリッド {g}x{g}（比 - 1、％）:")
    rows = []
    for j in range(g):
        y0, y1 = h * j // g, h * (j + 1) // g
        row = []
        for k in range(g):
            x0, x1 = w * k // g, w * (k + 1) // g
            row.append(dev[y0:y1, x0:x1].mean())
        rows.append(row)
        print("  " + "  ".join(f"{v:+6.2f}" for v in row))
    print("\n四隅/中央の目安: 四隅の差が中央と 1% 以上ずれる場合は周辺の拡散が足りない")


if __name__ == "__main__":
    main()
