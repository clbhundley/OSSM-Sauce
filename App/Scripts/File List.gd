extends Panel

@onready var Item:Panel = $Scroll/VBox/Item

var selected_index

var drag_delta:float

var mode
enum Mode {
	PATH,
	PLAYLIST}

func _ready():
	$Scroll/VBox.remove_child(Item)

func _on_item_selected(item):
	if drag_delta > 7:
		return
	deselect_all()
	item.select()
	match mode:
		Mode.PATH:
			get_parent().get_node('HBox/AddPath').disabled = false
		Mode.PLAYLIST:
			get_parent().get_node('HBox/LoadPlaylist').disabled = false
	selected_index = item.get_index()
	var timer = item.get_node('Timer')
	if timer.time_left:
		match mode:
			Mode.PATH:
				get_parent()._on_add_path_pressed()
			Mode.PLAYLIST:
				get_parent()._on_load_playlist_pressed()
	else:
		timer.start()

func add_item(item_text:String):
	var item = Item.duplicate()
	item.get_node('Label').text = item_text
	$Scroll/VBox.add_child(item)
	var item_button = item.get_node('Button')
	item_button.connect('pressed', _on_item_selected.bind(item))

func get_item_text(item_index) -> String:
	return $Scroll/VBox.get_child(item_index).get_node('Label').text

func _input(event):
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			drag_delta = 0
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			drag_delta += abs(event.relative.y)
			$Scroll.scroll_vertical -= event.relative.y

func deselect_all():
	for item in $Scroll/VBox.get_children():
		item.deselect()

func clear():
	for item in $Scroll/VBox.get_children():
		$Scroll/VBox.remove_child(item)
