#!/usr/bin/env python3
"""Read the authored, scene-level R/P study corpus as a single source of truth.

The day containers are provisional. Only guaranteed main-path encounters enter
the primary totals; optional scenes and player replies are tracked separately.
"""
from __future__ import annotations
import json
import re
from pathlib import Path

DOCS = Path(__file__).resolve().parents[1] / "docs"
SCENES = DOCS / "ACT_DIALOGUE_SITUATIONS.json"
NORMALIZATION = DOCS / "ACT_VOCAB_NORMALIZATION.json"
WORD = re.compile(r"[^\W_]+", re.UNICODE)


def scene_data() -> dict:
    corpus = json.loads(SCENES.read_text(encoding="utf-8"))
    if corpus.get("exam_day") != 22:
        raise ValueError("Expected the provisional D22 exam to be excluded.")
    expected_days = list(range(1, 22))
    if [x["day"] for x in corpus["days"]] != expected_days:
        raise ValueError("Nonconsecutive scene day containers.")
    norm = json.loads(NORMALIZATION.read_text(encoding="utf-8"))
    if "primary_group_for_form" not in norm:
        raise ValueError("Scene corpus requires checked thematic form mapping.")
    allowed = set(norm["form_to_lexeme"]) | set(norm["excluded"])
    if any(v not in {f"{i:02}" for i in range(1, 30)}
           for v in norm["primary_group_for_form"].values()):
        raise ValueError("Unknown primary thematic group.")
    scene_ids = set()
    event_ids = set()
    days = []
    for day in corpus["days"]:
        r, p = [], []
        for scene in day["scenes"]:
            sid = scene["id"]
            if sid in scene_ids:
                raise ValueError(f"Duplicated scene: {sid}")
            scene_ids.add(sid)
            if not sid.startswith(f"D{day['day']:02}-S"):
                raise ValueError(f"Scene in wrong day: {sid}")
            for event in scene["r"]:
                if event["id"] in event_ids:
                    raise ValueError(f"Duplicate event {event['id']}")
                event_ids.add(event["id"])
                if event["required"] != scene["required"]:
                    raise ValueError(f"R exposure guarantee inconsistent: {event['id']}")
                missing = set(w.lower() for w in WORD.findall(event["de"])) - allowed
                if missing:
                    raise ValueError(f"Missing form normalization in {event['id']}: {sorted(missing)}")
                r.append({
                    **event,
                    "context": sid,
                    "scene_id": sid,
                    "tags": [],  # topical tagging uses exact word-form map, not ad hoc substring matches
                })
            for event in scene["p"]:
                if event["id"] in event_ids:
                    raise ValueError(f"Duplicate event {event['id']}")
                event_ids.add(event["id"])
                if not scene["required"] and event["required"]:
                    raise ValueError(f"Optional scene has guaranteed P: {event['id']}")
                if event["kind"] not in {"dialog", "form"}:
                    raise ValueError(f"Unknown output kind {event['id']}")
                if (not isinstance(event.get("after_r"), int)
                        or isinstance(event["after_r"], bool)
                        or not (1 <= event["after_r"] <= len(scene["r"]))):
                    raise ValueError(f"Invalid P turn placement after R at {event['id']}")
                if not event["slots"]:
                    raise ValueError(f"Missing P semantic tags {event['id']}")
                for slot in event["slots"]:
                    if slot["group"] not in {f"{i:02}" for i in range(1, 30)}:
                        raise ValueError(f"Unknown P topic: {slot['group']}")
                missing = set(w.lower() for w in WORD.findall(event["example"])) - allowed
                if missing:
                    raise ValueError(f"Missing P word normalizations in {event['id']}: {sorted(missing)}")
                p.append({**event, "scene_id": sid, "context": sid})
        if not r or not p:
            raise ValueError(f"No dialogue on D{day['day']}")
        days.append({"day": day["day"], "phase": day["phase"],
                     "scenes": day["scenes"], "r": r, "p": p})
    return {"version": corpus["version"], "status": corpus["status"],
            "exam_day": corpus["exam_day"], "days": days, "normalization": norm}


if __name__ == "__main__":
    result = scene_data()
    print(f"Validated {len(result['days'])} days, "
          f"{sum(len(d['scenes']) for d in result['days'])} scenes")
