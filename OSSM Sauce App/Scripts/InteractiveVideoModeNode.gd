extends Control

const VIDEO_EXTENSIONS: PackedStringArray = [
	"webm","mkv","flv","vob","ogv","ogg","mng","avi","mts","m2ts","ts","mov",
	"qt","wmv","yuv","rm","rmvb","viv","asf","amv","mp4","m4p","mp2","mpe",
	"mpv","mpg","mpeg","m2v","m4v","svi","3gp","3g2","mxf","roq","nsv","flv",
	"f4v","f4p","f4a","f4b", "gif"]

@onready var video_playback: VideoPlayback = %VideoPlayback
@onready var timeline: HSlider = %Timeline
@onready var play_pause_button: TextureButton = %PlayPauseButton
@onready var funscript_message = %FunscriptNotFound
@onready var current_frame_value: Label = %CurrentFrameValue
@onready var editor_fps_value: Label = %EditorFPSValue
@onready var max_frame_value: Label = %MaxFrameValue
@onready var fps_value: Label = %FPSValue
@onready var speed_spin_box: SpinBox = %SpeedSpinBox

@onready var loading_screen: Panel = $LoadingPanel
@onready var video_player = $VBox/FramePanel/VideoPlayback

var icons: Array[Texture2D] = [
	preload("res://icons/play_arrow_48dp_FILL1_wght400_GRAD0_opsz48.png"), # PLAY
	preload("res://icons/pause_48dp_FILL1_wght400_GRAD0_opsz48.png") # PAUSE
]

var is_dragging: bool = false
var was_playing: bool = false
var funscript_path: String = ""

func _ready() -> void:
	hide()  # Start hidden
	if OS.get_cmdline_args().size() > 1:
		open_video(OS.get_cmdline_args()[1])
	if OS.get_name().to_lower() == "android" and OS.request_permissions():
		print("Permissions already granted!")

	# Connect signals
	video_playback.video_loaded.connect(after_video_open)
	video_playback.frame_changed.connect(_frame_changed)
	loading_screen.visible = false
	%SpeedSpinBox.value = video_playback.playback_speed
func _input(event: InputEvent) -> void:
	if event.is_action_released("play_pause"):
		_on_play_pause_button_pressed()


func _on_video_drop(file_paths: PackedStringArray) -> void:
	if file_paths[0].get_extension().to_lower() not in VIDEO_EXTENSIONS:
		return print("Not a valid video file!");
	open_video(file_paths[0])


func _on_url_line_edit_text_submitted(path: String) -> void:
	open_video(path)

func _frame_changed(value: int) -> void:
	if timeline:
		timeline.value = value
		%CurrentFrameValue.text = str(value)
		%EditorFPSValue.text = str(Engine.get_frames_per_second())

func open_video(file_path: String) -> void:
	if timeline:
		timeline.value = 0
		loading_screen.visible = true
	if video_playback:
		video_playback.set_video_path(file_path)
	_try_load_funscript_for_video(file_path)

func after_video_open() -> void:
	if video_playback and video_playback.is_open():
		if timeline:
			timeline.max_value = video_playback.get_video_frame_count() - 1
		if play_pause_button:
			play_pause_button.texture_normal = icons[0]
		%MaxFrameValue.text = str(video_playback.get_video_frame_count())
		%FPSValue.text = str(video_playback.get_video_framerate()).left(5)
		loading_screen.visible = false

func _on_play_pause_button_pressed() -> void:
	if video_playback and video_playback.is_open():
		if video_playback.is_playing:
			video_playback.pause()
			if play_pause_button:
				play_pause_button.texture_normal = icons[0]
			# Pause funscript playback
			%CircleSelection._on_inside_button_pressed
		else:
			video_playback.play()
			if play_pause_button:
				play_pause_button.texture_normal = icons[1]
			# Start funscript playback
			%CircleSelection._on_inside_button_pressed
			play_pause_button.release_focus()

func _on_timeline_value_changed(_value: float) -> void:
	if is_dragging and video_playback:
		video_playback.seek_frame(timeline.value as int)

func _on_timeline_drag_started() -> void:
	is_dragging = true
	if video_playback:
		was_playing = video_playback.is_playing
		video_playback.pause()

func _on_timeline_drag_ended(_value: bool) -> void:
	is_dragging = false
	if was_playing and video_playback:
		video_playback.play()
		
func _on_load_video_button_pressed() -> void:
	var dialog: FileDialog = FileDialog.new()

	dialog.title = "Open video"
	dialog.force_native = true
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_connect(dialog.file_selected, open_video)

	add_child(dialog)
	dialog.popup_centered()


func _connect(from_signal: Signal, target_func: Callable) -> void:
	if from_signal.connect(target_func):
		printerr("Couldn't connect function '", target_func.get_method(), "' to '", from_signal.get_name(), "'!")

func load_video(video_path: String):
	video_player.set_video_path(video_path)
	_try_load_funscript_for_video(video_path)

func _try_load_funscript_for_video(video_path: String):
	var dir = video_path.get_base_dir()
	var funscript_filename = video_path.get_file().get_basename() + ".funscript"
	funscript_path = dir.path_join(funscript_filename)
	
	print("Looking for funscript at: " + funscript_path)
	
	if FileAccess.file_exists(funscript_path):
		if funscript_message:
			funscript_message.hide()
		if owner.has_method("load_path_from_directory"):
			# Load funscript from the same directory as the video
			var success = owner.load_path_from_directory(funscript_filename, dir + "/")
			if success:
				print("Successfully loaded funscript: " + funscript_filename)
			else:
				print("Failed to load funscript: " + funscript_filename)
	else:
		if funscript_message:
			funscript_message.text = "No funscript found for this video."
			funscript_message.show()
		print("Funscript not found at: " + funscript_path)

func activate():
	show()
	%BridgeControls.deactivate()
	%PositionControls.deactivate()
	%LoopControls.deactivate()
	%VibrationControls.deactivate()

func deactivate():
	hide() 

func _on_speed_spin_box_value_changed(value: float) -> void:
	video_playback.playback_speed = value
