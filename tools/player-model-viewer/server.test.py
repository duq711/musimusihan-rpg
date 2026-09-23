"""Exercise only the local outfit routes with a tiny stand-in file."""
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('player_viewer_server', Path(__file__).with_name('server.py'))
viewer_server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(viewer_server)


class OutfitRoutes(unittest.TestCase):
    @staticmethod
    def request(path):
        handler = viewer_server.Handler.__new__(viewer_server.Handler)
        handler.path = path
        handler.wfile = io.BytesIO()
        result = {'status': None, 'headers': {}}
        handler.send_response = lambda code: result.update(status=code)
        handler.send_header = lambda key, value: result['headers'].update({key: value})
        handler.end_headers = lambda: None
        handler.send_error = lambda code: result.update(status=code)
        handler.do_GET()
        result['body'] = handler.wfile.getvalue()
        return result

    def test_availability_and_binary(self):
        with tempfile.TemporaryDirectory() as folder:
            original = viewer_server.OUTFIT
            viewer_server.OUTFIT = Path(folder) / 'medival_outfit.glb'
            try:
                missing = self.request('/outfit-info.json')
                self.assertEqual(missing['status'], 200)
                self.assertFalse(json.loads(missing['body'])['available'])
                self.assertEqual(missing['headers']['Cache-Control'], 'no-store')
                self.assertEqual(self.request('/outfit.glb')['status'], 404)
                payload = b'glTF-local-preview'
                viewer_server.OUTFIT.write_bytes(payload)
                info = json.loads(self.request('/outfit-info.json')['body'])
                self.assertTrue(info['available'])
                self.assertEqual(info['bytes'], len(payload))
                self.assertIn('modified', info)
                binary = self.request('/outfit.glb')
                self.assertEqual(binary['status'], 200)
                self.assertEqual(binary['body'], payload)
                self.assertEqual(binary['headers']['Content-Type'], 'model/gltf-binary')
                self.assertEqual(binary['headers']['Cache-Control'], 'no-store')
            finally:
                viewer_server.OUTFIT = original


if __name__ == '__main__':
    unittest.main()
