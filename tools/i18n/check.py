"""Run this after changing player-facing text:  python tools/i18n/check.py
1. lists sentences in the player-facing scripts that are formatted (" ... %s ..." % x) or glued (" ... " + x) WITHOUT tr() - Godot only
   translates a text it sees whole, so these never get translated;
2. runs extract.py and lists the texts that have no translation yet in each language (tools/i18n/<lang>_*.txt)."""
import os, re, subprocess, sys
BS = chr(92); NL = chr(10); Q = chr(34)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools/i18n'))
from extract import literals, FILES            # noqa: E402
LANGS = ['es', 'nl']
FMT = re.compile('%[-+0-9.]*[sdif]|%%')


def sentence(body):
    if body.startswith(('[', '#', 'res://', 'user://', 'http')): return False
    if not re.search('[A-Za-z]{3,}', body): return False
    if ' ' not in body and ':' not in body: return False
    if body.startswith('set ') or BS + BS in body or '>nul' in body or '$' in body or '{' in body: return False
    if body.startswith('/') or re.search('[A-Za-z%]/[A-Za-z%]', body): return False
    if re.fullmatch('[a-z0-9_]+:', body) or re.fullmatch('[A-Z0-9_]{4,}:', body): return False
    return True


def unwrapped():
    found = []
    ignored = set(l.rstrip(NL) for l in open(os.path.join(ROOT, 'tools/i18n/ignore.txt'), encoding='utf-8').read().split(NL) if l and not l.startswith('#'))
    for f, _only in FILES.items():
        p = os.path.join(ROOT, 'scripts/%s.gd' % f)
        if not os.path.exists(p): p = os.path.join(ROOT, 'autoload/%s.gd' % f)
        text = open(p, encoding='utf-8', newline='').read().replace(chr(13) + NL, NL)
        for a, b, raw in literals(text):
            body = raw
            line_start = text.rfind(NL, 0, a) + 1
            before = text[line_start:a]; after = text[b:text.find(NL, b) if text.find(NL, b) >= 0 else len(text)]
            if re.search(r'(tr|translate|tr_n|translate_plural)\($', before.rstrip()): continue
            if before.strip().startswith(('push_warning', 'print', 'assert')) or 'push_warning(' in before: continue
            glued = re.match(r'\s*\+', after) or re.search(r'\+\s*$', before)
            formatted = re.match(r'\s*%\s*[\[\(\w]', after) and FMT.search(body)
            if (glued or formatted) and sentence(body) and body not in ignored:
                found.append('%s.gd:%d: %s' % (f, text.count(NL, 0, a) + 1, body[:90]))
    return found


if __name__ == '__main__':
    bad = unwrapped()
    print('%d unwrapped formatted/glued sentences' % len(bad))
    for b in bad: print('  ' + b)
    subprocess.run([sys.executable, os.path.join(ROOT, 'tools/i18n/extract.py')], check=True)
    ids = {}
    for line in open(os.path.join(ROOT, 'tools/i18n/_numbered.txt'), encoding='utf-8').read().split(NL):
        if line: ids[line.partition('|')[0]] = line.partition('|')[2]
    for lang in LANGS:
        have = set()
        for f in os.listdir(os.path.join(ROOT, 'tools/i18n')):
            if f.startswith(lang + '_') and f.endswith('.txt'):
                for line in open(os.path.join(ROOT, 'tools/i18n', f), encoding='utf-8').read().split(NL):
                    if line.strip(): have.add(line.partition('|')[0])
        missing = [k for k in ids if k not in have]
        print('%s: %d of %d texts have no translation yet' % (lang, len(missing), len(ids)))
        for k in missing[:40]: print('   %s|%s' % (k, ids[k][:100]))
