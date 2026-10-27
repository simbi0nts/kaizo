#!/usr/bin/env python3
"""Structural check of a kaizo-built Mach-O: headers, segments, dyld bind opcodes, entry point,
and the ad-hoc code signature (every page hash is recomputed with hashlib)."""
import hashlib, struct, sys

def check(path):
    b = open(path, "rb").read()
    ok = True
    def fail(msg):
        nonlocal ok
        ok = False
        print("FAIL", path, msg)
    magic, cpu, sub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from("<IiiIIIII", b, 0)
    if magic != 0xFEEDFACF or ftype != 2: fail("not a 64-bit MH_EXECUTE")
    arch = {0x01000007: "x86_64", 0x0100000C: "arm64"}.get(cpu, "?")
    off, segs, cmds = 32, {}, {}
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", b, off)
        cmds[cmd] = (off, size)
        if cmd == 0x19:
            name = b[off+8:off+24].rstrip(b"\0").decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", b, off+24)
            segs[name] = (vmaddr, vmsize, fileoff, filesize)
            if fileoff + filesize > len(b): fail(f"segment {name} beyond end of file")
            if name != "__PAGEZERO" and (vmaddr % 16384 or fileoff % 16384): fail(f"segment {name} not 16K aligned")
        off += size
    if off - 32 != sizeofcmds: fail("sizeofcmds mismatch")
    for need in ("__PAGEZERO", "__TEXT", "__DATA", "__LINKEDIT"):
        if need not in segs: fail("missing segment " + need)
    # entry point inside __TEXT
    o, _ = cmds[0x80000028]
    entry = struct.unpack_from("<Q", b, o+8)[0]
    if not (4096 <= entry < segs["__TEXT"][3]): fail("entry outside __text")
    # bind opcodes
    o, _ = cmds[0x80000022]
    bind_off, bind_size = struct.unpack_from("<II", b, o+16)
    ops, i, syms = b[bind_off:bind_off+bind_size], 0, []
    data_vm, data_size = segs["__DATA"][0], segs["__DATA"][1]
    while i < len(ops) and ops[i] != 0:
        op = ops[i] & 0xF0
        if op == 0x40:
            j = ops.index(0, i+1); syms.append(ops[i+1:j].decode()); i = j + 1
        elif op == 0x70:
            i += 1; v = s = 0
            while True:
                v |= (ops[i] & 0x7F) << s; s += 7; i += 1
                if not ops[i-1] & 0x80: break
            if v >= data_size: fail("bind offset outside __DATA")
        else:
            i += 1
    # code signature
    o, _ = cmds[0x1D]
    sig_off, sig_size = struct.unpack_from("<II", b, o+8)
    if sig_off + sig_size != len(b): fail("signature is not at end of file")
    sm, slen, count = struct.unpack_from(">III", b, sig_off)
    if sm != 0xFADE0CC0 or count < 1: fail("bad SuperBlob")
    _, cd_rel = struct.unpack_from(">II", b, sig_off+12)
    cd = sig_off + cd_rel
    (cm, clen, ver, cflags, hash_off, ident_off, nspecial, nslots, limit) = struct.unpack_from(">IIIIIIIII", b, cd)
    hsize, htype, _, pagesz = struct.unpack_from(">BBBB", b, cd+36)
    if cm != 0xFADE0C02 or htype != 2 or hsize != 32: fail("bad CodeDirectory")
    if limit != sig_off: fail("codeLimit != signature offset")
    bad = 0
    for k in range(nslots):
        page = b[k*4096:min(limit, (k+1)*4096)]
        if hashlib.sha256(page).digest() != b[cd+hash_off+32*k:cd+hash_off+32*(k+1)]: bad += 1
    if bad: fail(f"{bad} of {nslots} page hashes wrong")
    print(("PASS" if ok else "FAIL"), f"{path}: {arch}, {len(syms)} imports, {nslots} signed pages")
    return ok

sys.exit(0 if all([check(p) for p in sys.argv[1:]]) else 1)
