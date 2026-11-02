#!/usr/bin/env python3
"""Leaf Me Alone's balance lab: a Monte Carlo simulator of the whole economy.

Stdlib only. It reads every tuning number straight out of the game's scripts
(tools/balance/gdconst.py over core/constants.gd, core/balance.gd, core/ranks.gd,
core/seasons.gd, net/town/neighborhoods.gd and core/catalog.gd), mirrors the
formulas of core/economy.gd line for line, and plays crews of 1 to 4 players
through the town day after day: requests and referrals, the job board, the
homeowner's verdict and pay, XP and rank unlocks, purchases, hired hands and
wages, heat and the NICE BOYS. What it can't read from the game (how fast people
rake, how they choose) is in tools/balance/model.json, each with its source.
Money sinks are tools/balance/sinks.json. docs/BALANCE.md explains it all.

    python tools/balance_sim.py                  # print the table, write build/balance/report.json and .md
    python tools/balance_sim.py --check          # exit 1 when a blocking check fails
    python tools/balance_sim.py --check --baseline   # tuning checks don't fail (until the retune lands); parity still does
    python tools/balance_sim.py --set TOWN_REGROW_PER_DAY=0.3 --set Ranks.XP_FIRST_TIER=160
    python tools/balance_sim.py --players 1,4 --seeds 20 --html
    python tools/balance_sim.py --propose        # suggest values; writes build/balance/proposal.json, edits nothing
    python tools/balance_sim.py --check --engine-dump build/soak/local-balance/host.json

Exit codes: 0 pass, 1 a blocking check failed, 2 a parse or usage error.

Mirrors by hand (keep in step when they change): net/town/town.gd (requests,
referrals, the rival), levels/job_board.gd choose_tasks, npcs/homeowner.gd
_judge, Campaign.finish_job and _split_pool, net/crew/hires.gd pay_wages,
net/day/day_clock.gd, net/run_events/director.gd _consider_roll and heat.gd.
core/economy.gd is mirrored exactly and checked by --engine-dump.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import html
import json
import math
import os
import random
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "balance"))
import gdconst  # noqa: E402

EXIT_PASS, EXIT_FAIL, EXIT_USAGE = 0, 1, 2
INF = float("inf")


class UsageError(Exception):
    """A parse or usage problem: exit 2."""


# Every constant the simulator reads. One that is missing or doesn't parse is a
# hard error, and --engine-dump compares each of these with the engine's value.
NEEDED = {
    "Constants": [
        "BUILD_VERSION", "MAX_PLAYERS", "MINUTES_PER_HOUR", "DAY_START_HOUR", "QUIET_HOURS_START",
        "DAY_CLOSE_HOUR", "SLEEP_FROM_HOUR", "QUIET_HOURS_PAY_BONUS", "QUIET_HOURS_HEAT_SCALE",
        "NIGHT_OWL_PAY_BONUS", "XP_LEAVES_FULL", "XP_LEAVES_CLEAN_AT", "XP_PER_TASK", "XP_PER_STAR",
        "XP_NEW_CLIENT", "XP_REFERRAL", "XP_WON_BACK", "XP_SIGN_PULLED", "SWEET_TALK_PATIENCE",
        "BAG_BONUS_PER_PERK", "COOL_HEADS_COOLING", "BIG_SPENDERS_BUDGET", "TOWN_REGROW_PER_DAY",
        "TOWN_FIRST_MESS", "TOWN_MIN_MESS", "TOWN_REQUESTS_PER_DAY", "TOWN_REQUEST_MIN_MESS",
        "TOWN_START_RELATIONSHIP", "TOWN_RELATIONSHIP_PER_STAR", "TOWN_REFERRAL_AT",
        "TOWN_STARTING_CLIENTS", "TOWN_DAYTIME_TEXT_HOURS", "TOWN_DAYTIME_TEXT_CHANCE",
        "TOWN_RELATIONSHIP_PER_JOB", "TOWN_RELATIONSHIP_MISSED", "TOWN_LEAD_REFERRAL_SHARE",
        "HOMEOWNER_CLEAN_ENOUGH", "HOMEOWNER_MESSY_BELOW", "HOMEOWNER_STANDARDS_CLEAN_SLOPE",
        "HOMEOWNER_STANDARDS_MESSY_SLOPE", "HOMEOWNER_THRILLED_CHANCE", "HOMEOWNER_HAPPY_CHANCE",
        "HOMEOWNER_STANDARDS_PIVOT", "HOMEOWNER_CLEAN_ENOUGH_MIN", "HOMEOWNER_CLEAN_ENOUGH_MAX",
        "HOMEOWNER_MESSY_BELOW_MIN", "HOMEOWNER_MESSY_BELOW_MAX", "HOMEOWNER_PATIENCE_MINUTES",
        "HOMEOWNER_PAY_BY_MOOD", "MOOD_STARS", "JOB_UNOWNED_TASK_CHANCE", "JOB_EXTRA_TASKS",
        "YARD_EXTRA_TASKS", "YARD_LEAVES", "YARD_TREES", "YARD_LEAF_BASE", "YARD_TREE_LEAVES",
        "YARD_TREE_SPREAD", "TASK_TOOLS", "TASK_PAY", "TOOL_PRICES", "SHOP_PRICES", "TOOL_TIER_PRICE",
        "VENDING_PRICE_SCALE", "TRUCK_BAG_CAPACITY", "HEAT_NOISE_PER_SECOND", "HEAT_COOL_PER_SECOND",
        "HEAT_COOL_PER_JOB", "HEAT_AFTER_RAID", "HEAT_ROLL_SECONDS", "HEAT_CHANCE_AT_MAX",
        "HEAT_RAID_AT", "RUN_PROGRESS_FRACTION", "HIRE_SIGNING_FEE", "HIRE_DAILY_WAGE", "HIRE_SKILL",
        "SEASON_DAYS", "RIVAL_POACH_CHANCE", "RIVAL_POACH_BELOW", "RIVAL_WIN_BACK_CHANCE",
        "RIVAL_MAX_SIGNS", "SHOP_HOURS", "SPIGOT_HOOKUP_FEE", "SPIGOT_FEE_PER_SECOND", "PAD_HALF",
        "TOWN_MAP_DEFAULT", "ARC_HOURS", "RANK_PACE_HOURS", "ARC_SOLO_RATIO_MAX",
    ],
    "Balance": [
        "CREDITS_PER_1_PERCENT_LOT_CLEANUP", "RUN_EVENT_BASE_CHANCE", "RUN_CHANCE_ESCALATION_PER_TIER",
        "MAXIMUM_RUN_EVENT_CHANCE", "RUN_EVENT_COOLDOWN_MINUTES", "TOOL_THROUGHPUT_GROWTH_MULTIPLIER",
        "ACTIVE_CLEANUP_UTILIZATION",
    ],
    "Ranks": [
        "NAMES", "ENDLESS_NAME", "TIERS_PER_RANK", "XP_FIRST_TIER", "XP_PER_TIER_STEP",
        "XP_ENDLESS_TIER", "CURVE_ID", "ENDLESS_PAY_PER_STAR", "ENDLESS_PAY_CAP", "UNLOCKS",
        "EXTRA_UNLOCKS",
    ],
    "Seasons": ["IDS", "LEAVES", "FAVORED", "PAY_BONUS"],
    "Hoods": ["HOODS", "PERSONALITIES"],
    "Catalog": ["ITEMS", "TIER_USED", "TIER_STOCK", "TIER_MK2", "TIER_MK3"],
}
# Constants the crew-size hooks will read once balance:E adds them; optional until then.
OPTIONAL = {"Constants": ["CREW_WORK_SCALE", "CREW_PATIENCE_SCALE", "XP_CREW_SCALE"]}


# ---------------------------------------------------------------- GDScript arithmetic

def g_round(x: float) -> int:
    """Godot's round(): halves away from zero (Python's round() is to even)."""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def clampf(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def percentile(values, p):
    """Linear-interpolated percentile (p 0..100); INF values sort last."""
    if not values:
        return INF
    data = sorted(values)
    if len(data) == 1:
        return data[0]
    k = (len(data) - 1) * p / 100.0
    lo, hi = int(math.floor(k)), int(math.ceil(k))
    if data[lo] == INF or data[hi] == INF:
        return data[hi] if k - lo > 0 else data[lo]
    return data[lo] + (data[hi] - data[lo]) * (k - lo)


def median(values):
    return percentile(values, 50)


# ---------------------------------------------------------------- the game's tables

def load_tables(repo: str, sets: list) -> tuple[dict, list]:
    """{script: {name: value}} from the game, with --set what-ifs applied.
    Returns (tables, notes)."""
    every = gdconst.load_all(repo)
    tables = {script: entry["values"] for script, entry in every.items()}
    problems = []
    for script, names in NEEDED.items():
        unparsed = {u["name"]: u["reason"] for u in every[script]["unparsed"]}
        for name in names:
            if name in unparsed:
                problems.append("%s.%s does not parse: %s" % (script, name, unparsed[name]))
            elif name not in tables[script]:
                problems.append("%s.%s is missing from %s" % (script, name, every[script]["path"]))
    if problems:
        raise UsageError("constants the simulator needs:\n  " + "\n  ".join(problems))
    notes = []
    for assignment in sets:
        notes.append(apply_set(tables, assignment))
    return tables, notes


def apply_set(tables: dict, assignment: str) -> str:
    """NAME=VALUE, NAME as Script.NAME[.key...] or a bare constant name (looked up in
    Constants, then Ranks, Balance, Seasons). VALUE is a GDScript expression."""
    if "=" not in assignment:
        raise UsageError("--set wants NAME=VALUE, got %r" % assignment)
    path, text = assignment.split("=", 1)
    parts = path.strip().split(".")
    if parts[0] in tables:
        script, keys = parts[0], parts[1:]
    else:
        script = next((s for s in ("Constants", "Ranks", "Balance", "Seasons", "Hoods") if parts[0] in tables[s]), "Constants")
        keys = parts
    if not keys:
        raise UsageError("--set %s names no constant" % path)
    try:
        value = gdconst.parse_value(text.strip(), tables[script])
    except Exception as error:  # noqa: BLE001 - any parse failure is a usage error
        raise UsageError("--set %s: can't read %r (%s)" % (path, text, error))
    target = tables[script]
    # A what-if changes a number the game has. A name or key that isn't there is a
    # typo (exit 2), except the crew-scale hooks balance:E will add (OPTIONAL).
    new = keys[0] not in target
    if new and not (len(keys) == 1 and keys[0] in OPTIONAL.get(script, [])):
        raise UsageError("--set %s: %s has no constant %s%s" % (
            path, script, keys[0], " (new names allowed: %s)" % ", ".join(OPTIONAL[script]) if script in OPTIONAL else ""))
    for key in keys[:-1]:
        target = _child(target, key, path)
    last = keys[-1]
    if isinstance(target, list):
        if not last.lstrip("-").isdigit() or not -len(target) <= int(last) < len(target):
            raise UsageError("--set %s: no index %s there" % (path, last))
        target[int(last)] = value
    elif isinstance(target, dict):
        if last not in target and last.isdigit() and int(last) in target:
            last = int(last)
        if last not in target and len(keys) > 1:
            raise UsageError("--set %s: no %s there" % (path, last))
        target[last] = value
    else:
        raise UsageError("--set %s: %s is not a list or dictionary" % (path, ".".join(keys[:-1])))
    if script == "Ranks" and keys[0] in ("XP_FIRST_TIER", "XP_PER_TIER_STEP", "XP_ENDLESS_TIER"):
        r = tables["Ranks"]
        r["CURVE_ID"] = "%d/%d/%d" % (r["XP_FIRST_TIER"], r["XP_PER_TIER_STEP"], r["XP_ENDLESS_TIER"])
    return "%s.%s = %r%s" % (script, ".".join(keys), value, " (new constant, what-if)" if new and len(keys) == 1 else "")


def _child(container, key, path):
    if isinstance(container, list):
        if key.lstrip("-").isdigit() and -len(container) <= int(key) < len(container):
            return container[int(key)]
        raise UsageError("--set %s: no index %s there" % (path, key))
    if isinstance(container, dict):
        if key in container:
            return container[key]
        if key.isdigit() and int(key) in container:
            return container[int(key)]
    raise UsageError("--set %s: no %s there" % (path, key))


def resolve_ref(ref, tables: dict, model: dict, product: bool = False):
    """'const:Script.NAME.key.idx' or 'model:name' (or a plain value). With product,
    a list multiplies its parts (sinks.json effects and prices). Raises KeyError
    when a path doesn't resolve."""
    if product and isinstance(ref, list):
        product = 1.0
        for part in ref:
            product *= float(resolve_ref(part, tables, model))
        return product
    if not isinstance(ref, str):
        return ref
    if ref.startswith("const:"):
        parts = ref[len("const:"):].split(".")
        if parts[0] not in tables:
            raise KeyError(ref)
        value = tables[parts[0]]
        for key in parts[1:]:
            if isinstance(value, (list, tuple)):
                index = int(key)
                if index >= len(value):
                    raise KeyError(ref)
                value = value[index]
            elif isinstance(value, dict):
                if key in value:
                    value = value[key]
                elif key.isdigit() and int(key) in value:
                    value = value[int(key)]
                else:
                    raise KeyError(ref)
            else:
                raise KeyError(ref)
        return value
    if ref.startswith("model:"):
        name = ref[len("model:"):]
        if name not in model:
            raise KeyError(ref)
        return model[name]
    return ref


def load_model(path: str, tables: dict) -> tuple[dict, dict]:
    """model.json as {name: value} (refs resolved) plus {name: source}."""
    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)
    values, sources = {}, {}
    for name, entry in raw.items():
        if name.startswith("_"):
            continue
        if not isinstance(entry, dict) or "value" not in entry or "source" not in entry:
            raise UsageError("model.json %s needs a value and a source" % name)
        values[name] = entry["value"]
        sources[name] = entry["source"]
    for name, value in list(values.items()):
        try:
            values[name] = resolve_ref(value, tables, values)
        except KeyError as error:
            raise UsageError("model.json %s: %s doesn't resolve" % (name, error))
    return values, sources


def load_sinks(path: str, tables: dict, model: dict) -> tuple[list, list, bool]:
    """Resolved sink entries, warnings, and enforce_endless."""
    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)
    out, warnings = [], []
    for entry in raw.get("entries", []):
        item = dict(entry)
        try:
            price = float(resolve_ref(item.get("price", 0), tables, model, True))
            if "price_mult" in item:
                price *= float(resolve_ref(item["price_mult"], tables, model, True))
            item["price"] = g_round(price)
            if "rent_per_day" in item:
                item["rent_per_day"] = float(resolve_ref(item["rent_per_day"], tables, model))
            if "per_unit" in item:
                item["per_unit"] = float(resolve_ref(item["per_unit"], tables, model))
            effect = {}
            for key, value in (item.get("effect") or {}).items():
                effect[key] = value if key == "tool" or isinstance(value, bool) else float(resolve_ref(value, tables, model, True))
            item["effect"] = effect
        except KeyError as error:
            warnings.append("sink %s skipped: %s doesn't resolve yet" % (entry.get("id"), error))
            continue
        gates = item.get("gate", [])
        item["gate"] = gates if isinstance(gates, list) else [gates]
        out.append(item)
    return out, warnings, bool(raw.get("enforce_endless", False))


# ---------------------------------------------------------------- mirrors of the game's pure code

class Ranks:
    """core/ranks.gd."""

    def __init__(self, tables):
        r = tables["Ranks"]
        self.names = r["NAMES"]
        self.per_rank = r["TIERS_PER_RANK"]
        self.first, self.step, self.endless = r["XP_FIRST_TIER"], r["XP_PER_TIER_STEP"], r["XP_ENDLESS_TIER"]
        self.curve_id = r["CURVE_ID"]
        self.unlocks = r["UNLOCKS"]
        self.extra = {int(k): list(v) for k, v in r["EXTRA_UNLOCKS"].items()}
        self.pay_per_star, self.pay_cap = r["ENDLESS_PAY_PER_STAR"], r["ENDLESS_PAY_CAP"]
        self.last = len(self.names) * self.per_rank
        self._tier_of = {}
        for index, unlock in enumerate(self.unlocks):
            self._tier_of.setdefault(unlock, index + 1)
        for tier in self.extra:
            for unlock in self.extra[tier]:
                self._tier_of.setdefault(unlock, tier)
        self._reach = [0]
        for tier in range(self.last + 60):
            self._reach.append(self._reach[-1] + self.xp_for_tier(tier))

    def xp_for_tier(self, tier):
        if tier >= self.last:
            return self.endless
        return self.first + self.step * tier

    def xp_to_reach(self, tier):
        total = 0
        for below in range(max(0, tier)):
            total += self.xp_for_tier(below)
        return total

    def tier_for_xp(self, xp):
        tier, left = 0, xp
        while left >= self.xp_for_tier(tier):
            left -= self.xp_for_tier(tier)
            tier += 1
        return tier

    def xp_into_tier(self, xp):
        tier, left = 0, xp
        while left >= self.xp_for_tier(tier):
            left -= self.xp_for_tier(tier)
            tier += 1
        return left

    def tier_of(self, unlock):
        return self._tier_of.get(unlock, 0)

    def pay_bonus(self, tier):
        stars = tier - self.last + 1
        if stars <= 0:
            return 0.0
        return min(float(stars) * self.pay_per_star, self.pay_cap)


class Seasons:
    """core/seasons.gd (the numbers)."""

    def __init__(self, tables):
        s = tables["Seasons"]
        self.leaves, self.favored, self.pay_bonus = s["LEAVES"], s["FAVORED"], s["PAY_BONUS"]
        self.days = tables["Constants"]["SEASON_DAYS"]

    def of_day(self, day):
        length = max(1, self.days)
        return int(float(max(day, 1) - 1) / float(length)) % 4

    def year_of(self, day):
        length = max(1, self.days)
        return int(float(max(day, 1) - 1) / float(length * 4)) + 1


class Economy:
    """core/economy.gd, line for line. Changing a formula there means changing it here
    (balance_test's case grid catches a mismatch)."""

    def __init__(self, tables):
        self.C, self.B = tables["Constants"], tables["Balance"]
        self.ranks = Ranks(tables)

    def job_xp(self, cleaned, task_done, stars, crew):
        C = self.C
        xp = float(C["XP_LEAVES_FULL"]) * clampf(cleaned / C["XP_LEAVES_CLEAN_AT"], 0.0, 1.0)
        for done in task_done:
            xp += float(C["XP_PER_TASK"]) * clampf(float(done), 0.0, 1.0)
        xp += float(C["XP_PER_STAR"]) * float(stars)
        return int(g_round(xp * self.xp_crew_scale(crew)))

    def migrate_xp(self, xp, from_id, to_id):
        if from_id == to_id:
            return xp
        frm, to = self._parse_curve(from_id), self._parse_curve(to_id)
        if not frm or not to:
            return xp
        tier, left = 0, xp
        while left >= self._curve_tier_xp(frm, tier):
            left -= self._curve_tier_xp(frm, tier)
            tier += 1
        frac = float(left) / float(self._curve_tier_xp(frm, tier))
        reach = 0
        for below in range(tier):
            reach += self._curve_tier_xp(to, below)
        return reach + int(math.floor(frac * float(self._curve_tier_xp(to, tier))))

    @staticmethod
    def _parse_curve(curve_id):
        parts = str(curve_id).split("/")
        if len(parts) != 3:
            return []
        out = []
        for part in parts:
            text = part.strip()
            if not (text.lstrip("+-").isdigit()) or int(text) <= 0:
                return []
            out.append(int(text))
        return out

    def _curve_tier_xp(self, curve, tier):
        if tier >= self.ranks.last:
            return curve[2]
        return curve[0] + curve[1] * tier

    def regrow(self, days_since, never_done):
        C = self.C
        if never_done:
            return C["TOWN_FIRST_MESS"]
        return clampf(float(days_since) * C["TOWN_REGROW_PER_DAY"], C["TOWN_MIN_MESS"], 1.0)

    def relationship_after(self, rel, stars):
        C = self.C
        if stars <= 0:
            return rel
        return clampf(rel + float(stars - 3) * C["TOWN_RELATIONSHIP_PER_STAR"] + C["TOWN_RELATIONSHIP_PER_JOB"], 0.0, 100.0)

    def mood_thresholds(self, standards):
        return (self.clean_enough_at(standards), self.messy_below_at(standards))

    def clean_enough_at(self, standards):
        C = self.C
        return clampf(C["HOMEOWNER_CLEAN_ENOUGH"] + (standards - C["HOMEOWNER_STANDARDS_PIVOT"]) * C["HOMEOWNER_STANDARDS_CLEAN_SLOPE"],
                      C["HOMEOWNER_CLEAN_ENOUGH_MIN"], C["HOMEOWNER_CLEAN_ENOUGH_MAX"])

    def messy_below_at(self, standards):
        C = self.C
        return clampf(C["HOMEOWNER_MESSY_BELOW"] + (standards - C["HOMEOWNER_STANDARDS_PIVOT"]) * C["HOMEOWNER_STANDARDS_MESSY_SLOPE"],
                      C["HOMEOWNER_MESSY_BELOW_MIN"], C["HOMEOWNER_MESSY_BELOW_MAX"])

    def job_pay(self, bag_value, task_value, mood, budget, water_fee, bills):
        if mood == "nothing":
            return 0
        by_mood = float(self.C["HOMEOWNER_PAY_BY_MOOD"].get(mood, 1.0))
        return max(0, int(g_round(float(bag_value + task_value) * by_mood * budget)) - water_fee - bills)

    def bag_bonus(self, perk_count):
        bonus = 1.0
        for _ in range(max(0, perk_count)):
            bonus += self.C["BAG_BONUS_PER_PERK"]
        return bonus

    # The crew-size hooks return 1.0 until balance:E adds the tables; once the
    # constants exist (or a --set what-if adds them) they are read like E will.
    def crew_work_scale(self, players):
        return self._scale_for("CREW_WORK_SCALE", players)

    def crew_patience_scale(self, players):
        return self._scale_for("CREW_PATIENCE_SCALE", players)

    def xp_crew_scale(self, players):
        return self._scale_for("XP_CREW_SCALE", players)

    def _scale_for(self, name, players):
        table = self.C.get(name)
        if not table:
            return 1.0
        return float(table[int(clampf(players, 1, len(table))) - 1])

    def run_roll_chance(self, heat, lots_completed):
        B, C = self.B, self.C
        chance = B["RUN_EVENT_BASE_CHANCE"]
        chance += B["RUN_CHANCE_ESCALATION_PER_TIER"] * float(lots_completed)
        chance += C["HEAT_CHANCE_AT_MAX"] * heat / 100.0
        return min(chance, B["MAXIMUM_RUN_EVENT_CHANCE"])


class Catalog:
    """core/catalog.gd price and gate_of."""

    def __init__(self, tables):
        self.items, self.C = tables["Catalog"]["ITEMS"], tables["Constants"]

    def price(self, item_id):
        entry = self.items.get(item_id)
        if entry is None:
            return -1
        C = self.C
        if "tool" in entry and "tier" in entry:
            tool, tier = entry["tool"], int(entry["tier"])
            if tool not in C["TOOL_PRICES"] or tier < 0 or tier >= len(C["TOOL_TIER_PRICE"]):
                return -1
            base = float(C["TOOL_PRICES"][tool]) * C["TOOL_TIER_PRICE"][tier]
        elif item_id in C["SHOP_PRICES"]:
            base = float(C["SHOP_PRICES"][item_id])
        else:
            return -1
        if entry.get("shop", "") == "snak_o_matic":
            base *= C["VENDING_PRICE_SCALE"]
        return g_round(base)

    def gate_of(self, item_id):
        entry = self.items.get(item_id, {})
        return entry.get("gate", "shop:" + item_id)


# ---------------------------------------------------------------- one crew's campaign

class Game:
    """Everything a run needs that is the same for every run: tables, model, sinks."""

    def __init__(self, tables, model, sinks, enforce_endless):
        self.T, self.M = tables, model
        self.C, self.B = tables["Constants"], tables["Balance"]
        self.econ = Economy(tables)
        self.ranks = self.econ.ranks
        self.seasons = Seasons(tables)
        self.catalog = Catalog(tables)
        self.hoods = tables["Hoods"]["HOODS"]
        self.hood_index = {h["id"]: i for i, h in enumerate(self.hoods)}
        self.personalities = tables["Hoods"]["PERSONALITIES"]
        self.sinks = sinks
        self.live = [s for s in sinks if s.get("status") == "live"]
        self.enforce_endless = enforce_endless
        C = self.C
        self.mph = C["MINUTES_PER_HOUR"]
        # How much of a fresh lot's leaf density each yard size starts with:
        # the even base plus the trees' gaussian heaps (lot_generator._shape_leaves).
        area = (2.0 * C["PAD_HALF"]) ** 2
        spread = sum(C["YARD_TREE_SPREAD"]) / 2.0
        per_tree = C["YARD_TREE_LEAVES"] * 2.0 * math.pi * spread * spread / area
        base = sum(C["YARD_LEAF_BASE"]) / 2.0
        self.cover = []
        for size in range(3):
            trees = sum(C["YARD_TREES"][size]) / 2.0
            self.cover.append(model["leafable_share"] * (base * C["YARD_LEAVES"][size] + trees * per_tree))
        self.travel = model["travel_minutes_by_hood"]["town" if C["TOWN_MAP_DEFAULT"] else "legacy"]
        self.tasks_by_order = list(C["TASK_TOOLS"].keys())


class House:
    __slots__ = ("id", "hood", "hood_i", "size", "standards", "budget_nudge", "likes", "known", "rel",
                 "last_day", "jobs", "referred", "poached")


class Run:
    """One crew of `players` through the campaign with one seed."""

    def __init__(self, game: Game, players: int, seed: int, days_max: int, endless_days: int):
        self.g, self.n = game, players
        self.seed_key = "%d:%d" % (seed, players)
        self.rng = random.Random(self.seed_key)
        self.days_max, self.endless_days = days_max, endless_days
        C = game.C
        self.day = 1
        self.xp = 0
        self.pending = 0
        self.tier = 0
        self.wallets = [0] * players
        self.owned = set()               # crew-shared sink ids
        self.owned_by = [set() for _ in range(players)]
        self.hands = []                  # {skill, wage, earned_today}
        self.heat = 0.0
        self.last_event = -INF           # real minutes
        self.lots_completed = 0
        self.ratings = []
        self.now = 0.0                   # real minutes since the campaign began
        self.day_min = 0.0               # real minutes since 7:00 today
        self.requests = []
        self.daytime_checked = -1
        self.current_house = -1
        self._make_town()
        # Results.
        self.tier_hours = {0: 0.0}
        self.tier_day = {0: 0}
        self.tier_jobs = {0: 0}
        self.jobs = 0
        self.first_night_tier = 0
        self.lawnfather_day = None
        self.cash_by_day = []
        self.income_by_day = []          # per-player gross
        self.tier_by_day = []
        self.jobs_by_day = []
        self.day_binding = {"clock": 0, "requests": 0}
        self.patience_jobs = 0
        self.raids = 0
        self.raid_bands = {"quiet_maple_day": [0, 0], "loud": [0, 0], "mansion_night": [0, 0]}
        self.purchases = {}              # id -> {unlock_day, buy_day, days_of_income}
        self.quits = 0
        self.hire_unlock_day = None
        self.hire_fee_days = None
        self.first_hire_day = None
        self.hand_value_days = []
        self.endless = {"gross": 0.0, "recurring": 0.0, "days": 0}
        self.catalog_days_at_lawnfather = None
        self._today_income = 0.0
        self._today_jobs = 0
        self._today_wages = 0.0
        self._today_recurring = 0.0
        self._hand_earned_today = 0.0

    # ---------------------------------------------------------------- unlocks

    def has_unlock(self, unlock):
        return self.g.ranks.tier_of(unlock) <= self.tier

    def has_perk(self, perk):
        return self.g.ranks.tier_of("perk:" + perk) > 0 and self.has_unlock("perk:" + perk)

    def feature_on(self, feature):
        return self.g.ranks.tier_of("feature:" + feature) > 0 and self.has_unlock("feature:" + feature)

    def owns(self, sink_id):
        return sink_id in self.owned or any(sink_id in mine for mine in self.owned_by)

    def crew_tools(self):
        return {t for t in self.g.C["TOOL_PRICES"] if t in self.owned}

    # ---------------------------------------------------------------- the town (net/town/town.gd)

    def _make_town(self):
        g, rng = self.g, self.rng
        likes_from = g.M["town_inline"]["likes_from"]
        kinds = list(g.personalities.keys())
        self.houses = []
        for hood_i, hood in enumerate(g.hoods):
            for _ in range(int(hood["houses"])):
                sizes = hood["sizes"]
                roll = rng.random()
                size = 0 if roll < sizes[0] else 1 if roll < sizes[0] + sizes[1] else 2
                nudge = g.personalities[kinds[rng.randrange(len(kinds))]]
                lo, hi = hood["standards"]
                house = House()
                house.id, house.hood, house.hood_i, house.size = len(self.houses), hood["id"], hood_i, size
                house.standards = clampf(rng.uniform(lo, hi) + float(nudge["standards"]), 0.0, 1.0)
                house.budget_nudge = float(nudge["budget"])
                house.likes = likes_from[rng.randrange(len(likes_from))]
                house.known, house.rel, house.last_day, house.jobs = False, 0.0, -1, 0
                house.referred, house.poached = False, False
                self.houses.append(house)
        starters = [h for h in self.houses if h.hood == g.hoods[0]["id"]][: g.C["TOWN_STARTING_CLIENTS"]]
        for house in starters:
            house.known = True
            house.rel = g.C["TOWN_START_RELATIONSHIP"]
            self.requests.append(house.id)

    def hood_open(self, hood_id):
        if self.g.hood_index.get(hood_id, -1) <= 0:
            return True
        return self.has_unlock("hood:" + hood_id)

    def mess(self, house):
        return self.g.econ.regrow(self.day - house.last_day, house.last_day < 0)

    def budget(self, house):
        g = self.g
        value = float(g.hoods[house.hood_i]["budget"]) * (1.0 + house.budget_nudge)
        for perk in ("big_spenders", "big_spenders_2"):
            if self.has_perk(perk):
                value *= 1.0 + g.C["BIG_SPENDERS_BUDGET"]
        return value

    def can_do(self, task, size, tools):
        if task == "skim_pool" and size != 2:
            return False
        tool = self.g.C["TASK_TOOLS"].get(task, "")
        return tool == "" or tool in tools

    def choose_tasks(self, size, tools, rng):
        """levels/job_board.gd choose_tasks."""
        C = self.g.C
        chosen = ["rake_leaves"]
        possible, unowned = [], []
        for task in self.g.tasks_by_order:
            if task == "rake_leaves":
                continue
            if task == "skim_pool" and size != 2:
                continue
            tool = C["TASK_TOOLS"][task]
            (possible if tool == "" or tool in tools else unowned).append(task)
        lo, hi = C["JOB_EXTRA_TASKS"]
        count = rng.randint(lo, hi) + int(C["YARD_EXTRA_TASKS"][size])
        wants_unowned = rng.random() < C["JOB_UNOWNED_TASK_CHANCE"]
        pick = rng.getrandbits(32)
        if wants_unowned and unowned:
            chosen.append(unowned[pick % len(unowned)])
        rng.shuffle(possible)
        for task in possible:
            if len(chosen) - 1 >= count:
                break
            chosen.append(task)
        return chosen

    def offer_for(self, house):
        g = self.g
        tools = self.crew_tools()
        # Town.offer_for seeds its RNG with hash([house seed, _day]): a house's job is
        # the same all day however often the crew looks at it, never a fresh re-roll.
        rng = random.Random("%s:offer:%d:%d" % (self.seed_key, house.id, self.day))
        tasks = self.choose_tasks(house.size, tools, rng)
        if house.likes and house.likes not in tasks and self.can_do(house.likes, house.size, tools):
            tasks.append(house.likes)
        season = g.seasons.of_day(self.day)
        favored = g.seasons.favored[season]
        pick = favored[rng.randrange(len(favored))]
        if pick not in tasks and self.can_do(pick, house.size, tools):
            tasks.append(pick)
        return {
            "house": house, "size": house.size, "tasks": tasks, "hood": house.hood, "hood_i": house.hood_i,
            "mess": self.mess(house) * float(g.seasons.leaves[season]),
            "budget": self.budget(house), "standards": house.standards,
            "signs": min(g.C["RIVAL_MAX_SIGNS"], self.poached_in(house.hood)),
        }

    def ask_for_jobs(self, count):
        g, rng = self.g, self.rng
        candidates = []
        for house in self.houses:
            if not house.known or house.poached or house.id in self.requests or house.id == self.current_house:
                continue
            if not self.hood_open(house.hood):
                continue
            mess = self.mess(house)
            if mess < g.C["TOWN_REQUEST_MIN_MESS"]:
                continue
            weight = mess + house.rel / 100.0 + rng.random() * g.M["town_inline"]["request_luck"]
            candidates.append((weight, house.id))
        candidates.sort(key=lambda pair: -pair[0])
        asked = 0
        for _, house_id in candidates:
            if asked >= count:
                break
            self.add_request(house_id)
            asked += 1
        return asked

    def add_request(self, house_id):
        if house_id not in self.requests:
            self.requests.append(house_id)

    def unknown_in(self, hood_id):
        for house in self.houses:
            if house.hood == hood_id and not house.known:
                return house
        return None

    def meet(self, house):
        house.known = True
        house.rel = self.g.C["TOWN_START_RELATIONSHIP"]
        self.add_request(house.id)
        self.add_xp(self.g.C["XP_REFERRAL"])

    def maybe_refer(self, house):
        g = self.g
        needed = g.C["TOWN_REFERRAL_AT"]
        for perk in ("word_of_mouth", "word_of_mouth_2"):
            if self.has_perk(perk):
                needed -= g.M["town_inline"]["word_of_mouth_step"]
        if house.referred or house.rel < needed:
            return
        target = self.unknown_in(house.hood)
        if target is None:
            for hood in g.hoods:
                if self.hood_open(hood["id"]):
                    target = self.unknown_in(hood["id"])
                    if target is not None:
                        break
        if target is None:
            return
        house.referred = True
        self.meet(target)

    def open_new_hoods(self):
        g = self.g
        for hood in g.hoods[1:]:
            if not self.hood_open(hood["id"]):
                continue
            if any(h.hood == hood["id"] and h.known for h in self.houses):
                continue
            target = self.unknown_in(hood["id"])
            if target is not None:
                self.meet(target)

    def poached_in(self, hood_id):
        return sum(1 for h in self.houses if h.hood == hood_id and h.poached)

    def rival_morning(self):
        g, rng = self.g, self.rng
        if not self.feature_on("rival"):
            return
        if rng.random() >= g.C["RIVAL_POACH_CHANCE"]:
            return
        candidates = [h for h in self.houses if h.known and not h.poached and h.id != self.current_house and h.rel < g.C["RIVAL_POACH_BELOW"]]
        if not candidates:
            return
        house = candidates[rng.randrange(len(candidates))]
        house.poached = True
        if house.id in self.requests:
            self.requests.remove(house.id)

    def win_back(self, hood_id):
        for house in self.houses:
            if house.hood == hood_id and house.poached:
                house.poached = False
                house.rel = max(house.rel, self.g.C["TOWN_START_RELATIONSHIP"])
                self.add_xp(self.g.C["XP_WON_BACK"])
                self.add_request(house.id)
                return

    def town_job_finished(self, house, stars):
        g = self.g
        first_time = house.jobs == 0
        if stars > 0:
            house.rel = g.econ.relationship_after(house.rel, stars)
        house.jobs += 1
        house.last_day = self.day
        if house.id in self.requests:
            self.requests.remove(house.id)
        bonus = 0
        if first_time:
            self.add_xp(g.C["XP_NEW_CLIENT"])
            bonus += g.C["XP_NEW_CLIENT"]
        self.maybe_refer(house)
        if stars >= 4 and self.poached_in(house.hood) > 0 and self.rng.random() < g.C["RIVAL_WIN_BACK_CHANCE"]:
            self.win_back(house.hood)
        return bonus

    def town_new_day(self):
        g = self.g
        for house_id in self.requests:
            house = self.houses[house_id]
            house.rel = max(0.0, house.rel - g.C["TOWN_RELATIONSHIP_MISSED"])
        self.requests = []
        self.daytime_checked = -1
        self.open_new_hoods()
        self.rival_morning()
        self.ask_for_jobs(self.requests_per_day())
        if not self.requests:
            for hood in g.hoods:
                if not self.hood_open(hood["id"]):
                    continue
                lead = self.unknown_in(hood["id"])
                if lead is not None:
                    self.meet(lead)
                    break

    def requests_per_day(self):
        count = self.g.C["TOWN_REQUESTS_PER_DAY"]
        for perk in ("extra_request", "extra_request_2", "extra_request_3"):
            if self.has_perk(perk):
                count += 1
        return count

    def daytime_texts(self):
        C = self.g.C
        hour = self.hour()
        for slot, at in enumerate(C["TOWN_DAYTIME_TEXT_HOURS"]):
            if slot > self.daytime_checked and hour >= at:
                self.daytime_checked = slot
                if self.rng.random() < C["TOWN_DAYTIME_TEXT_CHANCE"]:
                    self.ask_for_jobs(1)

    # ---------------------------------------------------------------- the clock

    def hour(self):
        C = self.g.C
        return C["DAY_START_HOUR"] + min(self.day_min / self.g.mph, C["DAY_CLOSE_HOUR"] - C["DAY_START_HOUR"])

    def advance(self, minutes):
        self.now += minutes
        self.day_min += minutes

    def add_xp(self, amount):
        if amount > 0:
            self.pending += amount

    # ---------------------------------------------------------------- the crew's gear

    def crew_effects(self):
        """Leaf-rate multipliers and tool tiers from what the crew owns."""
        rake_mult, leaf_mult, blower = 1.0, 1.0, False
        speed, noise = {}, {}
        for sink in self.g.live:
            if not self.owns(sink["id"]):
                continue
            effect = sink["effect"]
            if effect.get("blower"):
                blower = True
            if "rake_mult" in effect:
                rake_mult = max(rake_mult, effect["rake_mult"])
            if "leaf_rate_mult" in effect:
                leaf_mult *= effect["leaf_rate_mult"]
            if "tool" in effect:
                tool = effect["tool"]
                speed[tool] = max(speed.get(tool, 1.0), effect.get("speed", 1.0))
                noise[tool] = min(noise.get(tool, 1.0), effect.get("heat_mult", 1.0))
        return rake_mult, leaf_mult, blower, speed, noise

    def leaf_rate(self, crew, effects):
        M = self.g.M
        rake_mult, leaf_mult, blower, _, _ = effects
        index = int(clampf(crew, 1, len(M["leaf_rate_yard_per_min"]))) - 1
        rate = M["leaf_rate_yard_per_min"][index]
        share = M["rake_share"][index]
        rate *= 1.0 + (rake_mult - 1.0) * share
        rate *= leaf_mult
        if blower:
            rate *= M["blower_bonus"][index]
        return rate

    def hands_rate(self):
        return sum(self.g.M["hand_leaf_rate"] * hand["skill"] for hand in self.hands)

    # ---------------------------------------------------------------- a job

    def plan(self, offer, cleaned, effects):
        """Minutes of work and what it achieves, done to the crew's target."""
        g, M, C, n = self.g, self.g.M, self.g.C, self.n
        size = offer["size"]
        mess = clampf(offer["mess"] * g.econ.crew_work_scale(n), 0.0, 1.5)
        leaf_units = g.cover[size] * mess / g.cover[1] * cleaned
        hands = self.hands_rate()
        rate_n = self.leaf_rate(n, effects) + hands
        rate_1 = self.leaf_rate(1, effects) + hands
        leaf_n = leaf_units / rate_n if rate_n > 0 else 0.0
        leaf_1 = leaf_units / rate_1 if rate_1 > 0 else 0.0
        tools = self.crew_tools()
        speed, noise_mult = effects[3], effects[4]
        tasks, task_minutes, noise_seconds = [], 0.0, {}
        for task in offer["tasks"]:
            if task not in C["TASK_PAY"]:
                continue
            doable = self.can_do(task, size, tools)
            minutes = 0.0
            if doable:
                tool = C["TASK_TOOLS"].get(task, "")
                minutes = M["task_person_minutes"].get(task, 2.5) * M["task_size_scale"][size] / M["utilization"]
                minutes /= speed.get(tool, 1.0)
                task_minutes += minutes * M["task_done_target"]
                if task in M["noise_by_task"]:
                    spec = M["noise_by_task"][task]
                    noise_seconds[spec["tool"]] = noise_seconds.get(spec["tool"], 0.0) + minutes * 60.0 * spec["share"]
            tasks.append((task, M["task_done_target"] if doable else 0.0))
        if effects[2]:
            noise_seconds["leaf_blower"] = noise_seconds.get("leaf_blower", 0.0) + leaf_n * 60.0 * M["blower_use_share"]
        work = max(leaf_n, (leaf_1 + task_minutes) / n) if n > 1 else leaf_1 + task_minutes
        yard_value = float(g.B["CREDITS_PER_1_PERCENT_LOT_CLEANUP"]) * 100.0 * g.cover[size] * mess
        hand_share = hands / rate_n if rate_n > 0 else 0.0
        return {"work": work, "cleaned": cleaned, "tasks": tasks, "noise": noise_seconds, "noise_mult": noise_mult,
                "yard_value": yard_value, "hand_share": hand_share}

    def scaled(self, plan, share):
        out = dict(plan)
        out["work"] = plan["work"] * share
        out["cleaned"] = plan["cleaned"] * share
        out["tasks"] = [(task, done * share) for task, done in plan["tasks"]]
        out["noise"] = {tool: seconds * share for tool, seconds in plan["noise"].items()}
        return out

    def patience(self):
        C = self.g.C
        patience = C["HOMEOWNER_PATIENCE_MINUTES"]
        if self.has_perk("sweet_talk"):
            patience *= C["SWEET_TALK_PATIENCE"]
        return patience * self.g.econ.crew_patience_scale(self.n)

    def judge_clean(self, plan, standards):
        """homeowner._judge: how done the whole job is, leaves and tasks weighed alike."""
        econ = self.g.econ
        clean_enough = econ.clean_enough_at(standards)
        messy_below = econ.messy_below_at(standards)
        parts = [clampf(plan["cleaned"] / clean_enough, 0.0, 1.0)] + [done for _, done in plan["tasks"]]
        return sum(parts) / len(parts) * clean_enough, clean_enough, messy_below

    def mood_odds(self, clean, clean_enough, messy_below, slow):
        """The chance of each mood (homeowner._judge, with its inline surprise rolls)."""
        C, M = self.g.C, self.g.M["homeowner_inline"]
        if clean < messy_below:
            base = {"messy": 1.0}
        elif slow:
            base = {"slow": 1.0}
        elif clean >= clean_enough:
            base = {"thrilled": C["HOMEOWNER_THRILLED_CHANCE"], "happy": 1.0 - C["HOMEOWNER_THRILLED_CHANCE"]}
        else:
            base = {"happy": C["HOMEOWNER_HAPPY_CHANCE"], "fine": 1.0 - C["HOMEOWNER_HAPPY_CHANCE"]}
        good, bad = M["surprise_good_below"], 1.0 - M["surprise_bad_above"]
        odds = {mood: p * (1.0 - good - bad) for mood, p in base.items()}
        for mood in ("happy", "thrilled"):
            odds[mood] = odds.get(mood, 0.0) + good / 2.0
        for mood in ("slow", "fine"):
            odds[mood] = odds.get(mood, 0.0) + bad / 2.0
        return odds

    def raw_value(self, plan):
        """Bags in Chefty (capped by the truck) and the tasks' share of TASK_PAY."""
        g, C, M = self.g, self.g.C, self.g.M
        perks = sum(1 for p in ("bag_bonus", "bag_bonus_2", "bag_bonus_3") if self.has_perk(p))
        bonus = g.econ.bag_bonus(perks)
        bags = min(plan["yard_value"] * plan["cleaned"] * M["bag_efficiency"], C["TRUCK_BAG_CAPACITY"] * M["bag_value_avg"])
        bag_value = int(g_round(bags * bonus))
        task_value = sum(int(g_round(float(C["TASK_PAY"][task]) * done)) for task, done in plan["tasks"])
        return bag_value, task_value

    def expected_pay(self, plan, offer, minutes_on_clock):
        C = self.g.C
        clean, enough, messy = self.judge_clean(plan, offer["standards"])
        slow = minutes_on_clock > self.patience()
        odds = self.mood_odds(clean, enough, messy, slow)
        mult = sum(p * float(C["HOMEOWNER_PAY_BY_MOOD"].get(mood, 1.0)) for mood, p in odds.items())
        bag_value, task_value = self.raw_value(plan)
        return (bag_value + task_value) * mult * offer["budget"]

    def overhead(self, offer):
        M = self.g.M
        return M["store_minutes_per_job"] + M["job_overhead_minutes"] + self.g.travel[offer["hood_i"]]

    def choose(self, offer, effects, cleaned):
        """The plan the crew goes with: finish, or wrap up at the patience line."""
        M = self.g.M
        full = self.plan(offer, cleaned, effects)
        arrive = M["arrive_to_work_minutes"]
        extra = self.overhead(offer) + offer["signs"] * M["sign_minutes"]
        best = (self.expected_pay(full, offer, full["work"] + arrive) / (full["work"] + extra), full, False)
        patience = self.patience()
        if full["work"] + arrive > patience and M["rush_policy"] == "best_pay_per_minute":
            share = clampf((patience - arrive - 0.1) / full["work"], 0.3, 1.0)
            rushed = self.scaled(full, share)
            value = self.expected_pay(rushed, offer, rushed["work"] + arrive) / (rushed["work"] + extra)
            if value > best[0]:
                best = (value, rushed, True)
        return best

    def pick_offer(self, effects):
        best, best_value = None, -1.0
        for house_id in self.requests:
            offer = self.offer_for(self.houses[house_id])
            value, _, _ = self.choose(offer, effects, self.g.M["clean_target"])
            if value > best_value:
                best, best_value = offer, value
        return best

    def heat_and_raids(self, plan, offer):
        """director._consider_roll every HEAT_ROLL_SECONDS while the crew works, with
        heat.gd's noise and cooling. Returns (extra minutes the raids cost, raids)."""
        g, C, B, M = self.g, self.g.C, self.g.B, self.g.M
        work_s = plan["work"] * 60.0
        if work_s <= 0:
            return 0.0, 0
        dt = C["HEAT_ROLL_SECONDS"]
        # The loud tools run in one stretch once the job is under way, as many at
        # once as there are players to run them; the rest of the job is quiet and cools.
        heat_total, noisy, tools = 0.0, 0.0, 0
        for tool, seconds in plan["noise"].items():
            if seconds <= 0:
                continue
            heat_total += C["HEAT_NOISE_PER_SECOND"].get(tool, 0.0) * plan["noise_mult"].get(tool, 1.0) * seconds
            noisy += seconds
            tools += 1
        gate = work_s * clampf(C["RUN_PROGRESS_FRACTION"] / max(plan["cleaned"], 0.05), 0.0, 1.0)
        loud_for = min(noisy / max(1, min(self.n, tools)), work_s) if tools else 0.0
        loud_from = min(gate, work_s - loud_for)
        loud_rate = heat_total / loud_for if loud_for > 0 else 0.0
        cool = C["HEAT_COOL_PER_SECOND"]
        for perk in ("cool_heads", "cool_heads_2"):
            if self.has_perk(perk):
                cool *= C["COOL_HEADS_COOLING"]
        hood_heat = float(g.hoods[offer["hood_i"]]["heat"])
        raid = M["raid"]
        # done: seconds of work done; lost: seconds the raids cost on top. The
        # director rolls (and the tools run) only while the crew is working.
        done, lost, raids = 0.0, 0.0, 0
        start_now, start_day = self.now, self.day_min
        while done < work_s:
            step = min(dt, work_s - done)
            elapsed = done + lost
            hour = C["DAY_START_HOUR"] + (start_day + elapsed / 60.0) / g.mph
            scale = hood_heat * (C["QUIET_HOURS_HEAT_SCALE"] if hour >= C["QUIET_HOURS_START"] else 1.0)
            loud = max(0.0, min(done + step, loud_from + loud_for) - max(done, loud_from))
            self.heat = clampf(self.heat + loud_rate * scale * loud - cool * (step - loud), 0.0, 100.0)
            done += step
            if done < gate:
                continue
            at = start_now + (done + lost) / 60.0
            since = (at - self.last_event) * 60.0
            if since < B["RUN_EVENT_COOLDOWN_MINUTES"] * 60.0 * (1.0 - self.heat / 100.0):
                continue
            chance = g.econ.run_roll_chance(self.heat, self.lots_completed)
            if self.heat >= C["HEAT_RAID_AT"] or self.rng.random() < chance:
                raids += 1
                self.last_event = at
                caught = sum(1 for _ in range(self.n) if self.rng.random() < raid["capture_chance"])
                lost += (raid["chase_minutes"] + caught * raid["border_return_minutes"] / self.n) * 60.0
                self.heat = min(self.heat, C["HEAT_AFTER_RAID"])
        return lost / 60.0, raids

    def do_job(self, offer, effects):
        g, C, M, rng = self.g, self.g.C, self.g.M, self.rng
        cleaned = clampf(rng.gauss(M["clean_target"], M["clean_noise"]), 0.5, 1.0)
        _, plan, rushed = self.choose(offer, effects, cleaned)
        house = offer["house"]
        self.current_house = house.id
        travel = g.travel[offer["hood_i"]]
        self.advance(M["store_minutes_per_job"] + M["job_overhead_minutes"] / 2.0 + travel / 2.0)
        start_hour = self.hour()
        quiet_start = start_hour >= C["QUIET_HOURS_START"]
        extra, raids = self.heat_and_raids(plan, offer)
        signs = offer["signs"]
        work = plan["work"] + extra + signs * M["sign_minutes"]
        self.advance(work)
        on_clock = work + M["arrive_to_work_minutes"]
        if on_clock > self.patience() or rushed:
            self.patience_jobs += 1
        # The homeowner (npcs/homeowner.gd _handle_talk and _judge).
        clean, enough, messy = self.judge_clean(plan, offer["standards"])
        odds = self.mood_odds(clean, enough, messy, on_clock > self.patience())
        roll, mood = rng.random(), "fine"
        for name, p in odds.items():
            roll -= p
            mood = name
            if roll <= 0:
                break
        bag_value, task_value = self.raw_value(plan)
        water = 0
        if any(task == "wash_windows" and done > 0 for task, done in plan["tasks"]) and rng.random() < M["water"]["spigot_share"]:
            water = int(g_round(C["SPIGOT_HOOKUP_FEE"] + C["SPIGOT_FEE_PER_SECOND"] * M["water"]["hose_spray_seconds"]))
        bills = int(g_round(M["bills"]["mean"])) if rng.random() < M["bills"]["chance"] else 0
        if bag_value + task_value <= 0:
            mood = "nothing"
        paid = g.econ.job_pay(bag_value, task_value, mood, offer["budget"], water, bills)
        stars = int(C["MOOD_STARS"].get(mood, 0))
        # Campaign.finish_job: bonuses, XP, the town, the split.
        bonus = g.ranks.pay_bonus(self.tier)
        season = g.seasons.of_day(self.day)
        bonus += float(g.seasons.pay_bonus[season])
        if self.hour() >= C["QUIET_HOURS_START"]:
            bonus += C["QUIET_HOURS_PAY_BONUS"]
            for perk in ("night_owl", "night_owl_2"):
                if self.has_perk(perk):
                    bonus += C["NIGHT_OWL_PAY_BONUS"]
        pool = float(paid)
        if bonus > 0.0 and pool > 0.0:
            pool *= 1.0 + bonus
        self.add_xp(g.econ.job_xp(plan["cleaned"], [done for _, done in plan["tasks"]], stars, self.n))
        self.town_job_finished(house, stars)
        if signs > 0:
            for _ in range(signs):
                self.add_xp(C["XP_SIGN_PULLED"])
            if self.poached_in(house.hood) > 0:
                self.win_back(house.hood)
        share = 1.0 / self.n
        for index in range(self.n):
            self.wallets[index] += int(g_round(pool * share))
        self._today_income += pool / self.n
        self._today_jobs += 1
        self._hand_earned_today += bag_value * plan["hand_share"]
        self.lots_completed += 1
        self.jobs += 1
        self.heat = max(0.0, self.heat - C["HEAT_COOL_PER_JOB"])
        self.current_house = -1
        self.advance(M["job_overhead_minutes"] / 2.0 + travel / 2.0)
        self.raids += raids
        tools_used = plan["noise"]
        loud = tools_used.get("lawn_mower", 0) > 0 and tools_used.get("leaf_blower", 0) > 0
        if offer["hood_i"] == 0 and not quiet_start and not tools_used:
            self._band("quiet_maple_day", raids)
        if loud:
            self._band("loud", raids)
        if offer["hood"] == g.hoods[-1]["id"] and quiet_start:
            self._band("mansion_night", raids)
        self.consumables(plan, bag_value)

    def _band(self, band, raids):
        self.raid_bands[band][0] += 1
        self.raid_bands[band][1] += 1 if raids > 0 else 0

    def consumables(self, plan, bag_value):
        for sink in self.g.live:
            if sink["kind"] != "consumable" or not self.gates_ok(sink):
                continue
            if sink.get("uses") == "bags":
                units = bag_value / self.g.M["bag_value_avg"] / max(sink.get("per_unit", 1.0), 1.0)
            else:
                units = float(sink.get("uses_per_job", 0.0))
            cost = int(g_round(units * sink["price"]))
            if cost > 0:
                self.spend_crew(cost)
                self._today_recurring += cost

    def spend_crew(self, amount):
        """Shared costs come out of the richest wallets first."""
        left = amount
        for index in sorted(range(self.n), key=lambda i: -self.wallets[i]):
            paid = min(left, self.wallets[index])
            self.wallets[index] -= paid
            left -= paid
            if left <= 0:
                break

    # ---------------------------------------------------------------- the shops and hires

    def gates_ok(self, sink):
        for gate in sink["gate"]:
            kind, _, rest = gate.partition(":")
            if kind == "unlock" and not self.has_unlock(rest):
                return False
            if kind == "tier" and self.tier < int(rest):
                return False
            if kind == "after" and not self.owns(rest):
                return False
        return True

    def income_per_day(self):
        """A player's gross per day, over the last two days (today's so far on day 1)."""
        recent = self.income_by_day[-2:]
        if not recent:
            return max(self._today_income, 1.0)
        return max(sum(recent) / len(recent), 1.0)

    def wages(self):
        return sum(hand["wage"] for hand in self.hands)

    def shop(self):
        g, M = self.g, self.g.M
        hours = g.C["SHOP_HOURS"]["homie_depot"]
        if not (hours[0] <= self.hour() < hours[1]):
            return
        policy = M["buy_policy"]
        income = self.income_per_day()
        for kind in policy["order"]:
            for sink in g.live:
                if sink["kind"] != kind:
                    continue
                record = self.purchases.setdefault(sink["id"], {"unlock_day": None, "buy_day": None, "days_of_income": None})
                if not self.gates_ok(sink):
                    continue
                if record["unlock_day"] is None:
                    record["unlock_day"] = self.day
                    record["days_of_income"] = sink["price"] / income
                reserve = policy["reserve_days_of_wages"] * self.wages() / self.n
                if sink.get("want") in ("endless", "cosmetic"):
                    reserve += policy["endless_buffer_days"] * income
                if sink.get("per_player"):
                    for index in range(self.n):
                        if sink["id"] not in self.owned_by[index] and self.wallets[index] - sink["price"] >= reserve:
                            self.wallets[index] -= sink["price"]
                            self.owned_by[index].add(sink["id"])
                            if record["buy_day"] is None:
                                record["buy_day"] = self.day
                elif not self.owns(sink["id"]):
                    buyer = max(range(self.n), key=lambda i: self.wallets[i])
                    if self.wallets[buyer] - sink["price"] >= reserve:
                        self.wallets[buyer] -= sink["price"]
                        self.owned.add(sink["id"])
                        record["buy_day"] = self.day

    def hire_slots(self):
        if not self.feature_on("hiring"):
            return 0
        return 1 + sum(1 for p in ("hire_slot_2", "hire_slot_3", "hire_slot_4") if self.has_perk(p))

    def hire(self):
        g, C, M = self.g, self.g.C, self.g.M
        if not any(s["kind"] == "wage" for s in g.live):
            return
        if self.hire_slots() == 0:
            return
        if self.hire_unlock_day is None:
            self.hire_unlock_day = self.day
            self.hire_fee_days = C["HIRE_SIGNING_FEE"] / self.income_per_day()
        policy = M["hire_policy"]
        while len(self.hands) < self.hire_slots():
            fee = C["HIRE_SIGNING_FEE"]
            if fee > policy["max_fee_days"] * self.income_per_day():
                return
            buyer = max(range(self.n), key=lambda i: self.wallets[i])
            reserve = policy["reserve_days_of_wages"] * (self.wages() + C["HIRE_DAILY_WAGE"])
            if self.wallets[buyer] - fee < reserve / self.n:
                return
            self.wallets[buyer] -= fee
            lo, hi = C["HIRE_SKILL"]
            self.hands.append({"skill": self.rng.uniform(lo, hi), "wage": C["HIRE_DAILY_WAGE"]})
            if self.first_hire_day is None:
                self.first_hire_day = self.day

    def pay_wages(self):
        """net/crew/hires.gd pay_wages."""
        if not self.hands:
            return 0
        total = self.wages()
        cash = sum(self.wallets)
        while total > cash and self.hands:
            leaving = self.hands.pop()
            total -= leaving["wage"]
            self.quits += 1
        if total > 0:
            owed = total
            share = int(math.ceil(float(total) / float(self.n)))
            for index in range(self.n):
                paid = min(share, min(owed, self.wallets[index]))
                self.wallets[index] -= paid
                owed -= paid
            for index in range(self.n):
                if owed <= 0:
                    break
                paid = min(owed, self.wallets[index])
                self.wallets[index] -= paid
                owed -= paid
        return total

    # ---------------------------------------------------------------- days

    def play_day(self):
        g, C, M = self.g, self.g.C, self.g.M
        self.day_min = 0.0
        self._today_income = 0.0
        self._today_jobs = 0
        self._today_wages = 0.0
        self._today_recurring = 0.0
        self._hand_earned_today = 0.0
        cutoff = M["start_job_cutoff_hour"]
        binding = "requests"
        while True:
            self.daytime_texts()
            if self.hour() >= cutoff:
                binding = "clock" if self.requests else "requests"
                break
            self.shop()
            self.hire()
            if not self.requests:
                if self.hour() >= C["SLEEP_FROM_HOUR"]:
                    break
                pending = [at for slot, at in enumerate(C["TOWN_DAYTIME_TEXT_HOURS"]) if slot > self.daytime_checked and at < C["SLEEP_FROM_HOUR"]]
                if M["wait_for_texts"] and pending:
                    self.advance((min(pending) - self.hour()) * g.mph)
                    continue
                self.advance(max(0.0, (C["SLEEP_FROM_HOUR"] - self.hour()) * g.mph))
                break
            effects = self.crew_effects()
            offer = self.pick_offer(effects)
            self.do_job(offer, effects)
        self.day_binding[binding] += 1
        self.now += M["day_overhead_minutes"]
        day_minutes = self.day_min + M["day_overhead_minutes"]
        self.sleep(day_minutes)

    def sleep(self, day_minutes):
        """DayClock._end_day: bank the XP, payroll, the town's new day."""
        g = self.g
        before = self.tier
        self.xp += self.pending
        self.pending = 0
        self.tier = g.ranks.tier_for_xp(self.xp)
        hours = self.now / 60.0
        for tier in range(before + 1, self.tier + 1):
            self.tier_hours[tier] = hours
            self.tier_day[tier] = self.day
            self.tier_jobs[tier] = self.jobs
        if self.day == 1:
            self.first_night_tier = self.tier
        wages = self.pay_wages()
        rent = 0.0
        for sink in g.live:
            if sink["kind"] == "property" and self.owns(sink["id"]):
                rent += sink.get("rent_per_day", 0.0)
        if rent > 0:
            self.spend_crew(int(g_round(rent)))
        recurring = wages + rent + self._today_recurring
        if self.hands:
            self.hand_value_days.append(self._hand_earned_today / len(self.hands))
        self.cash_by_day.append(sum(self.wallets) / self.n)
        self.income_by_day.append(self._today_income)
        self.tier_by_day.append(self.tier)
        self.jobs_by_day.append(self._today_jobs)
        if self.lawnfather_day is not None:
            self.endless["gross"] += self._today_income * self.n
            self.endless["recurring"] += recurring
            self.endless["days"] += 1
        elif self.tier >= g.ranks.last:
            self.lawnfather_day = self.day
            self.catalog_days_at_lawnfather = self.catalog_days()
        # DayClock._end_day calls town.on_new_day(day + 1), which sets the town's day
        # first: the morning's requests, mess and season are the new day's.
        self.day += 1
        self.town_new_day()

    def catalog_days(self):
        """What's left to buy at The Lawnfather, in days of the crew's net income."""
        value = 0.0
        for sink in self.g.sinks:
            if sink["kind"] in ("wage", "consumable"):
                continue
            if sink.get("per_player"):
                value += sink["price"] * sum(1 for mine in self.owned_by if sink["id"] not in mine)
            elif not self.owns(sink["id"]):
                value += sink["price"]
        recent = self.income_by_day[-3:]
        net = sum(recent) / max(1, len(recent)) * self.n - self.wages()
        return value / max(net, 1.0)

    def play(self):
        while self.day <= self.days_max:
            self.play_day()
            if self.lawnfather_day is not None and self.endless["days"] >= self.endless_days:
                break
        return self


# ---------------------------------------------------------------- many runs, one summary

def simulate(game: Game, crews, seeds, days_max, endless_days):
    out = {}
    for players in crews:
        runs = [Run(game, players, seed, days_max, endless_days).play() for seed in range(seeds)]
        out[str(players)] = summarize(game, players, runs)
    return out


def summarize(game: Game, players, runs):
    ranks = game.ranks
    last = ranks.last
    tier_hours = []
    for tier in range(last + 1):
        tier_hours.append(median([r.tier_hours.get(tier, INF) for r in runs]))
    rank_hours = {}
    for rank in range(len(ranks.names) + 1):
        tier = rank * ranks.per_rank
        name = ranks.names[rank] if rank < len(ranks.names) else "The Lawnfather"
        values = [r.tier_hours.get(tier, INF) for r in runs]
        rank_hours[name] = {"p10": percentile(values, 10), "p50": percentile(values, 50), "p90": percentile(values, 90)}
    days_tier = []
    for tier in range(1, last + 1):
        diffs = []
        for r in runs:
            if tier in r.tier_day and (tier - 1) in r.tier_day:
                diffs.append(r.tier_day[tier] - r.tier_day[tier - 1])
            else:
                diffs.append(INF)
        days_tier.append(median(diffs))
    # Days at least half the runs played (later days are the slowest runs only).
    longest_day = sorted(len(r.cash_by_day) for r in runs)[len(runs) // 2]
    cash = []
    for day in range(longest_day):
        values = [r.cash_by_day[day] for r in runs if day < len(r.cash_by_day)]
        cash.append(round(median(values), 1))
    income_by_rank = {}
    for rank in range(len(ranks.names) + 1):
        values = []
        for r in runs:
            for day in range(len(r.tier_by_day)):
                # Income earned on a day belongs to the rank the crew had that day.
                had = r.tier_by_day[day - 1] if day > 0 else 0
                if min(had // ranks.per_rank, len(ranks.names)) == rank:
                    values.append(r.income_by_day[day])
        name = ranks.names[rank] if rank < len(ranks.names) else "The Lawnfather"
        income_by_rank[name] = round(median(values), 1) if values else None
    purchases = {}
    for sink in game.live:
        if sink["kind"] in ("wage", "consumable"):
            continue
        unlock = [r.purchases.get(sink["id"], {}).get("unlock_day") for r in runs]
        buy = [r.purchases.get(sink["id"], {}).get("buy_day") for r in runs]
        doi = [r.purchases.get(sink["id"], {}).get("days_of_income") for r in runs]
        delays = [(b - u) if (u is not None and b is not None) else INF for u, b in zip(unlock, buy) if u is not None]
        purchases[sink["id"]] = {
            "price": sink["price"],
            "unlock_day": median([u for u in unlock if u is not None]) if any(u is not None for u in unlock) else None,
            "buy_day_p50": median([b if b is not None else INF for b in buy]) if any(u is not None for u in unlock) else None,
            "buy_delay_p50": median(delays) if delays else None,
            "days_of_income": round(median([d for d in doi if d is not None]), 3) if any(d is not None for d in doi) else None,
        }
    day_total = sum(sum(r.day_binding.values()) for r in runs) or 1
    jobs_total = sum(r.jobs for r in runs) or 1
    bands = {}
    for band in ("quiet_maple_day", "loud", "mansion_night"):
        jobs = sum(r.raid_bands[band][0] for r in runs)
        raided = sum(r.raid_bands[band][1] for r in runs)
        bands[band] = {"jobs": jobs, "raided_share": (raided / jobs) if jobs else None}
    endless_shares = [r.endless["recurring"] / r.endless["gross"] for r in runs if r.endless["gross"] > 0]
    lawnfather_days = [r.lawnfather_day if r.lawnfather_day is not None else INF for r in runs]
    lawnfather_jobs = [r.tier_jobs.get(last, INF) for r in runs]
    jobs_per_day = [statistics.mean(r.jobs_by_day[: r.lawnfather_day or len(r.jobs_by_day)]) for r in runs if r.jobs_by_day]
    hire_fee_days = [r.hire_fee_days for r in runs if r.hire_fee_days is not None]
    hire_delay = [(r.first_hire_day - r.hire_unlock_day) if r.first_hire_day is not None else INF for r in runs if r.hire_unlock_day is not None]
    hand_days = [v for r in runs for v in r.hand_value_days]
    return {
        "players": players,
        "seeds": len(runs),
        "tier_hours": [round(h, 3) if h != INF else None for h in tier_hours],
        "rank_hours": {k: {q: (round(v, 3) if v != INF else None) for q, v in d.items()} for k, d in rank_hours.items()},
        "days_per_tier": [d if d != INF else None for d in days_tier],
        "days_to_lawnfather": _finite(median(lawnfather_days)),
        "jobs_to_lawnfather": _finite(median(lawnfather_jobs)),
        "jobs_per_day": round(median(jobs_per_day), 2) if jobs_per_day else None,
        "first_night_tier_p50": median([r.first_night_tier for r in runs]),
        "first_night_share": sum(1 for r in runs if r.first_night_tier >= 1) / len(runs),
        "cash_per_player_by_day": cash,
        "income_per_day_by_rank": income_by_rank,
        "purchases": purchases,
        "binding": {
            "clock": sum(r.day_binding["clock"] for r in runs) / day_total,
            "requests": sum(r.day_binding["requests"] for r in runs) / day_total,
            "patience": sum(r.patience_jobs for r in runs) / jobs_total,
        },
        "raids_per_job": sum(r.raids for r in runs) / jobs_total,
        "raid_bands": bands,
        "hire": {
            "fee_days_at_unlock": round(median(hire_fee_days), 3) if hire_fee_days else None,
            "hire_delay_days_p50": _finite(median(hire_delay)) if hire_delay else None,
            "quits": sum(r.quits for r in runs),
            "hand_value_per_day_p50": round(median(hand_days), 1) if hand_days else None,
        },
        "recurring_sink_share_endless": round(median(endless_shares), 4) if endless_shares else None,
        "catalog_days_at_lawnfather": _finite(median([r.catalog_days_at_lawnfather for r in runs if r.catalog_days_at_lawnfather is not None] or [INF])),
        "_lawnfather_hours": [r.tier_hours.get(last, INF) for r in runs],
    }


def _finite(value):
    return None if value is None or value == INF else round(value, 3)


# ---------------------------------------------------------------- checks

def run_checks(game: Game, crews: dict, parity, strict: bool, self_problems=()) -> list:
    """Every check. baseline_ok marks the tuning checks --baseline may excuse; the
    integrity checks (engine parity, the self-test) always fail the exit code."""
    C, T = game.C, game.M["targets"]
    checks = []

    def add(name, ok, value, limit, blocking=True, baseline_ok=True):
        checks.append({"name": name, "ok": bool(ok), "value": value, "limit": limit,
                       "blocking": bool(blocking or strict), "baseline_ok": bool(baseline_ok)})

    add("self-test: sink prices equal Catalog.price", not self_problems, len(self_problems), 0, baseline_ok=False)

    arc = C["ARC_HOURS"]
    last_name = "The Lawnfather"
    for key in ("1", "4"):
        if key not in crews:
            continue
        hours = crews[key]["rank_hours"][last_name]["p50"]
        add("(a) arc hours, crew %s" % key, hours is not None and arc[0] <= hours <= arc[1], hours, list(arc))
        share = crews[key]["first_night_share"]
        add("(b) first rank-up on night 1, crew %s" % key, share >= T["first_night_share"], round(share, 3), ">= %s of seeds" % T["first_night_share"])
        for tool in C["TOOL_PRICES"]:
            info = crews[key]["purchases"].get(tool)
            if info is None:
                continue
            delay, doi = info["buy_delay_p50"], info["days_of_income"]
            ok = delay is not None and delay != INF and delay <= T["buy_within_days"] and doi is not None and T["price_days"][0] <= doi <= T["price_days"][1]
            add("(c) %s bought and priced right, crew %s" % (tool, key), ok,
                {"buy_delay_days": _finite(delay), "days_of_income": doi},
                {"buy_within_days": T["buy_within_days"], "days_of_income": T["price_days"]})
        hire = crews[key]["hire"]
        if hire["fee_days_at_unlock"] is not None:
            delay = hire["hire_delay_days_p50"]
            ok = hire["fee_days_at_unlock"] <= T["hire_fee_max_days"] and delay is not None and delay <= T["hire_within_days"] and hire["quits"] == 0
            add("(d) hiring affordable and nobody quits, crew %s" % key, ok,
                {"fee_days": hire["fee_days_at_unlock"], "hire_delay_days": delay, "quits": hire["quits"]},
                {"fee_days": T["hire_fee_max_days"], "hire_within_days": T["hire_within_days"], "quits": 0})
        per_tier = [d if d is not None else INF for d in crews[key]["days_per_tier"]]
        worst = max(per_tier) if per_tier else INF
        add("(e) days per tier before The Lawnfather, crew %s" % key, worst <= T["max_days_per_tier"], _finite(worst), T["max_days_per_tier"])
        if game.enforce_endless:
            share = crews[key]["recurring_sink_share_endless"]
            band = T["endless_recurring_share"]
            add("(g) endless recurring sinks, crew %s" % key, share is not None and band[0] <= share <= band[1], share, band)
            days = crews[key]["catalog_days_at_lawnfather"]
            add("(g) endless catalog left, crew %s" % key, days is not None and days >= T["endless_catalog_days"], days, T["endless_catalog_days"])
    if parity is not None:
        add("(f) engine parity: constants", not parity["constant_mismatches"], len(parity["constant_mismatches"]), 0, baseline_ok=False)
        # A case for a function the sim has no mirror of is drift too: the engine
        # grew a formula that the sim can't follow.
        add("(f) engine parity: formulas", not parity["case_mismatches"] and not parity["unknown_functions"] and parity["cases"] > 0,
            {"cases": parity["cases"], "mismatches": len(parity["case_mismatches"]), "unmirrored": parity["unknown_functions"]}, 0,
            baseline_ok=False)
        # The engine's own rules about the tables (net/dev/balance_test.gd invariants).
        add("(f) engine invariants (--balance-test ok)", parity["engine_ok"] is True,
            {"failed": parity["failed_invariants"]}, True, baseline_ok=False)

    # Warnings (blocking with --strict).
    pace = C["RANK_PACE_HOURS"]
    names = list(game.ranks.names) + [last_name]
    for key, crew in crews.items():
        for rank in range(1, len(names)):
            target = pace[rank] if rank < len(pace) else None
            hours = crew["rank_hours"][names[rank]]["p50"]
            if target:
                ok = hours is not None and abs(hours - target) <= T["pace_band"] * target
                add("pace %s, crew %s" % (names[rank], key), ok, hours, [round(target * (1 - T["pace_band"]), 2), round(target * (1 + T["pace_band"]), 2)], blocking=False)
        lf = crew["rank_hours"][last_name]
        ok = lf["p10"] is not None and lf["p90"] is not None and lf["p10"] >= arc[0] - T["p10_slack_hours"] and lf["p90"] <= arc[1] + T["p90_slack_hours"]
        add("arc spread p10..p90, crew %s" % key, ok, [lf["p10"], lf["p90"]], [arc[0] - T["p10_slack_hours"], arc[1] + T["p90_slack_hours"]], blocking=False)
        if key in ("2", "3"):
            add("(a') arc hours, crew %s" % key, lf["p50"] is not None and arc[0] <= lf["p50"] <= arc[1], lf["p50"], list(arc), blocking=False)
        for band, (lo, hi) in T["raid_bands"].items():
            share = crew["raid_bands"][band]["raided_share"]
            if share is None:
                continue
            add("raids, %s, crew %s" % (band, key), lo <= share <= hi, round(share, 3), [lo, hi], blocking=False)
    if "1" in crews and "4" in crews:
        solo = crews["1"]["rank_hours"][last_name]["p50"]
        quad = crews["4"]["rank_hours"][last_name]["p50"]
        ratio = (solo / quad) if solo and quad else None
        add("solo/quad arc ratio", ratio is not None and ratio <= C["ARC_SOLO_RATIO_MAX"], _finite(ratio), C["ARC_SOLO_RATIO_MAX"], blocking=False)
    return checks


# ---------------------------------------------------------------- engine parity (--engine-dump)

def find_balance_result(data):
    if isinstance(data, dict):
        if "balance_test" in data and isinstance(data["balance_test"], dict):
            return data["balance_test"]
        if "constants" in data and "cases" in data:
            return data
        for value in data.values():
            found = find_balance_result(value)
            if found is not None:
                return found
    return None


def same(a, b, tol=1e-6):
    if isinstance(a, bool) or isinstance(b, bool):
        return bool(a) == bool(b) and isinstance(a, bool) == isinstance(b, bool)
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if isinstance(a, int) and isinstance(b, int):
            return a == b
        return abs(float(a) - float(b)) <= tol * max(1.0, abs(float(a)), abs(float(b)))
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(same(x, y, tol) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        ka = {str(k): v for k, v in a.items()}
        kb = {str(k): v for k, v in b.items()}
        return ka.keys() == kb.keys() and all(same(ka[k], kb[k], tol) for k in ka)
    return a == b


SCRIPT_ALIASES = {"Hoods": ["Hoods", "Neighborhoods", "neighborhoods"]}


def engine_parity(path: str, tables: dict) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        raise UsageError("--engine-dump %s: %s" % (path, error))
    result = find_balance_result(data)
    if result is None:
        raise UsageError("--engine-dump %s has no balance_test result" % path)
    engine_consts = result.get("constants", {})
    if isinstance(engine_consts, str):
        # --balance-test stores the dump as a JSON string, so PowerShell can read
        # the rest of host.json (its tables have keys ConvertFrom-Json rejects).
        try:
            engine_consts = json.loads(engine_consts)
        except ValueError as error:
            raise UsageError("--engine-dump %s: its constants don't parse: %s" % (path, error))
    mismatches = []
    for script, names in NEEDED.items():
        engine_script = None
        for alias in SCRIPT_ALIASES.get(script, [script]):
            if alias in engine_consts:
                engine_script = engine_consts[alias]
                break
        if engine_script is None:
            mismatches.append({"name": script, "why": "missing from the engine dump"})
            continue
        for name in names + OPTIONAL.get(script, []):
            ours = tables[script].get(name)
            if name not in engine_script:
                if ours is not None:
                    mismatches.append({"name": "%s.%s" % (script, name), "why": "missing from the engine dump"})
                continue
            if not same(ours, engine_script[name]):
                mismatches.append({"name": "%s.%s" % (script, name), "ours": ours, "engine": engine_script[name]})
    mirror = mirror_functions(tables)
    case_mismatches, unknown = [], []
    cases = result.get("cases", [])
    for case in cases:
        fn = case.get("fn", "")
        if fn not in mirror:
            unknown.append(fn)
            continue
        try:
            ours = mirror[fn](*case.get("args", []))
        except Exception as error:  # noqa: BLE001 - report, don't crash
            case_mismatches.append({"fn": fn, "args": case.get("args"), "error": str(error)})
            continue
        if not same(ours, case.get("out")):
            case_mismatches.append({"fn": fn, "args": case.get("args"), "ours": ours, "engine": case.get("out")})
    failed = [row.get("name") for row in result.get("invariants", []) if isinstance(row, dict) and not row.get("ok")]
    return {"constant_mismatches": mismatches, "case_mismatches": case_mismatches, "cases": len(cases),
            "unknown_functions": sorted(set(unknown)), "engine_ok": result.get("ok"), "failed_invariants": failed}


def mirror_functions(tables: dict) -> dict:
    econ = Economy(tables)
    ranks, seasons, catalog = econ.ranks, Seasons(tables), Catalog(tables)
    return {
        "Economy.job_xp": lambda c, t, s, n: econ.job_xp(c, t, s, n),
        "Economy.migrate_xp": econ.migrate_xp,
        "Economy.regrow": lambda d, never: econ.regrow(d, bool(never)),
        "Economy.relationship_after": econ.relationship_after,
        "Economy.mood_thresholds": econ.mood_thresholds,
        "Economy.clean_enough_at": econ.clean_enough_at,
        "Economy.messy_below_at": econ.messy_below_at,
        "Economy.job_pay": econ.job_pay,
        "Economy.bag_bonus": econ.bag_bonus,
        "Economy.crew_work_scale": econ.crew_work_scale,
        "Economy.crew_patience_scale": econ.crew_patience_scale,
        "Economy.xp_crew_scale": econ.xp_crew_scale,
        "Economy.run_roll_chance": econ.run_roll_chance,
        "Ranks.xp_for_tier": ranks.xp_for_tier,
        "Ranks.xp_to_reach": ranks.xp_to_reach,
        "Ranks.tier_for_xp": ranks.tier_for_xp,
        "Ranks.xp_into_tier": ranks.xp_into_tier,
        "Ranks.pay_bonus": ranks.pay_bonus,
        "Ranks.tier_of": ranks.tier_of,
        "Seasons.of_day": seasons.of_day,
        "Seasons.year_of": seasons.year_of,
        "Catalog.price": catalog.price,
    }


# ---------------------------------------------------------------- reports

def hashes(tables, model_path, sinks_path):
    consts = json.dumps({k: tables[k] for k in sorted(tables)}, sort_keys=True, default=str)
    with open(model_path, "rb") as handle:
        model = handle.read()
    with open(sinks_path, "rb") as handle:
        sinks = handle.read()
    return (hashlib.sha1(consts.encode()).hexdigest()[:12], hashlib.sha1(model + sinks).hexdigest()[:12])


def _fmt(value, digits=1):
    if value is None or value == INF:
        return "-"
    if isinstance(value, float):
        return ("%." + str(digits) + "f") % value
    return str(value)


def table_lines(game, report) -> list:
    crews = report["crews"]
    keys = sorted(crews)
    names = list(game.ranks.names[1:]) + ["The Lawnfather"]
    pace = game.C["RANK_PACE_HOURS"]
    width = 26
    lines = []
    head = "%-*s" % (width, "") + "".join("%10s" % ("crew %s" % k) for k in keys) + "%10s" % "target"
    lines.append(head)
    lines.append("-" * len(head))
    lines.append("hours to tier I of each rank (median)")
    for index, name in enumerate(names, start=1):
        row = "  %-*s" % (width - 2, name)
        for k in keys:
            row += "%10s" % _fmt(crews[k]["rank_hours"][name]["p50"])
        row += "%10s" % _fmt(pace[index] if index < len(pace) else None)
        lines.append(row)
    def row_of(label, getter, digits=1):
        row = "%-*s" % (width, label)
        for k in keys:
            row += "%10s" % _fmt(getter(crews[k]), digits)
        return row
    lines.append(row_of("Lawnfather p10 (h)", lambda c: c["rank_hours"]["The Lawnfather"]["p10"]))
    lines.append(row_of("Lawnfather p90 (h)", lambda c: c["rank_hours"]["The Lawnfather"]["p90"]))
    lines.append(row_of("days to The Lawnfather", lambda c: c["days_to_lawnfather"]))
    lines.append(row_of("jobs to The Lawnfather", lambda c: c["jobs_to_lawnfather"], 0))
    lines.append(row_of("jobs per day", lambda c: c["jobs_per_day"]))
    lines.append(row_of("tier after night 1", lambda c: float(c["first_night_tier_p50"]), 0))
    for rank in ("Rake Rookie", "Bag Hauler", "Hedge Hog", "Lawn Lord", "The Lawnfather"):
        lines.append(row_of("$/player/day, %s" % rank, lambda c, r=rank: c["income_per_day_by_rank"].get(r), 0))
    lines.append(row_of("days of income, blower", lambda c: (c["purchases"].get("leaf_blower") or {}).get("days_of_income"), 2))
    lines.append(row_of("days of income, washer", lambda c: (c["purchases"].get("pressure_washer") or {}).get("days_of_income"), 2))
    lines.append(row_of("hire fee, days of income", lambda c: c["hire"]["fee_days_at_unlock"], 2))
    lines.append(row_of("raids per job", lambda c: c["raids_per_job"], 2))
    lines.append(row_of("days bound by clock", lambda c: c["binding"]["clock"], 2))
    lines.append(row_of("days bound by requests", lambda c: c["binding"]["requests"], 2))
    lines.append(row_of("jobs past patience", lambda c: c["binding"]["patience"], 2))
    return lines


def write_markdown(path, game, report, sources):
    lines = ["# Balance simulator report", "",
             "Build %s, constants %s, model %s, %d seeds per crew. Generated by `tools/balance_sim.py`; see docs/BALANCE.md." % (
                 report["build_version"], report["constants_hash"], report["model_hash"], report["seeds"]), "",
             "```"] + table_lines(game, report) + ["```", "", "## Checks", "",
             "| | check | value | limit | blocking |", "| --- | --- | --- | --- | --- |"]
    for check in report["checks"]:
        lines.append("| %s | %s | %s | %s | %s |" % ("PASS" if check["ok"] else "FAIL", check["name"],
                     json.dumps(check["value"]), json.dumps(check["limit"]), "yes" if check["blocking"] else "warning"))
    if report.get("set"):
        lines += ["", "## What-ifs (--set)", ""] + ["- `%s`" % s for s in report["set"]]
    if report.get("warnings"):
        lines += ["", "## Warnings", ""] + ["- %s" % w for w in report["warnings"]]
    lines += ["", "## Assumptions (tools/balance/model.json)", ""]
    for name, source in sources.items():
        lines.append("- **%s**: %s" % (name, source))
    _write(path, "\n".join(lines) + "\n")


PALETTE = [("#2a78d6", "#3987e5"), ("#eb6834", "#d95926"), ("#1baf7a", "#199e70"), ("#eda100", "#c98500")]


def write_html(path, game, report):
    crews = report["crews"]
    keys = sorted(crews)
    css_vars = "".join("--s%d:%s;" % (i + 1, PALETTE[i % 4][0]) for i in range(4))
    css_dark = "".join("--s%d:%s;" % (i + 1, PALETTE[i % 4][1]) for i in range(4))

    def chart(title, series, x_label, y_label, targets=None):
        w, h, left, bottom, top, right = 760, 300, 56, 36, 16, 90
        all_x = [x for _, pts in series for x, _ in pts] or [0, 1]
        all_y = [y for _, pts in series for _, y in pts] + [y for _, y in (targets or [])] or [0, 1]
        x_max, y_max = max(all_x) or 1, _nice(max(all_y) or 1)
        x_step = _nice(x_max / 5.0, (1.0, 2.0, 5.0, 10.0))
        sx = lambda x: left + (w - left - right) * x / x_max
        sy = lambda y: top + (h - top - bottom) * (1 - y / y_max)
        out = ['<figure><figcaption>%s</figcaption><svg viewBox="0 0 %d %d" role="img" aria-label="%s">' % (html.escape(title), w, h, html.escape(title))]
        for i in range(5):
            y = y_max * i / 4
            out.append('<line class="grid" x1="%d" x2="%d" y1="%.1f" y2="%.1f"/><text class="tick" x="%d" y="%.1f" text-anchor="end">%s</text>' % (left, w - right, sy(y), sy(y), left - 6, sy(y) + 4, _fmt(y, 0)))
        x = 0.0
        while x <= x_max + 1e-9:
            out.append('<text class="tick" x="%.1f" y="%d" text-anchor="middle">%s</text>' % (sx(x), h - bottom + 16, _fmt(x, 0)))
            x += x_step
        out.append('<text class="axis" x="%d" y="%d" text-anchor="middle">%s</text>' % ((w - right + left) // 2, h - 4, html.escape(x_label)))
        out.append('<text class="axis" x="12" y="%d" transform="rotate(-90 12 %d)" text-anchor="middle">%s</text>' % (h // 2, h // 2, html.escape(y_label)))
        for x, y in targets or []:
            out.append('<circle class="target" cx="%.1f" cy="%.1f" r="5"><title>target %s: %s h</title></circle>' % (sx(x), sy(y), _fmt(x, 0), _fmt(y)))
        ends = []
        for index, (label, pts) in enumerate(series):
            if not pts:
                continue
            color = "var(--s%d)" % (index % 4 + 1)
            d = " ".join("%s%.1f,%.1f" % ("M" if i == 0 else "L", sx(x), sy(y)) for i, (x, y) in enumerate(pts))
            out.append('<path d="%s" fill="none" stroke="%s" stroke-width="2"/>' % (d, color))
            for x, y in pts[:: max(1, len(pts) // 20)]:
                out.append('<circle cx="%.1f" cy="%.1f" r="4" fill="%s" stroke="var(--surface)" stroke-width="2"><title>%s, %s: %s</title></circle>' % (sx(x), sy(y), color, html.escape(label), _fmt(x, 0), _fmt(y)))
            lx, ly = pts[-1]
            ends.append([sy(ly) + 4, sx(lx) + 6, label])
        # Direct labels at the line ends, nudged apart so they never overlap.
        ends.sort()
        for i in range(1, len(ends)):
            ends[i][0] = max(ends[i][0], ends[i - 1][0] + 13)
        for y, x, label in ends:
            out.append('<text class="label" x="%.1f" y="%.1f">%s</text>' % (x, y, html.escape(label)))
        out.append("</svg></figure>")
        return "".join(out)

    tier_series = [("crew %s" % k, [(t, hrs) for t, hrs in enumerate(crews[k]["tier_hours"]) if hrs is not None]) for k in keys]
    per = game.ranks.per_rank
    targets = [(rank * per, hours) for rank, hours in enumerate(game.C["RANK_PACE_HOURS"]) if rank > 0]
    cash_series = [("crew %s" % k, list(enumerate(crews[k]["cash_per_player_by_day"], start=1))) for k in keys]
    rows = "".join("<tr><td>%s</td></tr>" % html.escape(line) for line in table_lines(game, report))
    checks = "".join('<tr><td class="%s">%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' % (
        "pass" if c["ok"] else "fail", "PASS" if c["ok"] else "FAIL", html.escape(c["name"]), html.escape(json.dumps(c["value"])),
        html.escape(json.dumps(c["limit"])), "blocking" if c["blocking"] else "warning") for c in report["checks"])
    page = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Balance Sim Report</title><style>
:root{--surface:#fcfcfb;--page:#f9f9f7;--ink:#0b0b0b;--ink2:#52514e;--grid:#e4e3df;%s}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;--grid:#383835;%s}}
:root[data-theme="dark"]{--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;--grid:#383835;%s}
body{background:var(--page);color:var(--ink);font:14px/1.45 system-ui,sans-serif;margin:0;padding:16px;max-width:900px}
figure{background:var(--surface);margin:16px 0;padding:12px;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}
svg{width:100%%;height:auto}.grid{stroke:var(--grid);stroke-width:1}.tick,.axis,.label{fill:var(--ink2);font-size:11px}
.target{fill:none;stroke:var(--ink2);stroke-width:2;stroke-dasharray:2 2}
table{border-collapse:collapse;background:var(--surface);width:100%%;overflow-x:auto;display:block}
td{padding:2px 8px;font-family:ui-monospace,monospace;white-space:pre;color:var(--ink)}.pass{color:var(--ink2)}.fail{font-weight:700}
</style></head><body><h1>Balance simulator</h1><p>Build %s, constants %s, model %s, %d seeds per crew. Dashed circles are Constants.RANK_PACE_HOURS.</p>
%s%s<h2>Summary</h2><table>%s</table><h2>Checks</h2><table>%s</table></body></html>""" % (
        css_vars, css_dark, css_dark, html.escape(report["build_version"]), report["constants_hash"], report["model_hash"], report["seeds"],
        chart("Hours to reach each tier (median)", tier_series, "tier", "hours", targets),
        chart("Cash per player at bedtime (median)", cash_series, "day", "dollars"),
        rows, checks)
    _write(path, page)


def _nice(value, steps=(1.0, 1.2, 1.6, 2.0, 2.4, 3.0, 4.0, 6.0, 8.0, 10.0)):
    """The next round number at or above value (one of steps times a power of ten;
    the default steps all divide by four, for four even y gridlines)."""
    if value <= 0:
        return 1.0
    power = 10.0 ** math.floor(math.log10(value))
    for step in steps:
        if value <= step * power:
            return step * power
    return 10.0 * power


def _write(path, text):
    folder = os.path.dirname(os.path.abspath(path))
    os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def _json_safe(value):
    if isinstance(value, float):
        return None if math.isinf(value) or math.isnan(value) else value
    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items() if not str(k).startswith("_")}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    return value


# ---------------------------------------------------------------- --propose

PROPOSE_SPEC_START = [
    # The gap spec's candidate values (gap-specs/balance.json), the search's start.
    "Ranks.XP_FIRST_TIER=160", "Ranks.XP_PER_TIER_STEP=28", "Ranks.XP_ENDLESS_TIER=1500",
    "CREW_WORK_SCALE=[0.55, 0.75, 0.9, 1.0]", "CREW_PATIENCE_SCALE=[1.15, 1.05, 1.0, 1.0]",
    "XP_CREW_SCALE=[1.35, 1.15, 1.05, 1.0]",
]


def objective(game: Game, crews: dict) -> float:
    pace = game.C["RANK_PACE_HOURS"]
    names = list(game.ranks.names) + ["The Lawnfather"]
    total = 0.0
    for crew in crews.values():
        for rank in range(1, len(names)):
            hours = crew["rank_hours"][names[rank]]["p50"]
            hours = hours if hours else 400.0
            total += math.log(hours / pace[rank]) ** 2
    if "1" in crews and "4" in crews:
        solo = crews["1"]["rank_hours"]["The Lawnfather"]["p50"] or 400.0
        quad = crews["4"]["rank_hours"]["The Lawnfather"]["p50"] or 400.0
        ratio = solo / quad
        if ratio > game.C["ARC_SOLO_RATIO_MAX"]:
            total += 4.0 * math.log(ratio / game.C["ARC_SOLO_RATIO_MAX"]) ** 2
    return total


def propose(repo, base_sets, model_path, sinks_path, seeds, days_max, log):
    """Coordinate descent on the XP curve and the crew-size scales toward
    RANK_PACE_HOURS, then prices solved from income. Prints a diff; edits nothing."""
    started = time.time()
    sets = list(PROPOSE_SPEC_START) + list(base_sets)
    params = {}

    def build(extra):
        tables, _ = load_tables(repo, sets + ["%s=%s" % (k, v) for k, v in extra.items()])
        model, _ = load_model(model_path, tables)
        sinks, _, enforce = load_sinks(sinks_path, tables, model)
        return Game(tables, model, sinks, enforce)

    def evaluate(extra, crews=(1, 2, 3, 4)):
        game = build(extra)
        result = simulate(game, crews, seeds, days_max, 0)
        return objective(game, result), game, result

    tables0, _ = load_tables(repo, sets)
    knobs = [
        ("Ranks.XP_FIRST_TIER", tables0["Ranks"]["XP_FIRST_TIER"], True),
        ("Ranks.XP_PER_TIER_STEP", tables0["Ranks"]["XP_PER_TIER_STEP"], True),
        ("Constants.XP_CREW_SCALE.0", tables0["Constants"]["XP_CREW_SCALE"][0], False),
        ("Constants.XP_CREW_SCALE.1", tables0["Constants"]["XP_CREW_SCALE"][1], False),
        ("Constants.XP_CREW_SCALE.2", tables0["Constants"]["XP_CREW_SCALE"][2], False),
        ("Constants.CREW_WORK_SCALE.0", tables0["Constants"]["CREW_WORK_SCALE"][0], False),
    ]
    for name, value, _ in knobs:
        params[name] = value
    best, _, _ = evaluate(params)
    log("propose: start objective %.4f (%d seeds per crew)" % (best, seeds))
    for step in (0.12, 0.05, 0.02):
        improved = True
        while improved:
            improved = False
            for name, _, is_int in knobs:
                for direction in (1, -1):
                    trial = dict(params)
                    value = params[name] * (1 + direction * step)
                    trial[name] = int(round(value)) if is_int else round(value, 3)
                    if trial[name] == params[name] or trial[name] <= 0:
                        continue
                    score, _, _ = evaluate(trial)
                    if score < best - 1e-4:
                        best, params, improved = score, trial, True
                        log("  %s -> %s  objective %.4f" % (name, trial[name], score))
                        break
            if time.time() - started > 600:
                log("propose: stopping the search at 10 minutes")
                break
    # Prices from income: tools and upgrades at propose_price_days of one player's
    # income when they unlock; the hire fee at propose_hire_fee_days; the wage so a
    # hand nets propose_hand_net_ratio times what they cost.
    game = build(params)
    targets = game.M["targets"]
    prices = {}
    for _ in range(2):
        result = simulate(game, (1, 4), seeds, days_max, 0)
        for sink in game.live:
            if sink["kind"] != "tool" and sink["id"] not in targets["propose_priced_upgrades"]:
                continue
            dois = [result[k]["purchases"].get(sink["id"], {}).get("days_of_income") for k in ("1", "4")]
            dois = [d for d in dois if d]
            if not dois:
                continue
            income_at_unlock = sink["price"] / statistics.mean(dois)
            path = "Constants.TOOL_PRICES.%s" % sink["id"] if sink["kind"] == "tool" else "Constants.SHOP_PRICES.%s" % sink["id"]
            prices[path] = max(50, int(round(income_at_unlock * targets["propose_price_days"] / 10.0)) * 10)
        fee_days = [result[k]["hire"]["fee_days_at_unlock"] for k in ("1", "4") if result[k]["hire"]["fee_days_at_unlock"]]
        if fee_days:
            income = game.C["HIRE_SIGNING_FEE"] / statistics.mean(fee_days)
            prices["Constants.HIRE_SIGNING_FEE"] = int(round(income * targets["propose_hire_fee_days"] / 10.0)) * 10
        hand = [result[k]["hire"]["hand_value_per_day_p50"] for k in ("1", "4") if result[k]["hire"]["hand_value_per_day_p50"]]
        if hand:
            prices["Constants.HIRE_DAILY_WAGE"] = max(10, int(round(statistics.mean(hand) / targets["propose_hand_net_ratio"] / 5.0)) * 5)
        game = build({**params, **prices})
    params.update(prices)
    final_score, game, final = evaluate(params)
    return {"params": params, "start_sets": PROPOSE_SPEC_START, "objective": final_score, "seconds": round(time.time() - started, 1)}, game, final


# ---------------------------------------------------------------- self-tests and main

def self_test(game, log):
    """The same seed gives the same result twice; the Catalog mirror agrees with sinks.json."""
    a = summarize(game, 2, [Run(game, 2, 7, 60, 0).play()])
    b = summarize(game, 2, [Run(game, 2, 7, 60, 0).play()])
    if json.dumps(_json_safe(a), sort_keys=True) != json.dumps(_json_safe(b), sort_keys=True):
        raise UsageError("self-test: the same seed gave two different results")
    problems = []
    for sink in game.sinks:
        price = game.catalog.price(sink["id"])
        if price >= 0 and price != sink["price"]:
            problems.append("sink %s is $%d but Catalog.price says $%d" % (sink["id"], sink["price"], price))
    for problem in problems:
        log("warning: " + problem)
    return problems


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--players", default="1,2,3,4", help="crew sizes, e.g. 1,4")
    parser.add_argument("--seeds", type=int, default=None, help="runs per crew size (model.json seeds)")
    parser.add_argument("--days", type=int, default=None, help="most days a run plays (model.json days_max)")
    parser.add_argument("--set", action="append", default=[], metavar="NAME=VALUE", help="what-if: override a constant (repeatable)")
    parser.add_argument("--model", default=os.path.join(HERE, "balance", "model.json"))
    parser.add_argument("--sinks", default=os.path.join(HERE, "balance", "sinks.json"))
    parser.add_argument("--report", default=os.path.join(REPO, "build", "balance", "report.json"))
    parser.add_argument("--md", default=os.path.join(REPO, "build", "balance", "report.md"))
    parser.add_argument("--html", nargs="?", const=os.path.join(REPO, "build", "balance", "report.html"), default=None)
    parser.add_argument("--check", action="store_true", help="exit 1 when a blocking check fails")
    parser.add_argument("--strict", action="store_true", help="warnings block too")
    parser.add_argument("--baseline", action="store_true", help="with --check: the tuning checks don't fail the exit code (until balance:E); parity (f) and the self-test still do")
    parser.add_argument("--engine-dump", default=None, metavar="HOST_JSON", help="compare constants and formulas with --balance-test's output")
    parser.add_argument("--propose", action="store_true", help="search for values toward the targets; writes build/balance/proposal.json")
    parser.add_argument("--repo", default=REPO, help=argparse.SUPPRESS)
    parser.add_argument("--quiet", action="store_true")
    try:
        args = parser.parse_args(argv)
    except SystemExit as error:
        return EXIT_USAGE if error.code else EXIT_PASS
    log = (lambda *_: None) if args.quiet else (lambda text: print(text, flush=True))
    started = time.time()
    try:
        try:
            crews = sorted({int(p) for p in args.players.split(",") if p.strip()})
        except ValueError:
            raise UsageError("--players wants crew sizes like 1,4, got %r" % args.players)
        if not crews:
            raise UsageError("--players names no crew size")
        tables, set_notes = load_tables(args.repo, args.set)
        if any(p < 1 or p > tables["Constants"]["MAX_PLAYERS"] for p in crews):
            raise UsageError("--players must be 1 to %d" % tables["Constants"]["MAX_PLAYERS"])
        model, sources = load_model(args.model, tables)
        sinks, warnings, enforce = load_sinks(args.sinks, tables, model)
        seeds = args.seeds or int(model["seeds"])
        days_max = args.days or int(model["days_max"])
        game = Game(tables, model, sinks, enforce)
        if args.check and not args.propose and not {1, 4} <= set(crews):
            raise UsageError("--check needs crews 1 and 4 in --players (the blocking checks (a) to (e) are for them), got %r" % args.players)
        self_problems = self_test(game, lambda *_: None)
        warnings += self_problems
        if args.propose:
            proposal, game, result = propose(args.repo, args.set, args.model, args.sinks, min(seeds, 12), days_max, log)
            log("")
            log("Proposed values (nothing was edited; apply them by hand in balance:E):")
            for name, value in proposal["params"].items():
                script, _, rest = name.partition(".")
                old = resolve_ref("const:" + name, tables, model) if _resolves("const:" + name, tables, model) else "(new)"
                log("  %-40s %s -> %s" % (name, old, value))
            for line in proposal["start_sets"]:
                log("  (search started from %s)" % line)
            proposal["crews"] = _json_safe(result)
            _write(os.path.join(os.path.dirname(args.report), "proposal.json"), json.dumps(_json_safe(proposal), indent=1))
            log("objective %.4f, %s s; wrote %s" % (proposal["objective"], proposal["seconds"], os.path.join(os.path.dirname(args.report), "proposal.json")))
            return EXIT_PASS
        crew_results = simulate(game, crews, seeds, days_max, int(model["endless_days"]))
        parity = engine_parity(args.engine_dump, tables) if args.engine_dump else None
        checks = run_checks(game, crew_results, parity, args.strict, self_problems)
        constants_hash, model_hash = hashes(tables, args.model, args.sinks)
        report = {
            "build_version": tables["Constants"]["BUILD_VERSION"],
            "constants_hash": constants_hash,
            "model_hash": model_hash,
            "seeds": seeds,
            "days_max": days_max,
            "set": set_notes,
            "warnings": warnings,
            "crews": crew_results,
            "checks": checks,
            "parity": parity,
            "proposal": None,
            "seconds": None,
        }
        report["seconds"] = round(time.time() - started, 2)
        safe = _json_safe(report)
        _write(args.report, json.dumps(safe, indent=1))
        if args.md:
            write_markdown(args.md, game, safe, sources)
        if args.html:
            write_html(args.html, game, safe)
    except UsageError as error:
        print("balance_sim: %s" % error, file=sys.stderr)
        return EXIT_USAGE
    for note in set_notes:
        log("what-if: " + note)
    for warning in warnings:
        log("warning: " + warning)
    log("Leaf Me Alone balance sim: build %s, constants %s, model %s, %d seeds, %.1f s" % (
        report["build_version"], constants_hash, model_hash, seeds, report["seconds"]))
    for line in table_lines(game, safe):
        log(line)
    failed = [c for c in checks if c["blocking"] and not c["ok"]]
    warned = [c for c in checks if not c["blocking"] and not c["ok"]]
    log("")
    for check in checks:
        if not check["ok"] or check["blocking"]:
            log("%s %-9s %s: %s (limit %s)" % ("PASS" if check["ok"] else "FAIL", "" if check["blocking"] else "(warning)",
                                              check["name"], json.dumps(_json_safe(check["value"])), json.dumps(_json_safe(check["limit"]))))
    if parity is not None:
        for item in parity["constant_mismatches"][:20] + parity["case_mismatches"][:20]:
            log("  parity: %s" % json.dumps(_json_safe(item)))
        if parity["unknown_functions"]:
            log("  parity: no mirror for %s" % ", ".join(parity["unknown_functions"]))
    log("%d blocking checks failed, %d warnings; wrote %s" % (len(failed), len(warned), args.report))
    if args.check and failed:
        if args.baseline:
            hard = [c for c in failed if not c.get("baseline_ok", True)]
            if hard:
                log("BASELINE does not excuse %s: the simulator or its mirror is wrong, not the tuning." % ", ".join(c["name"] for c in hard))
                return EXIT_FAIL
            log("BASELINE: %d blocking checks fail on today's numbers; --baseline keeps the exit code 0 until balance:E retunes them." % len(failed))
            return EXIT_PASS
        return EXIT_FAIL
    return EXIT_PASS


def _resolves(ref, tables, model):
    try:
        resolve_ref(ref, tables, model)
        return True
    except KeyError:
        return False


if __name__ == "__main__":
    sys.exit(main())
