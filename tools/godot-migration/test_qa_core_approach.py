"""CPU checks for the narrow browser oracle; does not launch a browser."""
import ast
import copy
import math
import unittest
from pathlib import Path

from qa_core_approach import authored_core_approach, reached_core_approach


def observed():
    return {
        "snapshot": {"levelId": "3-4", "active": "luvie", "actors": {"luvie": "f:-3:0", "buddy": "f:-3:0"}, "flags": ["root"]},
        "moving": False, "worldVisible": True, "gameHudVisible": True, "ui": {"modalOpen": False},
        "tiles": [{"id": "f:-4:0", "x": -4, "z": 0, "h": 0}, {"id": "f:-3:0", "x": -3, "z": 0, "h": 0}],
        "native": {"actors": {
            who: {"support": "f:-3:0", "position": [-2.82, .001, z], "floorHeight": 0}
            for who, z in [("luvie", -.28), ("buddy", .30)]
        }},
    }


class CoreApproachChecks(unittest.TestCase):
    def test_explicit_core_and_both_actual_native_actors(self):
        for who in ["luvie", "buddy"]:
            self.assertIsNotNone(reached_core_approach(observed(), "f:-4:0", who))

    def test_ordinary_floor_and_other_levels_never_get_exception(self):
        self.assertIsNone(authored_core_approach(observed(), "f:-3:0"))
        state = observed()
        state["snapshot"]["levelId"] = "1-4"
        self.assertIsNone(authored_core_approach(state, "f:-4:0"))

    def test_different_height_or_disconnected_tile_rejected(self):
        for field, value in [("h", 1), ("x", -2), ("solid", True)]:
            state = observed()
            state["tiles"][1][field] = value
            self.assertIsNone(authored_core_approach(state, "f:-4:0"))

    def test_label_only_motion_and_wrong_native_support_rejected(self):
        for mutate in [
            lambda s: s.update(moving=True),
            lambda s: s["native"]["actors"]["luvie"].update(position=[-4, 0, 0]),
            lambda s: s["native"]["actors"]["luvie"].update(support="f:-4:0"),
            lambda s: s["native"]["actors"]["luvie"].update(position=[-2.82, float("nan"), 0]),
        ]:
            state = observed()
            mutate(state)
            self.assertIsNone(reached_core_approach(state, "f:-4:0"))

    def test_restore_verifier_keeps_every_other_snapshot_field_strict(self):
        # Load only the pure assertion function, without Playwright or setup.
        source = Path(__file__).with_name("check-level-acceptance.py").read_text(encoding="utf-8")
        node = next(n for n in ast.parse(source).body if isinstance(n, ast.FunctionDef) and n.name == "verify")
        namespace = {"math": math, "reached_core_approach": reached_core_approach}
        exec(compile(ast.Module(body=[node], type_ignores=[]), "verify", "exec"), namespace)
        state = observed()
        expected = copy.deepcopy(state["snapshot"])
        expected["actors"] = {"luvie": "f:-4:0", "buddy": "f:-4:0"}
        self.assertEqual(namespace["verify"](state, expected), [])
        expected["flags"] = []
        self.assertIn("restored snapshot differs in flags", namespace["verify"](state, expected))
        expected["actors"]["buddy"] = "f:-4:1"
        self.assertIn("restored snapshot differs in actors/buddy", namespace["verify"](state, expected))


if __name__ == "__main__":
    unittest.main()
