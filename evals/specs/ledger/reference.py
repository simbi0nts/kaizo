import sys, re
def main():
    lines=sys.stdin.read().split("\n")
    if lines and lines[-1]=="": lines.pop()
    bal={}
    for i,l in enumerate(lines,1):
        if l=="": continue
        f=l.split(",")
        ok=len(f)==3 and all(re.fullmatch(r"[A-Za-z0-9_]+",x) for x in f[:2]) and re.fullmatch(r"[0-9]+",f[2]) and int(f[2])>0 and f[0]!=f[1]
        if not ok: print("error: line %d"%i); return 1
        a=int(f[2]); bal[f[0]]=bal.get(f[0],0)-a; bal[f[1]]=bal.get(f[1],0)+a
    for k in sorted(bal): print(k, bal[k])
    return 0
sys.exit(main())
