extends VBoxContainer
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
signal submitted(text: String)
signal cancelled
signal help_requested
signal point_requested
signal focus_changed
var phrase: LineEdit
var prefix: LineEdit
var matches: ItemList
var help_button: Button
var opener_key := 0

func _ready() -> void:
	add_theme_constant_override("separation",5)
	var phrase_row := HBoxContainer.new()
	add_child(phrase_row)
	phrase = LineEdit.new()
	phrase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phrase.placeholder_text = "Напишите реплику по-немецки…"
	phrase.keep_editing_on_text_submit = true
	phrase_row.add_child(phrase)
	add_button(phrase_row,"Отправить · Enter",send)
	add_button(phrase_row,"Очистить",clear)
	prefix = LineEdit.new()
	prefix.placeholder_text = "Найти слово в каталоге…"
	prefix.keep_editing_on_text_submit = true
	add_child(prefix)
	matches = ItemList.new()
	matches.custom_minimum_size.y = 48
	matches.max_columns = 8
	matches.same_column_width = true
	add_child(matches)
	prefix.text_changed.connect(update_matches)
	prefix.text_submitted.connect(func(_text): prefix_enter())
	phrase.text_submitted.connect(func(_text): send())
	matches.item_activated.connect(func(index): matches.select(index); choose_word())
	for field in [phrase,prefix]:
		field.focus_entered.connect(func(): focus_changed.emit())
		field.focus_exited.connect(func(): focus_changed.emit.call_deferred())
	var hint := Label.new()
	hint.text = "Ctrl+Tab · переключить строку   /   ↓/↑ · перейти к поиску/реплике   /   Tab · вариант   /   Пробел · добавить слово   /   Enter · отправить"
	hint.add_theme_font_size_override("font_size", 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	update_matches("")

func add_button(row: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	row.add_child(button)
	return button

func update_matches(value: String) -> void:
	matches.clear()
	for word in Parser.suggestions(value): matches.add_item(word)
	if matches.item_count > 0: matches.select(0)

func choose_word() -> void:
	var chosen := matches.get_selected_items()
	if chosen.is_empty(): return
	phrase.text = (phrase.text+" "+matches.get_item_text(chosen[0])).strip_edges()
	prefix.clear()
	update_matches("")
	prefix.grab_focus()

func prefix_enter() -> void:
	send()

func send() -> void:
	# Never silently drop an unconfirmed token such as 'nicht', and never
	# replace it with the first autocomplete suggestion on Enter.
	var text := (phrase.text+" "+prefix.text).strip_edges()
	if text.is_empty(): return
	phrase.text = text
	prefix.clear()
	update_matches("")
	submitted.emit(text)

func suppress_opener(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		opener_key = event.physical_keycode if event.physical_keycode != 0 else event.keycode

func consume_opener(event: InputEvent) -> bool:
	if opener_key == 0 or not event is InputEventKey: return false
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code != opener_key: return false
	if not event.pressed: opener_key = 0
	get_viewport().set_input_as_handled()
	return true

func editing() -> bool:
	return is_visible_in_tree() and (phrase.has_focus() or prefix.has_focus())

func release() -> void:
	phrase.release_focus()
	prefix.release_focus()

func clear() -> void:
	phrase.clear()
	prefix.clear()
	update_matches("")

func route_key(event: InputEvent) -> bool:
	if consume_opener(event): return true
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed: return false
	if event.keycode == KEY_F1 and (editing() or matches.has_focus()):
		get_viewport().set_input_as_handled()
		if not event.echo: help_requested.emit()
		return true
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER] and (editing() or matches.has_focus()):
		get_viewport().set_input_as_handled()
		if not event.echo: send()
		return true
	if event.keycode == KEY_TAB and event.ctrl_pressed and (editing() or matches.has_focus()):
		get_viewport().set_input_as_handled()
		if not event.echo:
			if phrase.has_focus(): prefix.grab_focus()
			else: phrase.grab_focus()
		return true
	if event.keycode == KEY_DOWN and phrase.has_focus():
		prefix.grab_focus()
		get_viewport().set_input_as_handled()
		return true
	if event.keycode == KEY_UP and prefix.has_focus():
		phrase.grab_focus()
		get_viewport().set_input_as_handled()
		return true
	if event.keycode == KEY_TAB and (editing() or matches.has_focus()):
		get_viewport().set_input_as_handled()
		if not event.echo and matches.item_count > 0:
			var selected := matches.get_selected_items()
			var index := int(selected[0]) if not selected.is_empty() else -1
			index = posmod(index + (-1 if event.shift_pressed else 1), matches.item_count)
			matches.select(index)
			matches.ensure_current_is_visible()
			prefix.grab_focus()
		return true
	if event.keycode == KEY_SPACE and (prefix.has_focus() or matches.has_focus()):
		get_viewport().set_input_as_handled()
		if not event.echo: choose_word()
		return true
	if event.keycode in [KEY_UP,KEY_DOWN] and matches.item_count > 0 and (prefix.has_focus() or matches.has_focus()):
		var selected := matches.get_selected_items()
		var index := int(selected[0]) if not selected.is_empty() else 0
		index = clampi(index+(-1 if event.keycode == KEY_UP else 1),0,matches.item_count-1)
		matches.select(index)
		matches.ensure_current_is_visible()
		get_viewport().set_input_as_handled()
		return true
	return false
