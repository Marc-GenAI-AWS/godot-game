"""Specialist inference: one call = one layer file from contract + brief.

Backends (--backend):
  teacher            Claude on Bedrock (the stand-in until a specialist is trained)
  local:<url>        an OpenAI-compatible server, e.g. vLLM on the dev box serving
                     the merged SFT weights: vllm serve <model_dir> --port 8000
  endpoint:<name>    a SageMaker real-time endpoint (DJL/TGI/vLLM container,
                     OpenAI-compatible or "inputs" JSON)

Batch mode (used by the evaluation stage and by hand):
    python3 pipeline/loop/specialist.py --segment sky --briefs heldout_briefs.jsonl --out runs/eval1 \
        --backend local:http://127.0.0.1:8000/v1 --model sky-sft
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import PIPE, TEACHER_MODEL, converse, extract_code, read, read_jsonl, write_jsonl  # noqa: E402
from teacher import revise_prompt, user_prompt  # noqa: E402


class Specialist:
    def __init__(self, segment: str, backend: str = "teacher", model: str = None):
        self.segment = segment
        self.backend = backend
        self.model = model
        self.system = read(PIPE / "contract" / f"{segment}.md")

    def _chat(self, prompt: str) -> str:
        if self.backend == "teacher":
            text, _ = converse(self.model or TEACHER_MODEL, self.system, [{"text": prompt}])
            return text
        if self.backend.startswith("local:"):
            import urllib.request
            url = self.backend[len("local:"):].rstrip("/") + "/chat/completions"
            body = {"model": self.model or "specialist", "max_tokens": 6000, "temperature": 0.4,
                    "messages": [{"role": "system", "content": self.system}, {"role": "user", "content": prompt}]}
            req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=600) as r:
                return json.load(r)["choices"][0]["message"]["content"]
        if self.backend.startswith("endpoint:"):
            import boto3
            name = self.backend[len("endpoint:"):]
            rt = boto3.client("sagemaker-runtime")
            body = {"messages": [{"role": "system", "content": self.system}, {"role": "user", "content": prompt}],
                    "max_tokens": 6000, "temperature": 0.4}
            r = rt.invoke_endpoint(EndpointName=name, ContentType="application/json", Body=json.dumps(body))
            out = json.loads(r["Body"].read())
            if "choices" in out:
                return out["choices"][0]["message"]["content"]
            return out.get("generated_text", json.dumps(out))
        raise ValueError("unknown backend " + self.backend)

    def write(self, brief: dict) -> tuple:
        prompt = user_prompt(brief)
        return extract_code(self._chat(prompt)), prompt

    def revise(self, brief: dict, previous: str, evidence: str) -> tuple:
        prompt = revise_prompt(brief, previous, evidence)
        return extract_code(self._chat(prompt)), prompt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--segment", default="sky")
    ap.add_argument("--briefs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--backend", default="teacher")
    ap.add_argument("--model")
    a = ap.parse_args()
    out = Path(a.out)
    (out / "candidates").mkdir(parents=True, exist_ok=True)
    sp = Specialist(a.segment, a.backend, a.model)
    rows = []
    for b in read_jsonl(a.briefs):
        code, prompt = sp.write(b)
        cid = b["id"] + "_s"
        p = out / "candidates" / f"{cid}.gd"
        p.write_text(code)
        rows.append({"candidate": cid, "brief_id": b["id"], "brief": b, "segment": a.segment, "mode": "write",
                     "prompt": prompt, "path": str(p), "backend": a.backend})
        print(" ", cid, len(code), "chars")
    write_jsonl(out / "candidates.jsonl", rows)


if __name__ == "__main__":
    main()
