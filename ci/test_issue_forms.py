"""Check GitHub issue forms offline against the documented form syntax rules."""
from pathlib import Path
import re
import unittest

try:
    import yaml
except ImportError:  # PyYAML is optional on developer machines.
    yaml = None

ROOT = Path(__file__).resolve().parents[1]
FORMS = ROOT / '.github/ISSUE_TEMPLATE'
TYPES = {'markdown', 'input', 'textarea', 'dropdown', 'checkboxes'}


@unittest.skipIf(yaml is None, 'PyYAML is not installed')
class IssueFormTests(unittest.TestCase):
    def load(self, path):
        return yaml.safe_load(path.read_text(encoding='utf-8'))

    def test_config(self):
        config = self.load(FORMS / 'config.yml')
        self.assertIs(config['blank_issues_enabled'], False)
        for link in config['contact_links']:
            self.assertEqual(set(link), {'name', 'url', 'about'})
            self.assertTrue(link['url'].startswith('https://'))

    def test_forms(self):
        forms = sorted(p for p in FORMS.glob('*.yml') if p.name != 'config.yml')
        self.assertEqual(len(forms), 3)
        commands = {p.stem for p in (ROOT / 'bin').glob('*.cmd')}
        for path in forms:
            with self.subTest(form=path.name):
                form = self.load(path)
                self.assertTrue(form['name'] and form['description'])
                self.assertLessEqual(set(form), {'name', 'description', 'title', 'labels', 'body', 'assignees', 'projects', 'type'})
                ids, labels = set(), set()
                for element in form['body']:
                    self.assertIn(element['type'], TYPES)
                    attributes = element['attributes']
                    if element['type'] == 'markdown':
                        self.assertTrue(attributes['value'].strip())
                        continue
                    self.assertRegex(element['id'], r'^[A-Za-z0-9_-]+$')
                    self.assertNotIn(element['id'], ids)
                    ids.add(element['id'])
                    self.assertNotIn(attributes['label'], labels)
                    labels.add(attributes['label'])
                    if 'render' in attributes:
                        self.assertEqual(element['type'], 'textarea')
                    if element['type'] in ('dropdown', 'checkboxes'):
                        options = attributes['options']
                        names = [o['label'] if isinstance(o, dict) else o for o in options]
                        self.assertTrue(names and all(names))
                        self.assertEqual(len(names), len(set(names)))
                        self.assertFalse({n.lower() for n in names} & {'none'})
                    if element['id'] == 'command':
                        self.assertTrue(commands <= set(attributes['options']))
                self.assertTrue(ids)


if __name__ == '__main__':
    unittest.main()
