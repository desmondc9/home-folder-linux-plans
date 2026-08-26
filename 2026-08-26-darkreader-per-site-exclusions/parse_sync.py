import struct, json

def varint(buf, i):
    r = 0; s = 0
    while True:
        b = buf[i]; i += 1
        r |= (b & 0x7F) << s
        if not b & 0x80: return r, i
        s += 7

FIELDS = ['automation','schemeVersion','disabledFor','enabled','installation','location','time','theme',
 'displayedNews','customThemes','fetchNews','detectDarkTheme','changeBrowserTheme','enableContextMenus',
 'enableForPDF','enableForProtectedPages','enabledByDefault','enabledFor','presets','previewNewDesign',
 'previewNewestDesign','syncSettings','syncSitesFixes']

def parse_batch(rec):
    out = []
    cnt = struct.unpack("<I", rec[8:12])[0]
    j = 12
    for _ in range(cnt):
        if j >= len(rec): break
        t = rec[j]; j += 1
        if t != 1: break
        klen, j = varint(rec, j)
        vlen, j = varint(rec, j)
        k = rec[j:j+klen]; j += klen
        v = rec[j:j+vlen]; j += vlen
        out.append((k, v))
    return out

def main():
    data = open('/tmp/drhistory/dr-sync/000003.log','rb').read()
    pos = 0; frag = b""; batches = []
    while pos < len(data):
        block = data[pos:pos+32768]
        i = 0
        while i + 7 <= len(block):
            ln = struct.unpack("<H", block[i+4:i+6])[0]
            ctype = block[i+6]
            if i + 7 + ln > len(block): break
            rec = block[i+7:i+7+ln]
            if ctype == 2:
                frag = rec
            elif ctype == 3:
                frag += rec
            elif ctype == 4:
                frag += rec
                batches.append(parse_batch(frag)); frag = b""
            elif ctype == 1:
                if frag: frag += rec
                else: batches.append(parse_batch(rec))
            i += 7 + ln
        pos += 32768
    flat = [w for b in batches for w in b]

    def canon(k):
        s = k.decode('latin1')
        cands = [f for f in FIELDS if s.startswith(f[1:])]
        return max(cands, key=len) if cands else '??' + s

    final = {}
    for k, v in flat:
        final[canon(k)] = v.decode('utf-8', 'replace')

    bad = [k for k in final if k.startswith('??')]
    assert not bad, bad
    cfg = {}
    badv = []
    for k, v in final.items():
        try:
            cfg[k] = json.loads(v)
        except Exception as e:
            badv.append((k, str(e)[:50], v[:60]))
    for b in badv: print('BAD VALUE:', b)
    print('parsed fields: %d/%d' % (len(cfg), len(final)))
    assert not badv
    json.dump(cfg, open('/tmp/drhistory/final-state.json','w'), ensure_ascii=False, indent=1)
    print('automation:', cfg['automation'])
    print('enabled:', cfg['enabled'], '| disabledFor:', cfg['disabledFor'], '| syncSettings:', cfg['syncSettings'])
    print('customThemes hosts:', [t['url'] for t in cfg['customThemes']])

if __name__ == '__main__':
    main()
