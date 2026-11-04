"""Registers every built translations/<lang>.po in project.godot (locale/translations) and in PlayerSettings.UI_LANGUAGES. Run after build.py."""
import os, re
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORDER = ['es', 'nl', 'fr', 'de', 'it', 'pt', 'pl', 'cs', 'hu', 'ru', 'ko', 'zh', 'zh-TW']
langs = [l for l in ORDER if os.path.exists(os.path.join(ROOT, 'translations', l.replace('-', '_') + '.po')) or os.path.exists(os.path.join(ROOT, 'translations', l + '.po'))]
def po(l): return 'translations/%s.po' % l
p = os.path.join(ROOT, 'project.godot'); s = open(p, encoding='utf-8').read()
new = 'locale/translations=PackedStringArray(' + ', '.join('"res://%s"' % po(l) for l in langs) + ')'
s = re.sub(r'locale/translations=PackedStringArray\([^)]*\)', new, s); open(p, 'w', encoding='utf-8', newline='\n').write(s)
p = os.path.join(ROOT, 'autoload/PlayerSettings.gd'); s = open(p, encoding='utf-8').read()
s = re.sub(r'const UI_LANGUAGES: Array\[String\] = \[[^\]]*\]', 'const UI_LANGUAGES: Array[String] = [' + ', '.join('"%s"' % l for l in ['en'] + langs) + ']', s)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print(langs)
