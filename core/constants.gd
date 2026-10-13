class_name Constants
extends RefCounted

## Project-wide constants that are not tuning values. Tuning values live in
## core/balance.gd, which is generated from the design workbook.

## Bump on every build you hand to someone else. Peers on different versions cannot join each other.
const BUILD_VERSION: String = "0.2.0"

## Used to tag Steam lobbies while we share Valve's test app ID with everyone else.
const PROJECT_SLUG: String = "leaf-me-alone"

## ENet port for local development and the smoke test.
const DEFAULT_PORT: int = 7777

## Provisional. We build and test for up to 8 until the player count (OQ-016) is decided.
const MAX_PLAYERS: int = 8

## Valve's Spacewar test app. Replace with our own app ID once the game is registered in Steamworks.
const STEAM_APP_ID: int = 480

## Gray-box haul sizes Taylan set on 2026-10-12. Move them into the workbook when it has a row for them.
const WHEELBARROW_BAG_CAPACITY: int = 4
const WHEELBARROW_UPGRADED_BAG_CAPACITY: int = 8
const TRUCK_BAG_CAPACITY: int = 50
const BAG_LOAD_RADIUS: float = 1.8
const TRUCK_UNLOAD_RADIUS: float = 4.0

## OQ-025: captures this many seconds apart share one van. Not in the workbook yet.
const CAPTURE_BATCH_SECONDS: float = 3.0
## TODO(balance): forgiving capture distance, crew speed, and how long the warning shows.
const CAPTURE_RADIUS: float = 2.0
const CREW_SPEED: float = 5.5
const RUN_WARNING_SECONDS: float = 8.0

## Disembark beat before the crossing clock.
## The workbook's full crossing is Balance.BORDER_RETURN_TARGET_DURATION_MINUTES.
## This gray-box run is 60 seconds, set 2026-10-13.
const BORDER_CROSSING_SECONDS: float = 60.0
const BORDER_STAGING_SECONDS: float = 3.0
const BORDER_THROWBACK_SECONDS: float = 0.55
const BORDER_RETURN_IMMUNITY_SECONDS: float = 4.0
