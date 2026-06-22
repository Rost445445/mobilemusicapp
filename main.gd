@tool
extends Control

# --- DESIGN TOKENS (Константи дизайну) ---
const COLOR_MAIN_BG = Color("0a0a14")   
const COLOR_SIDEBAR = Color("141428")   
const COLOR_TOPBAR  = Color("1a1a32")   
const COLOR_ACCENT_CYAN = Color("00f2ff")
const COLOR_ACCENT_YELLOW = Color("ffff00")
const COLOR_ACCENT_PINK = Color("ff00ff")
const COLOR_BTN_BG = Color("23233c")

const SIDEBAR_WIDTH = 220 
const TOPBAR_HEIGHT = 140 

@onready var play_button = $GlobalPlayButton
@onready var stop_button = $GlobalStopButton
@onready var bpm_minus = $HBoxContainer/BPMMinus
@onready var bpm_plus = $HBoxContainer/BPMPlus
@onready var bpm_label = $HBoxContainer/BPMLabel
@onready var preview_player = $PreviewPlayer
@onready var master_timer = $MasterTimer

var sound_library = {
	"Kick 1": preload("res://Sounds/Kick1.mp3"), 
	"Kick (Bounce)": preload("res://Sounds/Steven Cymatics - Kick (Bounce).wav"),
	"Kick (Knock)": preload("res://Sounds/Steven Cymatics - Kick (Knock).wav"),
	"Hit 1": preload("res://Sounds/Hit.mp3"),       
	"Clap (Fighter)": preload("res://Sounds/Steven Cymatics - Clap (Fighter).wav"),
	"Clap (Meal)": preload("res://Sounds/Steven Cymatics - Clap (Meal).wav"),
	"Clap (Paper)": preload("res://Sounds/Steven Cymatics - Clap (Paper).wav"),
	"Snare 1": preload("res://Sounds/Snare1.mp3"),
	"Snare (Join)": preload("res://Sounds/Steven Cymatics - Snare (Join).wav"),
	"Snare (Sniper)": preload("res://Sounds/Steven Cymatics - Snare (Sniper).wav"),
	"Piano": preload("res://Sounds/Piano.wav"),
	"Sin Synth": preload("res://Sounds/sin.mp3"),
	"Hihat (Traplord)": preload("res://Sounds/Steven Cymatics - Hihat (Traplord).wav"),
	"Open Hat (Clank)": preload("res://Sounds/Steven Cymatics - Open Hat (Clank).wav"),
	"Open Hat (House)": preload("res://Sounds/Steven Cymatics - Open Hat (House).wav"),
	"Open Hat (One)": preload("res://Sounds/Steven Cymatics - Open Hat (One).wav")
}

var bpm = 120
var current_global_step = 0

var tracks_vbox: VBoxContainer
var add_track_btn: Button
var tracks = [] 
var next_track_id = 0

var roll_template: Control
var lane_template: Control
var sound_btn_template: Button

var record_effect: AudioEffectRecord
var record_effect_index: int
var export_button: Button
var is_exporting: bool = false
var export_steps: int = 0
var web_warning_dialog: AcceptDialog
var save_file_dialog: FileDialog
var success_dialog: AcceptDialog
var current_export_buffer: PackedByteArray
var current_export_name: String

func _ready():
	_apply_premium_style()
	if Engine.is_editor_hint(): return
	
	_build_sound_menu()
	_setup_tracks()
	_setup_export_button()
	_setup_recording()
	_connect_signals()
	update_bpm_display()

func _connect_signals():
	if play_button: play_button.pressed.connect(_on_global_play_pressed)
	if stop_button: stop_button.pressed.connect(_on_global_stop_pressed)
	if bpm_minus: bpm_minus.pressed.connect(_on_bpm_minus_pressed)
	if bpm_plus: bpm_plus.pressed.connect(_on_bpm_plus_pressed)
	
	if master_timer:
		master_timer.timeout.connect(_on_master_timer_timeout)

func _setup_tracks():
	# Знаходимо вузол TrackLanes, якщо він створений в редакторі
	tracks_vbox = get_node_or_null("TrackLanes")
	if not tracks_vbox:
		tracks_vbox = VBoxContainer.new()
		tracks_vbox.name = "TrackLanes"
		tracks_vbox.position = Vector2(240, 160)
		add_child(tracks_vbox)
	else:
		# Очищаємо всі статичні доріжки з редактора!
		for child in tracks_vbox.get_children():
			child.queue_free()
			
	tracks_vbox.add_theme_constant_override("separation", 20)
	
	# 2. Кнопка додати доріжку
	add_track_btn = Button.new()
	add_track_btn.text = "[ + New Track ]"
	add_track_btn.custom_minimum_size = Vector2(400, 45)
	add_track_btn.add_theme_font_size_override("font_size", 20)
	_style_btn(add_track_btn, COLOR_ACCENT_PINK)
	add_track_btn.pressed.connect(_on_add_track)
	add_child(add_track_btn)
	
	# 3. Зберігаємо шаблони
	if get_node_or_null("PianoRoll"):
		roll_template = get_node("PianoRoll").duplicate()
		roll_template.visible = false
	
	lane_template = Control.new()
	var track_lane = get_node_or_null("TrackLane")
	var t_size = track_lane.size if track_lane else Vector2(600, 80)
	lane_template.custom_minimum_size = t_size
	lane_template.size = t_size
	_inject_panel(lane_template, COLOR_SIDEBAR.lightened(0.02), 8, 1)
	
	if get_node_or_null("TrackSoundButton"):
		sound_btn_template = get_node("TrackSoundButton").duplicate()
		_style_btn(sound_btn_template, COLOR_ACCENT_YELLOW)
	else:
		sound_btn_template = Button.new()
		sound_btn_template.custom_minimum_size = Vector2(100, 40)
		_style_btn(sound_btn_template, COLOR_ACCENT_YELLOW)
	
	# Видаляємо жорстко закодовані вузли з дизайну
	var to_remove = ["PianoRoll", "PianoRoll2", "PianoRoll3", "TrackLane", "TrackLane2", "TrackLane3", "TrackSoundButton", "TrackSoundButton2", "TrackSoundButton3"]
	for n in to_remove:
		var node = get_node_or_null(n)
		if node: node.queue_free()
		
	# Додаємо початкові доріжки (3 рази поспіль)
	_add_new_track("Kick 1")
	_add_new_track("Hit 1")
	_add_new_track("Piano")

func _add_new_track(instrument_name: String = "Piano"):
	if tracks.size() >= 6: return
	
	var track_id = next_track_id
	next_track_id += 1
	
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)
	
	# VBoxContainer (Блок керування)
	var controls_vbox = VBoxContainer.new()
	controls_vbox.custom_minimum_size.x = 160
	controls_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls_vbox.add_theme_constant_override("separation", 5)
	row.add_child(controls_vbox)
	
	# [Кнопка Інструменту]
	var btn = sound_btn_template.duplicate()
	btn.text = instrument_name
	btn.toggle_mode = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): _on_track_btn_pressed(track_id))
	controls_vbox.add_child(btn)
	
	# [HSlider Гучність]
	var slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.8
	slider.value_changed.connect(func(val): _on_track_volume_changed(val, track_id))
	controls_vbox.add_child(slider)
	
	# [Базова сітка секвенсора]
	var lane = lane_template.duplicate()
	lane.custom_minimum_size = lane_template.custom_minimum_size
	lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var open_btn = Button.new()
	open_btn.modulate.a = 0.0
	open_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_btn.pressed.connect(func(): _open_roll(track_id))
	lane.add_child(open_btn)
	row.add_child(lane)
	
	# [Кнопка "-"]
	var del_btn = Button.new()
	del_btn.text = " – "
	del_btn.custom_minimum_size = Vector2(50, lane.custom_minimum_size.y)
	del_btn.add_theme_font_size_override("font_size", 24)
	_style_btn(del_btn, Color.RED)
	del_btn.pressed.connect(func(): _on_delete_track(track_id))
	row.add_child(del_btn)
	
	# Piano Roll Popup
	var roll = roll_template.duplicate() if roll_template else Control.new()
	roll.visible = false
	roll.z_index = 100
	add_child(roll) # Має бути дитиною головного екрану, щоб перекривати все
	
	if roll.has_signal("closed"):
		roll.closed.connect(func(data): update_preview(data, track_id))
	
	if sound_library.has(instrument_name) and roll.has_method("set_instrument"):
		roll.set_instrument(sound_library[instrument_name])
	
	if roll.has_method("set_volume"):
		roll.set_volume(linear_to_db(slider.value))
		
	tracks_vbox.add_child(row)
	
	tracks.append({
		"id": track_id,
		"row": row,
		"btn": btn,
		"slider": slider,
		"lane": lane,
		"roll": roll
	})
	
	_update_add_btn()

func _update_add_btn():
	if tracks.size() >= 6:
		add_track_btn.disabled = true
		add_track_btn.modulate.a = 0.5
	else:
		add_track_btn.disabled = false
		add_track_btn.modulate.a = 1.0
	call_deferred("_reposition_add_btn")

func _reposition_add_btn():
	if not is_instance_valid(tracks_vbox) or not is_instance_valid(add_track_btn): return
	# Розташовуємо кнопку додавання під списком доріжок
	add_track_btn.position = tracks_vbox.position + Vector2(0, tracks_vbox.size.y + 20)

func _on_add_track():
	_add_new_track("Kick 1")

func _on_delete_track(track_id: int):
	for i in range(tracks.size()):
		if tracks[i].id == track_id:
			var t = tracks[i]
			t.row.queue_free()
			if is_instance_valid(t.roll):
				t.roll.queue_free()
			tracks.remove_at(i)
			break
	_update_add_btn()

func _on_track_volume_changed(val: float, track_id: int):
	for t in tracks:
		if t.id == track_id:
			if t.roll.has_method("set_volume"):
				t.roll.set_volume(linear_to_db(val))
			break

func _on_track_btn_pressed(track_id: int):
	# Коли натискаємо кнопку інструменту доріжки, інші маємо вимкнути
	for t in tracks:
		if t.id != track_id:
			t.btn.button_pressed = false

func _on_sound_menu_pressed(sound_name: String):
	if !sound_library.has(sound_name): return
	
	var applied = false
	for t in tracks:
		if t.btn.button_pressed:
			t.btn.text = sound_name
			if t.roll.has_method("set_instrument"):
				t.roll.set_instrument(sound_library[sound_name])
			t.btn.button_pressed = false
			applied = true
			
	if not applied and preview_player:
		preview_player.stream = sound_library[sound_name]
		preview_player.play()

func _open_roll(track_id: int):
	if export_button:
		export_button.hide()
	for t in tracks:
		if t.id == track_id:
			t.roll.visible = true
			t.roll.modulate.a = 0
			_open_roll_async(t.roll)
			break

func _open_roll_async(roll):
	if roll.has_method("sync_ui_to_data"):
		await roll.sync_ui_to_data()
	create_tween().tween_property(roll, "modulate:a", 1.0, 0.2)

func _play_current_step():
	var step_time = 60.0 / bpm / 4.0
	for t in tracks:
		if is_instance_valid(t.roll) and t.roll.has_method("play_step"):
			t.roll.play_step(current_global_step, step_time)

func _on_global_play_pressed():
	if play_button: _animate_click(play_button)
	current_global_step = 0
	var step_time = 60.0 / bpm / 4.0
	if master_timer:
		master_timer.wait_time = step_time
		master_timer.start()
	_play_current_step()
	current_global_step = 1
	if play_button: play_button.self_modulate = COLOR_ACCENT_CYAN

func _on_global_stop_pressed():
	if stop_button: _animate_click(stop_button)
	if master_timer: master_timer.stop()
	current_global_step = 0
	if play_button: play_button.self_modulate = Color.WHITE

func _on_master_timer_timeout():
	if is_exporting:
		export_steps += 1
		if export_steps >= 16:
			# 16-й такт завершився (остання нота прозвучала).
			# Зупиняємо експорт і НЕ граємо нове коло!
			_finish_export()
			return
			
	_play_current_step()
	current_global_step = (current_global_step + 1) % 16

func update_preview(data, track_id):
	if export_button:
		export_button.show()
	var target_lane = null
	for t in tracks:
		if t.id == track_id:
			target_lane = t.lane
			break
			
	if not target_lane: return
	
	for child in target_lane.get_children():
		if child.name == "NoteContainer": child.queue_free()
	
	var container = Control.new()
	container.name = "NoteContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_lane.add_child(container)
	
	var step_w = target_lane.custom_minimum_size.x / 17.0
	var step_h = target_lane.custom_minimum_size.y / 7.0
	
	for r in range(data.size()):
		for c in range(data[r].size()):
			if data[r][c][0] == true:
				var length = data[r][c][1]
				var note = Panel.new()
				
				var sb = StyleBoxFlat.new()
				sb.bg_color = COLOR_ACCENT_YELLOW
				sb.set_corner_radius_all(3)
				sb.shadow_color = COLOR_ACCENT_YELLOW.darkened(0.2)
				sb.shadow_color.a = 0.5
				sb.shadow_size = 4
				
				note.add_theme_stylebox_override("panel", sb)
				note.size = Vector2((step_w * length) - 2.0, step_h - 4.0)
				note.position = Vector2((c + 1) * step_w + 1.0, r * step_h + 2.0)
				note.mouse_filter = Control.MOUSE_FILTER_IGNORE
				container.add_child(note)

func _animate_click(node):
	var t = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2(0.92, 0.92), 0.05)
	t.tween_property(node, "scale", Vector2(1.0, 1.0), 0.05)

func update_bpm_display():
	if bpm_label:
		bpm_label.text = str(bpm) + " BPM"
		bpm_label.add_theme_color_override("font_color", COLOR_ACCENT_CYAN)

func _setup_recording():
	record_effect = AudioEffectRecord.new()
	var master_idx = AudioServer.get_bus_index("Master")
	AudioServer.add_bus_effect(master_idx, record_effect)
	record_effect_index = AudioServer.get_bus_effect_count(master_idx) - 1

func _setup_export_button():
	export_button = Button.new()
	export_button.text = "Export WAV"
	if stop_button:
		export_button.position = stop_button.position + Vector2(stop_button.size.x + 150, 0)
		export_button.size = stop_button.size
		export_button.custom_minimum_size = stop_button.size
	else:
		export_button.position = Vector2(700, 30)
		export_button.custom_minimum_size = Vector2(150, 45)
	
	_style_btn(export_button, COLOR_ACCENT_PINK)
	export_button.pressed.connect(_on_export_pressed)
	add_child(export_button)

	web_warning_dialog = AcceptDialog.new()
	web_warning_dialog.name = "WebWarningDialog"
	web_warning_dialog.dialog_text = "Експорт доступний лише у мобільній версії додатка. Будь ласка, завантажте повну версію!"
	add_child(web_warning_dialog)
	
	save_file_dialog = FileDialog.new()
	save_file_dialog.name = "SaveFileDialog"
	save_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_file_dialog.add_filter("*.wav", "WAV Audio")
	save_file_dialog.file_selected.connect(_on_file_selected)
	add_child(save_file_dialog)
	
	success_dialog = AcceptDialog.new()
	success_dialog.name = "SuccessDialog"
	add_child(success_dialog)

func _on_export_pressed():
	if OS.has_feature("web"):
		if web_warning_dialog: web_warning_dialog.popup_centered()
		return
		
	if is_exporting: return
	is_exporting = true
	export_steps = 0
	if export_button:
		export_button.text = "Recording..."
		export_button.disabled = true
	
	# Зупиняємо відтворення
	_on_global_stop_pressed()
	
	# Увімкнути запис
	record_effect.set_recording_active(true)
	
	# Запуск відтворення
	_on_global_play_pressed()

func _finish_export():
	is_exporting = false
	if master_timer: master_timer.stop()
	record_effect.set_recording_active(false)
	
	if play_button: play_button.self_modulate = Color.WHITE
	current_global_step = 0
	
	var recording = record_effect.get_recording()
	if recording:
		var project_name = "my_beat"
		var name_edit = get_node_or_null("Background/Background/ProjectNameLabel")
		if name_edit and name_edit.text != "":
			var raw_text = name_edit.text
			# Очищаємо від декоративних символів » та « і пробілів
			raw_text = raw_text.replace("»", "").replace("«", "").strip_edges()
			if raw_text != "":
				project_name = raw_text
				
		var file_name = project_name + ".wav"
		var save_path = "user://" + file_name
		recording.save_to_wav(save_path)
		
		var audio_buffer = PackedByteArray()
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			audio_buffer = file.get_buffer(file.get_length())
			file.close()
			
		current_export_buffer = audio_buffer
		current_export_name = project_name
		
		if OS.has_feature("android"):
			var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
			if downloads_dir == "": 
				downloads_dir = "user://"
				
			var final_path = downloads_dir + "/" + project_name + ".wav"
			var out_file = FileAccess.open(final_path, FileAccess.WRITE)
			if out_file:
				out_file.store_buffer(audio_buffer)
				out_file.close()
				if success_dialog:
					success_dialog.dialog_text = "File successfully saved to:\n" + final_path
					success_dialog.popup_centered()
		else:
			if save_file_dialog:
				save_file_dialog.current_file = project_name + ".wav"
				save_file_dialog.popup_centered(Vector2(600, 400))
			
	if export_button:
		export_button.text = "Export WAV"
		export_button.disabled = false

func _on_file_selected(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(current_export_buffer)
		file.close()

func _on_bpm_minus_pressed():
	bpm = max(40, bpm - 5)
	update_bpm_display()

func _on_bpm_plus_pressed():
	bpm = min(240, bpm + 5)
	update_bpm_display()
	
func _build_sound_menu():
	var old_list = get_node_or_null("Background/Background/Background2/InstrumentList")
	if old_list:
		old_list.queue_free()
	
	var scroll = ScrollContainer.new()
	scroll.name = "DynamicInstrumentList"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_top = 157
	scroll.offset_bottom = -20
	scroll.offset_left = 30
	scroll.offset_right = 205
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var sb_empty = StyleBoxEmpty.new()
	scroll.add_theme_stylebox_override("panel", sb_empty)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContent"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	
	add_child(scroll)
	
	var categories = {
		"Kicks": ["Kick 1", "Kick (Bounce)", "Kick (Knock)"],
		"Hats & Claps": ["Hit 1", "Clap (Fighter)", "Clap (Meal)", "Clap (Paper)", "Hihat (Traplord)", "Open Hat (Clank)", "Open Hat (House)", "Open Hat (One)"],
		"Snares": ["Snare 1", "Snare (Join)", "Snare (Sniper)"],
		"Synths & Keys": ["Piano", "Sin Synth"]
	}
	
	for cat_name in categories.keys():
		var cat_vbox = VBoxContainer.new()
		cat_vbox.add_theme_constant_override("separation", 6)
		vbox.add_child(cat_vbox)
		
		# Головна кнопка-папка
		var folder_btn = Button.new()
		folder_btn.text = cat_name
		_style_btn(folder_btn, COLOR_ACCENT_PINK)
		cat_vbox.add_child(folder_btn)
		
		# Внутрішній контейнер
		var sub_vbox = VBoxContainer.new()
		sub_vbox.visible = false
		sub_vbox.add_theme_constant_override("separation", 4)
		cat_vbox.add_child(sub_vbox)
		
		folder_btn.pressed.connect(func(): sub_vbox.visible = !sub_vbox.visible)
		
		# Кнопки звуків
		for sound_name in categories[cat_name]:
			if sound_library.has(sound_name):
				var sound_btn = Button.new()
				sound_btn.text = sound_name
				_style_btn(sound_btn, COLOR_ACCENT_CYAN)
				sound_btn.add_theme_font_size_override("font_size", 12)
				sound_btn.custom_minimum_size.y = 28
				sound_btn.modulate = Color(0.85, 0.9, 1.0) # Приглушити колір
				
				var sb_n = sound_btn.get_theme_stylebox("normal").duplicate()
				sb_n.content_margin_left = 25
				sb_n.content_margin_right = 5
				sound_btn.add_theme_stylebox_override("normal", sb_n)
				
				sound_btn.pressed.connect(func(): _on_sound_menu_pressed(sound_name))
				sub_vbox.add_child(sound_btn)
				
	if old_list:
		old_list.queue_free()

func _apply_premium_style():
	if not Engine.is_editor_hint():
		_cleanup_node($Background)
		_create_global_background()
		_create_sidebar_bg()
		_create_topbar_bg()
	
	_style_btn(play_button, COLOR_ACCENT_CYAN)
	_style_btn(stop_button, Color.WHITE)
	_style_btn(bpm_minus, COLOR_ACCENT_CYAN)
	_style_btn(bpm_plus, COLOR_ACCENT_CYAN)

	var name_edit = get_node_or_null("Background/Background/ProjectNameLabel")
	if name_edit:
		var sb_empty = StyleBoxEmpty.new()
		name_edit.add_theme_stylebox_override("normal", sb_empty)
		name_edit.add_theme_stylebox_override("focus", sb_empty)
		name_edit.add_theme_stylebox_override("read_only", sb_empty)
		name_edit.add_theme_color_override("font_color", COLOR_ACCENT_YELLOW)
		name_edit.add_theme_color_override("caret_color", COLOR_ACCENT_YELLOW)
		name_edit.add_theme_color_override("selection_color", Color(1,1,0,0.3))
		name_edit.add_theme_font_size_override("font_size", 24)

func _create_global_background():
	var bg = CanvasLayer.new()
	bg.layer = -1
	bg.name = "GlobalBG"
	add_child(bg)
	var rect = ColorRect.new()
	rect.color = COLOR_MAIN_BG
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(rect)

func _create_sidebar_bg():
	var panel = Panel.new()
	panel.custom_minimum_size.x = SIDEBAR_WIDTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.show_behind_parent = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = COLOR_SIDEBAR
	sb.set_border_width_all(0)
	sb.border_width_right = 2
	sb.border_color = COLOR_ACCENT_CYAN.darkened(0.5)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	move_child(panel, 0)

func _create_topbar_bg():
	var panel = Panel.new()
	panel.custom_minimum_size.y = TOPBAR_HEIGHT
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.show_behind_parent = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = COLOR_TOPBAR
	sb.set_border_width_all(0)
	sb.border_width_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.05)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	move_child(panel, 1)

func _cleanup_node(node):
	if !node: return
	if node is ColorRect: node.color = Color(0,0,0,0)
	for child in node.get_children(): _cleanup_node(child)

func _inject_panel(parent: Control, color: Color, radius: int, border: int):
	if !parent: return
	if parent is ColorRect: parent.color = Color(0,0,0,0)
	for child in parent.get_children():
		if child.name == "StyledPanel" or child.name == "StepGrid": child.queue_free()
		
	var panel = Panel.new()
	panel.name = "StyledPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.show_behind_parent = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = color.lightened(0.1)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	
	var grid = Control.new()
	grid.name = "StepGrid"
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grid)
	
	var step_w = parent.custom_minimum_size.x / 17.0
	for i in range(1, 17):
		var line = ColorRect.new()
		line.color = Color(1, 1, 1, 0.03)
		line.size = Vector2(1, parent.custom_minimum_size.y)
		line.position.x = i * step_w
		grid.add_child(line)

func _style_btn(btn: Button, color: Color):
	if !btn: return
	var sb = StyleBoxFlat.new()
	sb.bg_color = COLOR_BTN_BG
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.04)
	sb.border_width_bottom = 3
	sb.border_color = color
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 15
	sb.content_margin_right = 15
	btn.add_theme_stylebox_override("normal", sb)
	var sb_h = sb.duplicate()
	sb_h.bg_color = COLOR_BTN_BG.lightened(0.08)
	btn.add_theme_stylebox_override("hover", sb_h)
	var sb_p = sb.duplicate()
	sb_p.bg_color = color
	sb_p.border_width_bottom = 0
	btn.add_theme_stylebox_override("pressed", sb_p)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
