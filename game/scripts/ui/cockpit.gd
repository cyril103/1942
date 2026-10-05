extends Control
## Gameplay lives in its own 3:4 viewport: panels cannot obscure actors or shots.
const PANEL = preload("res://scripts/ui/cockpit_panel.gd")
const SAVE_PATH := "user://pilot-record.cfg"
var campaign_mode := false
var campaign: Node
var flight: Node3D
var combat: Node3D
var player: Node3D
var viewport: SubViewport
var screen: TextureRect
var left: Control
var right: Control
var play_rect := Rect2()
var high_score := 0
var persistence_enabled := true
var save_path := SAVE_PATH
var _saved_high_score := 0
var _save_delay := 0.0
var message: Label
var _quitting := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.color = Color("070a09")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	viewport = SubViewport.new()
	viewport.name = "FlightViewport"
	viewport.size = Vector2i(810,1080)
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	flight = preload("res://scenes/main.tscn").instantiate()
	viewport.add_child(flight)
	if campaign_mode: flight.set_process_unhandled_key_input(false)
	combat = flight.get_node("Combat")
	player = flight.get_node("Player")
	combat.remaining_lives = 3
	combat.hud.get_parent().hide()
	screen = TextureRect.new()
	screen.texture = viewport.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var record := ConfigFile.new()
	if persistence_enabled and record.load(save_path) == OK:
		high_score = maxi(0,int(record.get_value("pilot","high_score",0)))
	_saved_high_score = high_score
	left = PANEL.new()
	left.dashboard = self
	add_child(left)
	right = PANEL.new()
	right.dashboard = self
	right.right_side = true
	add_child(right)
	message = Label.new()
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_override("font",preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf"))
	message.add_theme_font_size_override("font_size",32)
	message.add_theme_color_override("font_color",Color("efdab1"))
	message.add_theme_color_override("font_outline_color",Color("080e0d"))
	message.add_theme_constant_override("outline_size",10)
	add_child(message)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if not is_instance_valid(viewport): return
	if campaign_mode:
		var ui_scale := size.y / 1080.0
		play_rect = Rect2(Vector2(0,64*ui_scale),Vector2(size.x,size.y-108*ui_scale))
		viewport.size = Vector2i(play_rect.size)
		screen.position = play_rect.position
		screen.size = play_rect.size
		left.hide()
		right.hide()
		message.position = play_rect.position
		message.size = play_rect.size
		return
	var available := size
	var origin := Vector2.ZERO
	# Narrow displays keep the entire cockpit visible, letterboxed as needed.
	if available.x / maxf(1,available.y) < 1.25:
		available.y = available.x * 9.0 / 16.0
		origin.y = (size.y-available.y)*0.5
	var unit := maxi(1, floori(available.y/4.0))
	var field := Vector2(unit*3,unit*4)
	play_rect = Rect2(origin+Vector2((available.x-field.x)*0.5,(available.y-field.y)*0.5),field)
	viewport.size = Vector2i(field)
	screen.position = play_rect.position
	screen.size = field
	var side_width := (available.x-field.x)*0.5
	left.position = origin
	left.scale = Vector2(side_width/555.0, available.y/1080.0)
	right.position = origin+Vector2(side_width+field.x,0)
	right.scale = left.scale
	message.position = play_rect.position
	message.size = field

func _process(delta: float) -> void:
	if not is_instance_valid(combat): return
	if combat.score > high_score:
		high_score = combat.score
		if _save_delay <= 0: _save_delay = 0.75
	if _save_delay > 0:
		_save_delay -= delta
		if _save_delay <= 0: save_record()
	if not campaign_mode:
		left.refresh(delta)
		right.refresh(delta)
	message.visible = not campaign_mode and (combat.game_over or combat.respawn_time > 0)
	message.text = "MISSION TERMINÉE\n\nR  —  REJOUER\nÉCHAP  —  QUITTER" if combat.game_over else "RENFORT EN APPROCHE"

func save_record() -> void:
	if not persistence_enabled or high_score <= _saved_high_score: return
	var record := ConfigFile.new()
	record.set_value("pilot","high_score",high_score)
	var result := record.save(save_path)
	if result == OK: _saved_high_score = high_score
	else: push_warning("Could not save pilot record: %s" % error_string(result))

func _unhandled_key_input(event: InputEvent) -> void:
	if campaign_mode: return
	if event.is_action_pressed("restart_test") and not event.echo:
		save_record()
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	elif event.is_action_pressed("quit_game"):
		_quit_game()

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		node.stop()
	for child in node.get_children(): _stop_audio(child)

func _quit_game() -> void:
	if _quitting: return
	_quitting = true
	save_record()
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	_stop_audio(flight)
	# Allow the mixer to release active loop playback before destroying its viewport.
	await get_tree().create_timer(0.12).timeout
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(combat): save_record()
