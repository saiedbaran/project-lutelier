"""Optional private-LAN depth inference. Official model environments stay separate."""
import argparse
import base64
import binascii
import hmac
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
from PIL import Image, ImageOps

CATALOG = {
    "patchfusion": "PatchFusion · CVPR 2024",
    "depth-anything-3": "Depth Anything 3 · 2025",
    "depth-pro": "Apple Depth Pro · ICLR 2025",
}
BODY_LIMIT = 32 * 1024 * 1024
PIXEL_LIMIT = 24_000_000
Image.MAX_IMAGE_PIXELS = PIXEL_LIMIT


def near_white(values, metric=True):
    """Relative inverse depth. Never accept a colourised visualisation as depth."""
    values = np.asarray(values, dtype=np.float32)
    if values.ndim != 2 or values.size < 16:
        raise ValueError("Expected a scalar depth map")
    valid = np.isfinite(values) & ((values > 0) if metric else True)
    if valid.sum() < values.size * 0.9:
        raise ValueError("Depth map contains too many invalid samples")
    if metric:
        values = np.where(valid, 1 / np.maximum(values, 1e-6), np.nan)
    low, high = np.percentile(values[valid], [1, 99])
    if high - low < 1e-6:
        raise ValueError("Depth map has no usable variation")
    normalized = np.nan_to_num(np.clip((values - low) / (high - low), 0, 1))
    return np.rint(normalized * 65535).astype(np.uint16)


def patchfusion_command(settings, input_dir, output_dir, size):
    width, height = size
    return [settings["python"], "tools/test.py", settings.get("config", "configs/patchfusion_depthanything/depthanything_general.py"),
            "--ckp-path", settings["checkpoint"], "--test-type", "general", "--cfg-options",
            "general_dataloader.dataset.rgb_image_dir=" + str(input_dir),
            "--cai-mode", "m2", "--image-raw-shape", str(height), str(width),
            "--patch-split-num", "2", "2", "--process-num", "1", "--save", "--work-dir", str(output_dir)]


class Engines:
    def __init__(self, config):
        self.config = config
        self.lock = threading.Lock()

    def capabilities(self):
        return [{"id": key, "name": name, "configured": self.configured(key),
                 "verified": False, "detail": "Configured; model inference not preflighted" if self.configured(key) else "Install official repository, environment and weights first"}
                for key, name in CATALOG.items()]

    def configured(self, key):
        settings = self.config.get(key, {})
        return (Path(settings.get("python", "__missing__")).is_file()
                and Path(settings.get("repo", "__missing__")).is_dir()
                and bool(settings.get("checkpoint") if key == "patchfusion" else settings.get("model") if key == "depth-anything-3" else settings.get("repo")))

    def infer(self, key, image):
        if key not in CATALOG or not self.configured(key):
            raise ValueError("Engine is not configured")
        if not self.lock.acquire(blocking=False):
            raise BlockingIOError("Another inference is running")
        try:
            settings = self.config[key]
            with tempfile.TemporaryDirectory(prefix="lutelier-depth-") as temporary:
                work = Path(temporary)
                incoming, outgoing = work / "input", work / "output"
                incoming.mkdir()
                outgoing.mkdir()
                # The official PatchFusion tiling path expects sizes divisible by four.
                if key == "patchfusion":
                    width, height = image.size
                    image = image.resize((max(4, width // 4 * 4), max(4, height // 4 * 4)), Image.Resampling.LANCZOS)
                image.save(incoming / "photo.png")
                environment = dict(os.environ, HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")
                repo = Path(settings["repo"]).resolve()
                environment["PYTHONPATH"] = os.pathsep.join([str(repo), str(repo / "external"), environment.get("PYTHONPATH", "")])
                if key == "patchfusion":
                    command = patchfusion_command(settings, incoming, outgoing, image.size)
                else:
                    command = [settings["python"], str(Path(__file__).with_name("worker.py")), key,
                               str(incoming / "photo.png"), str(outgoing / "raw.npy"),
                               settings.get("model", ""), settings.get("device", "cuda")]
                # No shell, request-supplied command or automatic model download.
                subprocess.run(command, cwd=repo, env=environment, check=True, timeout=600,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if key == "patchfusion":
                    matches = list(outgoing.rglob("photo_uint16.png"))
                    if len(matches) != 1:
                        raise ValueError("Official raw depth output missing; colourised output is not accepted")
                    with Image.open(matches[0]) as texture:
                        raw = np.asarray(texture).copy()
                    # Official tester stores metres multiplied by 256.
                    raw = raw.astype(np.float32) / 256
                else:
                    raw = np.load(outgoing / "raw.npy", allow_pickle=False)
                texture = Image.fromarray(near_white(raw))
                buffer = io.BytesIO()
                texture.save(buffer, format="PNG")
                return {"engine": key, "convention": "relative-near-white", "texture": base64.b64encode(buffer.getvalue()).decode(),
                        "width": texture.width, "height": texture.height}
        finally:
            self.lock.release()


def make_handler(engines, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Photographs, credentials and paths never enter request logs.

        def reply(self, status, payload):
            data = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def authorized(self):
            return hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + token).encode())

        def do_GET(self):
            if not self.authorized():
                return self.reply(401, {"error": "Authentication required"})
            if self.path != "/v1/engines":
                return self.reply(404, {"error": "Unknown endpoint"})
            self.reply(200, {"engines": engines.capabilities()})

        def do_POST(self):
            if not self.authorized():
                return self.reply(401, {"error": "Authentication required"})
            if self.path != "/v1/depth":
                return self.reply(404, {"error": "Unknown endpoint"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= BODY_LIMIT:
                    return self.reply(413, {"error": "Photograph exceeds request limit"})
                self.connection.settimeout(30)
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict) or request.get("engine") not in CATALOG:
                    raise ValueError("Unknown engine")
                data = base64.b64decode(request["image"], validate=True)
                with Image.open(io.BytesIO(data)) as source:
                    if source.width * source.height > PIXEL_LIMIT:
                        raise ValueError("Photograph exceeds pixel limit")
                    image = ImageOps.exif_transpose(source).convert("RGB")
                result = engines.infer(request["engine"], image)
                self.reply(200, result)
            except BlockingIOError:
                self.reply(409, {"error": "Another inference is running"})
            except (ValueError, KeyError, TypeError, binascii.Error, OSError, Image.DecompressionBombError):
                self.reply(400, {"error": "Invalid photograph, unavailable engine or unusable depth output"})
            except (subprocess.SubprocessError, RuntimeError, ImportError):
                self.reply(503, {"error": "Model failed. Check the companion environment and cached weights"})
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8770)
    args = parser.parse_args()
    token = os.environ.get("LUTELIER_DEPTH_TOKEN", "")
    if len(token) < 24 or not token.isascii():
        parser.error("Set LUTELIER_DEPTH_TOKEN to an ASCII secret of at least 24 characters")
    config = json.loads(args.config.read_text())
    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(Engines(config), token))
    print(f"Lutelier depth companion listening on {args.host}:{args.port}. No model weights are bundled.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.server_close()


if __name__ == "__main__":
    main()
