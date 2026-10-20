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
	"hide_taken": "Occupied",
	"hud_hidden": "Hiding. E to come out.",
	"prompt_format": "[E]  %s",
	"prompt_hide": "Hide",
	"prompt_unhide": "Come out",
	"prompt_load_bag": "Load the bag",
	"prompt_pick_up": "Pick up %s",
	"prompt_pick_up_plain": "Pick up",
	"prompt_board": "Board Chefty",
	"prompt_finish": "Call the job done",
	"prompt_shop": "Shop",
	"prompt_gate_lot": "Go to the lot",
	"prompt_gate_store": "Back to Homie Depot",
	"prompt_gate_border": "Go to the border",
	"hud_rake_hint": "Left click  rake leaves into a pile     Right click  bag them",
	"shop_title": "Homie Depot",
	"shop_subtitle": "Tools and upgrades",
	"shop_credits": "Your cash: $%d",
	"shop_close": "Close",
	"shop_price": "$%d",
	"shop_buy": "Buy",
	"shop_owned": "Owned",
	"shop_short": "Not enough cash",
	"shop_rake_name": "Rake tune-up",
	"shop_rake_blurb": "Raking moves %.2fx as many leaves.",
	"shop_barrow_name": "Bigger wheelbarrow",
	"shop_barrow_blurb": "Holds %d bags instead of %d.",
	"clerk_name": "[CLERK NAME]",
	"homeowner_name": "[HOMEOWNER NAME]",
	"prompt_talk": "Talk to the homeowner",
	"prompt_take_cash": "Take the cash ($%d)",
	"cash_amount": "$%d",
	"homeowner_thanks": "Thanks!",
	"hud_wallet": "Cash $%d",
	"receipt_title": "Job paid",
	"receipt_bags": "Bags delivered",
	"receipt_mood": "Homeowner was %s",
	"receipt_paid": "Paid",
	"receipt_split": "Your crew's split",
	"receipt_close": "Nice",
	"receipt_no_homeowner": "Paid for the cleanup",
}

## What the homeowner says when you report the job done, by mood. Taylan wrote the
## first two on 2026-10-19. The rest are plain stand-ins until there are real lines.
const HOMEOWNER_LINES: Dictionary = {
	"thrilled": ["You did a great job, here's a tip!"],
	"happy": ["Nice work. Here you go."],
	"fine": ["Thanks. Here's your money."],
	"slow": ["Took long enough eh?"],
	"messy": ["There are still leaves out there."],
	"nothing": ["You haven't bagged anything yet."],
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

## How each homeowner mood reads on the payout receipt.
const MOOD_NAMES: Dictionary = {
	"thrilled": "thrilled", "happy": "happy", "fine": "fine", "slow": "impatient", "messy": "unimpressed",
}
