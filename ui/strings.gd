extends RefCounted

## Every player-facing sentence in the game lives here, so it can be read and
## reviewed in one place (docs/DECISIONS.md, 2026-11-01). --cast-test
## (net/dev/cast_test.gd) audits all of it: no empty or unfinished text, nothing
## that crosses the humor guardrail, "NICE BOYS" in capitals, the right number of
## %s/%d slots per pool (FORMAT_ARGS), and a pool for every personality, mood,
## rank, neighborhood, season, unlock, bark kind and shopkeeper trigger.
## LINES are the workbook's Humor & Quips drafts, kept with their Q ids. The rest
## was written for the game and is canon until changed (docs/GAME.md, developer
## notes). How often a quip may repeat is Constants.QUIP_COOLDOWN_SECONDS.
## Proper nouns that are also data ids stay with their data: rank names in
## core/ranks.gd, neighborhood, street and homeowner names in
## net/town/neighborhoods.gd, hire nicknames in net/crew/hires.gd.

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
	"cue_radio": "RADIO: the NICE BOYS are on the way to this address",
	"cue_countdown": "%d",
	"cue_arrived": "The NICE BOYS are here. Run. Hide. Break line of sight.",
	"cue_clear": "All clear",
	# ---- cast: the NICE BOYS, their van and beacon, and text that moves here from
	# inline sites (wired up by later cast chunks; docs/GAME.md "2026-11-01, the cast").
	"van_label": "NICE BOYS Courtesy Shuttle",
	"van_side": "THE NICE BOYS",
	"van_motto": "Courtesy Patrol · We Noticed.",
	"van_rear": "HOW'S MY ENFORCING? FILL OUT FORM 9-B",
	"beacon_label": "NICE BOYS INBOUND",
	"crew_tag": "NICE BOY %s",
	"crew_tag_lead": "HEAD NICE BOY %s",
	"rival_name": "TurfMasters™",
	"rival_sign_text": "TurfMasters™\nLAWNS DONE RIGHT",
	"status_crew_coming": "The NICE BOYS are on the way",
	"status_crew_here": "The NICE BOYS are here",
	"border_step_off": "Step off the van",
	"border_thrown_back": "Thrown back",
	"border_lanes": "Red bar blocks one side. Stand on the empty side. A and D move sideways. Exit in %d s.",
	"border_exit_open": "Exit is open. Walk to the green line.",
	"border_exit_mark": "EXIT",
	"border_hint": "Stand on the empty side of the red bar",
	"menu_dev_host": "Dev host (ENet)",
	"pause_call_crew": "Call the NICE BOYS",
	"lobby_title": "Lobby",
	"lobby_ready_button": "Ready",
	"lobby_invite": "Invite Friends",
	"lobby_start": "Start",
	"lobby_leave": "Leave Session",
	"lobby_ready": "ready",
	"lobby_not_ready": "not ready",
	"error_host": "Could not host: %s",
	"error_join": "Could not join: %s",
	"ride_chefty_label": "Chefty\n%d/%d bags  $%d%s",
	"ride_chefty_full": " full",
	"phone_no_favorite": "no favorite job",
	"picky_0": "easy to please",
	"picky_1": "a little picky",
	"picky_2": "picky",
	"picky_3": "impossible",
	"phone_text_head": "%s  ·  Day %d %s",
	"phone_close_x": "✕",
	"popup_cash": "+$%d",
	# ---- end cast
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
	"prompt_job_board": "Pick the next job",
	"prompt_pile_dive": "Dive into the pile",
	"prompt_pile_out": "Climb out",
	"hud_heat": "Heat",
	"heat_warn_0": "Curtains are twitching.",
	"heat_warn_1": "Somebody's on the phone.",
	"prompt_grab_player": "Grab %s",
	"prompt_put_down_player": "Put %s down  (G throws them)",
	"hud_carried": "You're being carried. Mash keys to wriggle free!",
	"hud_punch": "Hold left click to wind up a punch",
	"board_title": "JOBS",
	"board_house": "No. %d",
	"board_size_0": "Small yard",
	"board_size_1": "Yard",
	"board_size_2": "Big yard",
	"board_tasks": "%d jobs",
	"board_pay": "$%d + leaves",
	"board_pay_short": "$%d+",
	"board_picked": "NEXT UP",
	"board_window_title": "Job Board",
	"board_window_subtitle": "Pick where Chefty goes next. Leaves pay by the bag.",
	"board_rating": "Crew rating: %s  (%d jobs)",
	"board_rating_none": "Crew rating: no reviews yet",
	"receipt_stars": "The homeowner's review: %s",
	"board_take": "Take this job",
	"board_taken": "Next up",
	"board_close": "Close",
	"board_locked": "Chefty's already on the way",
	"prompt_gate_lot": "Go to the lot",
	"prompt_gate_store": "Back to Homie Depot",
	"prompt_gate_border": "Go to the border",
	"hud_rake_hint": "Left click  rake leaves into a pile     Right click  bag them     Hold G  throw",
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
	"homeowner_name": "The Homeowner",
	"prompt_talk": "Talk to the homeowner",
	"prompt_toss_truck": "Toss into Chefty",
	"prompt_dump_truck": "Dump into Chefty",
	"prompt_take_cash": "Take the cash ($%d)",
	"cash_amount": "$%d",
	"homeowner_thanks": "Thanks!",
	"hud_wallet": "Cash $%d",
	# The goal line (ui/job_goal.gd): what to do next on the job.
	"shop_tool_unlocks": "Unlocks: %s",
	"shop_tools": "Tools",
	"shop_upgrades": "Upgrades",
	"tool_leaf_blower": "Leaf blower",
	"tool_lawn_mower": "Lawn mower",
	"tool_ladder": "Ladder",
	"tool_hose": "Garden hose",
	"tool_pressure_washer": "Pressure washer",
	"tool_hedge_trimmer": "Hedge trimmer",
	"tool_paint_roller": "Paint roller",
	"tool_blurb_leaf_blower": "Blasts leaves into piles way faster than raking. Hold left click.",
	"tool_blurb_lawn_mower": "Push it around to mow. Heavy, loud, satisfying.",
	"tool_blurb_ladder": "Reach the gutters. Hold left click under one to scoop it out.",
	"tool_blurb_hose": "Spray dirty windows clean from across the yard.",
	"tool_blurb_pressure_washer": "Blasts the grime off driveways.",
	"tool_blurb_hedge_trimmer": "Turns shaggy hedges into neat ones.",
	"tool_blurb_paint_roller": "Fresh paint on faded fences.",
	"task_rake_leaves": "Rake and bag the leaves",
	"task_pick_litter": "Pick up the litter",
	"task_pull_weeds": "Pull the weeds",
	"task_mow_lawn": "Mow the lawn",
	"task_clean_gutters": "Clean the gutters",
	"task_wash_windows": "Wash the windows",
	"task_power_wash": "Pressure wash the driveway",
	"task_trim_hedges": "Trim the hedges",
	"task_paint_fence": "Paint the fence",
	"tasks_title": "Today's job",
	"task_line": "%s  %d%%",
	"task_needs": "%s (needs a %s)",
	"prompt_pick_litter": "Pick up",
	"prompt_climb_up": "Climb up    F  take it down",
	"task_clear_roof": "Clear the leaves off the roof",
	"task_skim_pool": "Scoop the leaves out of the pool",
	"prompt_skim_pool": "Scoop out the leaves",
	"goal_roof": "Hold left click to scoop the roof and gutters (W at the ladder's top steps onto the roof)",
	"goal_mower_running": "Push it over the lawn. Left click stops it; let go and it drives off",
	"goal_start_mower": "Left click to pull the cord and start it (pull again to stop it)",
	"goal_dip_roller": "The roller's dry. E at the paint bucket to dip it",
	"prompt_dip": "Dip the roller",
	"prompt_hook_chefty": "Hook the hose to Chefty's tank",
	"prompt_hook_spigot": "Hook the hose to the house (they'll bill you)",
	"prompt_hook_hydrant": "Hook the hose to the hydrant (uh oh)",
	"prompt_unhook": "Unhook the hose",
	"prompt_refill": "Fill the washer",
	"goal_hook_hose": "Hook the hose up first: E at Chefty's tank, the house spigot, or a hydrant",
	"goal_refill": "The washer's empty. E at a water source to fill it",
	"goal_washer_tank": "Pressure wash the driveway (tank %d%%)",
	"receipt_water": "Water from the house",
	"receipt_bill_hose": "A new hose (you mowed it)",
	"receipt_bill_gnome": "A new gnome (you mowed it)",
	"receipt_bill_medical": "Medical bills",
	"prompt_climb_down": "Climb down",
	"goal_set_ladder": "Walk up to the house and left click under a gutter to set the ladder up",
	"goal_gutters": "Hold left click to scoop the gutters (a leaf blower goes faster). W steps onto the roof",
	"prompt_pull_weed": "Pull weed",
	"goal_task": "Next: %s",
	"receipt_task": "%s (%d%%)",
	"goal_board": "Board Chefty to head to the job",
	"goal_grab_rake": "Grab the rake",
	"goal_rake": "Rake leaves into one big pile, then right click to bag it",
	"goal_carry_held": "Carry the bag to Chefty and press E",
	"goal_carry_loose": "Carry the bags to Chefty (%d lying around)",
	"goal_talk": "Talk to the homeowner to get paid ($%d in Chefty)",
	"goal_rake_or_talk": "Grab the rake for more, or talk to the homeowner to get paid ($%d in Chefty)",
	"goal_no_rake": "Someone has the rake. Scoop by hand, or carry their bags",
	"goal_take_cash": "Grab the cash!",
	"receipt_title": "Job paid",
	"receipt_bags": "Bags delivered",
	"receipt_mood": "Homeowner was %s",
	"receipt_paid": "Paid",
	"receipt_split": "Your crew's split",
	"receipt_close": "Nice",
	"receipt_no_homeowner": "Paid for the cleanup",
	# The spine (docs/SPINE.md): the day, sleeping, the crew's rank, the town, the phone.
	"prompt_cot": "Lie down  (%d of %d in bed)",
	"prompt_cot_early": "Too early for bed (after 6 PM)",
	"pile_value": "Pile: $%d  (right click)",
	"pile_thin": "Pile's too thin to bag",
	"prompt_cot_lying": "Zzz... %d of %d in bed. Move to get up",
	"prompt_cot_host": "Zzz... %d of %d in bed. Hold E: everyone to bed",
	"camp_sign": "CREW CAMP\nmgmt. not responsible",
	"hud_clock": "Day %d · %s  %s",
	"hud_quiet_hours": "Quiet hours: +%d%% pay, noise draws more heat",
	"hud_closed": "2 AM. Go to bed, the crew camp is by the side wall",
	"hud_rank": "%s",
	"hud_unread": "%d new texts  (Tab)",
	"hud_xp": "%d / %d XP  (+%d tonight)",
	"goal_no_jobs": "No jobs right now. Check your phone (Tab), or sleep it off at the crew camp",
	"goal_sleep": "It's 2 AM. Sleep at the crew camp by the side wall",
	"goal_texts": "You've got texts. Tab to read them, then pick a job at the board",
	"board_client_line": "%s, %s",
	"board_none": "Nobody's asked for a job yet. Wait for a text, or sleep on it.",
	"receipt_bonus": "Night shift and rank bonus",
	"receipt_xp": "Crew XP (banked when you sleep)",
	"summary_title": "Day %d is over",
	"summary_jobs": "Jobs done: %d",
	"summary_cash": "Cash earned: $%d",
	"summary_stars": "Stars: %d",
	"summary_xp": "XP banked: +%d",
	"summary_rank": "Crew rank: %s",
	"summary_rank_up": "RANK UP: %s",
	"summary_unlock": "  Unlocked: %s",
	"summary_requests": "%d clients texted for tomorrow",
	"summary_missed": "%d jobs went to somebody else",
	"summary_opened": "New neighborhood: %s",
	"summary_close": "Rise and shine",
	"shop_needs_rank": "Rank: %s",
	"phone_title": "Crew Phone",
	"phone_tab_texts": "Texts",
	"phone_tab_clients": "Clients",
	"phone_tab_map": "Map",
	"phone_tab_crew": "Crew",
	"phone_close": "Put it away (Tab)",
	"phone_no_texts": "No texts yet.",
	"phone_take_job": "Take it",
	"phone_job_up_next": "Up next",
	"phone_client_line": "%s  ·  %s",
	"phone_client_detail": "%s · %s · %d jobs · last here: %s",
	"phone_last_never": "never",
	"phone_last_today": "today",
	"phone_last_days": "%d days ago",
	"phone_hood_open": "%s  (%d clients)",
	"phone_hood_locked": "%s  (opens at %s)",
	"phone_hood_waiting": "%s  (open, waiting for a referral)",
	"phone_next_unlock": "Next: %s at %s",
	"phone_perks": "Perks: %s",
	"phone_hires_locked": "Hiring opens at %s",
	"phone_hires_title": "Hired hands (%d of %d)",
	"phone_hire_line": "%s  ·  %d%% good  ·  $%d/day  ·  %d bags",
	"phone_fire": "Let go",
	"phone_hire": "Hire a hand ($%d, then $%d a day)",
	"summary_wages": "Wages paid: $%d",
	"summary_poached": "TurfMasters™ poached %s",
	"phone_poached": "With TurfMasters™ now. Win them back: great work on their street, or pull the signs.",
	"summary_quit": "%s quit (no pay)",
	"clerk_name": "Marty",
}

## What a rank unlock reads as, on the summary card and the phone.
const UNLOCK_NAMES: Dictionary = {
	"perk:extra_request": "one more job text every morning",
	"perk:extra_request_2": "another job text every morning",
	"perk:extra_request_3": "yet another job text every morning",
	"perk:sweet_talk": "homeowners wait 25% longer before they get cranky",
	"perk:bag_bonus": "leaf bags are worth 10% more",
	"perk:bag_bonus_2": "leaf bags are worth another 10% more",
	"perk:bag_bonus_3": "leaf bags are worth yet another 10% more",
	"perk:night_owl": "quiet-hours jobs pay 10% more",
	"perk:night_owl_2": "quiet-hours jobs pay another 10% more",
	"perk:cool_heads": "heat cools 25% faster",
	"perk:cool_heads_2": "heat cools another 25% faster",
	"perk:word_of_mouth": "clients refer neighbors sooner",
	"perk:word_of_mouth_2": "clients refer neighbors even sooner",
	"perk:chefty_tuneup": "Chefty gets a tune-up and drives faster",
	"perk:big_spenders": "clients pay 15% more",
	"perk:big_spenders_2": "clients pay another 15% more",
	"perk:hire_slot_2": "room for a second hire",
	"perk:hire_slot_3": "room for a third hire",
	"perk:hire_slot_4": "room for a fourth hire",
	"feature:rival": "TurfMasters™ move into town (uh oh)",
	"feature:hiring": "hiring: crew hands who rake and haul",
	"feature:garage": "a rented garage for the crew",
	"feature:barn": "a barn for the crew",
	"feature:warehouse": "a warehouse for the crew",
	"feature:lawnfather": "the endless rank: The Lawnfather",
	"shop:rake_tier_1": "the rake tune-up at Homie Depot",
	"shop:wheelbarrow_tier_1": "the bigger wheelbarrow at Homie Depot",
	# ---- shops
	"feature:salvage": "Rusty's Salvage & Pawn opens (he buys junk)",
	"feature:lunch_money": "Lunch Money, a food truck, parks at Homie Depot",
	"feature:deliveries": "deliveries: order from Homie Depot on your phone",
	"feature:truck_paint": "paint jobs and decals for Chefty",
	"shop:rake_tier_2": "The Leafinator rake at Homie Depot",
	"shop:big_bags": "contractor bags at Homie Depot",
	"shop:paint_gold": "GOLD paint for Chefty at Homie Depot",
	"shop:hat_crown": "the Lawnfather's crown at Homie Depot",
}


## What an unlock id reads as: "the ladder at Homie Depot", "Oak Hollow opens",
## "the leaf blower Mk II at Homie Depot".
static func unlock_name(unlock: String) -> String:
	if UNLOCK_NAMES.has(unlock):
		return str(UNLOCK_NAMES[unlock])
	if unlock.begins_with("shop:"):
		var tool := unlock.trim_prefix("shop:")
		if not UI.has("tool_" + tool) and SHOP_UI.has("item_" + tool):
			# Any other catalog item: its name, at the shop that sells it.
			var item_name := str(SHOP_UI["item_" + tool])
			var shop := str(Catalog.item(tool).get("shop", "homie_depot"))
			return "the %s at %s" % [item_name.left(1).to_lower() + item_name.substr(1), str(SHOP_UI.get("shop_title_" + shop, shop))]
		return "the %s at Homie Depot" % str(UI.get("tool_" + tool, tool)).to_lower()
	if unlock.begins_with("hood:"):
		var hood_id := unlock.trim_prefix("hood:")
		return "%s opens" % hood_id.capitalize()
	return unlock

## What the homeowner says when you ask to be paid, by mood (Taylan, 2026-10-21:
## funny, and they know who the NICE BOYS are). Taylan's own 2026-10-19 line,
## "You did a great job, here's a tip!", is in "thrilled". The "bill_*" pools
## replace the mood line some of the time when the crew owes for something it
## broke; "paid" is said once the cash is grabbed. A homeowner with a personality
## usually speaks from PERSONALITY_LINES instead (homeowner_pool(), below).
const HOMEOWNER_LINES: Dictionary = {
	"thrilled": [
		"Oh my GOD. You can see the GRASS. I forgot we HAD grass.",
		"Take this. Take it. If the NICE BOYS ask, you were never here.",
		"The neighbors are going to be sick with envy. Here. Buy something loud.",
		"Cleanest it's been in years. I'm putting you in the will. Not for much.",
		"Ten out of ten. I'm tipping in cash so there's no paper trail.",
		"I cried a little. Don't look at me. Here, take it and go.",
		"You did a great job, here's a tip!",
	],
	"happy": [
		"Nice work, nice boys. Wait. No. Forget I said that.",
		"Looks good! Don't count it in front of me, it's weird.",
		"Honestly? Better than my kid did. Don't tell him. Don't tell anyone.",
		"Solid. Here's your money. Go before the HOA sees your truck.",
		"You missed one leaf. Kidding. Or am I. Here.",
		"Good job. I'd shake your hand but I saw what it touched.",
	],
	"fine": [
		"Yeah, that's... a yard. Here.",
		"It's fine. It's fine. I said it's FINE. Here.",
		"Adequate. That's the word I'm going with. Adequate.",
		"I'll take it. Mostly because I'm not raking it myself.",
		"Thanks. Here's your money. Please stop looking at my windows.",
		"Three stars. Maybe three and a half. Don't push it.",
	],
	"slow": [
		"Took long enough, eh? The leaves were about to unionize.",
		"I watched the whole thing from the window. All of it. Here.",
		"The seasons changed. The leaves came back. You were still here.",
		"Did you take a nap in the bags? Here's your money.",
		# Flagged for Taylan (2026-11-01): the one line that jokes about calling
		# enforcement on the workers. Kept for now, recased.
		"I nearly called the NICE BOYS myself. Kidding. Mostly. Here.",
		"My coffee went cold three times. Three. Here.",
	],
	"messy": [
		"There's still leaves. I can see them. They can see me.",
		"Half a job gets half a thank you. Than. Here.",
		"My gnome has seen things today. Here. It's less than you wanted.",
		"I'm not paying full price for a yard that still crunches.",
		"You call this clean? The raccoons filed a complaint.",
		"I've seen tidier yards AFTER a tornado. Here. Go.",
	],
	"nothing": [
		"You haven't bagged anything. Are you here for the Wi-Fi?",
		"Nothing in the truck. Nothing in my heart. Come back with bags.",
		"I pay per bag. Zero bags. I can do that math. Can you?",
		"Did you come to LOOK at the leaves? Because they're looking back.",
		"The rake is right there. It's the thing with the teeth.",
	],
	"bill_hose": [
		"That hose was a gift from my mother. It's coming out of your pay.",
		"You MOWED my HOSE. Who mows a hose. Here. Minus a hose.",
		"The hose is in three pieces. So is my patience. Here.",
	],
	"bill_gnome": [
		"You ran over the gnome. He had a NAME. I'm not telling you it. Here.",
		"The gnome's been in this family longer than my husband. Minus the gnome.",
		"I heard the gnome go through the mower. The whole street heard. Here.",
	],
	"bill_medical": [
		"I saw the foot. The whole street saw the foot. The clinic bill's yours.",
		"Somebody's foot is in my hedge. I'm taking the clinic off the top.",
		"Not my foot, not my problem, but the ambulance was my phone call. Here.",
	],
	# ---- cast
	"bill_water": [
		"That was MY water. I could hear the meter spinning.",
		"I'm billing you for the water. And for the sound of it.",
		"Next time bring your own water. Or rain.",
	],
	"paid": [
		"Thanks!",
		"Pleasure doing business. Mostly.",
		"Same time next week? Don't answer that.",
		"Go on, before I check the gutters.",
	],
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


## A rating as five stars, filled to the nearest whole star: "★★★☆☆".
static func stars(rating: float) -> String:
	var filled := clampi(int(round(rating)), 0, 5)
	return "★".repeat(filled) + "☆".repeat(5 - filled)


# ---- shops
# docs/GAME.md, "Shops". Every core/catalog.gd id has item_<id> and item_blurb_<id>;
# every shop has shop_title_<shop>, every tab shop_tab_<tab>. Kept apart from UI so
# the shop chunks and other writers don't edit the same lines.

const SHOP_UI: Dictionary = {
	# Shops and tabs.
	"shop_title_homie_depot": "Homie Depot",
	"shop_title_rustys": "Rusty's Salvage & Pawn",
	"shop_title_lunch_money": "Lunch Money",
	"shop_title_snak_o_matic": "Snak-o-Matic",
	"shop_subtitle_homie_depot": "Tools, upgrades, and everything a crew runs out of",
	"shop_subtitle_rustys": "WE BUY JUNK. WE SELL JUNK.",
	"shop_subtitle_lunch_money": "Food-shaped fuel. Chefty-certified.",
	"shop_subtitle_snak_o_matic": "EXACT CHANGE PREFERRED. NOT REQUIRED. NOT RETURNED.",
	"shop_tab_tools": "Tools",
	"shop_tab_upgrades": "Upgrades",
	"shop_tab_supplies": "Supplies",
	"shop_tab_workwear": "Workwear",
	"shop_tab_truck": "Truck",
	"shop_tab_sell": "Sell",
	"shop_tab_used": "Used",
	"shop_tab_oddities": "Oddities",
	"shop_tab_menu": "Menu",
	"shop_tab_snacks": "Snacks",
	"shop_hours": "Open %s to %s",
	"shop_hours_always": "Open all hours. Watching.",
	# Keepers.
	"keeper_marty": "Marty",
	"keeper_rusty": "Rusty",
	"keeper_dot": "Dot",
	# Tools: stock (the names match UI tool_*), Mk II, Mk III, and Rusty's used ones.
	"item_leaf_blower": "Leaf blower",
	"item_lawn_mower": "Lawn mower",
	"item_ladder": "Ladder",
	"item_hose": "Garden hose",
	"item_hedge_trimmer": "Hedge trimmer",
	"item_pressure_washer": "Pressure washer",
	"item_paint_roller": "Paint roller",
	"item_blurb_leaf_blower": "Blasts leaves into piles way faster than raking. Hold left click.",
	"item_blurb_lawn_mower": "Push it around to mow. Heavy, loud, satisfying.",
	"item_blurb_ladder": "Reach the gutters. Hold left click under one to scoop it out.",
	"item_blurb_hose": "Spray dirty windows clean from across the yard.",
	"item_blurb_hedge_trimmer": "Turns shaggy hedges into neat ones.",
	"item_blurb_pressure_washer": "Blasts the grime off driveways.",
	"item_blurb_paint_roller": "Fresh paint on faded fences.",
	"item_leaf_blower_mk2": "Leaf blower Mk II",
	"item_lawn_mower_mk2": "Lawn mower Mk II",
	"item_ladder_mk2": "Ladder Mk II",
	"item_hose_mk2": "Garden hose Mk II",
	"item_hedge_trimmer_mk2": "Hedge trimmer Mk II",
	"item_pressure_washer_mk2": "Pressure washer Mk II",
	"item_paint_roller_mk2": "Paint roller Mk II",
	"item_blurb_leaf_blower_mk2": "Faster, wider, quieter. The neighbors only mostly hear it.",
	"item_blurb_lawn_mower_mk2": "Cuts faster and grumbles less. Starts on a good day.",
	"item_blurb_ladder_mk2": "Longer reach, fewer wobbles. Wobbles still included.",
	"item_blurb_hose_mk2": "A longer hose with opinions about water pressure.",
	"item_blurb_hedge_trimmer_mk2": "Sharper, quieter, and slightly smug about it.",
	"item_blurb_pressure_washer_mk2": "More pressure, less noise, same lack of safety rails.",
	"item_blurb_paint_roller_mk2": "A fatter roller for people with places to be.",
	"item_leaf_blower_mk3": "Leaf blower Mk III",
	"item_lawn_mower_mk3": "Lawn mower Mk III",
	"item_ladder_mk3": "Ladder Mk III",
	"item_hose_mk3": "Garden hose Mk III",
	"item_hedge_trimmer_mk3": "Hedge trimmer Mk III",
	"item_pressure_washer_mk3": "Pressure washer Mk III",
	"item_paint_roller_mk3": "Paint roller Mk III",
	"item_blurb_leaf_blower_mk3": "Black and gold. Shoves leaves into next week. Whispers.",
	"item_blurb_lawn_mower_mk3": "Starts on the first pull. Every pull. It respects you.",
	"item_blurb_ladder_mk3": "Climbs twice as fast. Do not ask how a ladder does that.",
	"item_blurb_hose_mk3": "Forty meters of hose. Water the whole block. Get billed by the whole block.",
	"item_blurb_hedge_trimmer_mk3": "Cuts a double-wide swath. Hedges fear it.",
	"item_blurb_pressure_washer_mk3": "The tank lasts twice as long. Driveways surrender.",
	"item_blurb_paint_roller_mk3": "Holds three times the paint. Dip less, roll more, judge others.",
	"item_leaf_blower_used": "Used leaf blower",
	"item_lawn_mower_used": "Used lawn mower",
	"item_ladder_used": "Used ladder",
	"item_hose_used": "Used garden hose",
	"item_hedge_trimmer_used": "Used hedge trimmer",
	"item_pressure_washer_used": "Used pressure washer",
	"item_paint_roller_used": "Used paint roller",
	"item_blurb_leaf_blower_used": "Works. Slower, louder, thirstier. Rusty says it has character.",
	"item_blurb_lawn_mower_used": "Takes a few extra pulls. And a few words you shouldn't say.",
	"item_blurb_ladder_used": "Every rung is there. Rusty counted twice.",
	"item_blurb_hose_used": "Only leaks where it counts.",
	"item_blurb_hedge_trimmer_used": "Rattles like a shopping cart. Still trims.",
	"item_blurb_pressure_washer_used": "Loud enough to hear from the next hood. Mostly washes.",
	"item_blurb_paint_roller_used": "Pre-painted. Several colors. None of them yours.",
	# Upgrades.
	"item_rake_tier_1": "Rake tune-up",
	"item_blurb_rake_tier_1": "Raking moves more leaves per stroke.",
	"item_rake_tier_2": "The Leafinator",
	"item_blurb_rake_tier_2": "The rake tune-up, again, harder. Rake Mk III. Not street legal.",
	"item_wheelbarrow_tier_1": "Bigger wheelbarrow",
	"item_blurb_wheelbarrow_tier_1": "Holds twice the bags. Tips over twice as dramatically.",
	# Supplies (for the whole crew).
	"item_lawn_bags": "Lawn bags",
	"item_blurb_lawn_bags": "A roll of bags. Every pile you bag uses one.",
	"item_big_bags": "Contractor bags",
	"item_blurb_big_bags": "Scoop wider, so fewer, fatter bags. Used before lawn bags.",
	"item_gas_can": "Gas can",
	"item_blurb_gas_can": "Gas for the mower, blower, trimmer, and washer. Rides along in Chefty.",
	"item_fertilizer": "Fertilizer",
	"item_blurb_fertilizer": "Spring and summer. Lawns love it. Noses don't.",
	"item_grass_seed": "Grass seed",
	"item_blurb_grass_seed": "Spring only. Bare patches, meet your future.",
	"item_rock_salt": "Rock salt",
	"item_blurb_rock_salt": "Winter only. For walks that have it out for somebody.",
	"item_vend_bags": "Bag roll (small)",
	"item_blurb_vend_bags": "A small roll of bags, at vending-machine prices.",
	# Workwear.
	"item_hat_hd_cap": "Homie Depot cap",
	"item_blurb_hat_hd_cap": "Orange. Official-ish. Marty's employee discount does not apply.",
	"item_hat_beanie": "Beanie",
	"item_blurb_hat_beanie": "Warm ears, cool crew.",
	"item_hat_bucket": "Bucket hat",
	"item_blurb_hat_bucket": "Keeps the sun off and the respect away.",
	"item_hat_hard": "Hard hat",
	"item_blurb_hat_hard": "For when the ladder wins.",
	"item_hat_cowboy": "Cowboy hat",
	"item_blurb_hat_cowboy": "Yeehaw is a lifestyle. So is raking.",
	"item_hat_chef": "Chefty chef's hat",
	"item_blurb_hat_chef": "Chefty-brand. Cooks nothing. Commands respect.",
	"item_hat_crown": "The Lawnfather's crown",
	"item_blurb_hat_crown": "For the crew who raked the whole town. Heavy is the head.",
	"item_shirt_0": "Red shirt dye",
	"item_shirt_1": "Orange shirt dye",
	"item_shirt_2": "Yellow shirt dye",
	"item_shirt_3": "Green shirt dye",
	"item_shirt_4": "Teal shirt dye",
	"item_shirt_5": "Blue shirt dye",
	"item_shirt_6": "Purple shirt dye",
	"item_shirt_7": "Gray shirt dye",
	"item_blurb_shirt_0": "Your shirt, but red. Hides ketchup.",
	"item_blurb_shirt_1": "Your shirt, but orange. Matches the cones.",
	"item_blurb_shirt_2": "Your shirt, but yellow. Visible from space.",
	"item_blurb_shirt_3": "Your shirt, but green. Camouflage on a lawn.",
	"item_blurb_shirt_4": "Your shirt, but teal. Nobody knows why.",
	"item_blurb_shirt_5": "Your shirt, but blue. Calm under pressure washers.",
	"item_blurb_shirt_6": "Your shirt, but purple. Royalty of the rake.",
	"item_blurb_shirt_7": "Your shirt, but gray. Blends into the paperwork.",
	"item_shirt_hivis": "Hi-vis vest",
	"item_blurb_shirt_hivis": "Looks official. The NICE BOYS can tell.",
	# Chefty: paint and decals.
	"item_paint_classic": "Factory red paint",
	"item_blurb_paint_classic": "Chefty as the factory intended. Free, because it's already on there.",
	"item_paint_mint": "Mint paint",
	"item_blurb_paint_mint": "Fresh. Minty. Smells like paint.",
	"item_paint_sunset": "Sunset paint",
	"item_blurb_paint_sunset": "Orange fading into more orange. Very evening.",
	"item_paint_pink": "Hot pink paint",
	"item_blurb_paint_pink": "Impossible to lose in a parking lot.",
	"item_paint_black": "Matte black paint",
	"item_blurb_paint_black": "Very serious. Very stealthy. Still says Chefty.",
	"item_paint_gold": "GOLD paint",
	"item_blurb_paint_gold": "Solid gold. Not actually gold. Do not scratch it anyway.",
	"item_decal_stripes": "Racing stripes",
	"item_blurb_decal_stripes": "Adds zero speed. Feels like more.",
	"item_decal_googly": "Googly eyes",
	"item_blurb_decal_googly": "On the grille. Chefty sees you now.",
	"item_decal_flames": "Flames",
	"item_blurb_decal_flames": "Hot rod energy for a truck full of leaves.",
	"item_decal_leaves": "Leaf wrap",
	"item_blurb_decal_leaves": "Chefty, covered in the thing you get paid to remove.",
	"item_decal_rust": "Rust bucket",
	"item_blurb_decal_rust": "Painted-on rust. Cheapest decal in town. Rusty's proudest work.",
	# Rusty's oddities.
	"item_hat_cone": "Traffic cone hat",
	"item_blurb_hat_cone": "Found it. Do not ask where. Do not return it there.",
	"item_hat_propeller": "Propeller beanie",
	"item_blurb_hat_propeller": "Spins when you run. Lift not included.",
	"item_hat_viking": "Viking helmet",
	"item_blurb_hat_viking": "Raid yards. Politely. With permission and an invoice.",
	# Lunch Money.
	"item_hot_dog": "Hot dog",
	"item_blurb_hot_dog": "Full for a while: carrying heavy things slows you half as much.",
	"item_turbo_juice": "Turbo Juice",
	"item_blurb_turbo_juice": "Fast feet and fast rake strokes. Then the crash. Then the yawn.",
	"item_coffee": "Burnt coffee",
	"item_blurb_coffee": "Hold heavy things longer before you strain or faint. Tastes like a tire.",
	"item_hat_lunch_money": "Lunch Money trucker cap",
	"item_blurb_hat_lunch_money": "Dot's merch. Mesh back. Smells faintly of onions.",
	# Snak-o-Matic.
	"item_vend_sandwich": "Gas-station-adjacent sandwich",
	"item_blurb_vend_sandwich": "Half the time you're full. The other half, you know what you did.",
	"item_vend_turbo": "Turbo Juice (warm)",
	"item_blurb_vend_turbo": "The same Turbo Juice, from a machine, at room temperature.",
	# Junk for Rusty's.
	"junk_old_tv": "Old TV",
	"junk_tire": "Bald tire",
	"junk_grill": "Busted grill",
	"junk_toilet": "Toilet",
	"junk_bike": "Bike frame",
	"junk_flamingo": "Lawn flamingo",
	"junk_mannequin": "Mannequin",
	"junk_boombox": "Boombox",
	"junk_flamingo_vintage": "Vintage flamingo",
	# Buffs.
	"buff_full": "Full",
	"buff_turbo": "Turbo",
	"buff_crash": "Crashing",
	"buff_coffee": "Wired",
	"buff_queasy": "Queasy",
	# The shop window.
	"shop_stock_left": "%d left today",
	"shop_crew_has": "Crew has: %d bags · %d gal",
	"shop_sold_out": "SOLD OUT",
	"shop_owned_tag": "OWNED",
	"shop_price_tag": "$%d",
	"shop_rank_tag": "Rank: %s",
	"shop_free": "Free",
	"shop_buy_qty": "x%d",
	"shop_next_tier": "%s $%d",
	"shop_wear": "Wear",
	"shop_wearing": "Wearing",
	"shop_apply": "Put it on Chefty",
	"shop_applied": "On Chefty",
	"shop_out_of_season": "Not this season",
	"shop_closed_shutter": "CLOSED\nOpens %s",
	"shop_offer": "Rusty offers $%d",
	"shop_take": "Take it",
	"shop_haggle": "Haggle",
	"shop_scale_empty": "Put junk on the scale.",
	"haggle_won": "Fine. FINE. You drive a hard bargain for a toilet.",
	"haggle_lost": "Now it's worth less. Emotionally.",
	"rusty_mood_0": "TODAY: GRUMPY",
	"rusty_mood_1": "TODAY: EH",
	"rusty_mood_2": "TODAY: PAYING GOOD",
	"gone_fishin": "GONE FISHIN'\nback tomorrow, probably",
	# What the host says back about a buy (Shops.result codes).
	"shop_result_ok": "Bought: %s",
	"shop_result_closed": "Closed",
	"shop_result_far": "Get closer to the counter",
	"shop_result_locked": "Not for sale at your rank yet",
	"shop_result_sold_out": "Sold out",
	"shop_result_owned": "You already own that",
	"shop_result_needs": "You need the one before it first",
	"shop_result_short": "Not enough cash",
	"shop_result_eaten": "The machine thanks you for your donation.",
	"shop_result_full": "No room for more",
	"shop_result_season": "Not this season",
	# Prompts, hints, and goals.
	"prompt_shop_closed": "Closed. Opens %s",
	"prompt_look_at": "Look at %s",
	"prompt_refuel": "Fill it up (%d%%)",
	"prompt_vending": "Use the Snak-o-Matic",
	"hud_out_of_bags": "Out of lawn bags. Homie Depot, the Snak-o-Matic, or your phone.",
	"hud_out_of_gas": "Out of gas",
	"goal_out_of_gas": "Out of gas. Hold the gas can and press E at the tool",
	# Phone: Orders (app id "deliveries") and Closet.
	"phone_tab_deliveries": "Orders",
	"phone_tab_closet": "Closet",
	"deliveries_title": "Homie Depot Deliveries",
	"deliveries_locked": "Deliveries open at %s",
	"deliveries_order": "Order ($%d incl. fees)",
	"deliveries_fees": "Price + $%d + %d%% (delivery fee, service fee, fee fee)",
	"deliveries_eta": "%s  ·  arrives %s",
	"deliveries_cap": "%d of %d orders on the way",
	"deliveries_none": "Nothing on the way.",
	"deliveries_full": "That's every order the van can take. The van has feelings.",
	"closet_title": "Closet",
	"closet_empty": "Nothing in here but a lonely hanger. Buy a hat.",
	"closet_wearing": "Wearing: %s",
	"pay_crewmate_title": "Pay a crewmate",
	"pay_crewmate_button": "$%d to %s",
	"pay_crewmate_sent": "You sent %s $%d",
	"pay_crewmate_got": "%s sent you $%d",
	# Texts.
	"text_from_marty": "Marty (Homie Depot)",
	"text_from_rusty": "Rusty",
	"text_from_deliveries": "Homie Depot Deliveries",
	"text_emergency_bags": "Found a few bags behind the paint mixer. Don't tell the manager.",
	"text_rusty_welcome": "Heard you're working the Acres. Bring me their junk. I pay cash. Mostly.",
	"text_delivery": "Your order's on the pallet in the back room: %s. Nobody signed for it. Nobody ever does.",
}

## What the shopkeepers say ({keeper: {trigger: [lines]}}, docs/GAME.md
## "Shops"). Triggers: greet (walking up), morning, night, open (the window
## opens), buy (Shops.result ok), after_raid, closed. Rusty, Dot and the
## Snak-o-Matic's screen are the shops writing; Marty's lines (last) are the cast's.
const KEEPER_LINES: Dictionary = {
	"rusty": {
		"greet": [
			"Yard's open. Mind the tires, they bite.",
			"Bring me something heavy. Heavy pays.",
			"Look around. Don't touch the mannequin. She's shy.",
		],
		"morning": [
			"Early bird gets the bald tire.",
			"Coffee's on. Coffee's always on. Coffee's mostly rust.",
			"New junk came in. Same as the old junk, but newer.",
		],
		"night": [
			"Shouldn't you be raking somebody's yard in the dark?",
			"Closing soon. The raccoons run the night shift.",
			"Late shoppers get the late prices. Same prices. Later.",
		],
		"open": [
			"Scale's calibrated. By me. Trust the scale.",
			"Everything's for sale except my opinion. That's free.",
			"Cash only. Cash mostly. Cash eventually.",
		],
		"buy": [
			"Pleasure doing business. Mostly my pleasure.",
			"No refunds. No returns. No questions. No answers.",
			"That one's got character. Character's extra. You're welcome.",
		],
		"after_raid": [
			"Saw the NICE BOYS go by. Very tidy van. Suspiciously tidy.",
			"They asked if I'd seen you. I said I only see junk.",
			"Clipboard crews. Never once bought a single tire.",
		],
		"closed": [
			"GONE FISHIN'. The fish are not biting. Neither am I.",
			"Closed. Try again when the sign says so.",
			"Rusty's out. The junk is in. The junk will wait.",
		],
	},
	"dot": {
		"greet": [
			"Hi hi hi! Hungry? You look hungry. Everyone looks hungry.",
			"Welcome to Lunch Money! It's a truck! It's a lifestyle!",
			"Ooh, a customer! My favorite kind of person!",
		],
		"morning": [
			"Coffee's burnt already! That's how you know it's working!",
			"Breakfast hot dog? Breakfast hot dog.",
			"Early shift! I love an early shift! I've been up since four!",
		],
		"night": [
			"Night menu is the day menu but spookier!",
			"Turbo Juice after dark? Bold. I respect bold.",
			"Last call for food-shaped fuel!",
		],
		"open": [
			"Everything's made fresh-ish to order!",
			"Turbo Juice isn't approved by anybody! It's just juice! Turbo!",
			"Hot dogs, coffee, juice. The holy trinity of yard work!",
		],
		"buy": [
			"Enjoy! Chew! Chew more than that!",
			"Lunch Money thanks you! Chefty thanks you! I thank you!",
			"Great choice! They're all great choices! There are three!",
		],
		"after_raid": [
			"Those NICE BOYS tried to inspect my napkins. My napkins are fine!",
			"Still here! Still serving! Still very legally parked!",
			"Rough day? Rough days need hot dogs.",
		],
		"closed": [
			"Kitchen's closed! The kitchen is also the truck!",
			"Back tomorrow! Dot needs her beauty sleep!",
			"We're closed but I'm still waving! Hi!",
		],
	},
	"snak_o_matic": {
		"greet": [
			"HELLO VALUED CUSTOMER. INSERT CASH. INSERT HOPE.",
			"SNAK-O-MATIC IS LISTENING. SNAK-O-MATIC IS ALWAYS LISTENING.",
			"PLEASE STAND STILL WHILE SNAK-O-MATIC JUDGES YOU.",
		],
		"morning": [
			"GOOD MORNING. SANDWICHES WERE RESTOCKED AT SOME POINT.",
			"BREAKFAST OPTIONS: SANDWICH. SANDWICH AGAIN.",
			"SNAK-O-MATIC NEVER SLEEPS. SNAK-O-MATIC NEVER FORGETS.",
		],
		"night": [
			"OPEN ALL NIGHT. LIKE A FRIDGE LIGHT.",
			"AFTER-HOURS PRICING IS THE SAME. THE GUILT IS EXTRA.",
			"THE STORE IS CLOSED. SNAK-O-MATIC IS NOT. SNAK-O-MATIC IS NEVER CLOSED.",
		],
		"open": [
			"SELECT AN ITEM. SELECT IT WITH CONFIDENCE.",
			"ALL SALES FINAL. SOME SALES FINAL-ER.",
			"PRICES INCLUDE THE CONVENIENCE OF ME.",
		],
		"buy": [
			"THANK YOU. DISPENSING. PROBABLY.",
			"ENJOY YOUR SNACK. SNAK-O-MATIC WILL KNOW IF YOU DON'T.",
			"TRANSACTION COMPLETE. FRIENDSHIP PENDING.",
		],
		"after_raid": [
			"SNAK-O-MATIC SAW NOTHING. SNAK-O-MATIC HAS NO EYES. LEGALLY.",
			"VISITORS IN A VAN ASKED FOR RECEIPTS. SNAK-O-MATIC DOES NOT DO RECEIPTS.",
			"STRESS DETECTED. RECOMMENDED: SANDWICH.",
		],
		"closed": [
			"OUT OF ORDER. JUST KIDDING. SNAK-O-MATIC IS NEVER OUT OF ORDER.",
			"SNAK-O-MATIC IS OPEN. SNAK-O-MATIC IS ALWAYS OPEN.",
			"THERE IS NO CLOSED. THERE IS ONLY SNACK.",
		],
	},
	# Marty runs Homie Depot: a deadpan lifer who takes the store far too seriously and
	# lets the crew sleep by the side wall (cast writing).
	"marty": {
		"greet": [
			"Welcome to Homie Depot. If we don't have it, you didn't need it.",
			"Back again? The rakes missed you. I didn't. Kidding. I did.",
			"Aisle nine is out of aisle nine.",
			"Don't touch the display mower. It's load-bearing.",
		],
		"morning": [
			"Rise and shine. The leaves didn't sleep, so neither did I.",
			"New day, new leaves. Same me.",
			"Morning. Your cots are where you left them. So is the smell.",
		],
		"night": [
			"We're open. We're always open. I don't know how to leave.",
			"Keep it down. The cots are trying to sleep.",
			"Quiet hours. Whisper your purchases.",
		],
		"open": [
			"What'll it be? Don't say leaves. You have all the leaves.",
			"Everything's on sale. Not for you. In general.",
			"Here's the catalog. I wrote the descriptions. They're all true.",
		],
		"buy": [
			"Great choice. No refunds, spiritually or financially.",
			"That one comes with a warranty. The warranty is me saying good luck.",
			"Ring ring. That's the register. It's happy for you.",
		],
		"after_raid": [
			"Rough day? The NICE BOYS came in earlier and bought forty clipboards.",
			"You look like you got a courtesy notice. It's the eyes.",
			"Heard the van. Want a cot? You want a cot.",
		],
		"closed": [
			"The sign says closed. The sign is wrong. I'm here.",
			"We're closed. Technically. Spiritually, I'm still on shift.",
			"Closed. Come back in eight hours. I'll be right here. I'm always right here.",
		],
	},
}


## A catalog item's name: "Leaf blower Mk II". Falls back to the id.
static func shop_item_name(id: String) -> String:
	return str(SHOP_UI.get("item_" + id, id))


static func shop_item_blurb(id: String) -> String:
	return str(SHOP_UI.get("item_blurb_" + id, ""))


# ---------------------------------------------------------------- cast
# The cast's writing (docs/GAME.md, "2026-11-01, the cast"). Every joke here aims
# at forms, citations, quotas, clipboards, impossible work or homeowner pettiness.
# None aims at where anyone is from, their papers, language or accent, and the
# name NICE is never spelled out as an acronym (net/dev/cast_test.gd checks).

const _Ranks = preload("res://core/ranks.gd")

## Homeowners by personality (net/town/neighborhoods.gd PERSONALITIES), then mood
## (npcs/homeowner.gd STAGING). Pool id "<personality>/<mood>" (homeowner_pool()).
## Used about two times in three when the homeowner has a personality.
const PERSONALITY_LINES: Dictionary = {
	"easygoing": {
		"thrilled": [
			"Whoa. WHOA. Is that my lawn? I thought it was a rumor.",
			"You absolute legends. Keep the change. Keep all the change.",
			"Best day of my life, and I've been married twice.",
		],
		"happy": [
			"Looks great. I'd have done it myself, but, you know. I wouldn't have.",
			"Nice! I don't know the going rate, so I just grabbed some money.",
			"Sweet. The leaves were stressing out the dog.",
		],
		"fine": [
			"Hey, it's a yard now. Good enough for me. Here.",
			"Eh, they'll be back tomorrow anyway. Here.",
			"I mean, I wasn't gonna do it. So. Yeah. Here.",
		],
		"slow": [
			"Took a while, huh? No worries. Well, some worries. Here.",
			"I fell asleep in the hammock waiting. Twice. Honestly, nice.",
			"Long day? Mine too. I watched you the whole time.",
		],
		"messy": [
			"There's still a lot of leaves, buddy. Like, a lot a lot.",
			"I'm chill, but my lawn isn't. Here's less.",
			"Half a yard is better than... no, it's half. Here's half-ish.",
		],
		"nothing": [
			"No bags? That's cool. That's cool. Is it cool? No.",
			"You guys just hanging out? Respect. Can't pay for it, though.",
			"I'll pay when there's leaves in the truck, dude. Any leaves.",
		],
	},
	"chatty": {
		"thrilled": [
			"Oh, this is WONDERFUL. Wait till I tell my sister. And her book club. And the mailman.",
			"My knee's been acting up, so you've saved me. Let me tell you about the knee. Actually, here's money.",
			"I'm putting you on my holiday card. You, the truck, the rake. All of it.",
		],
		"happy": [
			"Lovely! My husband used to rake. Badly. You're much better. Here.",
			"Good job, hon! Did I tell you about my cousin's gutters? Remind me next time.",
			"Nice work! I talked the whole time. Did you hear any of it? Here.",
		],
		"fine": [
			"Well, it's not how Gerald did it, but Gerald lives in Florida now. Here.",
			"It's fine! Fine. Do you want lemonade? No? More for me. Here.",
			"That'll do. That'll do! I say that about everything. Here.",
		],
		"slow": [
			"I've told you my whole life story twice. TWICE. And you're only done now?",
			"I started a scarf when you got here. It's a blanket now.",
			"My soap opera had a wedding, a divorce, and a secret twin while you raked.",
		],
		"messy": [
			"Now, I don't like to complain, but I'm going to. At length.",
			"Hon, there are more leaves than when I started talking, and I talked a LOT.",
			"I'll tell everyone you did great. I'll be lying. Here's less.",
		],
		"nothing": [
			"No bags, sweetie? Was it something I said? I said a lot.",
			"Empty truck! Well, sit down. I'll tell you about my knee instead.",
			"An hour, zero bags. I talked for an hour. I guess we're even.",
		],
	},
	"grumpy": {
		"thrilled": [
			"Hm. Huh. Well. ...It's good. Tell no one I said that.",
			"I've hated every crew I ever hired. I don't hate you. Take it before I change my mind.",
			"Fine. FINE. It's perfect. Are you happy? Here.",
		],
		"happy": [
			"Not bad. I've seen worse. I've mostly seen worse.",
			"Acceptable. Here's money. Don't spend it on anything fun.",
			"You did okay. My standards are low, but they exist.",
		],
		"fine": [
			"It's a yard. I've got a yard. Thrilling. Here.",
			"In my day we raked uphill. Both ways. Here.",
			"I've had better. I've had worse. Mostly better.",
		],
		"slow": [
			"I aged. Look at me. I aged watching you.",
			"I could've grown a beard. I did grow a beard. Here.",
			"By the time you finished, the trees wanted a second opinion.",
		],
		"messy": [
			"I can see leaves from my recliner. My recliner faces the wall.",
			"Garbage work. Here's garbage money.",
			"You raked like the leaves owed you money.",
		],
		"nothing": [
			"Get off my lawn. No, wait. Clean my lawn. THEN get off it.",
			"Zero bags. Zero dollars. I'm a fair man.",
			"I've seen squirrels do more. I've PAID squirrels to do more.",
		],
	},
	"neat_freak": {
		"thrilled": [
			"Every blade. Every single blade. I may weep. Here.",
			"I measured. You're within tolerance. Nobody is ever within my tolerance.",
			"It's perfect. I'm vacuuming it anyway, but it's perfect.",
		],
		"happy": [
			"Very good. I found one leaf, but I've decided to let it live.",
			"Crisp edges. I noticed the edges. Here.",
			"Ninety-seven percent. I'll do the other three with tweezers.",
		],
		"fine": [
			"It's... fine. I'll redo it tonight with a flashlight.",
			"There's a leaf on the walkway. There's a leaf on the walkway. Here.",
			"I'm paying you, but I'm also making a list.",
		],
		"slow": [
			"I had a schedule. It was color-coded. You ruined all the colors.",
			"I alphabetized my spices while I waited. Then by expiry. Then by mood.",
			"I timed you. I won't say the number out loud.",
		],
		"messy": [
			"I need you to see what I see. Leaves. Everywhere. Here's less.",
			"This is a crime scene, and the leaves are the victims. And the suspects.",
			"I'm docking you a dollar a leaf. Kidding. It's more than that.",
		],
		"nothing": [
			"The truck is empty and the yard is full. That's the opposite of what I asked.",
			"I color-coded the bags for you. You didn't fill a single color.",
			"Nothing? I need to lie down on something clean.",
		],
	},
	"nosy": {
		"thrilled": [
			"Beautiful! The Hendersons are SO jealous. I watched them watch you.",
			"Now everyone will ask who did it, and I'll tell them. I tell everyone everything.",
			"Perfect! I'm telling the whole street. I told half of it while you worked.",
		],
		"happy": [
			"Good work! Who's the tall one? Single? Asking for the whole street.",
			"Very nice. I took photos. For the newsletter. And my files.",
			"Nice job! I saw your break at 2:14. Don't worry, I won't tell. I'll tell.",
		],
		"fine": [
			"It's alright. Number twelve's crew did better. I watched through their blinds.",
			"Fine. I wrote down everything you did, so I'll know if it was fine.",
			"Here. Don't tell number eight what I paid you. I'll tell them myself.",
		],
		"slow": [
			"I watched the whole thing with binoculars. It was a slow movie.",
			"You took so long the neighbors started a betting pool. I lost.",
			"I've learned so much about you. Too much. Here.",
		],
		"messy": [
			"The whole street can see this. I KNOW, because I asked the whole street.",
			"Mrs. Albright's leaves are on my side now. Did you DO that?",
			"I'll be telling people about this. Accurately, for once.",
		],
		"nothing": [
			"I watched you do nothing for an hour. I have it written down. Timestamped.",
			"No bags? The neighbors are going to TALK. I'm the neighbors.",
			"I was so excited to watch you work. I'm still waiting to.",
		],
	},
	"penny_pincher": {
		"thrilled": [
			"Spectacular. Count it twice. Actually, give it back, I'll count it.",
			"Worth every penny. I mean that literally. Here are the pennies.",
			"I'm so happy I'm tipping. A coupon. It's barely expired.",
		],
		"happy": [
			"Nice work. Here. Some of it's in quarters.",
			"Good. I'd pay more, but I'd rather not.",
			"Here's your money. I'm going to miss it.",
		],
		"fine": [
			"That's fine. Do you take exposure as payment? No? Fine. Here.",
			"Adequate. I'm paying for adequate. Adequate is on sale.",
			"Full rate. For a slightly smaller yard.",
		],
		"slow": [
			"I pay by the job, not the hour. Just so you know, I thought about switching.",
			"You took so long I almost started charging YOU rent.",
			"Time is money, and you used up all of mine.",
		],
		"messy": [
			"I'm not paying for leaves I can still see. I'm a very visual person.",
			"I did the math. I always do the math. Here's the math.",
			"Half a yard, half a payment. Rounded down. I always round down.",
		],
		"nothing": [
			"Zero bags times my rate is my favorite number.",
			"Money for nothing? Me too. Nobody's getting it.",
			"This money stays right where it belongs. With me.",
		],
	},
}
## Phone texts. The host composes them from these pools and saves the final text.
## "request" has a generic pool and one per personality (client_line()); each
## request line takes the address (%s).
const TEXT_LINES: Dictionary = {
	"request": {
		"generic": [
			"Leaves are back. You know where I live. %s.",
			"Can your crew come by today? %s. Bring the good rake.",
			"It's a jungle out here again. %s, whenever you can.",
			"Hi it's me. The yard. %s. Please.",
			"My spouse says the yard is \"a disgrace\". %s. Help.",
		],
		"easygoing": [
			"Yo, leaves are back at %s. Whenever. No rush. Kind of a rush.",
			"Hey, it's me from %s. The yard's doing the thing again.",
			"%s could use you. Bring snacks, or don't. Chill either way.",
		],
		"chatty": [
			"Hi!! It's me, from %s!! The leaves are back and so is my knee thing, long story, come by!!",
			"Hello, dear. %s again. Bring the tall one. He listens.",
			"%s, today if you can! I have so much to tell you. Also, leaves.",
		],
		"grumpy": [
			"%s. Leaves. Now.",
			"Leaves again at %s. Don't make it a whole thing.",
			"%s. You know the drill. Don't be late, or early.",
		],
		"neat_freak": [
			"%s. I counted 4,112 leaves this morning. I need that number to be zero.",
			"%s needs you. The walkway has been compromised.",
			"Please come to %s. Bring the good rake. The one with all its teeth.",
		],
		"nosy": [
			"Hi, it's %s! Number six got a crew yesterday, so I need one TODAY.",
			"Come by %s! I'll make coffee and you can tell me about everyone.",
			"%s, whenever you're free. I already know when you're free.",
		],
		"penny_pincher": [
			"%s has leaves. Is there a loyalty discount? There should be.",
			"Job at %s. I hear your rates are reasonable. I'll be the judge.",
			"%s. Bring your own bags. And your own water. And your own lunch.",
		],
	},
	# From Marty (UI clerk_name): the first morning's welcome, and leads he passes on.
	"clerk_intro": [
		"Welcome to the crew. Three of your neighbors want their leaves gone. Check the board by the checkout. The cots by the side wall are yours after 6 PM. Tab to check your phone.",
	],
	"clerk_lead": [
		"Somebody came by the store asking for a leaf crew. I gave them your number. You're welcome.",
		"Lady at register two needs her yard done. I said you were the best. I lied a little.",
		"Guy bought eleven rakes and gave up. Sending him your way.",
	],
	# A referral is referral_body % [how, address, neighborhood], where how is
	# referral_named % referrer, or a referral_anon line.
	"referral_named": [
		"%s says you're good with a rake.",
		"%s won't stop talking about you.",
		"%s gave me your number, and a warning.",
		"%s says you're the crew with the wheelbarrow trick.",
	],
	"referral_anon": [
		"Saw your truck around.",
		"Your truck parked by my house and I took it as a sign.",
		"Found your number on a leaf.",
	],
	"referral_body": [
		"Hi! %s I'm at %s in %s. Got leaves?",
		"%s I'm over at %s, %s. My yard is an emergency.",
		"%s It's %s, in %s. When can you start? Yesterday?",
	],
	# TurfMasters™: a client leaving you, and coming back (why, then a tail line).
	"poached": [
		"TurfMasters™ came by with a coupon. Sorry, hon. It's just business.",
		"A man in a TurfMasters™ polo said you people \"lack synergy\". I'm trying them.",
		"TurfMasters™ does my lawn now. They have a jingle. Do YOU have a jingle?",
		"TurfMasters™ gave me a fridge magnet. Nobody's ever given me a fridge magnet.",
		"They said they'd do my lawn 'at scale'. I don't know what it means, but I want it.",
	],
	"won_back_named": [
		"Saw what you did for %s. TurfMasters™ mulched my petunias.",
		"%s's yard looks incredible. TurfMasters™ painted my grass green. With paint.",
		"%s told me everything. TurfMasters™ never told me anything.",
	],
	"won_back_signs": [
		"Somebody pulled the TurfMasters™ signs. Was that you? Come back?",
		"The TurfMasters™ signs are gone and I feel free.",
		"No more signs on my lawn. Was that you? Thank you?",
	],
	"won_back_tail": [
		"I'm back, if you'll have me.",
		"Take me back. I'll pay on time. Mostly.",
		"Same yard. Same me. Fewer coupons.",
	],
	# From TurfMasters™ themselves (UI rival_name, text kind "rival").
	"rival_arrival": [
		"Hi! TurfMasters™ is proud to be your town's new Lawn Solution™. Your services are no longer required™.",
		"TurfMasters™ has arrived! LAWNS DONE RIGHT™. Lawns done by you: under review™.",
	],
	"rival_taunt": [
		"Thank you for choosing TurfMasters™! (Not you. Your client.)",
		"Another satisfied TurfMasters™ customer! Formerly yours! Synergy!",
		"This is an automated message from TurfMasters™. We are automating your clients.",
		"TurfMasters™ Tip: have you tried being a franchise?",
	],
	"rival_sign": [
		"We noticed a TurfMasters™ sign is missing. Our signs have feelings™.",
		"Please return our sign. It was on a payment plan.",
		"Pulling signs is not a LAWN SOLUTION™.",
	],
	"rival_sore": [
		"TurfMasters™ is aware of some churn. We have scheduled a meeting about the churn.",
		"We're sorry to see a customer go. To you. Specifically you.",
		"TurfMasters™ wishes you the best™. Legally.",
	],
	# Hired hands (net/crew/hires.gd). hire_quit takes another hand's name.
	"hire_hired": [
		"Thanks for the gig, boss. I'll be on the truck. I bring my own rake (it's yours now).",
		"First day! Where do I put my lunch? In a leaf bag? Got it.",
		"Reporting for duty. I've raked before. Once. In a dream.",
	],
	"hire_quit": [
		"No pay, no rake. I'm out. Tell %s I said bye.",
		"No pay, no play. Tell %s the good wheelbarrow is behind the shed.",
		"I'm out. %s owes me five bucks. Collect it for me.",
	],
	"hire_fired": [
		"Fine. FINE. I'm keeping the gloves.",
		"That's fair. I did throw the rake at the homeowner.",
		"I'll be fine. I'm going to TurfMasters™. Kidding. Unless.",
	],
}

## Run-event captions (ui/run_cues.gd). Picked with pick_seeded() from the phase's
## start time, so every peer shows the same line.
const CUE_LINES: Dictionary = {
	"radio": [
		"RADIO: the NICE BOYS are on the way to this address",
		"RADIO: Courtesy Patrol to all units, we have a yard situation at this address.",
		"RADIO: Somebody reported excessive raking at this address.",
		"RADIO: The NICE BOYS are on the way. They packed extra clipboards.",
	],
	"arrived": [
		"The NICE BOYS are here. Run. Hide. Break line of sight.",
		"The NICE BOYS are here. Hide in a pile, throw a gnome, be anywhere else.",
		"The NICE BOYS are here. Don't let them see you get into a pile.",
	],
	"clear": [
		"All clear",
		"All clear. The NICE BOYS left a courtesy notice on your rake.",
		"All clear. Somebody's filling out a LOT of forms about you.",
		"All clear. They'll be back. They have a quota.",
	],
}

## What the NICE BOYS call out (npcs/crew_member.gd barks), by what they're doing.
## The host picks the kind and the line; the caption carries the joke, the audio
## is megaphone babble.
const CREW_BARKS: Dictionary = {
	"arrive": [
		"Hello hello! This is a courtesy visit!",
		"Nobody move! Politely!",
		"Hi! We've had a complaint about your vibes!",
		"Everybody stay right there and have a NICE day!",
		"This yard was selected for a random friendliness check!",
	],
	"spot": [
		"Sir! SIR! A word! Several words! On a form!",
		"Excuse me! You appear to be raking without a smile!",
		"Hold it right there, friend!",
		"I see you! I'm writing down that I see you!",
		"Stop! In the name of neighborliness!",
	],
	"chase": [
		"Running is a violation of the walking ordinance!",
		"We just want to talk! It's a short form! Eleven pages!",
		"Slow down! My lanyard's tangling!",
		"This would go faster if you'd cooperate pleasantly!",
		"You're making my clipboard nervous!",
	],
	"lost": [
		"Where'd they go? Check behind the... everything.",
		"Nobody panic. I'll make a note that we lost them.",
		"They were RIGHT here. I have it in writing.",
		"Has anybody seen a suspicious rake?",
		"Fan out! But not too far, we carpool.",
	],
	"search": [
		"Come out, come out, wherever you're non-compliant!",
		"We have cookies! They're for evidence!",
		"Statistically, you're in a leaf pile.",
		"Psst. Is anybody hiding? You can just tell us.",
		"This pile looks suspiciously fluffy.",
	],
	"pile": [
		"I saw that! Leaf piles are not a valid hiding place, per section 4!",
		"Knock knock! On the pile!",
		"We saw you go in there, friend!",
	],
	"caught": [
		"Gotcha! Have a NICE day!",
		"Thank you for your cooperation! Into the van!",
		# Flagged for Taylan (2026-11-01): riffs on generic arrest language, names no agency.
		"You have the right to remain pleasant!",
		"Another happy customer!",
		"Don't worry, the van has cupholders!",
	],
	"bonked": [
		"OW! That's a citation!",
		"Assaulting a clipboard is a serious offense!",
		"My visor! I'm writing this up!",
		"Rude! Very, very rude!",
		"Was that a GNOME?!",
	],
}

## The NICE BOYS' name tags (crew_tag()): suburban middle-manager names, none of
## them a homeowner's first name, picked per day so they change daily.
const CREW_NAMES: Array[String] = [
	"BRENT", "TODD", "KYLE", "CHIP", "LANCE", "TREVOR",
	"SKIP", "DIRK", "RODNEY", "WADE", "CLINT", "DARREN",
]

## Under "RANK UP" on the day summary when the crew reaches a rank's tier I,
## keyed by the rank's name (core/ranks.gd NAMES and ENDLESS_NAME).
const RANK_BLURBS: Dictionary = {
	"Rake Rookie": "Everybody starts somewhere. You started in a leaf pile.",
	"Leaf Grunt": "Promoted from 'those guys' to 'that crew'.",
	"Bag Hauler": "Your backs hurt in a professional way now.",
	"Mulch Mule": "Strong, stubborn, faintly smells of mulch. Somebody else is noticing.",
	"Hedge Hog": "Prickly. Productive. Kind of cute about it.",
	"Turf Boss": "People call you boss now. Some of them even mean it.",
	"Lawn Lord": "Mansion Hill knows your name. Mansion Hill mispronounces it.",
	"Yard Baron": "You own the block. Well, you rake it. Same thing, spiritually.",
	"The Lawnfather": "You don't do lawns anymore. Lawns get done, out of respect.",
}

## Under a rank-up to tiers II to V (and each Lawnfather star), in tier order.
const TIER_BLURBS: Array[String] = [
	"A little more legit than yesterday.",
	"Your rake has a slightly better reputation.",
	"The neighbors upgraded you from 'hey, you' to 'hey, you guys'.",
	"Somebody wrote your number on their fridge.",
]

## How the day went, for the summary quip (summary_quip()).
const QUIP_BUCKETS: Array[String] = ["zero", "rough", "solid", "great", "raided"]

## One line under the day summary's title, by QUIP_BUCKETS.
const SUMMARY_QUIPS: Dictionary = {
	"zero": [
		"No jobs today. The leaves won this round. They win most rounds.",
		"A day off! Nobody approved it, but a day off.",
		"Zero jobs. The cots got a lot of use, though.",
	],
	"rough": [
		"Not every day is a good day. Today was not every day.",
		"The yards fought back. Tomorrow: revenge (raking).",
		"Somebody's gnome is still talking about you.",
	],
	"solid": [
		"Another day, another mountain of leaves moved slightly to the left.",
		"The town is a little less crunchy because of you.",
		"Good work. The trees have already started on tomorrow's batch.",
	],
	"great": [
		"A legendary day. The leaves are writing songs about you. Sad ones.",
		"Five-star crew. Somebody frame this receipt.",
		"The whole town is talking. Mostly the nosy ones, but still.",
	],
	"raided": [
		"The NICE BOYS came by. You were not, technically, compliant.",
		"A raid, a chase, a van ride. Just a normal day of yard work.",
		"Somebody got a courtesy notice today. Nobody was courteous about it.",
	],
}

## The phone's line about each neighborhood (net/town/neighborhoods.gd HOODS ids).
const HOOD_BLURBS: Dictionary = {
	"maple_row": "Bungalows, old trees, and neighbors who all know each other's business.",
	"dandelion_acres": "A mobile-home park with huge shared lawns. Cash only, no questions.",
	"birchwood_commons": "Newer two-stories, first pools, and a lot of opinions about edging.",
	"oak_hollow": "The HOA. Everything is a violation, including you.",
	"lakeside": "Pools, boathouses, and hedges as long as a ferry.",
	"mansion_hill": "Estates. Celebrity clients. Lawyers on retainer for the gnome incidents.",
}

## The phone's line about each homeowner personality.
const PERSONALITY_BLURBS: Dictionary = {
	"easygoing": "Easy to please. Easy to forget to pay you.",
	"chatty": "Will tell you about their knee. Tips well.",
	"grumpy": "Has never been happy. Might be, for you.",
	"neat_freak": "Counts the leaves. Pays for perfect.",
	"nosy": "Watches from the window. Knows everyone.",
	"penny_pincher": "Has a coupon for you. Expired.",
}

## The seasons' names and the day summary's line when one turns, in core/seasons.gd
## order (autumn, winter, spring, summer).
const SEASON_NAMES: Array[String] = ["Autumn", "Winter", "Spring", "Summer"]
const SEASON_ARRIVALS: Array[String] = [
	"Autumn is back. Leaves everywhere. You're welcome.",
	"Winter. Fewer leaves, frozen gutters, and everybody pays a little extra.",
	"Spring. Weeds, mowing, and hedges with ambitions.",
	"Summer. Mowing, pools, and fences that need paint.",
]

## The audit's contract (net/dev/cast_test.gd): pool path -> [how many %s/%d/%.Nf
## slots every line has, the fewest lines the pool may have]. A path covers the
## pools under it ("TEXT_LINES/request" covers every personality's request pool).
## A pool with no entry here takes [0, 3]. A single string (a UI key) is checked
## only when it has an exact entry.
const FORMAT_ARGS: Dictionary = {
	"TEXT_LINES/request": [1, 3],
	"TEXT_LINES/clerk_intro": [0, 1],
	"TEXT_LINES/referral_named": [1, 3],
	"TEXT_LINES/referral_body": [3, 3],
	"TEXT_LINES/won_back_named": [1, 3],
	"TEXT_LINES/rival_arrival": [0, 2],
	"TEXT_LINES/hire_quit": [1, 3],
	"CREW_NAMES": [0, 8],
	"SEASON_NAMES": [0, 4],
	"SEASON_ARRIVALS": [0, 4],
	"TIER_BLURBS": [0, 4],
	"UI/crew_tag": [1, 1],
	"UI/crew_tag_lead": [1, 1],
	"UI/border_lanes": [1, 1],
	"UI/error_host": [1, 1],
	"UI/error_join": [1, 1],
	"UI/ride_chefty_label": [4, 1],
	"UI/phone_text_head": [3, 1],
	"UI/popup_cash": [1, 1],
}


## The lines for a homeowner pool id: "<mood>" or "bill_<reason>" from
## HOMEOWNER_LINES, or "<personality>/<mood>" from PERSONALITY_LINES. [""] when
## there is no such pool, so an index into it never crashes.
static func homeowner_pool(pool: String) -> Array:
	var lines: Array = []
	var slash := pool.find("/")
	if slash >= 0:
		var by_mood: Dictionary = PERSONALITY_LINES.get(pool.substr(0, slash), {})
		lines = by_mood.get(pool.substr(slash + 1), [])
	else:
		lines = HOMEOWNER_LINES.get(pool, [])
	return lines if not lines.is_empty() else [""]


## A line picked with the caller's rng (host-side choices; send the result or the index).
static func pick(lines: Array, rng: RandomNumberGenerator) -> String:
	if lines.is_empty():
		return ""
	return str(lines[rng.randi() % lines.size()])


## A line picked from a seed every peer already has, so all of them show the same one.
static func pick_seeded(lines: Array, seed_value: int) -> String:
	if lines.is_empty():
		return ""
	return str(lines[posmod(seed_value, lines.size())])


## A phone text line of this kind for a homeowner's personality: their own pool
## when TEXT_LINES has one, else the generic pool.
static func client_line(kind: String, personality: String, rng: RandomNumberGenerator) -> String:
	var entry: Variant = TEXT_LINES.get(kind, [])
	if entry is Dictionary:
		var pools: Dictionary = entry
		var lines: Array = pools.get(personality, pools.get("generic", []))
		return pick(lines, rng)
	return pick(entry as Array, rng)


## A NICE BOY's name tag: Crew1 leads. The same on every peer for a day, new the next.
## The day picks a start name and each crew member steps one along, so a raid
## never has two BRENTs (up to CREW_NAMES.size() crew).
static func crew_tag(index: int, day: int) -> String:
	var who := CREW_NAMES[posmod(hash(day) + index - 1, CREW_NAMES.size())]
	return str(UI["crew_tag_lead" if index == 1 else "crew_tag"]) % who


## The line under a rank-up to this tier: the rank's own blurb at its tier I (and
## the first Lawnfather tier), else the tier's.
static func rank_blurb(tier: int) -> String:
	var ranked := _Ranks.NAMES.size() * _Ranks.TIERS_PER_RANK
	if tier >= ranked:
		if tier == ranked:
			return str(RANK_BLURBS.get(_Ranks.ENDLESS_NAME, ""))
		return TIER_BLURBS[posmod(tier - ranked - 1, TIER_BLURBS.size())]
	var step := posmod(tier, _Ranks.TIERS_PER_RANK)
	if step == 0:
		return str(RANK_BLURBS.get(_Ranks.NAMES[int(float(tier) / float(_Ranks.TIERS_PER_RANK))], ""))
	return TIER_BLURBS[(step - 1) % TIER_BLURBS.size()]


## How the day went (QUIP_BUCKETS), from the day summary: no jobs; a raid; four and
## a half stars or better over two jobs or more; under three stars; otherwise solid.
static func quip_bucket(summary: Dictionary) -> String:
	var jobs := int(summary.get("jobs", 0))
	if jobs <= 0:
		return "zero"
	if int(summary.get("raids", 0)) > 0:
		return "raided"
	var average := float(summary.get("stars", 0.0)) / float(jobs)
	if jobs >= 2 and average >= 4.5:
		return "great"
	if average < 3.0:
		return "rough"
	return "solid"


## The day summary's quip: the bucket's line for this day, the same on every peer.
static func summary_quip(summary: Dictionary) -> String:
	var bucket := quip_bucket(summary)
	return pick_seeded(SUMMARY_QUIPS.get(bucket, []), hash([int(summary.get("day", 1)), bucket]))
