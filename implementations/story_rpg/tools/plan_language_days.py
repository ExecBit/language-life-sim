#!/usr/bin/env python3
"""Independent A0–A1 language-day allocation; never reads story/ACT sources."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from calculate_language_days import PROFILES, STAGES, calculate

DOCS = Path(__file__).resolve().parents[1] / "docs"
TARGET = DOCS / "LANGUAGE_DAY_SCHEDULE.json"
V_CAP = {"compact": 5, "baseline": 4, "gentle": 3}
CAP_FIELDS = ("U", "M", "G", "P", "A", "R", "LO", "V")
TRACKS = {"active_core": "A", "receptive_core": "R"}
FIELD_NAMES = {"U":"unit_start", "M":"first_m", "G":"first_g",
               "P":"first_p", "A":"lex_A", "R":"lex_R",
               "LO":"assess_lo", "V":"revisit_m"}

def empty_day(stage: str, slot: int) -> dict:
    return dict(stage=stage, slot=slot, unit_start=[], unit_activity=[],
                first_m=[], first_g=[], first_p=[], revisit_m=[],
                early_lo=[], assess_lo=[], lex_A=[], lex_R=[])

def used(day: dict, field: str) -> int:
    return len(day[FIELD_NAMES[field]])

def attempt(stage: str, units: list, words: list, caps: dict, length: int):
    days = [empty_day(stage, k+1) for k in range(length)]
    def seek(begin: int, field: str):
        return next((i for i in range(begin, length) if used(days[i], field) < caps[field]), -1)
    for i, u in enumerate(units):
        uid = u["id"]
        target = i * length // len(units)
        pos = next((j for j in range(target, length)
                    if used(days[j],"U") < caps["U"]
                    and used(days[j],"M")+len(u["introduce_m"]) <= caps["M"]), -1)
        if pos < 0:
            return None
        days[pos]["unit_start"].append(uid)
        days[pos]["first_m"].extend(u["introduce_m"])
        cursor = pos
        for code in u["introduce_g"]:
            cursor = seek(cursor, "G")
            if cursor < 0: return None
            days[cursor]["first_g"].append(code)
            if cursor != pos and uid not in days[cursor]["unit_activity"]:
                days[cursor]["unit_activity"].append(uid)
        for code in u["first_p"]:
            cursor = seek(cursor, "P")
            if cursor < 0: return None
            days[cursor]["first_p"].append(code)
            if cursor != pos and uid not in days[cursor]["unit_activity"]:
                days[cursor]["unit_activity"].append(uid)
        for code in u["revisit_m"]:
            at = seek(pos,"V")
            if at < 0: return None
            days[at]["revisit_m"].append(code)
            if at != pos and uid not in days[at]["unit_activity"]:
                days[at]["unit_activity"].append(uid)
        if stage != "P6":
            days[pos]["early_lo"].extend(u.get("outcome_candidates", []))
        else:
            for code in u.get("outcome_candidates", []):
                at = seek(pos,"LO")
                if at < 0: return None
                days[at]["assess_lo"].append(code)
                if at != pos and uid not in days[at]["unit_activity"]:
                    days[at]["unit_activity"].append(uid)
    for role, fld in TRACKS.items():
        entries = [e["text"] for e in words
                   if e["learning_scope"]["focus_band"] == stage
                   and e["learning_scope"]["track"] == role]
        for expression in entries:
            free = [d for d in days if used(d,fld) < caps[fld]]
            if not free: return None
            target = min(free,key=lambda d:(used(d,fld), d["slot"]))
            target["lex_"+fld].append(expression)
    return days

def build() -> dict:
    original = json.loads((DOCS/"LANGUAGE_PRACTICE_UNITS.json").read_text(encoding="utf-8"))
    lex = json.loads((DOCS/"LANGUAGE_LEXICAL_CATALOG.json").read_text(encoding="utf-8"))
    counts, lower_bounds = calculate()
    results = {}
    for name, profile in PROFILES.items():
        days, stage_summaries = [], {}
        for stage in STAGES:
            units = [u for u in original["items"] if u["stage"] == stage]
            cap = {**profile["default"],**profile.get(stage,{}),"V":V_CAP[name]}
            revisit_count = sum(len(u["revisit_m"]) for u in units)
            lower = max(1,lower_bounds[stage][name],math.ceil(revisit_count/cap["V"]))
            selected = None
            for length in range(lower,lower+31):
                selected=attempt(stage,units,lex["entries"],cap,length)
                if selected is not None:break
            if selected is None:raise ValueError(f"Cannot pack {name}:{stage}")
            for day in selected:
                day["day"]=len(days)+1
                day["needs_contract"]=not any(day[k] for k in
                   ("unit_start","first_g","first_p","revisit_m","assess_lo"))
            days.extend(selected)
            stage_summaries[stage] = dict(lower_bound=lower,
              proposed_days=len(selected),
              lexical_only_days=sum(d["needs_contract"] for d in selected))
        results[name] = dict(total_days=len(days),stages=stage_summaries,days=days)
    return dict(version="1.0",
      status="language_only_provisional_slots_not_proven_learning_or_story_days",
      input_versions=dict(units=original["version"],lexicon=lex["version"]),
      assumptions=dict(
        stages_are_sequential_for_this_projection=True,
        units_keep_canonical_first_R_order=True,
        A_R_are_focus_candidates_not_words_memorized=True,
        LO_in_P6_are_proposed_probes_not_exams_passed=True,
        lexical_only_slots_require_real_semantic_contracts=True,
        game_day_is_not_calendar_elapsed_time=True,
        real_A0_validation_required=True,
        capacity_profiles={name:dict(default=profile["default"],
           overrides={k:v for k,v in profile.items() if k!="default"},
           revisit=V_CAP[name]) for name,profile in PROFILES.items()}),
      baseline_profile="baseline", profiles=results)

def validate(plan:dict) -> None:
    original=json.loads((DOCS/"LANGUAGE_PRACTICE_UNITS.json").read_text(encoding="utf-8"))
    lex=json.loads((DOCS/"LANGUAGE_LEXICAL_CATALOG.json").read_text(encoding="utf-8"))
    expected={k:[] for k in ("unit_start","first_m","first_g","first_p","revisit_m","assess_lo","lex_A","lex_R")}
    for u in original["items"]:
        expected["unit_start"].append(u["id"])
        for dest,src in (("first_m","introduce_m"),("first_g","introduce_g"),
                         ("first_p","first_p"),("revisit_m","revisit_m")):
            expected[dest].extend(u[src])
        if u["stage"]=="P6":expected["assess_lo"].extend(u.get("outcome_candidates",[]))
    for e in lex["entries"]:
        tr=e["learning_scope"]["track"]
        if tr in TRACKS:expected["lex_"+TRACKS[tr]].append(e["text"])
    if plan["input_versions"]!=dict(units=original["version"],lexicon=lex["version"]):
        raise ValueError("Calendar source versions stale")
    for name,result in plan["profiles"].items():
        seen={k:[] for k in expected}
        first_R, first_P, revisits={}, {}, []
        stage_nos=[]
        if result["total_days"]!=len(result["days"]):raise ValueError("Bad total")
        for n,d in enumerate(result["days"],1):
            if d["day"]!=n or d["stage"] not in STAGES:raise ValueError("Bad day order")
            stage_nos.append(STAGES.index(d["stage"]))
            caps={**PROFILES[name]["default"],**PROFILES[name].get(d["stage"],{}),"V":V_CAP[name]}
            for field in CAP_FIELDS:
                if used(d,field)>caps[field]:raise ValueError(f"{name} day {n}: exceeds {field}")
            for k in expected:seen[k].extend(d[k])
            for code in d["first_m"]:
                if code in first_R:raise ValueError(f"Duplicated first R {code}")
                first_R[code]=n
            for code in d["first_p"]:
                if code in first_P:raise ValueError(f"Duplicated first P {code}")
                first_P[code]=n
            revisits.extend((code,n) for code in d["revisit_m"])
            incomplete=not any(d[k] for k in
                   ("unit_start","first_g","first_p","revisit_m","assess_lo"))
            if d["needs_contract"]!=incomplete:raise ValueError("Incorrect contract-needed flag")
        if stage_nos!=sorted(stage_nos):raise ValueError("Stage order changed")
        if seen["unit_start"]!=expected["unit_start"]:raise ValueError("Unit order changed")
        for k in expected:
            if sorted(seen[k])!=sorted(expected[k]):
                raise ValueError(f"{name}: missing/duplicate {k}")
        for code,n in first_P.items():
            if first_R.get(code,n+1)>n:raise ValueError(f"P before first R {code}")
        for code,n in revisits:
            if first_R.get(code,n)>=n:raise ValueError(f"Revisit not after R {code}")
        for stage in STAGES:
            ds=[d for d in result["days"] if d["stage"]==stage]
            ss=result["stages"][stage]
            if ss["proposed_days"]!=len(ds) or ss["lexical_only_days"]!=sum(d["needs_contract"] for d in ds):
                raise ValueError("Stage summary stale")

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument("--write",action="store_true")
    mode.add_argument("--check",action="store_true")
    args=parser.parse_args()
    proposed=build()
    validate(proposed)
    if args.write:
        TARGET.write_text(json.dumps(proposed,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    elif args.check:
        existing=json.loads(TARGET.read_text(encoding="utf-8"))
        validate(existing)
        if proposed!=existing:
            raise ValueError("LANGUAGE_DAY_SCHEDULE.json outdated; run --write")
    for name,p in proposed["profiles"].items():
        print(f"{name}: {p['total_days']} candidate slots")

if __name__=="__main__":
    main()
