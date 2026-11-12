"""Read-only QA exception for the occupied final flowerbed, never a floor fallback.

Native route/collision suites separately verify its blocked centre and clear
physical approach. Browser evidence still requires the real motor to settle on
the explicitly authored adjacent support; no snapshot or input is rewritten.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEVELS = {
    level["id"]: level
    for level in json.loads((ROOT / "godot/content/levels.json").read_text(encoding="utf-8"))["levels"]
}
OCCUPIED_CORES = {("3-4", "f:-4:0"): "f:-3:0"}


def authored_core_approach(state, requested):
    """Return the narrow supported destination contract, or None."""
    level = state.get("snapshot", {}).get("levelId")
    preferred = OCCUPIED_CORES.get((level, requested))
    if not preferred or not any(
        mark.get("kind") == "core" and mark.get("tile") == requested
        for mark in LEVELS.get(level, {}).get("marks", [])
    ):
        return None
    tiles = {tile["id"]: tile for tile in state.get("tiles", [])}
    core, approach = tiles.get(requested), tiles.get(preferred)
    if not core or not approach or approach.get("solid"):
        return None
    if abs(core["h"] - approach["h"]) > .1:
        return None
    if abs(core["x"] - approach["x"]) + abs(core["z"] - approach["z"]) != 1:
        return None
    return {"requested": requested, "support": preferred, "height": approach["h"]}


def reached_core_approach(state, requested, actor=None):
    """Require observed, settled native arrival at that exact authored support."""
    contract = authored_core_approach(state, requested)
    snapshot = state.get("snapshot", {})
    actor = actor or snapshot.get("active")
    if not contract or state.get("moving", True):
        return None
    support = snapshot.get("actors", {}).get(actor)
    body = state.get("native", {}).get("actors", {}).get(actor, {})
    if support != contract["support"] or body.get("support") != support:
        return None
    tile = next(tile for tile in state["tiles"] if tile["id"] == support)
    if actor == "luvie" and tile.get("small"):
        return None
    point, floor = body.get("position", []), body.get("floorHeight")
    if len(point) != 3 or floor is None or not all(math.isfinite(value) for value in [*point, floor]):
        return None
    # This explicit 3-4 terrace uses the ordinary unit ground mapping. Reject
    # an actor merely labelled with the right support while physically elsewhere.
    if abs(point[0] - tile["x"]) >= .5 or abs(point[2] - tile["z"]) >= .5 or abs(point[1] - floor) >= .16:
        return None
    return {**contract, "actor": actor, "position": point, "basis": "explicit core; original same-height adjacent support"}
