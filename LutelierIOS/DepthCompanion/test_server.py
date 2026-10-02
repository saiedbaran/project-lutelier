"""Contract tests use synthetic maps. They do not assert real model quality."""
import base64
import http.client
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image
from server import Engines, BODY_LIMIT, ThreadingHTTPServer, make_handler, near_white, patchfusion_command


class DepthTests(unittest.TestCase):
    def test_metric_polarity_and_roundtrip(self):
        near = near_white(np.linspace(1, 10, 100).reshape(10, 10))
        self.assertEqual(near[0, 0], 65535)
        self.assertEqual(near[-1, -1], 0)
        buffer = io.BytesIO()
        Image.fromarray(near).save(buffer, format="PNG")
        np.testing.assert_array_equal(np.asarray(Image.open(io.BytesIO(buffer.getvalue()))), near)

    def test_reject_colour_flat_and_invalid(self):
        for values in [np.ones((4, 4, 3)), np.ones((4, 4)), np.zeros((4, 4)), np.full((4, 4), np.nan)]:
            with self.assertRaises(ValueError):
                near_white(values)

    def test_cli_is_argument_list(self):
        settings = {"python": "python", "checkpoint": "cached-hub-id"}
        command = patchfusion_command(settings, Path("input with spaces"), Path("output"), (1280, 720))
        self.assertIn("general_dataloader.dataset.rgb_image_dir=input with spaces", command)
        self.assertEqual(command[command.index("--image-raw-shape") + 1:command.index("--image-raw-shape") + 3], ["720", "1280"])
        self.assertIn("--cfg-options", command)

    def test_adapter_reads_raw_output(self):
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            interpreter = repo / "python"
            interpreter.touch()
            engines = Engines({"patchfusion": {"python": str(interpreter), "repo": str(repo), "checkpoint": "cached"}})
            def fake_inference(command, **kwargs):
                self.assertNotIn("shell", kwargs)
                self.assertEqual(kwargs["env"]["HF_HUB_OFFLINE"], "1")
                outgoing = Path(command[command.index("--work-dir") + 1])
                Image.fromarray(np.linspace(256, 2560, 64).reshape(8, 8).astype(np.uint16)).save(outgoing / "photo_uint16.png")
            with patch("server.subprocess.run", side_effect=fake_inference):
                reply = engines.infer("patchfusion", Image.new("RGB", (17, 19)))
            self.assertEqual(reply["engine"], "patchfusion")
            self.assertEqual(reply["convention"], "relative-near-white")
            self.assertEqual(np.asarray(Image.open(io.BytesIO(base64.b64decode(reply["texture"]))))[0, 0], 65535)

    def test_reject_visualization_and_release_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder); interpreter = repo / "python"; interpreter.touch()
            engines = Engines({"patchfusion": {"python": str(interpreter), "repo": str(repo), "checkpoint": "cached"}})
            with patch("server.subprocess.run"):
                with self.assertRaises(ValueError):
                    engines.infer("patchfusion", Image.new("RGB", (16, 16)))
            self.assertFalse(engines.lock.locked())


class ProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.token = "test-only-token-01234567890123456789"
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(Engines({}), cls.token))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()

    def request(self, method, path, body=None, authorized=True, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        request_headers = {"Authorization": "Bearer " + self.token} if authorized else {}
        request_headers.update(headers or {})
        connection.request(method, path, body=body, headers=request_headers)
        response = connection.getresponse()
        status, payload = response.status, json.loads(response.read())
        connection.close()
        return status, payload

    def test_authentication_required(self):
        self.assertEqual(self.request("GET", "/v1/engines", authorized=False)[0], 401)
        self.assertEqual(self.request("POST", "/v1/depth", "{}", authorized=False)[0], 401)

    def test_capabilities_do_not_claim_verified_models(self):
        status, reply = self.request("GET", "/v1/engines")
        self.assertEqual(status, 200)
        self.assertTrue(all(not e["configured"] and not e["verified"] for e in reply["engines"]))

    def test_bad_image_and_unknown_engine(self):
        for body in [{"engine": "patchfusion", "image": "bad"}, {"engine": "unknown", "image": ""}, [], None]:
            self.assertEqual(self.request("POST", "/v1/depth", json.dumps(body))[0], 400)

    def test_request_size_limit(self):
        self.assertEqual(self.request("POST", "/v1/depth", "", headers={"Content-Length": str(BODY_LIMIT + 1)})[0], 413)

    def test_unconfigured_engine(self):
        image = io.BytesIO(); Image.new("RGB", (32, 32)).save(image, format="PNG")
        body = json.dumps({"engine": "patchfusion", "image": base64.b64encode(image.getvalue()).decode()})
        self.assertEqual(self.request("POST", "/v1/depth", body)[0], 400)

    def test_unknown_endpoint(self):
        self.assertEqual(self.request("GET", "/unknown")[0], 404)


if __name__ == "__main__":
    unittest.main()
