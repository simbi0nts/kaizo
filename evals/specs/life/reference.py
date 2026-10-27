import sys
def main(a):
    if len(a)!=1 or not a[0].isdigit(): print("usage: life <generations>"); return 2
    gens=int(a[0])
    lines=sys.stdin.read().split("\n")
    while lines and lines[-1]=="": lines.pop()
    if lines and (any(len(l)!=len(lines[0]) for l in lines) or any(c not in ".#" for l in lines for c in l)):
        print("error: bad grid"); return 1
    g=[[c=="#" for c in l] for l in lines]; h=len(g); w=len(g[0]) if h else 0
    for _ in range(gens):
        n=[[False]*w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                k=sum(g[yy][xx] for yy in range(max(0,y-1),min(h,y+2)) for xx in range(max(0,x-1),min(w,x+2)) if (yy,xx)!=(y,x))
                n[y][x]= k==3 or (g[y][x] and k==2)
        g=n
    for r in g: print("".join("#" if c else "." for c in r))
    print("alive: %d"%sum(map(sum,g))); return 0
sys.exit(main(sys.argv[1:]))
