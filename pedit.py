import sys

path, spec = sys.argv[1], sys.argv[2]
raw = open(path, 'rb').read()
crlf = b'\r\n' in raw
t = raw.decode('latin-1').replace('\r\n', '\n')
parts = open(spec, encoding='utf-8').read().split('\n=====\n')
assert len(parts) % 2 == 0, 'spec must hold old/new pairs separated by ===== lines'
for i in range(0, len(parts), 2):
    old, new = parts[i].strip('\n'), parts[i + 1].strip('\n')
    n = t.count(old)
    if n != 1:
        raise SystemExit('edit %d: old text found %d times' % (i // 2 + 1, n))
    t = t.replace(old, new)
if crlf:
    t = t.replace('\n', '\r\n')
open(path, 'wb').write(t.encode('latin-1'))
print('ok', path, len(parts) // 2, 'edits')
