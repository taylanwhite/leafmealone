extends RefCounted

## Draft lines from the workbook Humor & Quips sheet. Not canon.
## Cooldown minutes in the sheet are still TBD, so playback uses one stand-in cooldown.

const COOLDOWN_SECONDS: float = 90.0

## Plain interface text. Not jokes, so not in the workbook.
const UI: Dictionary = {
	"speaking_nameplate": "%s  (talking)",
	"lobby_talking": "  talking",
	"hud_talking": "Talking",
	"hud_push_to_talk": "Hold V to talk",
	"voice_button": "Voice",
	"voice_title": "Voice chat",
	"voice_unavailable": "Voice chat works in Steam sessions.",
	"voice_mode_push": "Push to talk (hold V)",
	"voice_mode_open": "Open mic (talks when it hears you)",
	"voice_mute": "Mute",
	"voice_close": "Close",
	"voice_nobody": "Nobody else is here yet.",
	"cue_radio": "RADIO: [CREW NAME] is on the way to this address",
	"cue_countdown": "%d",
	"cue_arrived": "[CREW NAME] is here. Run. Hide. Break line of sight.",
	"cue_clear": "All clear",
	"hide_hint": "E to hide",
	"hide_taken": "Occupied",
	"hud_hidden": "Hiding. E to come out.",
}

const LINES: Array[Dictionary] = [
	{
		"id": "Q-001",
		"trigger": "store_arrival",
		"line": "Welcome back. The leaves have filed an appeal.",
		"max_session": 1,
	},
	{
		"id": "Q-002",
		"trigger": "first_lot",
		"line": "That is less a yard and more a leaf-based economy.",
		"max_session": 1,
	},
	{
		"id": "Q-003",
		"trigger": "low_cleanup",
		"line": "Great work. The percentage almost moved.",
		"max_session": 2,
	},
	{
		"id": "Q-004",
		"trigger": "tool_purchase",
		"line": "Industrial optimism. No refunds.",
		"max_session": 2,
	},
	{
		"id": "Q-005",
		"trigger": "run_warning",
		"line": "Unscheduled personnel are approaching on schedule.",
		"max_session": 1,
	},
	{
		"id": "Q-006",
		"trigger": "teammate_captured",
		"line": "They took Pat. Pat had the good rake.",
		"max_session": 1,
	},
	{
		"id": "Q-007",
		"trigger": "full_clear",
		"line": "Perfect. Wind is forecast for four minutes ago.",
		"max_session": 1,
	},
	{
		"id": "Q-008",
		"trigger": "return_store",
		"line": "Please place all existential debris in the marked bin.",
		"max_session": 2,
	},
	{
		"id": "Q-009",
		"trigger": "crew_arrival",
		"line": "The lawn has requested additional documentation.",
		"max_session": 1,
	},
	{
		"id": "Q-010",
		"trigger": "border_fail",
		"line": "That crossing has been returned to sender.",
		"max_session": 1,
	},
]
