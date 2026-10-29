"""Finds the texts of the player-facing scripts (tools/i18n/player_files.txt) and writes translations/ascent.pot.

A text is (a) any literal inside tr() / tr_n() / TranslationServer.translate() / translate_plural(), or (b) a literal that looks like
text a player reads (Godot translates those automatically when they are put in a label, button, tooltip or title), minus
tools/i18n/ignore.txt (one exact text per line), plus tools/i18n/extra_msgids.txt (texts built at run time, one per line).
Texts are kept in their source form (a backslash-n stays backslash-n) which is exactly what a .po file wants.
Run:  python tools/i18n/extract.py   (also writes tools/i18n/_numbered.txt for translators)
"""
import os, re, sys
BS = chr(92); NL = chr(10); Q = chr(34)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FILES = {}
for _l in open(os.path.join(ROOT, 'tools/i18n/player_files.txt'), encoding='utf-8'):
    if _l.strip() and not _l.startswith('#'):
        _p = _l.split(); FILES[_p[0]] = len(_p) > 1 and _p[1] == 'tr'   # name -> only explicit tr() calls


def read_list(name):
    p = os.path.join(ROOT, 'tools/i18n', name)
    if not os.path.exists(p):
        return []
    return [l.rstrip(NL).rstrip(chr(13)) for l in open(p, encoding='utf-8') if l.strip() and not l.startswith('#')]


def literals(text):
    """(start, end, raw) of every double-quoted literal outside comments."""
    out = []; i = 0; n = len(text)
    while i < n:
        c = text[i]
        if c == '#':
            while i < n and text[i] != NL: i += 1
            continue
        if c == Q:
            j = i + 1
            while j < n:
                if text[j] == BS: j += 2; continue
                if text[j] == Q: break
                j += 1
            out.append((i, j + 1, text[i + 1:j].replace(NL, BS + 'n'))); i = j + 1; continue
        i += 1
    return out


def human(s):
    if len(s) < 2 or not re.search('[A-Za-z]{2,}', s): return False
    if re.fullmatch('[a-z0-9_./:-]+', s): return False
    if re.fullmatch('[A-Za-z0-9_]+', s) and ' ' not in s and not s[0].isupper(): return False
    if s.startswith(('res://', 'user://', 'http', '[color', '[/', '#', '@')): return False
    if re.fullmatch('[A-Z0-9_]{4,}', s) or re.fullmatch('[A-Z0-9_]+_ID:?', s): return False
    if re.fullmatch('[A-Z][A-Z0-9_]+', s) and ' ' not in s: return False       # ENUM_NAMES / ids
    if '%' not in s and ' ' not in s and ':' not in s and not s[0].isupper(): return False
    return True


TR_CALL = re.compile(r'(?:tr|translate)\(\s*$')
PLURAL_CALL = re.compile(r'(?:tr_n|translate_plural)\(\s*$')


def extract():
    singles = {}   # msgid -> [refs]
    plurals = {}   # (msgid, plural) -> [refs]
    for f, tr_only in FILES.items():
        p = os.path.join(ROOT, 'scripts/%s.gd' % f)
        if not os.path.exists(p): p = os.path.join(ROOT, 'autoload/%s.gd' % f)
        text = open(p, encoding='utf-8', newline='').read().replace(chr(13) + NL, NL)
        lits = literals(text)
        for idx, (a, b, raw) in enumerate(lits):
            line = text.count(NL, 0, a) + 1
            ref = '%s.gd:%d' % (f, line)
            before = text[:a]
            line_start = before.rfind(NL) + 1
            code_before = text[line_start:a]
            code_after = text[b:text.find(NL, b) if text.find(NL, b) >= 0 else len(text)]
            if PLURAL_CALL.search(before[-30:]):
                nxt = lits[idx + 1][2] if idx + 1 < len(lits) else ''
                plurals.setdefault((raw, nxt), []).append(ref); continue
            if idx > 0 and PLURAL_CALL.search(text[:lits[idx - 1][0]][-30:]):
                continue   # the plural form: handled above
            if TR_CALL.search(before[-30:]):
                singles.setdefault(raw, []).append(ref); continue
            if tr_only: continue
            stripped = code_before.strip()
            if stripped.startswith(('push_warning', 'print', 'assert')) or 'push_warning(' in code_before: continue
            if re.search(r'(get|has|erase|set|get_slice|begins_with|ends_with|trim_prefix|trim_suffix|class_exists|get_setting|has_method|call|connect|is_in_group|get_node|find|count)\($', code_before): continue
            if code_after.lstrip().startswith(':') and not code_after.lstrip().startswith(':='): continue   # dictionary key / match arm
            if code_before.rstrip().endswith('[') and code_after.lstrip().startswith(']'): continue        # d["key"]
            if re.search(r'(==|!=)\s*$', code_before) or code_after.lstrip().startswith(('==', '!=')): continue   # compared, not shown
            if not human(raw): continue
            singles.setdefault(raw, []).append(ref)
    for extra in read_list('extra_msgids.txt'):
        singles.setdefault(extra, []).append('extra')
    ignore = set(read_list('ignore.txt'))
    parts = [i[1:] for i in ignore if i.startswith('~')]     # '~text' = ignore every text that contains it
    for key in list(singles):
        if all(r != 'extra' for r in singles[key]) and (key in ignore or any(p in key for p in parts)): del singles[key]
    return singles, plurals


def po_quote(s):
    return Q + s + Q


def write_pot(singles, plurals):
    lines = ['# Ascent - texts of the game (generated by tools/i18n/extract.py; do not edit).', 'msgid ' + po_quote(''), 'msgstr ' + po_quote(''),
             po_quote('Project-Id-Version: Ascent' + BS + 'n'), po_quote('MIME-Version: 1.0' + BS + 'n'), po_quote('Content-Type: text/plain; charset=UTF-8' + BS + 'n'), '']
    for msgid in sorted(singles, key=lambda s: s.lower()):
        lines.append('#: ' + ' '.join(sorted(set(singles[msgid]))[:3]))
        lines.append('msgid ' + po_quote(msgid)); lines.append('msgstr ' + po_quote('')); lines.append('')
    for (one, many) in sorted(plurals, key=lambda s: s[0].lower()):
        lines.append('#: ' + ' '.join(sorted(set(plurals[(one, many)]))[:3]))
        lines.append('msgid ' + po_quote(one)); lines.append('msgid_plural ' + po_quote(many))
        lines.append('msgstr[0] ' + po_quote('')); lines.append('msgstr[1] ' + po_quote('')); lines.append('')
    open(os.path.join(ROOT, 'translations/ascent.pot'), 'w', encoding='utf-8', newline=NL).write(NL.join(lines))


def load_ids():
    """tools/i18n/ids.txt keeps the number of every text ever extracted (N|text, P-numbers for plurals) so translation files never go stale."""
    singles, plurals = {}, {}
    p = os.path.join(ROOT, 'tools/i18n/ids.txt')
    if os.path.exists(p):
        for line in open(p, encoding='utf-8').read().split(NL):
            if not line: continue
            key, _, rest = line.partition('|')
            if key.startswith('P'):
                one, _, many = rest.partition('|'); plurals[(one, many)] = key
            else:
                singles[rest] = key
    return singles, plurals


if __name__ == '__main__':
    singles, plurals = extract()
    write_pot(singles, plurals)
    ids, pids = load_ids()
    next_id = max([int(v) for v in ids.values()] + [0]) + 1
    next_pid = max([int(v[1:]) for v in pids.values()] + [0]) + 1
    for msgid in sorted(singles, key=lambda s: s.lower()):
        if msgid not in ids: ids[msgid] = str(next_id); next_id += 1
    for pair in sorted(plurals, key=lambda s: s[0].lower()):
        if pair not in pids: pids[pair] = 'P%d' % next_pid; next_pid += 1
    rows = [(int(v), '%s|%s' % (v, k)) for k, v in ids.items()] + [(1000000 + int(v[1:]), '%s|%s|%s' % (v, k[0], k[1])) for k, v in pids.items()]
    open(os.path.join(ROOT, 'tools/i18n/ids.txt'), 'w', encoding='utf-8', newline=NL).write(NL.join(r for _, r in sorted(rows)))
    # the texts that are in the source now, with their stable numbers (what build.py reads)
    nums = [(int(ids[m]), '%s|%s' % (ids[m], m)) for m in singles] + [(1000000 + int(pids[p][1:]), '%s|%s|%s' % (pids[p], p[0], p[1])) for p in plurals]
    open(os.path.join(ROOT, 'tools/i18n/_numbered.txt'), 'w', encoding='utf-8', newline=NL).write(NL.join(r for _, r in sorted(nums)))
    print('texts:', len(singles), 'plural forms:', len(plurals), '- new numbers start at', next_id)
