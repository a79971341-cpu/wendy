#!/usr/bin/env python3
"""Subset Galmuri11 to the characters index.html uses and embed it as base64 woff2.

Usage: python3 tools/embed_font.py <galmuri dist dir>
  e.g. npm pack galmuri && tar xzf galmuri-*.tgz && python3 tools/embed_font.py package/dist
Requires: pip install fonttools brotli
Run again whenever UI text changes.
"""
import base64, io, os, re, sys
from fontTools import subset
from fontTools.ttLib import TTFont

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
page = os.path.join(root, 'index.html')
src_dir = sys.argv[1]

html = open(page, encoding='utf-8').read()
# drop the embedded font data before collecting characters
body = re.sub(r'base64,[A-Za-z0-9+/=]*', 'base64,', html)
chars = set(body) | set(chr(c) for c in range(0x20, 0x7f)) | set('↑←→↓')
text = ''.join(sorted(ch for ch in chars if ch >= ' '))

def subset_b64(name):
    font = TTFont(os.path.join(src_dir, name))
    opts = subset.Options()
    opts.flavor = 'woff2'
    opts.layout_features = ['*']
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    buf = io.BytesIO()
    font.flavor = 'woff2'
    font.save(buf)
    return base64.b64encode(buf.getvalue()).decode('ascii')

for marker, name in (('G11', 'Galmuri11.ttf'), ('G11B', 'Galmuri11-Bold.ttf')):
    data = subset_b64(name)
    pat = re.compile(r'/\*%s\*/url\("data:font/woff2;base64,[A-Za-z0-9+/=]*"\)' % marker)
    if not pat.search(html):
        sys.exit('marker %s not found' % marker)
    html = pat.sub(lambda m: '/*%s*/url("data:font/woff2;base64,%s")' % (marker, data), html)
    print(marker, name, len(data) * 3 // 4, 'bytes')

open(page, 'w', encoding='utf-8').write(html)
print(len(text), 'characters')
