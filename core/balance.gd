# GENERATED FILE. Do not edit by hand.
# Source: design/leaf-me-alone-workbook.xlsx, sheet 'Balance Lab'.
# To change a value, edit the workbook and run: python3 design/export_balance.py
class_name Balance
extends RefCounted

## Tuning values from the design workbook's Balance Lab. Every constant keeps its
## BAL id so a value in code can be traced back to the workbook row it came from.
## Most of these are working assumptions, not canon. Check the status in each comment.

## BAL-01: Target completion minimum (hours). Confirmed range, status Confirmed.
## Lower bound from concept
const TARGET_COMPLETION_MINIMUM_HOURS: float = 5.0

## BAL-02: Target completion maximum (hours). Confirmed range, status Confirmed.
## Upper bound from concept
const TARGET_COMPLETION_MAXIMUM_HOURS: float = 10.0

## BAL-03: Planning target (hours). Working assumption, status Review.
## Midpoint used for pacing scaffold
const PLANNING_TARGET_HOURS: float = 7.5

## BAL-04: Target session length (minutes). Working assumption, status Review.
## Replace after playtests
const TARGET_SESSION_LENGTH_MINUTES: float = 45.0

## BAL-05: Expected traveling party size (players). Working assumption, status Review.
## Subset size is not yet defined
const EXPECTED_TRAVELING_PARTY_SIZE: int = 4

## BAL-06: Active cleanup utilization (% of job time; stored as a fraction where 0.25 means 25%). Working assumption, status Review.
## Allows movement, jokes, danger, coordination
const ACTIVE_CLEANUP_UTILIZATION: float = 0.7

## BAL-07: Base leaves per minute per player (leaf units/min). Working assumption, status Review.
## Abstract tuning unit
const BASE_LEAVES_PER_MINUTE_PER_PLAYER: float = 120.0

## BAL-08: Starting lot leaf volume (leaf units). Working assumption, status Review.
## Placeholder needed for formulas
const STARTING_LOT_LEAF_VOLUME: float = 8000.0

## BAL-09: Leaf volume growth per lot (%; stored as a fraction where 0.25 means 25%). Working assumption, status Review.
## Preserves impossible-scale escalation
const LEAF_VOLUME_GROWTH_PER_LOT: float = 0.65

## BAL-10: Credits per 1% lot cleanup (credits). Working assumption, status Review.
## Payout basis placeholder
const CREDITS_PER_1_PERCENT_LOT_CLEANUP: int = 8

## BAL-11: Tool cost growth multiplier (x). Working assumption, status Review.
## Cost curve placeholder
const TOOL_COST_GROWTH_MULTIPLIER: float = 1.55

## BAL-12: Tool throughput growth multiplier (x). Working assumption, status Review.
## Upgrade power curve placeholder
const TOOL_THROUGHPUT_GROWTH_MULTIPLIER: float = 1.35

## BAL-13: Full-clear payout bonus (%; stored as a fraction where 0.25 means 25%). TBD candidate, status Review.
## Optional incentive; not confirmed
const FULL_CLEAR_PAYOUT_BONUS: float = 0.2

## BAL-14: Run event base chance (% per lot; stored as a fraction where 0.25 means 25%). Working assumption, status Review.
## Exact trigger model TBD
const RUN_EVENT_BASE_CHANCE: float = 0.1

## BAL-15: Run chance escalation per tier (+% per tier; stored as a fraction where 0.25 means 25%). Working assumption, status Review.
## Escalation placeholder
const RUN_CHANCE_ESCALATION_PER_TIER: float = 0.05

## BAL-16: Run event cooldown (minutes). Working assumption, status Review.
## Prevents event spam
const RUN_EVENT_COOLDOWN_MINUTES: float = 12.0

## BAL-17: Border-return target duration (minutes). Working assumption, status Review.
## Placeholder until side-mode playtest
const BORDER_RETURN_TARGET_DURATION_MINUTES: float = 3.0

## BAL-18: Planned lots to win (lots). Working assumption, status Review.
## Scaffold count only
const PLANNED_LOTS_TO_WIN: int = 8

## BAL-19: Minimum contribution share (%; stored as a fraction where 0.25 means 25%). TBD candidate, status Review.
## Potential anti-zero-payout floor
const MINIMUM_CONTRIBUTION_SHARE: float = 0.05

## BAL-20: Rescue score weight (%; stored as a fraction where 0.25 means 25%). TBD candidate, status Review.
## Contribution model proposal
const RESCUE_SCORE_WEIGHT: float = 0.15

## BAL-21: Objective score weight (%; stored as a fraction where 0.25 means 25%). TBD candidate, status Review.
## Contribution model proposal
const OBJECTIVE_SCORE_WEIGHT: float = 0.15

## BAL-22: Leaf-clearing score weight (%; stored as a fraction where 0.25 means 25%). TBD candidate, status Review.
## Contribution model proposal
const LEAF_CLEARING_SCORE_WEIGHT: float = 0.7

## BAL-23: Store visit overhead (minutes/lot). Working assumption, status Review.
## Shopping and regrouping allowance
const STORE_VISIT_OVERHEAD_MINUTES_PER_LOT: float = 5.0

## BAL-24: Baseline tier-1 tool cost (credits). Working assumption, status Review.
## Placeholder
const BASELINE_TIER_1_TOOL_COST: int = 120

## BAL-25: Maximum run event chance (% per lot; stored as a fraction where 0.25 means 25%). Working assumption, status Review.
## Caps randomness
const MAXIMUM_RUN_EVENT_CHANCE: float = 0.65

## BAL-26: Failed-run recovery multiplier (x throughput). TBD candidate, status Review.
## Temporary setback idea
const FAILED_RUN_RECOVERY_MULTIPLIER: float = 0.85

## BAL-27: Expected captured cohort size (players). Working assumption, status Review.
## Test placeholder; runtime van count equals actual captured roster
const EXPECTED_CAPTURED_COHORT_SIZE: int = 2

## BAL-28: Border-return failure credit penalty (credits). Confirmed behavior, status Confirmed.
## Failure only causes a funny throwback and retry
const BORDER_RETURN_FAILURE_CREDIT_PENALTY: int = 0
