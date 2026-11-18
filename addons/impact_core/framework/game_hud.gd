class_name GameHud
extends CanvasLayer
## On-screen text for a game: the start screen, the in-round status line,
## the results screen, and floating "+3" style pops. Big, high-contrast type,
## because it's read from across a room on a projected wall.

var _status: Label
var _panel: PanelContainer
var _title: Label
var _body: Label


func _ready() -> void:
	_status = _make_label(40, HORIZONTAL_ALIGNMENT_LEFT)
	_status.position = Vector2(32.0, 20.0)
	add_child(_status)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.82)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(40)
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_title = _make_label(72, HORIZONTAL_ALIGNMENT_CENTER)
	_body = _make_label(32, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	box.add_child(_body)
	_panel.add_child(box)
	# A full-screen container that keeps the panel in the middle at any size.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)
	add_child(center)


## Show the big centered panel (start or results screen).
func show_panel(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_panel.visible = true


func hide_panel() -> void:
	_panel.visible = false


## The line at the top-left, e.g. "Throw 4 / 10    Score 12".
func set_status(text: String) -> void:
	_status.text = text


## A short word or number that floats up from a point on screen and fades.
func show_pop(text: String, screen_pos: Vector2, color: Color = Color(1.0, 0.85, 0.3)) -> void:
	var pop := _make_label(56, HORIZONTAL_ALIGNMENT_CENTER)
	pop.text = text
	pop.add_theme_color_override("font_color", color)
	add_child(pop)
	pop.reset_size()
	pop.position = screen_pos - pop.size / 2.0 - Vector2(0.0, 30.0)
	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "position:y", pop.position.y - 70.0, 0.8)
	tween.tween_property(pop, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(pop.queue_free)


func _make_label(font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	return label
