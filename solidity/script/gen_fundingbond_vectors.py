#!/usr/bin/env python3
"""
gen_fundingbond_vectors.py - FundingBond vectors from the funding bond reference.

Reads PERP/reference/fundingbond/vectors.json (the standard, computed by model.py at 60 digits)
and emits test/FundingBondVectors.gen.sol: every vector whose Solidity counterpart is in
FundingBond.sol, with the floor and ceiling of its exact value at WAD and the direction it names;
the basis_settle vectors entry by entry; the vectors on which FundingBond must revert, with the
error. It also imports model.py for what vectors.json does not carry: the exact total paid in
each basis_settle vector, and the gap-claim grid of brief 2026-09-25b stage 3e (Strikes 0.02 to
50, floors and caps a tenth to nine tenths away, sigma 0.8, h one hour).

Run:  python3 script/gen_fundingbond_vectors.py [path/to/vectors.json]
Out:  test/FundingBondVectors.gen.sol  (committed; regenerate when vectors.json changes)

Standard library only. British English.
"""
import json
import os
import sys
from decimal import ROUND_CEILING, ROUND_FLOOR, Decimal, localcontext

HERE = os.path.dirname(os.path.abspath(__file__))
FB = os.path.join(HERE, "..", "..", "..", "PERP", "reference", "fundingbond")
DEFAULT = os.path.join(FB, "vectors.json")
OUT = os.path.join(HERE, "..", "test", "FundingBondVectors.gen.sol")

sys.path.insert(0, FB)
import model  # noqa: E402

FNS = ["knock_in_log", "knock_in_long", "knock_in_short", "gap_claim_long", "gap_claim_short",
       "premium", "cap", "floor", "ito_transfer", "basis_log", "basis_log_ticks", "to_ratio"]

# Raising vectors: the error FundingBond reverts with, or None where uint256 cannot carry the
# input (a negative floor), which is then listed and not tested.
REVERT = {"knock_in_long": "KnockedIn()", "knock_in_short": "KnockedIn()",
          "gap_claim_short": "ZeroCap()", "gap_claim_long": None}

GRID_K = ("0.02", "0.05", "0.1", "0.2", "0.5", "0.9", "1", "1.1", "2", "5", "10", "20", "50")
GRID_F = ("0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9")
SIG = "0.8"
H = "0.000114155251141553"  # 3600 s of a 365-day year, 18 places (gen_vectors.years)


def wad(x):
    v = Decimal(x).scaleb(18)
    assert v == v.to_integral_value(), x
    return int(v)


def quant(v):
    with localcontext() as c:
        c.prec = 200
        s = Decimal(v).scaleb(18)
        return int(s.to_integral_value(ROUND_FLOOR)), int(s.to_integral_value(ROUND_CEILING))


def book_args(book, U):
    """[U, K1, q1, K2, q2, ...], Strikes ascending, sizes aggregated per Strike."""
    agg = {}
    for q, K in book:
        agg[wad(K)] = agg.get(wad(K), 0) + wad(q)
    out = [wad(U)]
    for K in sorted(agg):
        out += [K, agg[K]]
    return out


def ticks_args(perp, index):
    """(mean tick perp - mean tick index) as dTickTime / dt, both integers."""
    diff = Decimal(perp) - Decimal(index)
    dt = 1
    while diff * dt != (diff * dt).to_integral_value():
        dt *= 10
    return [int(diff * dt), dt]


def args_of(v):
    fn, a = v["fn"], v["args"]
    if fn in ("cap", "floor"):
        return book_args(a[0], a[1])
    if fn == "basis_log_ticks":
        return ticks_args(*a)
    return [wad(x) for x in a]


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    with open(src) as fh:
        doc = json.load(fh)
    vecs, settles, reverts, skipped = [], [], [], []
    for v in doc["vectors"]:
        if not v["counterpart"]["solidity"].startswith("solidity/src/FundingBond.sol"):
            continue
        vid, fn = v["id"], v["fn"]
        if "raises" in v:
            err = REVERT[fn]
            if err is None or any(Decimal(x) < 0 for x in v["args"] if not isinstance(x, list)):
                skipped.append(vid)
                continue
            reverts.append((vid, FNS.index(fn), args_of(v), err))
            continue
        if fn == "basis_settle":
            book, Ap, Ai, form = v["args"]
            out = model.basis_settle([tuple(e) for e in book], Ap, Ai, form)
            with localcontext() as c:
                c.prec = 200
                total = sum(-x for x in out if x < 0)
            rows = []
            for i, (side, q) in enumerate(book):
                key = ("pays_%d" if out[i] < 0 else "receives_%d") % i
                o = v["outputs"][key]["wad"]
                rows.append((side == "long", out[i] < 0, wad(q), int(o["floor"]), int(o["ceil"])))
            assert len(rows) == 4, vid
            settles.append((vid, wad(Ap), wad(Ai), form == "ratio", rows, quant(total)[0]))
            continue
        key = "paid" if fn == "ito_transfer" else "value"
        o = v["outputs"][key]
        vecs.append((vid, FNS.index(fn), args_of(v), int(o["wad"]["floor"]), int(o["wad"]["ceil"]),
                     o["exact"]))

    grid = []
    for K in GRID_K:
        for f in GRID_F:
            with localcontext() as c:
                c.prec = 60
                fl = (Decimal(K) * (1 - Decimal(f))).quantize(Decimal("1e-18"))
                cp = (Decimal(K) * (1 + Decimal(f))).quantize(Decimal("1e-18"))
            grid.append((wad(K), wad(fl), True, quant(model.gap_claim_long(K, fl, SIG, H))[1]))
            grid.append((wad(K), wad(cp), False, quant(model.gap_claim_short(K, cp, SIG, H))[1]))

    L = ["// SPDX-License-Identifier: UNLICENSED",
         "pragma solidity ^0.8.31;",
         "",
         "// AUTO-GENERATED by script/gen_fundingbond_vectors.py - do not edit by hand.",
         "// Source: PERP/reference/fundingbond/vectors.json and model.py (60 digits).",
         "// All values WAD (1e18); lo and hi are the floor and ceiling of the exact value.",
         "// fn: " + ", ".join("%d %s" % (i, f) for i, f in enumerate(FNS)) + ".",
         "// a: the arguments in FundingBond's order; cap and floor [U, K1, q1, K2, q2, ...],",
         "// Strikes ascending; basis_log_ticks [dTickTime, dt]; ito_transfer lo/hi for paid",
         "// and received alike.",
         "// Not representable in uint256, so not tested: " + (", ".join(skipped) or "none") + ".",
         "",
         "struct FBVector {",
         "    string id;",
         "    uint8 fn;",
         "    uint8 n;",
         "    int256[8] a;",
         "    int256 lo;",
         "    int256 hi;",
         "}",
         "",
         "struct SettleVector {",
         "    string id;",
         "    uint256 Ap;",
         "    uint256 Ai;",
         "    bool ratio;",
         "    bool[4] isLong;",
         "    bool[4] pays;",
         "    uint256[4] q;",
         "    uint256[4] lo;",
         "    uint256[4] hi;",
         "    uint256 totalFloor;",
         "}",
         "",
         "struct FBRevertVector {",
         "    string id;",
         "    uint8 fn;",
         "    uint8 n;",
         "    int256[8] a;",
         "    string err;",
         "}",
         "",
         "struct GridVector {",
         "    uint256 K;",
         "    uint256 X;",
         "    bool isLong;",
         "    uint256 ceil;",
         "}",
         "",
         "library FundingBondVectors {",
         "",
         "    uint256 internal constant SIGMA = %d;" % wad(SIG),
         "    uint256 internal constant H = %d;" % wad(H),
         ""]

    def a8(a):
        assert len(a) <= 8
        return "[%s]" % ", ".join(("int256(%d)" % x) if j == 0 else str(x)
                                  for j, x in enumerate(a + [0] * (8 - len(a))))

    L.append("    function vectors() internal pure returns (FBVector[] memory v) {")
    L.append("        v = new FBVector[](%d);" % len(vecs))
    for i, (vid, fn, a, lo, hi, ex) in enumerate(vecs):
        L.append("        // %s" % ex)
        L.append('        v[%d] = FBVector("%s", %d, %d, %s, %d, %d);'
                 % (i, vid, fn, len(a), a8(a), lo, hi))
    L.append("    }")
    L.append("")
    L.append("    function settles() internal pure returns (SettleVector[] memory v) {")
    L.append("        v = new SettleVector[](%d);" % len(settles))
    for i, (vid, Ap, Ai, ratio, rows, tf) in enumerate(settles):
        col = lambda j, t: "[%s]" % ", ".join(
            (("%s(%s)" % (t, str(r[j]).lower())) if k == 0 else str(r[j]).lower())
            for k, r in enumerate(rows))
        L.append('        v[%d] = SettleVector("%s", %d, %d, %s, %s, %s, %s, %s, %s, %d);'
                 % (i, vid, Ap, Ai, str(ratio).lower(), col(0, "bool"), col(1, "bool"),
                    col(2, "uint256"), col(3, "uint256"), col(4, "uint256"), tf))
    L.append("    }")
    L.append("")
    L.append("    function reverts() internal pure returns (FBRevertVector[] memory v) {")
    L.append("        v = new FBRevertVector[](%d);" % len(reverts))
    for i, (vid, fn, a, err) in enumerate(reverts):
        L.append('        v[%d] = FBRevertVector("%s", %d, %d, %s, "%s");'
                 % (i, vid, fn, len(a), a8(a), err))
    L.append("    }")
    L.append("")
    L.append("    /// @dev Stage 3e: gap claims at sigma 0.8, h one hour; ceil of the model's value.")
    L.append("    function grid() internal pure returns (GridVector[] memory v) {")
    L.append("        v = new GridVector[](%d);" % len(grid))
    for i, (K, X, lng, ce) in enumerate(grid):
        L.append("        v[%d] = GridVector(%d, %d, %s, %d);" % (i, K, X, str(lng).lower(), ce))
    L.append("    }")
    L.append("}")
    L.append("")
    with open(OUT, "w") as fh:
        fh.write("\n".join(L))
    n = len(vecs) + sum(1 for _ in settles) + len(reverts)
    print("%d vectors (%d value, %d basis_settle, %d revert; %d not representable), %d grid -> %s"
          % (n + len(skipped), len(vecs), len(settles), len(reverts), len(skipped), len(grid),
             os.path.relpath(OUT)))


if __name__ == "__main__":
    main()
