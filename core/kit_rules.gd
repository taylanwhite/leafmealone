extends RefCounted

## Pure rules for the crew's kit (p2-kit; docs/GAME.md "The crew's kit"), the
## same on every peer: which props are kit, and what a rake's tier does. No
## state and no preloads, so anything can preload it (the leaf field, the props,
## Campaign) without a cycle. The kit itself is net/kit/kit.gd.


## Whether a prop of this kind is crew kit: bought, saved, carried to jobs in
## Chefty's bed or in pockets (Constants.KIT_KINDS).
static func is_kit_kind(kind: String) -> bool:
	return Constants.KIT_KINDS.has(kind)


## Whether this node is a kit prop (a yard prop of a kit kind, not on its way out).
static func is_kit(node: Object) -> bool:
	if node == null or not node is Node or (node as Node).is_queued_for_deletion():
		return false
	var kind := str(node.get("kind"))
	# A sack poured dry (shops:9) is folding away (net_prop.gd host_use_sack): it
	# isn't saved, racked, swept or counted, so it can't come back empty.
	if Catalog.is_sack(kind) and float(node.get("fuel")) <= 0.0:
		return false
	return (node as Node).is_in_group("props") and is_kit_kind(kind)


## How much harder a rake of this tier rakes than a plain one: Rusty's used one a
## little less, the Mk II (the old Tune-Up) and Mk III (The Leafinator) the
## workbook's tool growth once and twice.
static func rake_multiplier(tier: int) -> float:
	if tier <= Catalog.TIER_USED:
		return Constants.KIT_USED_RAKE_SCALE
	return pow(Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER, float(maxi(tier - Catalog.TIER_STOCK, 0)))


## The rake a peer holds in their hands, or null.
static func held_rake(tree: SceneTree, peer_id: int) -> Node:
	if tree == null or peer_id == 0:
		return null
	for node: Node in tree.get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and int(node.get("held_by")) == peer_id:
			return node
	return null


## A tool's name on the phone and prompts: "rake", "Leaf blower Mk II" lowercased
## where it reads in a sentence ("Found your rake in my hydrangeas").
static func sentence_name(kind: String, tier: int) -> String:
	var strings := preload("res://ui/strings.gd")
	var id := Catalog.tool_item(kind, tier)
	var shown := strings.shop_item_name(id) if id != "" and tier != Catalog.TIER_STOCK else strings.item_name(kind)
	# A proper name brings its own article ("The Leafinator"); the sentence has
	# one already ("your %s", "a %s"), so it drops its own and keeps its capital.
	if shown.begins_with("The "):
		return shown.substr(4)
	if shown.length() > 1 and shown.substr(1, 1) == shown.substr(1, 1).to_lower():
		return shown.substr(0, 1).to_lower() + shown.substr(1)
	return shown


## "rake", "rake and leaf blower", "rake, mower and ladder".
static func sentence_list(names: Array) -> String:
	var strings := preload("res://ui/strings.gd")
	if names.is_empty():
		return ""
	if names.size() == 1:
		return str(names[0])
	var head := PackedStringArray()
	for index: int in names.size() - 1:
		head.append(str(names[index]))
	return str(strings.SHOP_UI["kit_list_and"]) % [", ".join(head), str(names[names.size() - 1])]
