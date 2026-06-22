@tool
extends Control

signal closed(final_data)

var grid_data = [] # [is_active, duration]
var rows: int = 7
var cols: int = 17 

var current_octave: int = 0
var octave_label: Label
var current_volume_db: float = 0.0

var is_dragging = false
var start_col = -1
var current_row = -1

var note_names = ["G", "F", "E", "D", "C", "B", "A"]
var pitch_steps = [1.888, 1.682, 1.498, 1.335, 1.26, 1.122, 1.0]

@onready var note_grid = $NoteGrid
@onready var note_player = $NotePlayer

var row_players = [] 

# Styles
var style_normal = StyleBoxFlat.new()
var style_active = StyleBoxFlat.new()
var style_hover = StyleBoxFlat.new()

# For responsive resize debounce
var _resize_pending = false

func _ready() -> void:
	self.mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_styles()
	_setup_octave_controls()
	
	if note_grid:
		# Якорі: займаємо весь простір батьківського контейнера
		note_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		note_grid.offset_top    = 60
		note_grid.offset_right  = -10
		note_grid.offset_left   = 10
		note_grid.offset_bottom = -10
		
	# Робимо 7 копій плеєра
	for player in row_players: if is_instance_valid(player): player.queue_free()
	row_players.clear()

	for i in range(rows):
		var new_player = note_player.duplicate()
		add_child(new_player)
		row_players.append(new_player)
		
	setup_grid()

func set_volume(db: float):
	current_volume_db = db
	for p in row_players:
		if is_instance_valid(p):
			p.volume_db = db

func _notification(what):
	if what == NOTIFICATION_RESIZED and not Engine.is_editor_hint():
		if not _resize_pending:
			_resize_pending = true
			call_deferred("_on_resized")

func _on_resized():
	_resize_pending = false
	if grid_data.is_empty(): return
	_rebuild_grid_sizes()

func _rebuild_grid_sizes():
	if not note_grid: return
	var single_w = _compute_single_width()
	var grid_h = note_grid.get_rect().size.y
	if grid_h < 100: grid_h = 500.0
	var button_h = grid_h / rows

	var children = note_grid.get_children()
	for idx in range(children.size()):
		var btn = children[idx]
		var r = idx / cols
		var c = idx % cols
		
		var new_min_w = single_w - 2.0
		var new_h = button_h - 2.0
		btn.custom_minimum_size = Vector2(new_min_w, new_h)
		btn.size = Vector2(new_min_w, new_h)
	
	# Re-apply note widths from data
	for r in range(rows):
		var c = 1
		while c < cols:
			if r >= grid_data.size() or c - 1 >= grid_data[r].size(): break
			var is_active = grid_data[r][c-1][0]
			var length = grid_data[r][c-1][1]
			if is_active and length > 1:
				var main_btn = note_grid.get_child(r * cols + c)
				main_btn.size.x = (single_w * length) - 2.0
			c += 1

func _setup_styles():
	style_normal.bg_color = Color("1e1e2e")
	style_normal.set_border_width_all(1)
	style_normal.border_color = Color("2a2a3a")
	style_normal.set_corner_radius_all(4)
	
	style_hover.bg_color = Color("2a2a3a")
	style_hover.set_corner_radius_all(4)
	
	style_active.bg_color = Color("ffff00")
	style_active.set_border_width_all(1)
	style_active.border_color = Color("ffffff")
	style_active.set_corner_radius_all(4)
	style_active.shadow_color = Color("ffff00", 0.3)
	style_active.shadow_size = 4

func _compute_single_width() -> float:
	if not note_grid: return 50.0
	var grid_w = note_grid.get_rect().size.x
	if grid_w < 100:
		grid_w = get_viewport_rect().size.x - 20.0
	return grid_w / cols

func get_single_width() -> float:
	return _compute_single_width()

func _setup_octave_controls():
	if has_node("OctaveContainer"):
		get_node("OctaveContainer").queue_free()
		
	var octave_container = HBoxContainer.new()
	octave_container.name = "OctaveContainer"
	# Розміщуємо зліва зверху
	octave_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	octave_container.offset_left = 10
	octave_container.offset_top = 10
	octave_container.offset_right = 200
	octave_container.offset_bottom = 50
	
	var btn_down = Button.new()
	btn_down.text = "<"
	btn_down.custom_minimum_size = Vector2(50, 40)
	btn_down.add_theme_font_size_override("font_size", 20)
	btn_down.pressed.connect(_on_octave_down)
	
	octave_label = Label.new()
	octave_label.custom_minimum_size = Vector2(60, 40)
	octave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	octave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	octave_label.add_theme_font_size_override("font_size", 20)
	
	var btn_up = Button.new()
	btn_up.text = ">"
	btn_up.custom_minimum_size = Vector2(50, 40)
	btn_up.add_theme_font_size_override("font_size", 20)
	btn_up.pressed.connect(_on_octave_up)
	
	octave_container.add_child(btn_down)
	octave_container.add_child(octave_label)
	octave_container.add_child(btn_up)
	
	add_child(octave_container)
	# Викликаємо для початкового відображення '0'
	_update_octave_label()

func _on_octave_down():
	if current_octave > -2:
		current_octave -= 1
		_update_octave_label()

func _on_octave_up():
	if current_octave < 2:
		current_octave += 1
		_update_octave_label()

func _update_octave_label():
	if octave_label:
		octave_label.text = str(current_octave)

func setup_grid():
	if not note_grid: return
	
	# Зберігаємо старі дані якщо вони є
	var old_data = grid_data.duplicate(true)
	
	grid_data.clear()
	for child in note_grid.get_children(): child.queue_free()
	
	note_grid.columns = cols
	var grid_h = note_grid.get_rect().size.y
	if grid_h < 100: grid_h = 500.0

	var button_w = _compute_single_width()
	var button_h = grid_h / rows 
	
	for r in range(rows):
		grid_data.append([]) 
		for c in range(cols):
			var note_btn = Button.new()
			note_btn.custom_minimum_size = Vector2(button_w - 2.0, button_h - 2.0)
			
			note_btn.add_theme_stylebox_override("normal", style_normal)
			note_btn.add_theme_stylebox_override("hover", style_hover)
			note_btn.add_theme_stylebox_override("pressed", style_active)
			note_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			
			if c == 0:
				note_btn.text = note_names[r]
				note_btn.add_theme_color_override("font_color", Color.GRAY)
				if not Engine.is_editor_hint():
					note_btn.pressed.connect(_play_note.bind(r))
			else:
				grid_data[r].append([false, 1])
				note_btn.gui_input.connect(_on_note_input.bind(r, c))
			
			note_grid.add_child(note_btn)
	
	# Відновлюємо старі дані якщо вони були
	if not old_data.is_empty():
		for r in range(min(old_data.size(), rows)):
			for c in range(min(old_data[r].size(), cols - 1)):
				grid_data[r][c] = old_data[r][c]

func _on_note_input(event: InputEvent, r: int, c: int):
	if Engine.is_editor_hint(): return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if grid_data[r][c-1][0]:
				_clear_note(r, c)
			else:
				is_dragging = true
				start_col = c
				current_row = r
				_toggle_note(r, c, true)
		else:
			is_dragging = false

	if is_dragging and event is InputEventMouseMotion and r == current_row:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var btn_w = _compute_single_width()
			var local_mouse_x = note_grid.get_local_mouse_position().x
			var new_c = int(local_mouse_x / btn_w)
			
			if new_c >= start_col and new_c < cols:
				_extend_note(current_row, start_col, new_c)

func _toggle_note(r, c, active):
	grid_data[r][c-1][0] = active
	var btn = note_grid.get_child(r * cols + c)
	
	if active:
		btn.add_theme_stylebox_override("normal", style_active)
		btn.z_index = 1
		_play_note(r) 
	else:
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.z_index = 0

func _extend_note(r, start_c, end_c):
	var length = (end_c - start_c) + 1
	grid_data[r][start_c-1][1] = length
	
	var main_btn = note_grid.get_child(r * cols + start_c)
	var single_w = _compute_single_width()
	
	main_btn.size.x = (single_w * length) - 2.0
	main_btn.add_theme_stylebox_override("normal", style_active)
	main_btn.z_index = 1
	
	for i in range(start_c + 1, cols):
		var other_btn = note_grid.get_child(r * cols + i)
		if i <= end_c:
			other_btn.modulate.a = 0.0
			other_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			other_btn.modulate.a = 1.0
			other_btn.mouse_filter = Control.MOUSE_FILTER_STOP

func _clear_note(r, c):
	var length = grid_data[r][c-1][1]
	grid_data[r][c-1] = [false, 1]
	
	var main_btn = note_grid.get_child(r * cols + c)
	main_btn.size.x = main_btn.custom_minimum_size.x 
	main_btn.add_theme_stylebox_override("normal", style_normal)
	main_btn.z_index = 0
	
	for i in range(c + 1, c + length):
		if i < cols:
			var other_btn = note_grid.get_child(r * cols + i)
			other_btn.modulate.a = 1.0
			other_btn.mouse_filter = Control.MOUSE_FILTER_STOP

func _play_note(row_index: int):
	var current_player = row_players[row_index]
	if current_player:
		if current_player.has_meta("fade_tween"):
			var t = current_player.get_meta("fade_tween")
			if t and is_instance_valid(t) and t is Tween:
				t.kill()
		current_player.stop()
		current_player.volume_db = current_volume_db
		current_player.pitch_scale = pitch_steps[row_index] * pow(2.0, current_octave)
		current_player.play()

func _play_note_with_decay(row_index: int, duration_sec: float):
	_play_note(row_index)
	var current_player = row_players[row_index]
	if not current_player: return
	
	var hold_time = max(0.01, duration_sec)
	var release_time = 0.35
	
	var tween = create_tween()
	current_player.set_meta("fade_tween", tween)
	tween.tween_interval(hold_time)
	tween.tween_property(current_player, "volume_db", -60.0, release_time).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func(): current_player.stop())

func _on_close_button_pressed():
	closed.emit(grid_data)
	self.visible = false

# --- ГОЛОВНЕ ВИПРАВЛЕННЯ: правильне відновлення нот при відкритті ---
func sync_ui_to_data():
	# Спочатку робимо рендер щоб note_grid мав правильний розмір
	await get_tree().process_frame
	await get_tree().process_frame
	
	var single_w = _compute_single_width()
	
	# Скидаємо всі кнопки до стандартного вигляду
	for child in note_grid.get_children():
		child.modulate.a = 1.0
		child.mouse_filter = Control.MOUSE_FILTER_STOP
		child.z_index = 0
		if child is Button:
			child.size.x = child.custom_minimum_size.x
			child.add_theme_stylebox_override("normal", style_normal)

	# Відновлюємо активні ноти з даних
	for r in range(rows):
		if r >= grid_data.size(): break
		var c = 1
		while c < cols:
			if c - 1 >= grid_data[r].size(): break
			var node_idx = r * cols + c
			if node_idx >= note_grid.get_child_count(): break
			
			var is_active = grid_data[r][c-1][0]
			var length = grid_data[r][c-1][1]

			if is_active:
				var main_btn = note_grid.get_child(node_idx)
				main_btn.add_theme_stylebox_override("normal", style_active)
				main_btn.z_index = 1
				if length > 1:
					# Рахуємо реальну ширину кнопки після рендеру
					main_btn.size.x = (single_w * length) - 2.0
					for i in range(c + 1, int(min(c + length, cols))):
						var other_btn = note_grid.get_child(r * cols + i)
						other_btn.modulate.a = 0.0
						other_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
				c += length
			else:
				c += 1

func set_instrument(new_stream: AudioStream):
	if note_player: note_player.stream = new_stream
	for player in row_players: player.stream = new_stream

func play_step(step_index: int, step_time: float = 0.5):
	if step_index >= cols - 1: return
	for r in range(rows):
		if r >= grid_data.size(): continue
		if step_index >= grid_data[r].size(): continue
		if grid_data[r][step_index][0] == true:
			var length = grid_data[r][step_index][1]
			_play_note_with_decay(r, length * step_time)
