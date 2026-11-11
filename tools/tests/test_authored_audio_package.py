import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_mobile_package import runtime_custom_audio_paths


class AuthoredAudioTests(unittest.TestCase):
    def test_only_published_assets_and_integrity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for kind in ('custom', 'dialogue'):
                directory = root / 'assets/audio' / kind
                directory.mkdir(parents=True)
                data = b'fixture'
                name = hashlib.sha256(data).hexdigest() + '.wav'
                (directory / name).write_bytes(data)
                (directory / 'unselected.wav').write_bytes(b'not shipped')
                lua = b'return {}'
                (directory / 'manifest.lua').write_bytes(lua)
                relative = f'assets/audio/{kind}/{name}'
                manifest = {'files': [relative], 'luaSha256': hashlib.sha256(lua).hexdigest()}
                (directory / 'manifest.json').write_text(json.dumps(manifest))
                paths = runtime_custom_audio_paths(root, kind)
                self.assertEqual(len(paths), 3)
                self.assertNotIn(directory / 'unselected.wav', paths)
                (directory / name).write_bytes(b'changed')
                with self.assertRaises(ValueError):
                    runtime_custom_audio_paths(root, kind)
                (directory / name).write_bytes(data)
                manifest['files'] = ['../../bad.wav']
                (directory / 'manifest.json').write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    runtime_custom_audio_paths(root, kind)


if __name__ == '__main__':
    unittest.main()
