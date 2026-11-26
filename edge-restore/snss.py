import struct, sys, collections, json

def cmds(path):
    b = open(path, 'rb').read()
    if b[:4] != b'SNSS':
        return
    p = 8
    while p + 2 <= len(b):
        size = struct.unpack_from('<H', b, p)[0]; p += 2
        if size == 0 or p + size > len(b): break
        yield b[p], b[p+1:p+size]; p += size

def pstr(d, o):
    n = struct.unpack_from('<I', d, o)[0]; o += 4
    return d[o:o+n].decode('utf-8', 'replace'), o + ((n + 3) & ~3)

def pstr16(d, o):
    n = struct.unpack_from('<I', d, o)[0]; o += 4
    return d[o:o+2*n].decode('utf-16-le', 'replace'), o + ((2*n + 3) & ~3)

def parse(path):
    tab_win, tab_index, sel = {}, {}, {}
    navs = collections.defaultdict(dict)
    closed_tabs, closed_wins = set(), set()
    for cid, d in cmds(path):
        try:
            if cid == 0:
                w, t = struct.unpack_from('<ii', d); tab_win[t] = w
            elif cid == 2:
                t, i = struct.unpack_from('<ii', d); tab_index[t] = i
            elif cid == 6:
                t, idx = struct.unpack_from('<ii', d, 4)
                url, o = pstr(d, 12)
                title, _ = pstr16(d, o)
                navs[t][idx] = (url, title)
            elif cid == 7:
                t, i = struct.unpack_from('<ii', d); sel[t] = i
            elif cid == 16:
                closed_tabs.add(struct.unpack_from('<i', d)[0])
            elif cid == 17:
                closed_wins.add(struct.unpack_from('<i', d)[0])
        except Exception:
            pass
    wins = collections.defaultdict(list)
    for t, n in navs.items():
        w = tab_win.get(t)
        if t in closed_tabs or w is None or w in closed_wins: continue
        url, title = n.get(sel.get(t, max(n))) or n[max(n)]
        wins[w].append((tab_index.get(t, 999), url, title))
    return [[{'url': u, 'title': ti} for _, u, ti in sorted(tabs)] for _, tabs in sorted(wins.items())]

if __name__ == '__main__':
    json.dump(parse(sys.argv[1]), sys.stdout, ensure_ascii=False)
