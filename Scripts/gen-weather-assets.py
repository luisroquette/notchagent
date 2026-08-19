#!/usr/bin/env python3
"""Generate realistic weather art with OpenAI image models.

Stage 1: gpt-image-1 with background=transparent (true alpha PNGs).
Stage 2 (fallback): gpt-image-2 on a pure black plate, then chroma-key
the black to alpha (Pillow) — the plate disappears, only the lit pixels
remain, composited as plain images (no blend modes in the app).

The key is loaded from ~/.claude/vision-openai/.env and never printed —
it only travels to the OpenAI Images API. Output lands in
Resources/Weather/ as alpha PNGs, bundled by make-app.sh.

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
    "sun": (
        "Photorealistic sun, bright warm yellow-white core with soft atmospheric "
        "glow and a delicate lens flare, on a fully transparent background, glow "
        "fading smoothly to full transparency at the edges, centered, no clouds, "
        "no horizon, high dynamic range, subtle, natural"
    ),
    "clouds": (
        "Photorealistic volumetric cumulus clouds, soft white puffy clouds with "
        "realistic shading and depth, on a fully transparent background, no sky, "
        "no ground, soft natural daylight, clouds fading to full transparency at "
        "the edges"
    ),
}

BLACK_PLATE_PROMPTS = {
    name: p.replace("on a fully transparent background", "on a pure black background")
    .replace("fading smoothly to full transparency at the edges", "fading smoothly into the black at the edges")
    .replace("fading to full transparency at the edges", "fading into the black at the edges")
    for name, p in PROMPTS.items()
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


def call_images_api(key: str, model: str, prompt: str, background: str | None) -> dict | None:
    body = {
        "model": model,
        "prompt": prompt,
        "n": 1,
        "size": "1024x1024",
        "quality": "high",
        "output_format": "png",
    }
    if background:
        body["background"] = background
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300, context=SSL_CONTEXT) as r:
        return json.loads(r.read().decode())


def chroma_key_black(src: str, dst: str) -> None:
    """Black plate -> alpha: luminance ramps 0..255 so only lit pixels stay."""
    from PIL import Image

    img = Image.open(src).convert("RGBA")
    lum = img.convert("L")
    # v < 24: transparent plate; v >= 109: fully opaque; linear ramp between.
    alpha = lum.point(lambda v: 0 if v < 24 else min(255, (v - 24) * 3))
    img.putalpha(alpha)
    img.save(dst)
    print(f"    chroma-key -> {dst}")


def generate(name: str, force_black: bool = False) -> bool:
    key = load_key()
    if not key:
        print(f"[{name}] ERRO: sem chave OpenAI em ~/.claude/vision-openai/.env")
        return False
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, f"weather-{name}.png")

    # Stage 1: true transparency. gpt-image-1 sometimes returns a fully
    # transparent alpha channel for bright subjects (the sun) — those are
    # re-keyed from the black-plate variant instead.
    if not force_black:
        try:
            resp = call_images_api(key, "gpt-image-1", PROMPTS[name], "transparent")
            b64 = resp["data"][0]["b64_json"]
            with open(out, "wb") as f:
                f.write(base64.b64decode(b64))
            print(f"[{name}] ok (gpt-image-1, transparent) -> {out}")
            return True
        except urllib.error.HTTPError as e:
            e.read()
            print(f"[{name}] gpt-image-1 transparent falhou ({e.code}) — tentando gpt-image-2 + chroma-key")
        except (KeyError, IndexError) as e:
            print(f"[{name}] resposta inesperada no estágio 1: {e}")

    # Stage 2: black plate + chroma-key.
    try:
        resp = call_images_api(key, "gpt-image-2", BLACK_PLATE_PROMPTS[name], None)
        b64 = resp["data"][0]["b64_json"]
        raw = os.path.join(OUT_DIR, f".raw-{name}.png")
        with open(raw, "wb") as f:
            f.write(base64.b64decode(b64))
        chroma_key_black(raw, out)
        os.remove(raw)
        print(f"[{name}] ok (gpt-image-2 + chroma-key) -> {out}")
        return True
    except urllib.error.HTTPError as e:
        print(f"[{name}] ERRO HTTP {e.code}: {e.read().decode()[:200]}")
        return False
    except Exception as e:
        print(f"[{name}] ERRO: {e}")
        return False


if __name__ == "__main__":
    args = sys.argv[1:]
    force_black = "--black" in args
    targets = [a for a in args if not a.startswith("--")] or ["sun", "clouds"]
    failed = [t for t in targets if not generate(t, force_black=force_black)]
    sys.exit(1 if failed else 0)
