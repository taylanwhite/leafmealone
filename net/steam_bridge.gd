extends Node

## Authority: local Steam client. Lobby membership is Steam's; the game session still belongs to the host.
## Only this file calls GodotSteam. Checked against GodotSteam 4.23: steamInitEx, createLobby, host_with_lobby.

var available: bool = false
var unavailable_reason: String = "Steam is not running"
var lobby_id: int = 0
var _creating_lobby: bool = false


func setup(skip: bool) -> void:
	if skip:
		unavailable_reason = "Steam skipped"
		return
	var result: Dictionary = Steam.steamInitEx(Constants.STEAM_APP_ID, true)
	var status := int(result.get("status", 1))
	if status != 0:
		unavailable_reason = str(result.get("verbal", "Steam is not running"))
		push_warning("[Net] %s" % unavailable_reason)
		return
	available = true
	unavailable_reason = ""
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	_open_command_line_lobby()
	print("[Net] Steam ready as %s" % Steam.getPersonaName())


func persona_name() -> String:
	if not available:
		return ""
	return Steam.getPersonaName()


func create_friends_lobby() -> void:
	_creating_lobby = true
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, Constants.MAX_PLAYERS)


func join_lobby(target_lobby_id: int) -> void:
	Steam.joinLobby(target_lobby_id)


func steam_id_for_peer(peer_id: int) -> int:
	var peer := multiplayer.multiplayer_peer as SteamMultiplayerPeer
	if peer == null:
		return 0
	return peer.get_steam_id_for_peer_id(peer_id)


func open_invite_dialog() -> void:
	if lobby_id <= 0:
		return
	Steam.activateGameOverlayInviteDialog(lobby_id)


func _open_command_line_lobby() -> void:
	var arguments := OS.get_cmdline_args()
	for index: int in arguments.size():
		if arguments[index] != "+connect_lobby" or index + 1 >= arguments.size():
			continue
		Steam.joinLobby(int(arguments[index + 1]))
		return


func _on_lobby_created(result: int, created_lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		push_error("[Net] lobby creation failed (%d)" % result)
		Net.abandon_steam_lobby()
		return
	lobby_id = created_lobby_id
	if not Steam.setLobbyData(lobby_id, "game_id", Constants.PROJECT_SLUG):
		push_warning("[Net] could not tag lobby game_id")
	if not Steam.setLobbyData(lobby_id, "build", Constants.BUILD_VERSION):
		push_warning("[Net] could not tag lobby build")
	var peer := SteamMultiplayerPeer.new()
	var error := peer.host_with_lobby(lobby_id)
	if error != OK:
		push_error("[Net] host_with_lobby failed: %s" % error_string(error))
		Net.abandon_steam_lobby()
		return
	multiplayer.multiplayer_peer = peer
	var steam_id := steam_id_for_peer(multiplayer.get_unique_id())
	Net.complete_steam_host(persona_name(), steam_id)


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.RESULT_OK:
		push_error("[Net] lobby join failed (%d)" % response)
		Net.abandon_steam_lobby()
		return
	if _creating_lobby:
		_creating_lobby = false
		return
	var build := Steam.getLobbyData(joined_lobby_id, "build")
	if build != "" and build != Constants.BUILD_VERSION:
		push_error("[Net] lobby build %s does not match %s" % [build, Constants.BUILD_VERSION])
		Net.abandon_steam_lobby()
		return
	lobby_id = joined_lobby_id
	var peer := SteamMultiplayerPeer.new()
	var error := peer.connect_to_lobby(lobby_id)
	if error != OK:
		push_error("[Net] connect_to_lobby failed: %s" % error_string(error))
		Net.abandon_steam_lobby()
		return
	multiplayer.multiplayer_peer = peer
	Net.complete_steam_join()


func _on_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	Steam.joinLobby(requested_lobby_id)
