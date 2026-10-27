import sys
PAIRS=[(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
def to_roman(n):
    out=""
    for v,s in PAIRS:
        while n>=v: out+=s; n-=v
    return out
def main(a):
    if len(a)!=1: print("usage: roman <number|numeral>"); return 2
    x=a[0]
    if x.isdigit() and x.isascii():
        n=int(x)
        if 1<=n<=3999: print(to_roman(n)); return 0
    elif x and all(c in "IVXLCDM" for c in x.upper()):
        for n in range(1,4000):
            if to_roman(n)==x.upper(): print(n); return 0
    print("error: invalid input "+x); return 1
sys.exit(main(sys.argv[1:]))
