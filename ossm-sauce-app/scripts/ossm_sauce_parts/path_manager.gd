extends RefCounted

var app


func setup(app_owner):
	app = app_owner


func _path_display():
	return app.get_node("PathDisplay")


func _paths_container():
	return app.get_node("PathDisplay/Paths")


func _menu_playlist():
	return app.get_node("Menu/Playlist")


func create_move_command(ms_timing: int, depth: float, trans: int, ease: int, auxiliary: int):
	var network_packet: PackedByteArray
	network_packet.resize(10)
	network_packet.encode_u8(0, OSSM.Command.MOVE)
	network_packet.encode_u32(1, ms_timing)
	network_packet.encode_u16(5, round(remap(abs(app.motor_direction - depth), 0, 1, 0, 10000)))
	network_packet.encode_u8(7, trans)
	network_packet.encode_u8(8, ease)
	network_packet.encode_u8(9, auxiliary)
	return network_packet


func round_to(value: float, decimals: int) -> float:
	var factor = pow(10, decimals)
	return round(value * factor) / factor


func load_path(file_name: String) -> bool:
	var file = FileAccess.open(app.paths_dir + file_name, FileAccess.READ)
	if not file:
		printerr("Error: Failed to read file.")
		return false
	var file_text := file.get_as_text()
	file.close()

	var file_data: Dictionary

	if file_name.ends_with(".funscript"):
		file_text = file_text.replace("\n", "")
		var parsed_funscript = JSON.parse_string(file_text)
		var inverted := false
		if parsed_funscript is Dictionary and parsed_funscript.get("inverted", false):
			inverted = true

		var actions_pattern = RegEx.new()
		actions_pattern.compile('"[Aa]ctions":\\s*\\[.*?\\]')
		var actions_regex = actions_pattern.search(file_text)
		if not actions_regex:
			actions_pattern.compile('"[Rr]aw[Aa]ctions":\\s*\\[.*?\\]')
			actions_regex = actions_pattern.search(file_text)
		if actions_regex:
			var actions_text = actions_regex.get_string(0)
			actions_text = actions_text.replace("'", '"')
			actions_text = actions_text.insert(0, "{")
			actions_text = actions_text.insert(actions_text.length(), "}")
			var actions_data = JSON.parse_string(actions_text)
			if actions_data:
				var actions_list = actions_data[actions_data.keys()[0]]
				var first_depth = round_to(clamp(actions_list[0].pos / 100, 0, 1), 4)
				if inverted:
					first_depth = round_to(1.0 - first_depth, 4)
				file_data[0] = [first_depth, 1, 2, 0]
				for action in actions_list:
					var frame: int = action.at / (1000.0 / 60.0)
					var depth = round_to(clamp(action.pos / 100, 0, 1), 4)
					if inverted:
						depth = round_to(1.0 - depth, 4)
					file_data[frame] = [depth, 1, 2, 0]
			else:
				printerr("Failed to parse funscript JSON")
		else:
			printerr("No actions data found in the funscript")
	else:
		file_data = JSON.parse_string(file_text)
		if not file_data:
			printerr("Error: No JSON data found in file.")
			return false
		if file_data.has("markers"):
			file_data = file_data["markers"]

	var marker_data: Dictionary = file_data
	if marker_data.size() < 6:
		printerr("Error: Insufficient path data in file.")
		return false

	var sorted_keys := marker_data.keys()
	sorted_keys.sort_custom(func(a, b): return int(a) < int(b))

	var network_packets: Array
	for marker_frame in sorted_keys:
		var marker = marker_data[marker_frame]
		var ms_timing := int(round((float(marker_frame) / 60) * 1000))
		network_packets.append(create_move_command(ms_timing, marker[0], marker[1], marker[2], marker[3]))
		marker_data[round(int(marker_frame) / 1.2)] = marker
		marker_data.erase(marker_frame)

	app.network_paths.append(network_packets)

	var previous_depth: float
	var previous_frame: int
	var marker_list: Array = marker_data.keys()
	var path: PackedFloat32Array
	var frames: PackedInt32Array
	var path_line := Line2D.new()
	path_line.width = 15
	path_line.hide()
	marker_list.sort()
	for marker_frame in marker_list:
		var marker = marker_data[marker_frame]
		var depth = marker[0]
		var trans = marker[1]
		var ease = marker[2]
		if marker_frame > 0:
			var steps: int = marker_frame - previous_frame
			frames.append(previous_frame)
			for step in steps:
				var step_depth: float = Tween.interpolate_value(
						previous_depth,
						depth - previous_depth,
						step,
						steps,
						trans,
						ease)
				path.append(step_depth)
				var x_pos = (previous_frame * app.path_speed) + (step * app.path_speed)
				var y_pos = app.render_depth(step_depth)
				path_line.add_point(Vector2(x_pos, y_pos))
		previous_depth = depth
		previous_frame = marker_frame
	app.paths.append(path)
	app.marker_frames.append(frames)
	_paths_container().add_child(path_line)
	return true


func create_delay(duration: float):
	var delay_path: PackedFloat32Array
	var path_line := Line2D.new()
	path_line.hide()
	for _point in round(duration * app.ticks_per_second):
		delay_path.append(-1)
	var frames: PackedInt32Array
	var network_packets: Array
	for timing in 6:
		var move_command = create_move_command(timing, 0, 0, 0, 0)
		network_packets.append(move_command)
		frames.append(timing)
	var end_move = create_move_command(duration * 1000, 0, 0, 0, 0)
	network_packets.append(end_move)
	app.network_paths.append(network_packets)
	app.paths.append(delay_path)
	app.marker_frames.append(frames)
	_paths_container().add_child(path_line)
	_menu_playlist().add_item("delay(%s)" % [duration])
