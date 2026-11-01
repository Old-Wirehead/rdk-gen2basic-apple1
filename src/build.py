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
gen = os.path.join(here, "rdkbasic.gen.s")
for _ in range(12):
    lines = []
    for i, line in enumerate(pre):
        m = re.match(r'^(\s+)(b[a-z]{2})\s+([@A-Za-z_][A-Za-z_0-9]*)(\s*;.*)?$', line)
        if i in far and m:
            ind, op, tgt = m.group(1), m.group(2), m.group(3)
            lines.append(f"{ind}{INV[op]} *+5      ; far branch: {op} {tgt}")
            lines.append(f"{ind}jmp {tgt}")
        else:
            lines.append(line)
    open(gen, "w").write("\n".join(lines))
    cmd = [asm, "asm", gen, "-o", out] + (["-l", lst] if lst else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    errs = (r.stdout + r.stderr).split("\n")
    bad = []
    for e in errs:
        m = re.match(r'.*?:(\d+):\d+ : branchement trop loin', e)
        if m:
            bad.append(int(m.group(1)) - 1)
    # map generated line numbers back to pre[] indices
    if not bad:
        print((r.stdout + r.stderr).strip())
        sys.exit(r.returncode)
    # generated line -> pre index
    mapping = []
    for i, line in enumerate(pre):
        mapping.append(i)
        if i in far and re.match(r'^(\s+)(b[a-z]{2})\s+([@A-Za-z_][A-Za-z_0-9]*)(\s*;.*)?$', line):
            mapping.append(i)
    for b in bad:
        far.add(mapping[b])
    other = [e for e in errs if e and 'branchement trop loin' not in e]
    if other and not bad:
        print("\n".join(other)); sys.exit(1)
print("did not converge"); sys.exit(1)
