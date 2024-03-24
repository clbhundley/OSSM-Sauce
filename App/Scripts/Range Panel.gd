extends Panel

var min_range_pos:float
var max_range_pos:float

@onready var min_slider:TextureRect = $RangeBar/MinSlider
@onready var max_slider:TextureRect = $RangeBar/MaxSlider

func _ready():
	$LabelTop.self_modulate.a = 0
	$LabelBot.self_modulate.a = 0
	$BackTexture.self_modulate.a = 0
	$BackTexture.self_modulate.a = 0
	$BackButton.hide()
	min_slider.connect('gui_input', min_slider_gui_input)
	max_slider.connect('gui_input', max_slider_gui_input)
	min_range_pos = min_slider.position.y
	max_range_pos = max_slider.position.y

func min_slider_gui_input(event):
	if 'relative' in event and event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var drag_pos = min_slider.position.y + event.relative.y
			var max_range = max_slider.position.y + max_slider.size.y
			var new_pos = clamp(drag_pos, max_range, min_range_pos)
			min_slider.position.y = new_pos
			var map = remap(new_pos, min_range_pos, max_range_pos, 0, 100)
			var m2:float = remap(new_pos, min_range_pos, max_range_pos, 0, 1)
			if owner.connected_to_server:
				var remap = remap(map, 0, 100, owner.USER_MAX_POS, owner.USER_MIN_POS)
				var clamped:int = round(clamp(m2, 0, 0.9999) * 10000)
				owner.max_pos = round(remap)
				owner.websocket.send_text('A' + str(clamped))
			var value = str(snapped(map, 0.01))
			$LabelBot.text = "Min Position:\n" + value + "%"

func max_slider_gui_input(event):
	if 'relative' in event:
		if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_LEFT:
				var drag_pos = max_slider.position.y + event.relative.y
				var min_range = min_slider.position.y - min_slider.size.y
				var new_pos = clamp(drag_pos, max_range_pos, min_range)
				max_slider.position.y = new_pos
				var map = remap(new_pos, min_range_pos, max_range_pos, 0, 100)
				var m2 = remap(new_pos, min_range_pos, max_range_pos, 0, 1)
				if owner.connected_to_server:
					var remap = remap(map, 0, 100, owner.USER_MAX_POS, owner.USER_MIN_POS)
					var clamped:int = round(clamp(m2, 0, 0.9999) * 10000)
					owner.min_pos = round(remap)
					owner.websocket.send_text('Z' + str(clamped))
				var value = str(snapped(map, 0.01))
				$LabelTop.text = "Max Position:\n" + value + "%"

func tween(activating:bool = true):
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	var viewport_right_edge = get_viewport_rect().size.x
	var viewport_middle = get_viewport_rect().size.x / 2
	var outside_pos := Vector2(viewport_right_edge, position.y)
	var inside_pos := Vector2(viewport_middle, outside_pos.y)
	var positions:Array = [outside_pos, inside_pos]
	if not activating:
		positions.reverse()
	tween.tween_method(set_position, position, positions[1], owner.ANIM_TIME)
	var back = $BackTexture
	var start_color:Color = $BackTexture.self_modulate
	var end_color:Color = start_color
	start_color.a = 0
	end_color.a = 1
	var colors:Array = [start_color, end_color]
	if not activating:
		colors.reverse()
		$BackButton.hide()
		tween.tween_callback(anim_finished).set_delay(owner.ANIM_TIME)
	else:
		$BackButton.show()
	var visuals = [$BackTexture, $LabelBot, $LabelTop]
	for node in visuals:
		tween.tween_method(
			node.set_self_modulate,
			colors[0],
			colors[1],
			owner.ANIM_TIME)

func anim_finished():
	%ActionPanel/Range/Selection.hide()
	%ActionPanel.self_modulate.a = 1
	$BackButton.hide()

func _on_back_button_pressed():
	if owner.connected_to_ossm and %Menu/Main/Mode.selected == 1:
		%CircleSelection.show_hourglass()
		%PositionControls.modulate.a = 0.05
		owner.websocket.send_text('H' + str(%PositionControls.last_position))
	$BackButton.hide()
	tween(false)
	%ActionPanel.show()
