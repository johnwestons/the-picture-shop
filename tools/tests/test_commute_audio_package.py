"""Exercise the shared package copy with a small isolated source tree."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_mobile_package as package


class CommuteAudioPackageTests(unittest.TestCase):
    def test_runtime_copy_includes_approved_audio_and_provenance(self):
        source = package.ROOT / 'assets/audio/commute'
        manifest = json.loads((source / 'manifest.json').read_text())
        expected = {entry['file'] for entry in manifest['files']}
        expected.update(('forest-ambience.mp3', 'manifest.json', 'SOURCES.md'))
        self.assertEqual(set(package.COMMUTE_AUDIO_FILES), expected)
        for entry in manifest['files']:
            self.assertEqual(hashlib.sha256((source/entry['file']).read_bytes()).hexdigest(), entry['sha256'])
        scratch = (package.ROOT/'output/motorcycle-audio/package-check').resolve()
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            self.assertTrue(Path(temp).resolve().is_relative_to(scratch))
            root, stage = Path(temp)/'root', Path(temp)/'stage'
            root.mkdir(); stage.mkdir()
            for name in ('main.lua', 'conf.lua'):
                (root/name).write_text('-- packaging fixture')
            shutil.copytree(source, root/'assets/audio/commute')
            for name in ('SOURCES.md', 'source_manifest.json'):
                (root/'assets/audio'/name).write_text('fixture')
            with patch.object(package, 'ROOT', root), patch.object(package, 'runtime_source_paths', return_value=[]), \
                 patch.object(package, 'runtime_music_paths', return_value=[]), patch.object(package, 'copy_runtime_source_assets'):
                package.copy_runtime(stage)
            for name in expected:
                self.assertEqual((stage/'assets/audio/commute'/name).read_bytes(), (source/name).read_bytes())
            self.assertFalse((stage/'output/motorcycle-audio/motorcycle-audition.wav').exists())


if __name__ == '__main__':
    unittest.main()
