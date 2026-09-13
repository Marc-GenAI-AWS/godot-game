"""Shared helpers for the specialist pipeline: paths, Bedrock calls, run dirs."""
import base64
import json
import os
import re
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
PIPE = ROOT / "pipeline"
RUNS = PIPE / "runs"
GODOT = Path(os.environ.get("GODOT_BIN", "/home/marc/opt/godot/Godot_v4.7.2-stable_linux.arm64"))
REGION = os.environ.get("AWS_REGION", "us-west-2")

# Bedrock inference profiles (on-demand invocation needs the profile id).
TEACHER_MODEL = os.environ.get("TEACHER_MODEL", "us.anthropic.claude-sonnet-5")
JUDGE_MODEL = os.environ.get("JUDGE_MODEL", "us.anthropic.claude-fable-5-1")
DIRECTOR_MODEL = os.environ.get("DIRECTOR_MODEL", "us.anthropic.claude-fable-5-1")

CONTRACT_VERSION = "v1.1"

SEGMENTS = {
    # segment -> (world used for verification, capture shots, capture script)
    # drags are held (~s) past the shot so the camera has not eased back yet
    "sky": {"world": "beach", "shots": "3,6,9", "script": "4:Drag_0_-220~2.5,7:Drag_-320_0~2.5"},
    # placement segments: default view, then the camera turned to the landward
    # side (negative dx turns left; the beach's promenade and furniture are on
    # the left) and slightly up so tall plants fit, then back along that side
    "vegetation": {"world": "beach", "shots": "3,6,9", "script": "4:Drag_-330_-110~2.5,7:Drag_-200_-30~2.5"},
    "props": {"world": "beach", "shots": "3,6,9", "script": "4:Drag_-300_-40~2.5,7:Drag_-230_20~2.5"},
    "ground": {"world": "beach", "shots": "3,6,9", "script": "4:Drag_0_260~2.5,7:Drag_-330_-200~2.5"},
    "water": {"world": "beach", "shots": "3,6,9", "script": "4:Drag_330_0~2.5,7:Drag_0_260~2.5"},
}
# load() paths a segment's candidates may use (everything else is forbidden)
ALLOWED_LOADS = {
    "ground": ["res://segments/ground/shaders/sand.gdshader", "res://segments/ground/shaders/asphalt.gdshader"],
    "water": ["res://segments/water/shaders/water.gdshader"],
}


def run_dir(name: str) -> Path:
    d = RUNS / name
    d.mkdir(parents=True, exist_ok=True)
    return d


def read(p) -> str:
    return Path(p).read_text()


def write_jsonl(path, rows):
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def read_jsonl(path):
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def extract_code(text: str) -> str:
    """Return the body of the first fenced gdscript block, or the whole text."""
    m = re.search(r"```(?:gdscript|gd)?\s*\n(.*?)```", text, re.S)
    return (m.group(1) if m else text).strip() + "\n"


_client = None


def bedrock():
    global _client
    if _client is None:
        import boto3
        from botocore.config import Config
        # long generations are fine, hung sockets are not: bounded read timeout, SDK retries off (we retry ourselves)
        _client = boto3.client("bedrock-runtime", region_name=REGION,
                               config=Config(connect_timeout=10, read_timeout=240, retries={"max_attempts": 1}))
    return _client


def converse(model: str, system: str, user_blocks, max_tokens=6000, temperature=None, retries=4):
    """One Bedrock Converse call. user_blocks is a list of {"text":..} or
    {"image": {"format": "png", "source": {"bytes": ...}}} blocks.
    Claude 5 models reject `temperature`; it is only sent when explicitly
    given for an older model."""
    cfg = {"maxTokens": max_tokens}
    if temperature is not None and "claude-5" not in model and "fable" not in model and "sonnet-5" not in model:
        cfg["temperature"] = temperature
    kwargs = dict(
        modelId=model,
        messages=[{"role": "user", "content": user_blocks}],
        inferenceConfig=cfg,
    )
    if system:
        kwargs["system"] = [{"text": system}]
    delay = 2.0
    for attempt in range(retries):
        try:
            r = bedrock().converse(**kwargs)
            text = "".join(b.get("text", "") for b in r["output"]["message"]["content"])
            return text, r.get("usage", {})
        except Exception as e:  # throttling, transient
            if attempt == retries - 1:
                raise
            print(f"  bedrock retry {attempt + 1}: {str(e)[:120]}")
            time.sleep(delay)
            delay *= 2


def image_block(path) -> dict:
    return {"image": {"format": "png", "source": {"bytes": Path(path).read_bytes()}}}


def parse_json(text: str):
    """Tolerant JSON extraction from a model reply: fenced block, raw_decode
    from the first brace (ignores trailing prose), then a greedy match."""
    m = re.search(r"```(?:json)?\s*\n(.*?)```", text, re.S)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    start = text.find("{")
    if start >= 0:
        try:
            return json.JSONDecoder().raw_decode(text[start:])[0]
        except json.JSONDecodeError:
            pass
    m = re.search(r"\{.*\}", text, re.S)
    return json.loads(m.group(0) if m else text)
