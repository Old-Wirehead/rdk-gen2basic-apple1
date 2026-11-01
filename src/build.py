#!/usr/bin/env python3
"""Build RDK G2 Basic.

1. `hs "TEXT"`  ->  .byte with bit 7 set on the last character of TEXT.
2. Branches that turn out to be out of range are rewritten as an inverted
   branch over a JMP (iterated with the assembler until the image is clean).
Writes rdkbasic.gen.s (plain ca65 source, assembles with ca65/ld65 too) and
the binary image.

usage: build.py [--asm PATH_TO_apple1-emu] out.bin [listing]
"""
import re, subprocess, sys, os

here = os.path.dirname(os.path.abspath(__file__))
asm = os.environ.get("APPLE1_EMU", "apple1-emu")
args = sys.argv[1:]
if args and args[0] == "--asm":
    asm = args[1]; args = args[2:]
out = args[0]
lst = args[1] if len(args) > 1 else None

INV = {"beq": "bne", "bne": "beq", "bcc": "bcs", "bcs": "bcc",
       "bmi": "bpl", "bpl": "bmi", "bvc": "bvs", "bvs": "bvc"}

src = open(os.path.join(here, "rdkbasic.s")).read().split("\n")
pre = []
for line in src:
    m = re.match(r'^(\s*|[A-Za-z_][A-Za-z_0-9]*:\s*)hs\s+"(.*)"\s*(;.*)?$', line)
    if m:
        t = m.group(2)
        body, last = t[:-1], ord(t[-1]) | 0x80
        parts = ([f'"{body}"'] if body else []) + [f"${last:02X}"]
        pre.append(m.group(1) + ".byte " + ", ".join(parts))
    else:
        pre.append(line)

far = set()
redirect = {}      # pre index of a short branch -> label of a nearby "jmp target" island
islands = {}       # pre index (insert before) -> list of [label, target]
BR = r'^(\s+)(b[a-z]{2})\s+([@A-Za-z_][A-Za-z_0-9]*)(\s*;.*)?$'
GLOB = re.compile(r'^[A-Za-z_][A-Za-z_0-9]*:')
nisl = [0]
refused = {}     # pre index -> islands that were too far for it

def instr(line):
    s = re.sub(r';.*', '', line)
    s = re.sub(r'^\s*[@A-Za-z_][A-Za-z_0-9]*:', '', s).strip()
    return s

def uncond_before(p):
    j = p - 1
    while j >= 0 and not instr(pre[j]):
        if re.match(r'^\s*[@A-Za-z_][A-Za-z_0-9]*:', pre[j]):
            return False        # a label alone: code may flow into it
        j -= 1
    if j < 0:
        return False
    s = instr(pre[j])
    return s == 'rts' or s.startswith('jmp ')

def find_island(i, tgt):
    for lbl_p, lst_ in islands.items():
        pass
    cands = []
    for d in range(0, 45):
        for p in (i + d, i - d):
            if 0 < p < len(pre) and p not in [c for c in cands]:
                cands.append(p)
    for p in cands:
        lo, hi = (i + 1, p) if p > i else (p, i + 1)
        if any(GLOB.match(pre[k]) for k in range(lo, hi)):
            continue
        if p in islands:
            for lb, tg in islands[p]:
                if tg == tgt and lb not in refused.get(i, ()):
                    return lb
        if not uncond_before(p):
            continue
        nisl[0] += 1
        lb = "@isl%d" % nisl[0]
        islands.setdefault(p, []).append([lb, tgt])
        return lb
    return None

def build_lines():
    used = set(redirect.values())
    lines, mapping = [], []
    for i, line in enumerate(pre):
        for lb, tg in islands.get(i, []):
            if lb in used:
                lines.append(f"{lb}: jmp {tg}      ; branch island")
                mapping.append(i)
        m = re.match(BR, line)
        if i in far and m:
            ind, op, tgt = m.group(1), m.group(2), m.group(3)
            lines.append(f"{ind}{INV[op]} *+5      ; far branch: {op} {tgt}")
            lines.append(f"{ind}jmp {tgt}")
            mapping += [i, i]
        elif i in redirect and m:
            lines.append(f"{m.group(1)}{m.group(2)} {redirect[i]}      ; via island: {m.group(3)}")
            mapping.append(i)
        else:
            lines.append(line)
            mapping.append(i)
    return lines, mapping

gen = os.path.join(here, "rdkbasic.gen.s")
for _ in range(60):
    lines, mapping = build_lines()
    open(gen, "w").write("\n".join(lines))
    cmd = [asm, "asm", gen, "-o", out] + (["-l", lst] if lst else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    errs = (r.stdout + r.stderr).split("\n")
    bad = []
    for e in errs:
        m = re.match(r'.*?:(\d+):\d+ : branchement trop loin', e)
        if m:
            bad.append(int(m.group(1)) - 1)
    if not bad:
        print((r.stdout + r.stderr).strip())
        sys.exit(r.returncode)
    other = [e for e in errs if e and 'branchement trop loin' not in e]
    for b in bad:
        i = mapping[b]
        m = re.match(BR, pre[i])
        if i in redirect:
            refused.setdefault(i, set()).add(redirect[i]); del redirect[i]
            if len(refused[i]) > 3:
                far.add(i)
            else:
                lb = find_island(i, m.group(3))
                if lb:
                    redirect[i] = lb
                else:
                    far.add(i)
        elif m:
            lb = find_island(i, m.group(3))
            if lb:
                redirect[i] = lb
            else:
                far.add(i)
        else:
            far.add(i)
print("did not converge"); sys.exit(1)
