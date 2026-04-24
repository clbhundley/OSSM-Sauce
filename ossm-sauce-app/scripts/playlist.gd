extends Panel

@onready var Item:Panel = $Scroll/VBox/Item

var selected_index

var drag_delta:float


func _ready():
	$Scroll/VBox.remove_child(Item)


func _on_item_selected(item):
	if drag_delta > 7:
		return
	
	deselect_all()
	item.select()
	
	var index = item.get_index()
	selected_index = index
	
	var restart_button = %Menu/PathControls/HBox/Restart
	if owner.active_path_index == index and owner.frame > 0:
		restart_button.show()
	else:
		restart_button.hide()
	
	if not owner.paused and owner.active_path_index == index:
		%Menu.show_pause()
	else:
		%Menu.show_play()
	
	var double_tap_timer = item.get_node('DoubleTapTimer')
	if double_tap_timer.time_left:
		%Menu._on_play_pressed()
	else:
		double_tap_timer.start()


func add_item(item_text:String):
	var item = Item.duplicate()
	item.get_node('Label').text = item_text
	$Scroll/VBox.add_child(item)
	var item_button = item.get_node('Button')
	item_button.connect('pressed', _on_item_selected.bind(item))
	%Menu/Main/PlaylistButtons/SavePlaylist.disabled = false


func move_item_ui(current_index, new_index):
	var item = $Scroll/VBox.get_child(current_index)
	var path = %PathDisplay/Paths.get_child(current_index)
	$Scroll/VBox.move_child(item, new_index)
	%PathDisplay/Paths.move_child(path, new_index)
	selected_index = new_index


func get_items() -> Array:
	var items:Array
	for item in $Scroll/VBox.get_children():
		items.append(item.get_node('Label').text)
	return items


func _input(event):
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			drag_delta = 0
	if event is InputEventScreenDrag:
		drag_delta += abs(event.relative.y)
		$Scroll.scroll_vertical -= event.relative.y


func deselect_all():
	for item in $Scroll/VBox.get_children():
		item.deselect()


func clear():
	owner.clear_playlist()


func clear_ui():
	for item in $Scroll/VBox.get_children():
		$Scroll/VBox.remove_child(item)


func remove_item_ui(index: int):
	var item = $Scroll/VBox.get_child(index)
	$Scroll/VBox.remove_child(item)


func get_item_count() -> int:
	return $Scroll/VBox.get_child_count()
