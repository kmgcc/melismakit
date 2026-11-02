#!/usr/bin/env python3
"""MelismaKit 性能阈值护栏。

输入：`MelismaKitBench --scale 120 --json` 的单行 JSON。
作用：以宽松阈值拦截大幅回退（例如把 `reflowBatchLimit` 改成 1 这类故意破坏）。

阈值依据：Documentation/PERFORMANCE.md 的参考测量（Release 构建，120 行 word）。
阈值取 5–10 倍以上的松弛余量，只拦「量级劣化」，不拦正常波动。
"""

import json
import sys

LIMITS = {
    # (名称, JSON 路径, 上限)
    "installMS": ("loadMilliseconds", "installMS", 4000.0),
    "frameP50": ("frames", "p50", 50.0),
    "frameP99": ("frames", "p99", 100.0),
    "frameMax": ("frames", "max", 600.0),
    "over8ms": ("frames", "over8ms", 900),
    "over16ms": ("frames", "over16ms", 300),
}


def main() -> int:
    if len(sys.argv) != 2:
        print("用法: bench_gate.py <bench.json>")
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)

    failed = False
    for name, (group, key, limit) in LIMITS.items():
        value = data.get(group, {}).get(key)
        if value is None:
            print(f"MISS\t{name} 未出现在 JSON 中")
            failed = True
            continue
        ok = float(value) <= float(limit)
        print(f"{'PASS' if ok else 'FAIL'}\t{name}: {value} <= {limit}")
        failed = failed or not ok

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
