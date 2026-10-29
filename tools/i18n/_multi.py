import os,sys
BS=chr(92)
files=[l.strip() for l in open('tools/i18n/player_files.txt') if l.strip() and not l.startswith('#')]
def scan(text):
    res=[];inside=False
    for n,line in enumerate(text.split(chr(10)),1):
        start=inside; i=0
        if not inside and line.lstrip().startswith('#'):
            res.append((n,False,False)); continue
        while i<len(line):
            c=line[i]
            if inside:
                if c==BS: i+=2; continue
                if c=='"': inside=False
            else:
                if c=='#': break
                if c=='"': inside=True
            i+=1
        res.append((n,start,inside))
    return res
if __name__=='__main__':
    root=sys.argv[1] if len(sys.argv)>1 else '.'
    tot=0
    for f in files:
        p=os.path.join(root,'scripts/%s.gd'%f)
        if not os.path.exists(p): p=os.path.join(root,'autoload/%s.gd'%f)
        t=open(p,encoding='utf-8',newline='').read().replace(chr(13)+chr(10),chr(10))
        bad=[n for n,s,e in scan(t) if s or e]
        if bad: print(f,len(bad),bad[:8]); tot+=len(bad)
    print('multi-line string lines:',tot)
