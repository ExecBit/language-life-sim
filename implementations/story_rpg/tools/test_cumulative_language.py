"""Regression checks for curriculum promises that ID counts alone cannot protect."""
import copy
import unittest
from unittest.mock import patch

import cumulative_language as curriculum


class CumulativeCurriculumTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = curriculum.build()
        cls.base = cls.plan["profiles"]["baseline"]

    def test_every_required_target_has_earlier_and_late_practice(self):
        for profile in self.plan["profiles"].values():
            for key, trajectory in profile["trajectories"].items():
                late = [x for x in trajectory if x["phase"] == "late_integration"]
                self.assertTrue(late, key)
                self.assertLess(trajectory[0]["day"], late[0]["day"], key)
                kind = self.plan["learning_items"][key]
                if kind["kind"] == "lex" and kind["mode"] == "P" and kind["expression"] not in ("ich verstehe nicht", "noch einmal", "Wie bitte?"):
                    self.assertTrue(any(x["mode"] == "P" for x in late), key)

    def test_entire_catalogue_has_practice_regardless_of_legacy_role(self):
        entries=curriculum.read('LANGUAGE_LEXICAL_CATALOG.json')['entries']
        targets={it['expression']:key for key,it in self.plan['learning_items'].items() if it['kind']=='lex'}
        self.assertEqual(set(targets),{e['text'] for e in entries})
        for e in entries:
            for profile in self.plan['profiles'].values():
                visits=profile['trajectories'][targets[e['text']]]
                self.assertEqual(visits[0]['phase'],'introduction')
                self.assertTrue(any(v['phase'] in ('reuse','late_integration') for v in visits[1:]),e['text'])

    def test_known_repertoire_is_not_dropped_while_new_material_continues(self):
        for profile in self.plan["profiles"].values():
            for d in profile["days"][1:]:
                if d["stage"] != "P6":
                    self.assertTrue(any(c["phase"] == "reuse" for c in d["contacts"]), d["day"])

    def test_shared_bin_bist_contrast_stays_atomic(self):
        for profile in self.plan["profiles"].values():
            d = next(d for d in profile["days"] if "G02" in d["first_g"])
            self.assertIn("G03", d["first_g"])
            self.assertTrue(any({"G02", "G03"} <= set(c["targets"]) for c in d["contacts"]))

    def test_first_support_precedes_demand_instead_of_late_catalogue_window(self):
        for expression, uid in (("ich", "P0-06"), ("zwei", "P1-10"), ("noch einmal", "P0-03")):
            k = next(k for k,v in self.plan["learning_items"].items() if v.get("expression") == expression)
            first = self.base["trajectories"][k][0]["day"]
            demand = next(d["day"] for d in self.base["days"] if any(c.get("activity", "").startswith(uid+":R") for c in d["contacts"]))
            self.assertLessEqual(first, demand, expression)

    def test_early_written_outcome_does_not_precede_own_production(self):
        for lo, mid in (("LO-W02", "M15"), ("LO-W05", "M51")):
            early = next(d["day"] for d in self.base["days"] if lo in d["early_lo"])
            prod = next(d["day"] for d in self.base["days"] if mid in d["first_p"])
            self.assertGreaterEqual(early, prod)

    def test_all_integration_precedes_first_independent_assessment(self):
        for profile in self.plan["profiles"].values():
            end = max(x["day"] for t in profile["trajectories"].values() for x in t if x["phase"] == "late_integration")
            exam = min(d["day"] for d in profile["days"] if d["assess_lo"])
            self.assertLess(end, exam)

    def test_clarification_remains_voluntary_and_doch_receptive(self):
        for d in self.base["days"]:
            for c in d["contacts"]:
                if "modes" not in c:
                    continue
                if "M05" in c["targets"]:
                    self.assertEqual(c["modes"]["M05"], "R")
                    self.assertTrue(c["clarification_is_voluntary"])
                if "G24" in c["targets"]:
                    self.assertEqual(c["modes"]["G24"], "R")

    def test_finishing_late_coverage_does_not_retire_the_queue(self):
        for profile in self.plan["profiles"].values():
            for d in profile["days"]:
                if d["assess_lo"]:
                    self.assertTrue(any(c["phase"] == "reuse" for c in d["contacts"]), d["day"])

    def test_writing_assessments_are_productive(self):
        cases = [a for a in self.plan["activities"].values() if a["kind"] == "assessment"]
        self.assertEqual(sum(a["mode"] == "P" for a in cases), 7)
        self.assertEqual(sum(a["mode"] == "R" for a in cases), 6)

    def test_explicit_existing_returns_are_credited(self):
        for unit, mid in (("P5-05", "M34"), ("P5-05", "M36"), ("P5-05", "M38"), ("P5-06", "M14"), ("P5-06", "M53")):
            days = [d["day"] for d in self.base["days"] if any(c.get("activity", "").startswith(unit+":R") and mid in c["targets"] for c in d["contacts"])]
            self.assertTrue(days, (unit, mid))
            self.assertTrue(set(days) <= {x["day"] for x in self.base["trajectories"][mid]})

    def test_lexical_P_waits_for_productive_prerequisites(self):
        first_p = {m:d["day"] for d in self.base["days"] for m in d["first_p"]}
        for key,it in self.plan["learning_items"].items():
            if it["kind"] == "lex":
                for visit in self.base["trajectories"][key]:
                    if visit["mode"] == "P":
                        self.assertLessEqual(first_p[it["productive_after"]], visit["day"])

    def test_compact_serialization_preserves_full_plan(self):
        import json
        self.assertEqual(json.loads(curriculum.serialize(self.plan)), self.plan)

    def test_missing_late_repertoire_is_rejected(self):
        damaged = copy.deepcopy(self.plan)
        c = next(c for d in damaged["profiles"]["baseline"]["days"] for c in d["contacts"] if c["phase"] == "late_integration")
        c["targets"].pop()
        with self.assertRaises(ValueError):
            curriculum.validate(damaged)

    def test_capacity_is_a_variable_not_a_fixed_day_target(self):
        items, activities, sequence, _ = curriculum.source_model()
        policy = copy.deepcopy(self.plan["policy"])
        policy["profiles"]["baseline"]["new_lex"] = 3
        alternate = curriculum.pack("baseline", items, activities, sequence, policy)
        self.assertNotEqual(alternate["total_days"], self.base["total_days"])
        self.assertEqual(set(alternate["trajectories"]), set(items))

    def test_generator_does_not_read_story_or_learner_state(self):
        original = curriculum.read
        names = []
        def guarded(name):
            names.append(name)
            self.assertTrue(name.startswith("LANGUAGE_"), name)
            return original(name)
        with patch.object(curriculum, "read", guarded):
            curriculum.source_model()
        self.assertIn("LANGUAGE_NUMBER_TIME_CONTRACTS.json", names)


if __name__ == "__main__":
    unittest.main()
