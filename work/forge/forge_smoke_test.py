"""Smoke test for the local Forge API: one cartoon concept image, timed."""
import base64
import json
import pathlib
import sys
import time
import urllib.request

OUT = pathlib.Path(__file__).with_name("forge_test")
OUT.mkdir(exist_ok=True)
payload = {
    "prompt": "stylized cartoon game character concept, a small goofy green goblin with big pointed ears and a brown loincloth, "
              "chunky proportions, big head, smooth rounded shapes, bold saturated colours, soft hand-painted shading, thick clean outline, "
              "full body, front three-quarter view, plain light grey background, 3D toy render look",
    "negative_prompt": "pixel art, photo, realistic, text, watermark, blurry, extra limbs, dark, gritty",
    "width": 1024, "height": 1024, "steps": 24, "cfg_scale": 6.0, "sampler_name": "Euler a", "seed": 12345, "batch_size": 1,
}
req = urllib.request.Request("http://127.0.0.1:7860/sdapi/v1/txt2img", data=json.dumps(payload).encode(),
                             headers={"Content-Type": "application/json"})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=540) as r:
        doc = json.loads(r.read())
except Exception as exc:  # noqa: BLE001
    print("FAILED:", repr(exc))
    sys.exit(1)
dt = time.time() - t0
img = base64.b64decode(doc["images"][0])
path = OUT / "goblin_concept.png"
path.write_bytes(img)
print(f"OK {len(img)} bytes in {dt:.1f}s -> {path}")
