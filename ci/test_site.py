"""Check command coverage, translations, links and generated Pages output offline."""
import json
from html.parser import HTMLParser
from pathlib import Path
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

from build_site import ROOT, build


class Document(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.links = []
        self.ids = set()
        self.lang = None
        self.h1 = 0
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'html':
            self.lang = a.get('lang')
        if tag == 'h1':
            self.h1 += 1
        if 'id' in a:
            assert a['id'] not in self.ids, f'Duplicate id: {a["id"]}'
            self.ids.add(a['id'])
        for key in ('href', 'src'):
            if key in a:
                self.links.append(a[key])
        if tag == 'script':
            assert not urlsplit(a.get('src', '')).scheme, 'External script'


class SiteTests(unittest.TestCase):
    def test_build_and_links(self):
        commands = json.loads((ROOT / 'site/commands.json').read_text(encoding='utf-8'))
        names = [c['name'] for c in commands]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(set(names), {p.stem for p in (ROOT / 'bin').glob('*.cmd')})
        for c in commands:
            self.assertEqual(set(c['ru']), set(c['en']))
            for lang in ('ru', 'en'):
                self.assertTrue(all(c[lang].values()))
            self.assertTrue(set(c['route']).issubset(names))
            self.assertIn(c['next'], names)
            self.assertIn(c['name'] + '.cmd', c['example'])
        with tempfile.TemporaryDirectory(prefix='stm32-pages-') as temp:
            output = build(Path(temp))
            docs = {p: Document(p.read_text(encoding='utf-8')) for p in output.rglob('*.html')}
            self.assertEqual(len(docs), 2 * (1 + len(names)))
            for path, doc in docs.items():
                self.assertEqual(doc.h1, 1, str(path))
                self.assertEqual(doc.lang, 'en' if path.name == 'index.en.html' else 'ru')
                for link in doc.links:
                    url = urlsplit(link)
                    if url.scheme:
                        self.assertEqual(url.scheme, 'https')
                        continue
                    self.assertFalse(url.netloc)
                    target = (path.parent / unquote(url.path)).resolve() if url.path else path
                    self.assertTrue(target.is_relative_to(output))
                    self.assertTrue(target.exists(), f'{path}: missing {link}')
                    if url.fragment:
                        self.assertIn(unquote(url.fragment), docs[target].ids)
            before = {p.relative_to(output): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            build(output)
            after = {p.relative_to(output): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
