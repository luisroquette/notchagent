#!/usr/bin/env python3
"""Generate realistic weather art with OpenAI's gpt-image-2.

The key is loaded from ~/.claude/vision-openai/.env and never printed —
it only travels to the OpenAI Images API. Output lands in
Resources/Weather/ as transparent PNGs, bundled by make-app.sh.

Usage: python3 Scripts/gen-weather-assets.py [sun|clouds|all]
"""
import base64
import json
import os
import ssl
import sys
import urllib.request

try:
    import certifi
    SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CONTEXT = ssl.create_default_context()

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Resources", "Weather")

PROMPTS = {
    # Pure black backgrounds: the app composites them with .blendMode(.screen),
    # so black contributes nothing and only the lit elements show.
    "sun": (
        "Photorealistic sun, bright warm yellow-white core with soft atmospheric "
        "glow and a delicate lens flare, on a pure black background, glow fading "
        "smoothly into the black at the edges, centered, no clouds, no horizon, "
        "high dynamic range, subtle, natural"
    ),
    "clouds": (
        "Photorealistic volumetric cumulus clouds, soft white puffy clouds with "
        "realistic shading and depth, on a pure black background, no sky, no "
        "ground, soft natural daylight, clouds fading into the black at the edges"
    ),
}


def load_key() -> str:
    env_path = os.path.expanduser("~/.claude/vision-openai/.env")
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("OPENAI_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return os.environ.get("OPENAI_API_KEY", "")


def generate(name: str) -> bool:
    key = load_key()
    if not key:
        print(f"[{name}] ERRO: sem chave OpenAI em ~/.claude/vision-openai/.env")
        return False
    body = {
        "model": "gpt-image-2",
        "prompt": PROMPTS[name],
        "n": 1,
        "size": "1024x1024",
        "quality": "high",
        "output_format": "png",
    }
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=300, context=SSL_CONTEXT) as r:
            resp = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        print(f"[{name}] ERRO HTTP {e.code}: {e.read().decode()[:200]}")
        return False
    except Exception as e:
        print(f"[{name}] ERRO de rede: {e}")
        return False
    try:
        b64 = resp["data"][0]["b64_json"]
    except (KeyError, IndexError):
        print(f"[{name}] ERRO resposta inesperada (sem b64_json)")
        return False
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, f"weather-{name}.png")
    with open(out, "wb") as f:
        f.write(base64.b64decode(b64))
    print(f"[{name}] ok -> {out} ({len(b64) // 1024} KB base64)")
    return True


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    targets = ["sun", "clouds"] if which == "all" else [which]
    failed = [t for t in targets if not generate(t)]
    sys.exit(1 if failed else 0)
