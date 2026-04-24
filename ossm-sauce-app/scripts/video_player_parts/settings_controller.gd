extends RefCounted

var player


func setup(player_owner):
	player = player_owner


func reconnect(selected_player_type: int) -> void:
	player.deactivate()
	if selected_player_type > 0:
		player.activate(selected_player_type)


func apply_player_selection(index: int) -> void:
	player.player_type = index as player.PlayerType
	match player.player_type:
		player.PlayerType.OFF:
			player.deactivate()
		player.PlayerType.VLC:
			player.player_port = player.owner.user_settings.get_value('video_player', 'vlc_port', 8080)
			player.get_node("VBox/PlayerPort/Input").set_value_no_signal(player.player_port)
			player.delay_ms = player.owner.user_settings.get_value('video_player', 'vlc_delay_ms', 0)
			player.get_node("VBox/DelayMs/Input").value = player.delay_ms
			player.advance_ms = player.owner.user_settings.get_value('video_player', 'vlc_advance_ms', 100)
			player.get_node("VBox/AdvanceMs/Input").value = player.advance_ms
			player.activate(player.player_type)
		player.PlayerType.MPC_HC:
			player.player_port = player.owner.user_settings.get_value('video_player', 'mpc_port', 13579)
			player.get_node("VBox/PlayerPort/Input").set_value_no_signal(player.player_port)
			player.delay_ms = player.owner.user_settings.get_value('video_player', 'mpc_delay_ms', 0)
			player.get_node("VBox/DelayMs/Input").value = player.delay_ms
			player.advance_ms = player.owner.user_settings.get_value('video_player', 'mpc_advance_ms', 100)
			player.get_node("VBox/AdvanceMs/Input").value = player.advance_ms
			player.activate(player.player_type)
		player.PlayerType.MPV:
			player.mpv_bridge_port = player.owner.user_settings.get_value('video_player', 'mpv_bridge_port', 9876)
			player.get_node("VBox/PlayerPort/Input").set_value_no_signal(player.mpv_bridge_port)
			player.delay_ms = player.owner.user_settings.get_value('video_player', 'mpv_delay_ms', 0)
			player.get_node("VBox/DelayMs/Input").value = player.delay_ms
			player.advance_ms = player.owner.user_settings.get_value('video_player', 'mpv_advance_ms', 100)
			player.get_node("VBox/AdvanceMs/Input").value = player.advance_ms
			player.activate(player.player_type)
	player.owner.user_settings.set_value('video_player', 'player_type', index)


func set_player_address(new_text: String) -> void:
	player.player_address = new_text
	player.owner.user_settings.set_value('video_player', 'player_address', new_text)
	reconnect(player.player_type)


func set_player_port(value: float) -> void:
	player.player_port = int(value)
	match player.player_type:
		player.PlayerType.VLC:
			player.owner.user_settings.set_value('video_player', 'vlc_port', player.player_port)
		player.PlayerType.MPC_HC:
			player.owner.user_settings.set_value('video_player', 'mpc_port', player.player_port)
		player.PlayerType.MPV:
			player.mpv_bridge_port = int(value)
			player.owner.user_settings.set_value('video_player', 'mpv_bridge_port', player.mpv_bridge_port)
	reconnect(player.player_type)


func set_vlc_password(new_text: String) -> void:
	player.vlc_password = new_text
	player.owner.user_settings.set_value('video_player', 'vlc_password', new_text)
	reconnect(player.player_type)


func set_delay_ms(value: float) -> void:
	player.delay_ms = int(value)
	match player.player_type:
		player.PlayerType.VLC:
			player.owner.user_settings.set_value('video_player', 'vlc_delay_ms', player.delay_ms)
		player.PlayerType.MPC_HC:
			player.owner.user_settings.set_value('video_player', 'mpc_delay_ms', player.delay_ms)
		player.PlayerType.MPV:
			player.owner.user_settings.set_value('video_player', 'mpv_delay_ms', player.delay_ms)


func set_advance_ms(value: float) -> void:
	player.advance_ms = int(value)
	match player.player_type:
		player.PlayerType.VLC:
			player.owner.user_settings.set_value('video_player', 'vlc_advance_ms', player.advance_ms)
		player.PlayerType.MPC_HC:
			player.owner.user_settings.set_value('video_player', 'mpc_advance_ms', player.advance_ms)
		player.PlayerType.MPV:
			player.owner.user_settings.set_value('video_player', 'mpv_advance_ms', player.advance_ms)


func set_video_offset_ms(value: float) -> void:
	player.video_offset_ms = int(value)
	player.owner.user_settings.set_value('video_player', 'video_offset_ms', player.video_offset_ms)


func set_vlc_seek_correction(value: float) -> void:
	player.vlc_seek_correction = value
	player.owner.user_settings.set_value('video_player', 'vlc_seek_correction', player.vlc_seek_correction)
