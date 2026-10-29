"""Builds translations/<lang>.po from translations/ascent.pot's source list (tools/i18n/_numbered.txt, made by extract.py) and the numbered
translation files tools/i18n/<lang>_*.txt (lines 'N|text', plural lines 'PN|singular|plural').
Checks every translation: the same placeholders (%s %d %f %%, {name}) as the source, no unescaped quote, the source's leading / trailing
whitespace and its leading / trailing \n kept (added when missing). Run: python tools/i18n/build.py
"""
import glob, os, re, sys
BS = chr(92); NL = chr(10); Q = chr(34)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LANGS = {'es': 'Spanish', 'nl': 'Dutch'}
PH = re.compile('%[-+0-9.]*[sdif]|%%|[{][a-z_]+[}]')


def load_numbered():
    singles = {}; plurals = {}
    for line in open(os.path.join(ROOT, 'tools/i18n/_numbered.txt'), encoding='utf-8').read().split(NL):
        if not line: continue
        key, _, rest = line.partition('|')
        if key.startswith('P'):
            one, _, many = rest.partition('|'); plurals[key] = (one, many)
        else:
            singles[key] = rest
    return singles, plurals


def split_ws(s):
    lead = re.match('^(?:' + BS + 'n| )*', s).group(0)
    tail = re.search('(?:' + BS + 'n| )*$', s).group(0)
    return lead, tail


def fix_ws(src, dst):
    sl, st = split_ws(src)
    core = dst
    dl = re.match('^(?:' + BS + 'n| )*', core).group(0)
    core = core[len(dl):]
    dt = re.search('(?:' + BS + 'n| )*$', core).group(0)
    if dt: core = core[:len(core) - len(dt)]
    return sl + core + st


def bare_quote(s):
    i = 0
    while i < len(s):
        if s[i] == BS: i += 2; continue
        if s[i] == Q: return True
        i += 1
    return False


def check(src, dst, label, problems):
    a = sorted(PH.findall(src)); b = sorted(PH.findall(dst))
    if a != b: problems.append('%s: placeholders %s -> %s | %s' % (label, a, b, dst[:60]))
    if bare_quote(dst): problems.append('%s: unescaped quote | %s' % (label, dst[:60]))


def build(lang):
    singles, plurals = load_numbered()
    tr = {}; trp = {}
    for f in sorted(glob.glob(os.path.join(ROOT, 'tools/i18n/%s_*.txt' % lang))):
        for line in open(f, encoding='utf-8').read().split(NL):
            if not line.strip(): continue
            key, _, rest = line.partition('|')
            if key.startswith('P'):
                one, _, many = rest.partition('|'); trp[key] = (one, many)
            else:
                tr[key] = rest
    problems = []; out = []
    out.append('msgid ' + Q + Q); out.append('msgstr ' + Q + Q)
    for h in ('Project-Id-Version: Ascent', 'Language: ' + lang, 'MIME-Version: 1.0', 'Content-Type: text/plain; charset=UTF-8', 'Plural-Forms: nplurals=2; plural=(n != 1);'):
        out.append(Q + h + BS + 'n' + Q)
    out.append('')
    missing = 0
    for key in sorted(singles, key=lambda k: int(k)):
        src = singles[key]
        if key not in tr:
            missing += 1; continue
        dst = fix_ws(src, tr[key])
        check(src, dst, '#' + key, problems)
        out.append('msgid ' + Q + src + Q); out.append('msgstr ' + Q + dst + Q); out.append('')
    for key in sorted(plurals):
        one, many = plurals[key]
        if key not in trp: missing += 1; continue
        d1, d2 = trp[key]
        check(one, d1, key + 'a', problems); check(many, d2, key + 'b', problems)
        out.append('msgid ' + Q + one + Q); out.append('msgid_plural ' + Q + many + Q)
        out.append('msgstr[0] ' + Q + d1 + Q); out.append('msgstr[1] ' + Q + d2 + Q); out.append('')
    open(os.path.join(ROOT, 'translations/%s.po' % lang), 'w', encoding='utf-8', newline=NL).write(NL.join(out))
    print('%s: %d translated, %d missing, %d problems' % (lang, len(tr) + len(trp), missing, len(problems)))
    for p in problems: print('  ' + p)


if __name__ == '__main__':
    for lang in (sys.argv[1:] or LANGS): build(lang)
