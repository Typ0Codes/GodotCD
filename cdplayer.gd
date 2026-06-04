extends Node

signal album_found(album: Dictionary)
signal disc_removed

const CD_DEVICE = "/dev/sr0"
const MPV_SOCKET = "/tmp/cdplayer_mpv.sock"

const NO_DISC_TEXTURE = preload("res://nodisc.png")

var is_paused    := false
var track_time_ms := 0.0

var mpv_socket := StreamPeerUDS.new()
var mpv_connected := false

var disc_rotation := 0.0
var disc_speed := 0.0
var shuffle := false

var _poll_thread: Thread = null

var pause = load("res://pause.png")
var play = load("res://play.png")

@onready var cover_http          := $CoverHTTPRequest
@onready var poll_timer          := $PollTimer
@onready var album_art           := $Ui/DiscContainer/AlbumArt
@onready var album_title         := $Ui/AlbumTitle
@onready var artist_label        := $Ui/Artist
@onready var track_list          := $Ui/ItemList
@onready var progress_bar        := $Ui/ProgressBar
@onready var current_track_label := $Ui/CurrentTrack
@onready var play_btn            := $Ui/Play #This is actually the shuffle i just couldnt be bothered to go change it
@onready var stop_btn            := $Ui/Stop
@onready var prev_btn            := $Ui/Previous
@onready var next_btn            := $Ui/Next
@onready var background_rect     := $Ui/Background
@onready var eject_btn           := $Ui/Eject
@onready var disc_container      := $Ui/DiscContainer

const HEADERS = [
	"User-Agent: GodotCDPlayer/1.0 (shippedinspace@gmail.com)",
	"Accept: application/json"
]

var current_album := {}
var current_track := 0
var last_disc_id  := ""
var mpv_pid       := -1
var play_start    := 0
var volume        := 80

func _ready() -> void:
	cover_http.max_redirects = 8
	
	_load_manual_db()
	
	await get_tree().process_frame

	disc_container.pivot_offset = disc_container.size / 2.0
	disc_container.resized.connect(func():
		disc_container.pivot_offset = disc_container.size / 2.0
	)

	album_art.texture = NO_DISC_TEXTURE


	_kill_dangling_mpv()






	var vol_slider = $Ui/Volume
	vol_slider.min_value = 0
	vol_slider.max_value = 100
	vol_slider.value     = volume
	vol_slider.value_changed.connect(_on_volume_changed)

	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value     = 0.0

	current_track_label.text = ""

	poll_timer.timeout.connect(_check_disc)
	poll_timer.start(1.5)

	await get_tree().create_timer(1.0).timeout
	var disc_id = get_disc_id()
	last_disc_id = disc_id
	if disc_id != "":
		lookup_disc(disc_id)

func _process(delta: float) -> void:
	_update_background(delta)
	var target_speed := 0.0
	if mpv_pid != -1 and not is_paused:
		target_speed = 45.0

	disc_speed = lerpf(disc_speed, target_speed, delta * 4.0)

	if abs(disc_speed - target_speed) < 0.05:
		disc_speed = target_speed

	disc_container.rotation_degrees += disc_speed * delta

	if current_album.is_empty() or current_track >= current_album["tracks"].size():
		return

	var length_ms := int(current_album["tracks"][current_track]["length"])
	if length_ms > 0:
		track_time_ms += delta * 1000.0
		progress_bar.value = clampf(track_time_ms / float(length_ms), 0.0, 1.0)

		if track_time_ms >= length_ms:
			_on_track_finished()

func _exit_tree() -> void:
	_stop_mpv()
	if _poll_thread != null and _poll_thread.is_alive():
		_poll_thread.wait_to_finish()

func _ensure_script() -> String:
	var tmp_path = OS.get_temp_dir() + "/cd_discid.py"
	
	var src = FileAccess.open("res://cd_discid.py", FileAccess.READ)
	if src == null:
		push_error("cd_discid.py not found in package!")
		return ""
	var src_text = src.get_as_text()
	src.close()


	var needs_write = true
	if FileAccess.file_exists(tmp_path):
		var existing = FileAccess.open(tmp_path, FileAccess.READ)
		if existing != null and existing.get_as_text() == src_text:
			needs_write = false
		if existing:
			existing.close()

	if needs_write:
		var dst = FileAccess.open(tmp_path, FileAccess.WRITE)
		if dst == null:
			push_error("Could not write script to temp dir!")
			return ""
		dst.store_string(src_text)
		dst.close()

	return tmp_path

func get_disc_id() -> String:
	var output    = []
	var script    = _ensure_script()
	var exit_code = OS.execute("python3", [script, CD_DEVICE], output, true)
	if exit_code == 0 and output.size() > 0:
		var id = output[0].strip_edges()
		if not id.begins_with("ERROR"):
			return id
	return ""

func _check_disc() -> void:
	if _poll_thread != null and _poll_thread.is_alive():
		return
	_poll_thread = Thread.new()
	_poll_thread.start(_check_disc_thread)

func _check_disc_thread() -> void:
	var disc_id = get_disc_id()
	call_deferred("_on_disc_check_result", disc_id)

func _on_disc_check_result(disc_id: String) -> void:
	_poll_thread.wait_to_finish()
	_poll_thread = null

	if disc_id == last_disc_id:
		return

	last_disc_id = disc_id

	if disc_id != "":
		lookup_disc(disc_id)
	else:
		disc_removed.emit()
		_stop_mpv()
		current_album = {}
		album_title.text         = "No disc"
		artist_label.text        = ""
		current_track_label.text = ""
		track_list.clear()
		album_art.texture = NO_DISC_TEXTURE
		last_disc_id = "EMPTY"

func lookup_disc(disc_id: String) -> void:
	var url = "https://musicbrainz.org/ws/2/discid/%s?fmt=json&inc=artists+recordings" % disc_id
	print("Looking up: ", url)
	$HTTPRequest.request(url, HEADERS)

func _on_http_request_completed(_result, code, _headers, body) -> void:
	if code != 200:
		print("MusicBrainz lookup failed: ", code)
		_try_manual_fallback()
		return

	var json = JSON.new()
	json.parse(body.get_string_from_utf8())
	var data = json.get_data()

	if not data.has("releases") or data["releases"].is_empty():
		print("No releases found for this disc")
		_try_manual_fallback()
		return

	if not data.has("releases") or data["releases"].is_empty():
		print("No releases found for this disc")
		album_art.texture = NO_DISC_TEXTURE
		return

	var release      = data["releases"][0]
	var release_mbid = release.get("id", "")

	var album = {
		"title":  release.get("title", "Unknown Album"),
		"date":   release.get("date", ""),
		"artist": release["artist-credit"][0]["artist"]["name"] if release.has("artist-credit") else "Unknown",
		"tracks": [],
		"mbid":   release_mbid
	}

	var media = release.get("media", [])
	if media.size() > 0:
		for track in media[0].get("tracks", []):
			album["tracks"].append({
				"number": track.get("number", ""),
				"title":  track.get("title", "Untitled"),
				"length": track.get("length", 0)
			})

	album_found.emit(album)

	if release_mbid != "":
		fetch_cover_art(release_mbid)

func fetch_cover_art(release_mbid: String) -> void:
	var url = "https://coverartarchive.org/release/%s/front-500" % release_mbid
	cover_http.request(url, HEADERS)

func _on_cover_http_request_completed(_result, code, headers, body) -> void:
	if code in [301, 302, 307, 308]:
		for header in headers:
			if header.to_lower().begins_with("location:"):
				var redirect_url = header.split(": ", true, 1)[1].strip_edges()
				cover_http.request(redirect_url, HEADERS)
				return
		return

	if code == 200:
		var img = Image.new()
		var err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
		if err == OK:
			album_art.texture = ImageTexture.create_from_image(img)
			var colors = _get_prominent_colors(img, 4)
			_set_background_colors(colors)
		else:
			print("Could not decode cover art image")
			album_art.texture = NO_DISC_TEXTURE
	else:
		print("Cover art failed: ", code)
		album_art.texture = NO_DISC_TEXTURE

func _on_album_found(album: Dictionary) -> void:
	current_album = album
	current_track = 0

	album_title.text  = album["title"]
	artist_label.text = album["artist"]
	current_track_label.text = ""

	track_list.clear()
	for track in album["tracks"]:
		var secs: int = int(track["length"]) / 1000
		var mins: int = secs / 60
		var s: int    = secs % 60
		track_list.add_item("%s. %s  (%d:%02d)" % [track["number"], track["title"], mins, s])

func _update_current_track_label() -> void:
	if current_album.is_empty() or current_track >= current_album["tracks"].size():
		current_track_label.text = ""
		return
	var track = current_album["tracks"][current_track]
	current_track_label.text = "%s. %s" % [track["number"], track["title"]]

func play_track(track_index: int) -> void:
	_stop_mpv()
	progress_bar.value = 0.0
	current_track = track_index

	is_paused = false
	track_time_ms = 0.0


	var track_argument = "--start=#%d" % (track_index + 1)

	mpv_pid = OS.create_process("mpv", [
		"cdda://",
		"--cdda-device=" + CD_DEVICE,
		track_argument,
		"--no-video",
		"--no-terminal",
		"--volume=%d" % volume,
		"--input-ipc-server=" + MPV_SOCKET
	])

	if mpv_pid == -1:
		print("Failed to start mpv process.")
		return

	_update_current_track_label()
	track_list.select(current_track)

func _stop_mpv() -> void:
	if mpv_pid != -1:
		OS.kill(mpv_pid)
		mpv_pid = -1
	progress_bar.value = 0.0
	current_track_label.text = ""

func _on_volume_changed(value: float) -> void:
	volume = int(value)
	_send_mpv_command(["set_property", "volume", volume])

func _on_play_pressed() -> void:
	shuffle = not shuffle


func _on_stop_pressed() -> void:
	if current_album.is_empty():
		return

	if mpv_pid == -1:
		play_track(current_track)
		stop_btn.icon = pause
		return

	is_paused = not is_paused
	_send_mpv_command(["set_property", "pause", is_paused])
	stop_btn.icon = play if is_paused else pause

func _on_prev_pressed() -> void:
	if current_album.is_empty():
		return
	current_track = max(0, current_track - 1)
	play_track(current_track)

func _on_next_pressed() -> void:
	if current_album.is_empty():
		return
	current_track = mini(current_album["tracks"].size() - 1, current_track + 1)
	play_track(current_track)

func _on_track_selected(index: int) -> void:
	current_track = index
	play_track(current_track)

func _on_track_finished() -> void:
	_stop_mpv()
	if current_album.is_empty():
		return
	if shuffle:
		var next = randi() % current_album["tracks"].size()
		play_track(next)
	elif current_track < current_album["tracks"].size() - 1:
		current_track += 1
		play_track(current_track)

func _on_eject_pressed() -> void:
	_stop_mpv()
	last_disc_id = ""
	current_album = {}
	album_title.text         = "No disc"
	artist_label.text        = ""
	current_track_label.text = ""
	track_list.clear()
	album_art.texture = NO_DISC_TEXTURE

	await get_tree().create_timer(0.5).timeout
	var output := []
	var exit_code := OS.execute("eject", [CD_DEVICE], output, true)
	if exit_code != 0:
		print("Eject failed:", output)

func _kill_dangling_mpv() -> void:
	OS.execute("pkill", ["-f", "input-ipc-server=" + MPV_SOCKET])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_mpv()

func _send_mpv_command(command_array: Array) -> void:
	if mpv_pid == -1:
		return
	_ensure_mpv_socket()
	if not mpv_connected:
		return
	var payload = JSON.stringify({"command": command_array}) + "\n"
	mpv_socket.put_data(payload.to_utf8_buffer())

func _ensure_mpv_socket() -> void:
	if mpv_connected:
		return
	var err = mpv_socket.connect_to_host(MPV_SOCKET)
	if err != OK:
		print("MPV socket connect failed")
		mpv_connected = false
		return
	mpv_connected = true

func _get_average_image_color(img: Image) -> Color:
	var width = img.get_width()
	var height = img.get_height()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var count := 0
	for y in range(0, height, 4):
		for x in range(0, width, 4):
			var c = img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			r += c.r
			g += c.g
			b += c.b
			count += 1
	if count == 0:
		return Color.BLACK
	return Color(r / count, g / count, b / count, 1.0)
	

func _get_prominent_colors(img: Image, count: int = 4) -> Array[Color]:
	var buckets := {}
	var width = img.get_width()
	var height = img.get_height()

	for y in range(0, height, 6):
		for x in range(0, width, 6):
			var c = img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			var key = "%d_%d_%d" % [int(c.r * 8), int(c.g * 8), int(c.b * 8)]
			if buckets.has(key):
				buckets[key]["count"] += 1
			else:
				buckets[key] = {"color": c, "count": 1}

	var sorted_buckets = buckets.values()
	sorted_buckets.sort_custom(func(a, b): return a["count"] > b["count"])

	var result: Array[Color] = []

	for bucket in sorted_buckets:
		var c: Color = bucket["color"]

		var luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
		if luminance > 0.75:
			continue

		if result.is_empty():
			result.append(c)
			continue

		var different_enough = true
		for picked in result:
			var dr = abs(c.r - picked.r)
			var dg = abs(c.g - picked.g)
			var db = abs(c.b - picked.b)
			if dr + dg + db < 0.5:
				different_enough = false
				break

		if different_enough:
			result.append(c)

		if result.size() >= count:
			break

	while result.size() < count:
		var base = result[0] if not result.is_empty() else Color(0.2, 0.2, 0.3)
		result.append(Color(
			clampf(base.r * randf_range(0.5, 0.85), 0.0, 0.75),
			clampf(base.g * randf_range(0.5, 0.85), 0.0, 0.75),
			clampf(base.b * randf_range(0.5, 0.85), 0.0, 0.75)
		))

	return result


var bg_colors: Array[Color] = []
var bg_target_colors: Array[Color] = []
var bg_lerp_t := 0.0
var bg_shift_timer := 0.0

func _set_background_colors(colors: Array[Color]) -> void:
	bg_target_colors = colors
	if bg_colors.is_empty():
		bg_colors = colors.duplicate()
	
func _update_background(delta: float) -> void:
	if bg_target_colors.is_empty():
		return


	bg_lerp_t = minf(bg_lerp_t + delta * 0.5, 1.0)
	for i in range(min(bg_colors.size(), bg_target_colors.size())):
		bg_colors[i] = bg_colors[i].lerp(bg_target_colors[i], delta * 0.5)


	bg_shift_timer += delta * 0.15
	var offset = (sin(bg_shift_timer) * 0.5) + 0.5

	if bg_colors.size() >= 2:
		var mat = background_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("color_a", bg_colors[0])
			mat.set_shader_parameter("color_b", bg_colors[1 % bg_colors.size()])
			mat.set_shader_parameter("color_c", bg_colors[2 % bg_colors.size()])
			mat.set_shader_parameter("color_d", bg_colors[3 % bg_colors.size()])
			mat.set_shader_parameter("shift", offset)
			mat.set_shader_parameter("time", bg_shift_timer)
			
const MANUAL_DB_PATH = "user://manual_albums.cfg"
var manual_db := ConfigFile.new()

func _load_manual_db() -> void:
	manual_db.load(MANUAL_DB_PATH)

func _save_manual_entry(disc_id: String, album: Dictionary) -> void:
	manual_db.set_value(disc_id, "title", album["title"])
	manual_db.set_value(disc_id, "artist", album["artist"])
	manual_db.set_value(disc_id, "cover_path", album.get("cover_path", ""))
	manual_db.set_value(disc_id, "tracks", album["tracks"])
	manual_db.save(MANUAL_DB_PATH)

func _load_manual_entry(disc_id: String) -> Dictionary:
	if not manual_db.has_section(disc_id):
		return {}
	return {
		"title":      manual_db.get_value(disc_id, "title", "Unknown Album"),
		"artist":     manual_db.get_value(disc_id, "artist", "Unknown"),
		"cover_path": manual_db.get_value(disc_id, "cover_path", ""),
		"tracks":     manual_db.get_value(disc_id, "tracks", []),
		"mbid":       ""
	}

func _try_manual_fallback() -> void:
	var saved = _load_manual_entry(last_disc_id)
	if not saved.is_empty():
		album_found.emit(saved)
		if saved["cover_path"] != "":
			_load_cover_from_path(saved["cover_path"])
		return
	_show_manual_entry_dialog()

func _show_manual_entry_dialog() -> void:
	var track_count = _get_track_count()

	var dialog = AcceptDialog.new()
	dialog.title = "Album Not Found"
	dialog.size = Vector2(400, 320)

	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	var title_label = Label.new()
	title_label.text = "Album Title:"
	vbox.add_child(title_label)

	var title_input = LineEdit.new()
	title_input.placeholder_text = "Enter album title"
	vbox.add_child(title_input)

	var artist_label_node = Label.new()
	artist_label_node.text = "Artist:"
	vbox.add_child(artist_label_node)

	var artist_input = LineEdit.new()
	artist_input.placeholder_text = "Enter artist name"
	vbox.add_child(artist_input)

	var cover_label = Label.new()
	cover_label.text = "Cover Image (optional):"
	vbox.add_child(cover_label)

	var cover_hbox = HBoxContainer.new()
	vbox.add_child(cover_hbox)

	var cover_input = LineEdit.new()
	cover_input.placeholder_text = "/path/to/image.jpg"
	cover_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cover_hbox.add_child(cover_input)

	var browse_btn = Button.new()
	browse_btn.text = "Browse"
	cover_hbox.add_child(browse_btn)


	var track_info = Label.new()
	track_info.text = "Tracks found: %d" % track_count if track_count > 0 else "Could not detect tracks"
	vbox.add_child(track_info)

	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = ["*.png,*.jpg,*.jpeg ; Images"]
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.current_dir = OS.get_environment("HOME")
	add_child(file_dialog)

	browse_btn.pressed.connect(func(): file_dialog.popup_centered(Vector2(600, 400)))
	file_dialog.file_selected.connect(func(path): cover_input.text = path)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(func():
		var tracks := []
		for i in range(track_count):
			tracks.append({
				"number": str(i + 1),
				"title":  "Track %d" % (i + 1),
				"length": 0
			})

		var album = {
			"title":      title_input.text if title_input.text != "" else "Unknown Album",
			"artist":     artist_input.text if artist_input.text != "" else "Unknown",
			"cover_path": cover_input.text,
			"tracks":     tracks,
			"mbid":       "",
			"date":       ""
		}
		_save_manual_entry(last_disc_id, album)
		album_found.emit(album)
		if cover_input.text != "":
			_load_cover_from_path(cover_input.text)
		file_dialog.queue_free()
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		file_dialog.queue_free()
		dialog.queue_free()
	)

func _load_cover_from_path(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Could not open file: ", path)
		album_art.texture = NO_DISC_TEXTURE
		return

	var buffer = file.get_buffer(file.get_length())
	file.close()

	var img = Image.new()
	var err = img.load_jpg_from_buffer(buffer)
	if err != OK:
		err = img.load_png_from_buffer(buffer)
	if err == OK:
		album_art.texture = ImageTexture.create_from_image(img)
		var colors = _get_prominent_colors(img, 4)
		_set_background_colors(colors)
	else:
		print("Failed to decode cover image: ", path)
		album_art.texture = NO_DISC_TEXTURE
		
func _get_track_count() -> int:
	var output := []
	var exit_code := OS.execute("sh", ["-c", "cd-info --no-header --quiet %s 2>/dev/null | grep -c 'track'" % CD_DEVICE], output, true)
	if exit_code == 0 and output.size() > 0:
		var count = output[0].strip_edges().to_int()
		if count > 0:
			return count

	output.clear()
	OS.execute("sh", ["-c", "cdparanoia -Q -d %s 2>&1 | grep -E '^\\s+[0-9]+\\.' | wc -l" % CD_DEVICE], output, true)
	if output.size() > 0:
		var count = output[0].strip_edges().to_int()
		if count > 0:
			return count

	return 0
