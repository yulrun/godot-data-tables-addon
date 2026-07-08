## Control panel for managing visual row schema definitions and code generation.
##
## Allows designers to define property rules visually and compiles them into 
## optimized, strongly-typed GDScript files for the core engine.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
class_name DataTableStructurePanel extends MarginContainer


#region Core Properties & State
enum SearchMode {
	NATIVE,
	CUSTOM
}

const BASE_TYPES: Array[String] = [
	"String", "StringName", "int", "float", "bool", 
	"Vector2", "Vector3", "Color", 
	"Texture2D", "PackedScene", "Resource"
]

const EXTRA_VARIANTS: Array[String] = [
	"AABB", "Array", "Basis", "Callable", "Dictionary", "NodePath", 
	"Plane", "Projection", "Quaternion", "Rect2", "Rect2i", "RID", 
	"Signal", "Transform2D", "Transform3D", "Vector4", "Vector4i"
]

var active_script_path: String = ""

## Tracks the root PanelContainer "Card" for every property injected into the workspace.
var property_rows: Array[PanelContainer] = []
var active_row_for_deletion: PanelContainer = null
var active_row_for_duplication: PanelContainer = null

var active_dropdown_for_custom: OptionButton = null
var active_default_container: HBoxContainer = null
var current_search_mode: SearchMode = SearchMode.CUSTOM

## Tracks if the UI has unsaved modifications pending a compile.
var is_dirty: bool = false

## Tracks if the schema editor is currently locked to prevent accidental modifications.
var is_locked: bool = false
#endregion


#region Dynamic UI Elements
var delete_confirm: ConfirmationDialog
var duplicate_confirm: ConfirmationDialog
var close_schema_confirm: ConfirmationDialog
var compile_confirm: ConfirmationDialog
var revert_confirm: ConfirmationDialog
var lock_dirty_warning: AcceptDialog
var success_dialog: AcceptDialog
var script_open_warning: AcceptDialog
var validation_dialog: AcceptDialog

var class_picker: ConfirmationDialog
var class_search: LineEdit
var class_list: ItemList

@onready var current_schema_label: Label = %CurrentSchemaLabel
@onready var fields_container: VBoxContainer = %FieldsContainer
@onready var btn_new_schema: Button = %BtnNewSchema
@onready var btn_load_schema: Button = %BtnLoadSchema
@onready var btn_close_schema: Button = %BtnCloseSchema
@onready var btn_revert: Button = %BtnRevert
@onready var btn_lock_unlock: Button = %BtnLockUnlock
@onready var btn_add_field: Button = %BtnAddField
@onready var btn_compile: Button = %BtnCompile
#endregion


#region UI Initialization & Setup
func _ready() -> void:
	if not Engine.is_editor_hint():
		return
		
	_initialize_dynamic_dialogs()
	
	# Apply Native Editor Icons & Tooltips
	btn_new_schema.icon = _get_safe_theme_icon("New")
	btn_load_schema.icon = _get_safe_theme_icon("Load")
	btn_close_schema.icon = _get_safe_theme_icon("Close")
	btn_revert.icon = _get_safe_theme_icon("UndoRedo")
	btn_lock_unlock.icon = _get_safe_theme_icon("Unlock")
	btn_add_field.icon = _get_safe_theme_icon("Add")
	btn_compile.icon = _get_safe_theme_icon("Save")
	
	btn_new_schema.tooltip_text = "Create a new DataStructure schema."
	btn_load_schema.tooltip_text = "Load an existing DataStructure schema from disk."
	btn_close_schema.tooltip_text = "Close the active schema workspace."
	btn_revert.tooltip_text = "Revert all unsaved changes and reload the schema from disk."
	btn_lock_unlock.tooltip_text = "Lock schema to prevent accidental edits."
	btn_add_field.tooltip_text = "Add a new property field to the active schema."
	btn_compile.tooltip_text = "Compile and save the schema to a strongly-typed .gd script."
	
	btn_new_schema.pressed.connect(_on_new_schema_pressed)
	btn_load_schema.pressed.connect(_on_load_schema_pressed)
	btn_close_schema.pressed.connect(_on_close_schema_pressed)
	btn_revert.pressed.connect(func(): revert_confirm.popup_centered())
	btn_lock_unlock.pressed.connect(_on_lock_unlock_pressed)
	
	# Connect add field so the new card instantly highlights yellow to signify unsaved!
	btn_add_field.pressed.connect(func(): 
		var card = add_blank_property_row()
		_mark_row_dirty(card)
	)
	
	# Safe compile routing
	btn_compile.pressed.connect(func(): compile_confirm.popup_centered())
	
	# Enforce breathing room between our property "Cards"
	fields_container.add_theme_constant_override("separation", 8)
	
	_update_ui_state()


## Builds native popups programmatically to keep the Scene tree clean.
func _initialize_dynamic_dialogs() -> void:
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.dialog_text = "Are you sure you want to remove this property?"
	delete_confirm.confirmed.connect(_execute_row_deletion)
	add_child(delete_confirm)
	
	duplicate_confirm = ConfirmationDialog.new()
	duplicate_confirm.dialog_text = "Duplicate this property?"
	duplicate_confirm.confirmed.connect(_execute_row_duplication)
	add_child(duplicate_confirm)
	
	close_schema_confirm = ConfirmationDialog.new()
	close_schema_confirm.dialog_text = "You have unsaved changes. Are you sure you want to close this schema without compiling?"
	close_schema_confirm.confirmed.connect(_execute_close_schema)
	add_child(close_schema_confirm)
	
	revert_confirm = ConfirmationDialog.new()
	revert_confirm.title = "Revert Changes"
	revert_confirm.dialog_text = "Are you sure you want to revert all unsaved changes?\n\nThis will reload the schema from disk and permanently discard your current modifications."
	revert_confirm.confirmed.connect(_execute_revert_schema)
	add_child(revert_confirm)
	
	compile_confirm = ConfirmationDialog.new()
	compile_confirm.title = "Confirm Compile"
	compile_confirm.dialog_text = "Do you wish to compile and save this schema?\n\nThis will overwrite the existing .gd script on your disk."
	compile_confirm.confirmed.connect(_on_compile_pressed)
	add_child(compile_confirm)
	
	lock_dirty_warning = AcceptDialog.new()
	lock_dirty_warning.title = "Cannot Lock Schema"
	lock_dirty_warning.dialog_text = "You have unsaved changes.\n\nPlease compile and save your schema, or revert changes, before locking the workspace."
	add_child(lock_dirty_warning)
	
	success_dialog = AcceptDialog.new()
	success_dialog.title = "Success"
	add_child(success_dialog)
	
	script_open_warning = AcceptDialog.new()
	script_open_warning.title = "Cannot Compile"
	script_open_warning.dialog_text = "This schema script is currently open in the Godot Script Editor.\n\nPlease close the script tab before compiling to prevent engine file-lock errors."
	add_child(script_open_warning)
	
	validation_dialog = AcceptDialog.new()
	validation_dialog.title = "Validation Error"
	add_child(validation_dialog)
	
	# The Fuzzy Resource/Type Selector 
	class_picker = ConfirmationDialog.new()
	class_picker.title = "Select Resource Type"
	class_picker.size = Vector2(400, 500)
	
	var picker_vbox := VBoxContainer.new()
	picker_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	class_picker.add_child(picker_vbox)
	
	class_search = LineEdit.new()
	class_search.placeholder_text = "Search types..."
	class_search.text_changed.connect(_populate_class_list)
	picker_vbox.add_child(class_search)
	
	class_list = ItemList.new()
	class_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	class_list.item_activated.connect(func(idx: int): class_picker.get_ok_button().emit_signal("pressed"))
	picker_vbox.add_child(class_list)
	
	class_picker.confirmed.connect(_on_custom_class_selected)
	class_picker.canceled.connect(_on_class_picker_canceled)
	add_child(class_picker)


## Safely fetches an icon from the editor theme, falling back to "Object" if broken/missing.
func _get_safe_theme_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control.has_theme_icon(icon_name, "EditorIcons"):
		return base_control.get_theme_icon(icon_name, "EditorIcons")
	return base_control.get_theme_icon("Object", "EditorIcons")


## Flags the workspace as unsaved, updating the label with yellow warning text.
func _mark_dirty() -> void:
	if not is_dirty and not active_script_path.is_empty():
		is_dirty = true
		_update_ui_state()


## Highlights a specific property card to visually indicate it has unsaved modifications.
func _mark_row_dirty(card: PanelContainer) -> void:
	if not card.has_meta("is_row_dirty"):
		card.set_meta("is_row_dirty", true)
		var style: StyleBoxFlat = card.get_theme_stylebox("panel")
		var warning_color := Color(1.0, 0.8, 0.4, 0.15) # Faint yellow tint
		style.bg_color = style.bg_color.blend(warning_color)
		style.border_color = Color(1.0, 0.8, 0.4, 0.5) # Hard yellow border
		
	# Ensure the global file is also flagged as unsaved!
	_mark_dirty()


## Wipes the yellow warning highlight from all cards after a successful compile.
func _clear_all_row_dirty_states() -> void:
	var base_color: Color = EditorInterface.get_editor_settings().get("interface/theme/base_color") if Engine.is_editor_hint() else Color(0.2, 0.2, 0.2)
	for card in property_rows:
		if card.has_meta("is_row_dirty"):
			card.remove_meta("is_row_dirty")
			var style: StyleBoxFlat = card.get_theme_stylebox("panel")
			style.bg_color = base_color.lightened(0.035)
			style.border_color = Color.BLACK.lightened(0.1)


## Refreshes the top label and toggles main action buttons.
## Now supports State-Aware colors: Transparent (None), Hint (Active), Warning (Dirty).
func _update_ui_state() -> void:
	var baseline_active := not active_script_path.is_empty()
	var has_unsaved_changes := baseline_active and is_dirty
	
	btn_lock_unlock.disabled = not baseline_active
	btn_add_field.disabled = not baseline_active or is_locked
	btn_close_schema.disabled = not baseline_active
	
	# Both revert and compile buttons are ONLY active if the table has unsaved changes
	btn_revert.disabled = not has_unsaved_changes
	btn_compile.disabled = not has_unsaved_changes
	
	# Icon / Tooltip mapping for lock
	if is_locked:
		btn_lock_unlock.icon = _get_safe_theme_icon("Lock")
		btn_lock_unlock.tooltip_text = "Unlock schema for editing."
	else:
		btn_lock_unlock.icon = _get_safe_theme_icon("Unlock")
		btn_lock_unlock.tooltip_text = "Lock schema to prevent accidental edits."
	
	# Fetch editor colors dynamically
	var hint_color: Color = EditorInterface.get_editor_settings().get("interface/theme/accent_color")
	var warning_color: Color = Color(1.0, 0.8, 0.4)
	
	if baseline_active:
		if is_dirty:
			current_schema_label.text = active_script_path.get_file() + " (Unsaved Changes)"
			current_schema_label.add_theme_color_override("font_color", warning_color)
		else:
			var locked_text = " [LOCKED]" if is_locked else ""
			current_schema_label.text = active_script_path.get_file() + locked_text
			current_schema_label.add_theme_color_override("font_color", hint_color)
	else:
		current_schema_label.text = "None Loaded (Create or Load a DataStructure Script)"
		# Set to transparent gray to indicate "Inactive"
		current_schema_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.5))


## Safely handles toggling the workspace lock state.
func _on_lock_unlock_pressed() -> void:
	if not is_locked:
		if is_dirty:
			lock_dirty_warning.popup_centered()
			return
		is_locked = true
	else:
		is_locked = false
		
	_update_ui_state()
	_update_button_states()
	_set_rows_locked(is_locked)
#endregion


#region Row Management & Manipulation
## Appends an interactive field mapping row encapsulated inside a stylish UI "Card".
func add_blank_property_row(prop_name: String = "", prop_type_string: String = "String", initial_default_val: Variant = null) -> PanelContainer:
	var is_core_identifier: bool = (prop_name == "row_id")
	
	# 1. The Card Enclosure (PanelContainer)
	var card := PanelContainer.new()
	if is_core_identifier:
		card.tooltip_text = "Default row key identifier. Cannot be modified or moved."
		
	var base_color: Color = EditorInterface.get_editor_settings().get("interface/theme/base_color") if Engine.is_editor_hint() else Color(0.2, 0.2, 0.2)
	var style := StyleBoxFlat.new()
	style.bg_color = base_color.lightened(0.035)
	style.set_corner_radius_all(8)
	style.border_color = Color.BLACK.lightened(0.1)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.shadow_color = Color.BLACK.lightened(0.1)
	style.shadow_offset = Vector2(0, 1)
	style.shadow_size = 1
	card.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	
	var row := HBoxContainer.new()
	margin.add_child(row)
		
	# 2. Property Name Input
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "property_name"
	name_edit.text = prop_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if is_core_identifier:
		name_edit.editable = false
	else:
		name_edit.text_changed.connect(func(_text: String): _mark_row_dirty(card))
		name_edit.focus_exited.connect(func(): _validate_real_time(name_edit))
		name_edit.text_submitted.connect(func(_text: String): _validate_real_time(name_edit))
	
	var v_sep0 := VSeparator.new()
	
	row.add_child(name_edit)
	row.add_child(v_sep0)
	
	# 3. Property Type Dropdown Selector
	var type_dropdown := OptionButton.new()
	type_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if is_core_identifier:
		type_dropdown.disabled = true
		
	for type_str: String in BASE_TYPES:
		type_dropdown.add_icon_item(_get_safe_theme_icon(type_str), type_str)
		
	type_dropdown.add_separator()
	
	var native_idx: int = type_dropdown.item_count
	type_dropdown.add_icon_item(_get_safe_theme_icon("Node"), "All Native Types...")
	
	var custom_idx: int = type_dropdown.item_count
	type_dropdown.add_icon_item(_get_safe_theme_icon("Object"), "Custom Resource...")
	
	var found_idx: int = BASE_TYPES.find(prop_type_string)
	if found_idx != -1:
		type_dropdown.selected = found_idx
	else:
		var fallback_icon = _get_safe_theme_icon(prop_type_string)
		if prop_type_string not in EXTRA_VARIANTS and not ClassDB.class_exists(prop_type_string):
			var global_classes := ProjectSettings.get_global_class_list()
			for cls in global_classes:
				if cls["class"] == prop_type_string and not cls.get("icon", "").is_empty():
					if ResourceLoader.exists(cls["icon"]):
						fallback_icon = load(cls["icon"]) as Texture2D
					break
		type_dropdown.add_icon_item(fallback_icon, prop_type_string)
		var new_idx := type_dropdown.item_count - 1
		type_dropdown.selected = new_idx
		
	var v_sep1 := VSeparator.new()
	
	# 4. Context-Aware Default Value Container
	var default_container := HBoxContainer.new()
	default_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_container.set_meta("is_core_identifier", is_core_identifier)
	
	_rebuild_default_value_ui(default_container, prop_type_string, initial_default_val, card)
	
	type_dropdown.item_selected.connect(func(idx: int):
		_mark_row_dirty(card)
		if idx == native_idx:
			active_dropdown_for_custom = type_dropdown
			current_search_mode = SearchMode.NATIVE
			class_picker.title = "Select Native Godot Type"
			class_search.text = ""
			_populate_class_list()
			class_picker.popup_centered()
		elif idx == custom_idx:
			active_dropdown_for_custom = type_dropdown
			current_search_mode = SearchMode.CUSTOM
			class_picker.title = "Select Custom Resource Type"
			class_search.text = ""
			_populate_class_list()
			class_picker.popup_centered()
		else:
			var new_type = type_dropdown.get_item_text(idx)
			_rebuild_default_value_ui(default_container, new_type, null, card)
	)
	
	row.add_child(type_dropdown)
	row.add_child(v_sep1)
	row.add_child(default_container)
	
	var v_sep2 := VSeparator.new()
	row.add_child(v_sep2)
	
	# 5. Move Up Action Button
	var up_btn := Button.new()
	up_btn.icon = _get_safe_theme_icon("MoveUp")
	up_btn.tooltip_text = "Move Property Up"
	up_btn.pressed.connect(func(): _move_row_up(card))
	row.add_child(up_btn)
	
	# 6. Move Down Action Button
	var down_btn := Button.new()
	down_btn.icon = _get_safe_theme_icon("MoveDown")
	down_btn.tooltip_text = "Move Property Down"
	down_btn.pressed.connect(func(): _move_row_down(card))
	row.add_child(down_btn)
	
	var v_sep3 := VSeparator.new()
	row.add_child(v_sep3)
	
	# 7. Duplicate Action Button
	var duplicate_btn := Button.new()
	duplicate_btn.icon = _get_safe_theme_icon("ActionCopy")
	if is_core_identifier:
		duplicate_btn.disabled = true
	else:
		duplicate_btn.tooltip_text = "Duplicate Property"
		duplicate_btn.pressed.connect(func():
			active_row_for_duplication = card
			duplicate_confirm.popup_centered()
		)
	row.add_child(duplicate_btn)
	
	# 8. Row Removal Action Button
	var delete_btn := Button.new()
	delete_btn.icon = _get_safe_theme_icon("Remove")
	if is_core_identifier:
		delete_btn.disabled = true
	else:
		delete_btn.tooltip_text = "Remove Property"
		delete_btn.pressed.connect(func():
			active_row_for_deletion = card
			delete_confirm.popup_centered()
		)
	row.add_child(delete_btn)
	
	# Append the Card wrapper, not just the row!
	fields_container.add_child(card)
	property_rows.append(card)
	
	_update_button_states()
	return card


## Iterates through all cards to strictly enforce the Lock/Unlock state dynamically.
func _set_rows_locked(locked: bool) -> void:
	for card in property_rows:
		var row := card.get_child(0).get_child(0) as HBoxContainer
		var name_edit := row.get_child(0) as LineEdit
		var type_drop := row.get_child(2) as OptionButton
		var default_container := row.get_child(4) as HBoxContainer
		var duplicate_btn := row.get_child(9) as Button
		var delete_btn := row.get_child(10) as Button
		
		var is_core = (name_edit.text == "row_id")
		
		if not is_core:
			name_edit.editable = not locked
			type_drop.disabled = locked
			duplicate_btn.disabled = locked
			delete_btn.disabled = locked
			
		_set_default_container_locked(default_container, locked)


## Safely strips interaction privileges from dynamically generated default value controls.
func _set_default_container_locked(container: HBoxContainer, locked: bool) -> void:
	for child in container.get_children():
		if child is CheckBox:
			child.disabled = locked
		elif child is SpinBox:
			child.editable = not locked
		elif child is LineEdit:
			child.editable = not locked
		elif child is HBoxContainer:
			for subchild in child.get_children():
				if subchild is ColorPickerButton:
					subchild.disabled = locked
				elif subchild is LineEdit:
					if subchild.placeholder_text == "#HEX Color":
						subchild.editable = not locked
					# Always keep the Resource string un-editable
				elif subchild is SpinBox:
					subchild.editable = not locked
				elif subchild is Button:
					subchild.disabled = locked


## Shifts a specific property card up in the visual hierarchy and internal array.
func _move_row_up(card: PanelContainer) -> void:
	var idx: int = property_rows.find(card)
	if idx <= 1: return 
	
	var swap_card: PanelContainer = property_rows[idx - 1]
	property_rows[idx] = swap_card
	property_rows[idx - 1] = card
	
	fields_container.move_child(card, idx - 1)
	_update_button_states()
	_mark_row_dirty(card)


## Shifts a specific property card down in the visual hierarchy and internal array.
func _move_row_down(card: PanelContainer) -> void:
	var idx: int = property_rows.find(card)
	if idx <= 0 or idx >= property_rows.size() - 1: return 
	
	var swap_card: PanelContainer = property_rows[idx + 1]
	property_rows[idx] = swap_card
	property_rows[idx + 1] = card
	
	fields_container.move_child(card, idx + 1)
	_update_button_states()
	_mark_row_dirty(card)


## Iterates through all rows and safely disables up/down movement on boundary items.
func _update_button_states() -> void:
	for i: int in property_rows.size():
		var card: PanelContainer = property_rows[i]
		var row := card.get_child(0).get_child(0) as HBoxContainer
		
		# Based on our injection order: Up is child 6, Down is child 7
		var up_btn := row.get_child(6) as Button
		var down_btn := row.get_child(7) as Button
		
		if is_locked:
			up_btn.disabled = true
			down_btn.disabled = true
		elif i == 0:
			up_btn.disabled = true
			down_btn.disabled = true
		else:
			up_btn.disabled = (i == 1) # First editable row cannot go up
			down_btn.disabled = (i == property_rows.size() - 1) # Last row cannot go down


## Handles the confirmed deletion of a property card.
func _execute_row_deletion() -> void:
	if is_instance_valid(active_row_for_deletion):
		property_rows.erase(active_row_for_deletion)
		active_row_for_deletion.queue_free()
		active_row_for_deletion = null
		_update_button_states()
		_mark_dirty()


## Handles the confirmed duplication of a property card, auto-incrementing its name.
func _execute_row_duplication() -> void:
	if is_instance_valid(active_row_for_duplication):
		var row := active_row_for_duplication.get_child(0).get_child(0) as HBoxContainer
		var name_edit := row.get_child(0) as LineEdit
		var type_drop := row.get_child(2) as OptionButton
		var default_container := row.get_child(4) as HBoxContainer
		
		var original_name: String = name_edit.text
		var new_name: String = _get_unique_property_name(original_name)
		var type_string: String = type_drop.get_item_text(type_drop.selected)
		
		var current_default: Variant = null
		if default_container.has_meta("default_val"):
			current_default = default_container.get_meta("default_val")
		
		var new_card = add_blank_property_row(new_name, type_string, current_default)
		_mark_row_dirty(new_card)
		active_row_for_duplication = null


## Generates a unique property name by appending or incrementing a trailing number.
func _get_unique_property_name(base_name: String) -> String:
	var existing_names: Array[String] = []
	for card: PanelContainer in property_rows:
		var row := card.get_child(0).get_child(0) as HBoxContainer
		var line_edit := row.get_child(0) as LineEdit
		existing_names.append(line_edit.text)
		
	var prefix: String = base_name.rstrip("0123456789")
	if prefix.is_empty():
		prefix = "property_"
		
	var counter: int = 2
	var regex := RegEx.new()
	regex.compile("\\d+$")
	var result := regex.search(base_name)
	
	if result:
		counter = result.get_string().to_int() + 1
		
	var new_name: String = prefix + str(counter)
	while new_name in existing_names:
		counter += 1
		new_name = prefix + str(counter)
		
	return new_name


## Clears all visual rows from the workspace when loading a new file.
func clear_workspace() -> void:
	for card: PanelContainer in property_rows:
		if is_instance_valid(card):
			card.queue_free()
	property_rows.clear()
#endregion


#region Type Selection & Validation
## Populates the searchable ItemList with all custom Resource scripts or Native Classes.
func _populate_class_list(filter: String = "") -> void:
	class_list.clear()
	var filter_lower := filter.to_lower()
	
	if current_search_mode == SearchMode.CUSTOM:
		var global_classes: Array[Dictionary] = ProjectSettings.get_global_class_list()
		for cls: Dictionary in global_classes:
			var cls_name: String = cls["class"]
			var cls_base: String = cls["base"]
			var cls_icon_path: String = cls.get("icon", "")
			
			if cls_base == "Resource" or cls_base == "DataStructure" or ClassDB.is_parent_class(cls_base, "Resource"):
				if filter_lower.is_empty() or filter_lower in cls_name.to_lower():
					var tex: Texture2D = null
					if not cls_icon_path.is_empty() and ResourceLoader.exists(cls_icon_path):
						tex = load(cls_icon_path) as Texture2D
					if not tex:
						tex = _get_safe_theme_icon(cls_base)
						
					var item_idx := class_list.add_item(cls_name, tex)
					class_list.set_item_metadata(item_idx, tex)
	else:
		var native_classes: Array[String] = EXTRA_VARIANTS.duplicate()
		native_classes.append_array(Array(ClassDB.get_class_list()))
		native_classes.sort()
		
		for cls_name: String in native_classes:
			if cls_name.begins_with("_"):
				continue
				
			if filter_lower.is_empty() or filter_lower in cls_name.to_lower():
				var tex: Texture2D = _get_safe_theme_icon(cls_name)
				var item_idx := class_list.add_item(cls_name, tex)
				class_list.set_item_metadata(item_idx, tex)


## Called when the user confirms their custom/native class selection from the popup.
func _on_custom_class_selected() -> void:
	if not is_instance_valid(active_dropdown_for_custom):
		return
		
	var selected_items: PackedInt32Array = class_list.get_selected_items()
	if selected_items.is_empty():
		_on_class_picker_canceled()
		return
		
	var chosen_class: String = class_list.get_item_text(selected_items[0])
	var chosen_tex: Texture2D = class_list.get_item_metadata(selected_items[0])
	
	active_dropdown_for_custom.add_icon_item(chosen_tex, chosen_class)
	var new_idx := active_dropdown_for_custom.item_count - 1
	active_dropdown_for_custom.selected = new_idx
	
	var row = active_dropdown_for_custom.get_parent() as HBoxContainer
	if row:
		var default_container = row.get_child(4) as HBoxContainer
		var card = row.get_parent().get_parent() as PanelContainer
		_rebuild_default_value_ui(default_container, chosen_class, null, card)
		_mark_row_dirty(card)
		
	active_dropdown_for_custom = null


## Called when the user cancels or closes the type selection popup to safely revert the UI.
func _on_class_picker_canceled() -> void:
	if is_instance_valid(active_dropdown_for_custom):
		active_dropdown_for_custom.selected = BASE_TYPES.find("String")
		
		var row = active_dropdown_for_custom.get_parent() as HBoxContainer
		if row:
			var default_container = row.get_child(4) as HBoxContainer
			var card = row.get_parent().get_parent() as PanelContainer
			_rebuild_default_value_ui(default_container, "String", null, card)
			_mark_row_dirty(card)
			
		active_dropdown_for_custom = null


## Helper trigger for pre-compilation error prompts.
func _show_validation_error(msg: String) -> void:
	validation_dialog.dialog_text = msg
	validation_dialog.popup_centered()


## Fired via signals to validate inputs instantly upon user completion (Enter/Click-away).
func _validate_real_time(edit: LineEdit) -> void:
	var raw_name := edit.text.strip_edges()
	
	if raw_name.is_empty() or raw_name == "row_id":
		return
		
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	if not regex.search(raw_name):
		_show_validation_error("Invalid property name: '" + raw_name + "'.\nGDScript variables must only contain letters, numbers, and underscores, and cannot start with a number.")
		edit.text = ""
		return
		
	var duplicate_count: int = 0
	for card: PanelContainer in property_rows:
		var row := card.get_child(0).get_child(0) as HBoxContainer
		var other_edit := row.get_child(0) as LineEdit
		if other_edit.text.strip_edges() == raw_name:
			duplicate_count += 1
			
	if duplicate_count > 1:
		_show_validation_error("Duplicate property name found: '" + raw_name + "'.\nProperty names must be completely unique.")
		edit.text = ""


## Dynamically injects context-specific Input UI for Default Values based on the property type.
func _rebuild_default_value_ui(container: HBoxContainer, type_str: String, initial_val: Variant, card: PanelContainer) -> void:
	for child in container.get_children():
		child.queue_free()
		
	# Store the parent card so the resource picker popup can flag it!
	container.set_meta("parent_card", card)
	
	if container.get_meta("is_core_identifier", false):
		var lbl := Label.new()
		lbl.text = " Managed Internally"
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		container.add_child(lbl)
		return
		
	# Safe metadata assignment lambda (prevents setting meta to null which deletes it)
	var set_safe_meta = func(val: Variant):
		if val != null:
			container.set_meta("default_val", val)
		elif container.has_meta("default_val"):
			container.remove_meta("default_val")
			
	if type_str == "bool":
		var actual_val: bool = initial_val if typeof(initial_val) == TYPE_BOOL else false
		set_safe_meta.call(actual_val)
		
		var cb := CheckBox.new()
		cb.text = "True"
		cb.button_pressed = actual_val
		cb.toggled.connect(func(t: bool): set_safe_meta.call(t); _mark_row_dirty(card))
		container.add_child(cb)
		
	elif type_str == "int" or type_str == "float":
		var is_int: bool = (type_str == "int")
		var actual_val: float = initial_val if (typeof(initial_val) == TYPE_INT or typeof(initial_val) == TYPE_FLOAT) else 0.0
		set_safe_meta.call(int(actual_val) if is_int else actual_val)
		
		var sb := SpinBox.new()
		sb.step = 1 if is_int else 0.01
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.value = actual_val
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.value_changed.connect(func(v: float): set_safe_meta.call(int(v) if is_int else v); _mark_row_dirty(card))
		container.add_child(sb)
		
	elif type_str == "Color":
		var actual_val: Color = initial_val if typeof(initial_val) == TYPE_COLOR else Color.WHITE
		set_safe_meta.call(actual_val)
		
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var cp := ColorPickerButton.new()
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.color = actual_val
		
		var hex_edit := LineEdit.new()
		hex_edit.text = "#" + actual_val.to_html(false)
		hex_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hex_edit.max_length = 9
		hex_edit.placeholder_text = "#HEX Color"
		
		cp.color_changed.connect(func(c: Color): 
			set_safe_meta.call(c)
			hex_edit.text = "#" + c.to_html(false)
			_mark_row_dirty(card)
		)
		
		hex_edit.text_submitted.connect(func(t: String):
			var safe_hex = t.strip_edges()
			if safe_hex.is_valid_html_color():
				var new_c = Color(safe_hex)
				cp.color = new_c
				set_safe_meta.call(new_c)
				hex_edit.text = "#" + new_c.to_html(false)
				_mark_row_dirty(card)
			else:
				hex_edit.text = "#" + cp.color.to_html(false)
		)
		
		hex_edit.focus_exited.connect(func():
			hex_edit.emit_signal("text_submitted", hex_edit.text)
		)
		
		hbox.add_child(cp)
		hbox.add_child(hex_edit)
		container.add_child(hbox)
		
	elif type_str == "String" or type_str == "StringName":
		var actual_val: String = str(initial_val) if initial_val != null else ""
		set_safe_meta.call(actual_val)
		
		var le := LineEdit.new()
		le.placeholder_text = "Default string..."
		le.text = actual_val
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t: String): set_safe_meta.call(t); _mark_row_dirty(card))
		container.add_child(le)
		
	elif type_str == "Vector2":
		var actual_val: Vector2 = initial_val if typeof(initial_val) == TYPE_VECTOR2 else Vector2.ZERO
		set_safe_meta.call(actual_val)
		
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var sb_x := SpinBox.new(); sb_x.prefix = "X:"; sb_x.step = 0.01; sb_x.allow_greater = true; sb_x.allow_lesser = true; sb_x.value = actual_val.x; sb_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb_y := SpinBox.new(); sb_y.prefix = "Y:"; sb_y.step = 0.01; sb_y.allow_greater = true; sb_y.allow_lesser = true; sb_y.value = actual_val.y; sb_y.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var update_vec = func(_v: float):
			var new_vec := Vector2(sb_x.value, sb_y.value)
			set_safe_meta.call(new_vec)
			_mark_row_dirty(card)
			
		sb_x.value_changed.connect(update_vec)
		sb_y.value_changed.connect(update_vec)
		
		hbox.add_child(sb_x)
		hbox.add_child(sb_y)
		container.add_child(hbox)
		
	elif type_str == "Vector3":
		var actual_val: Vector3 = initial_val if typeof(initial_val) == TYPE_VECTOR3 else Vector3.ZERO
		set_safe_meta.call(actual_val)
		
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var sb_x := SpinBox.new(); sb_x.prefix = "X:"; sb_x.step = 0.01; sb_x.allow_greater = true; sb_x.allow_lesser = true; sb_x.value = actual_val.x; sb_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb_y := SpinBox.new(); sb_y.prefix = "Y:"; sb_y.step = 0.01; sb_y.allow_greater = true; sb_y.allow_lesser = true; sb_y.value = actual_val.y; sb_y.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb_z := SpinBox.new(); sb_z.prefix = "Z:"; sb_z.step = 0.01; sb_z.allow_greater = true; sb_z.allow_lesser = true; sb_z.value = actual_val.z; sb_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var update_vec = func(_v: float):
			var new_vec := Vector3(sb_x.value, sb_y.value, sb_z.value)
			set_safe_meta.call(new_vec)
			_mark_row_dirty(card)
			
		sb_x.value_changed.connect(update_vec)
		sb_y.value_changed.connect(update_vec)
		sb_z.value_changed.connect(update_vec)
		
		hbox.add_child(sb_x)
		hbox.add_child(sb_y)
		hbox.add_child(sb_z)
		container.add_child(hbox)
		
	else: # Resources, PackedScenes, Objects
		set_safe_meta.call(initial_val)
		
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var path_lbl := LineEdit.new()
		path_lbl.editable = false
		path_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if typeof(initial_val) == TYPE_STRING and not initial_val.is_empty():
			path_lbl.text = initial_val.get_file()
		elif typeof(initial_val) == TYPE_OBJECT and initial_val is Resource and not initial_val.resource_path.is_empty():
			path_lbl.text = initial_val.resource_path.get_file()
			set_safe_meta.call(initial_val.resource_path)
		else:
			path_lbl.text = "<empty>"
			
		var load_btn := Button.new()
		load_btn.icon = _get_safe_theme_icon("LoadQuick")
		load_btn.tooltip_text = "Assign default resource"
		load_btn.pressed.connect(func():
			active_default_container = container
			_open_resource_picker_for_default(type_str)
		)
		
		var clear_btn := Button.new()
		clear_btn.icon = _get_safe_theme_icon("Reload")
		clear_btn.tooltip_text = "Clear default resource"
		clear_btn.pressed.connect(func():
			set_safe_meta.call(null)
			path_lbl.text = "<empty>"
			_mark_row_dirty(card)
		)
		
		hbox.add_child(path_lbl)
		hbox.add_child(load_btn)
		hbox.add_child(clear_btn)
		container.add_child(hbox)


## Spawns the Godot QuickOpen dialog to let users find a default asset.
func _open_resource_picker_for_default(class_type: String) -> void:
	var base_types := PackedStringArray()
	if class_type == "Texture2D" or class_type == "Texture":
		base_types.append("Texture2D")
	elif class_type == "PackedScene":
		base_types.append("PackedScene")
	elif not class_type.is_empty():
		base_types.append(class_type)
	else:
		base_types.append("Resource")
		
	EditorInterface.popup_quick_open(_on_default_resource_selected, base_types)


## Handles the return signal from the default resource quick-picker.
func _on_default_resource_selected(path: String) -> void:
	if path.is_empty() or not is_instance_valid(active_default_container): 
		return
		
	active_default_container.set_meta("default_val", path)
	var hbox := active_default_container.get_child(0) as HBoxContainer
	var path_lbl := hbox.get_child(0) as LineEdit
	path_lbl.text = path.get_file()
	
	if active_default_container.has_meta("parent_card"):
		var card = active_default_container.get_meta("parent_card")
		_mark_row_dirty(card)
	else:
		_mark_dirty()
	
	active_default_container = null
#endregion


#region File & Compilation
## Triggers the closing of the active schema, warning the user if unsaved changes exist.
func _on_close_schema_pressed() -> void:
	if is_dirty:
		close_schema_confirm.popup_centered()
	else:
		_execute_close_schema()


## Safely unloads the active schema from the workspace and resets the UI.
func _execute_close_schema() -> void:
	active_script_path = ""
	is_dirty = false
	is_locked = false
	clear_workspace()
	_update_ui_state()


## Discards all unsaved edits and completely reloads the schema structure from the disk script.
func _execute_revert_schema() -> void:
	if active_script_path.is_empty():
		return
	is_locked = false
	_on_load_picker_confirmed(active_script_path)


## Prompts the editor file browser to construct a pristine script destination.
func _on_new_schema_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.gd", "GDScript File")
	dialog.current_dir = "res://addons/GodotDataTables/data/data_structures/"
	
	dialog.file_selected.connect(func(path: String):
		active_script_path = path
		clear_workspace()
		is_locked = false
		add_blank_property_row("row_id", "StringName") 
		is_dirty = true
		_update_ui_state()
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


## Opens Godot's native File Dialog to securely find and load any .gd Schema Script.
func _on_load_schema_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.gd", "GDScript File")
	dialog.current_dir = "res://addons/GodotDataTables/data/data_structures/"
	dialog.file_selected.connect(func(path: String):
		_on_load_picker_confirmed(path)
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


## Extracts the selected script from the native loader and rebuilds the UI structure.
func _on_load_picker_confirmed(path: String) -> void:
	if path.is_empty(): return
	
	var loaded_script := load(path) as Script
	
	if not loaded_script or not loaded_script.can_instantiate():
		printerr("GodotDataTables: Selected file is not a valid instantiable script.")
		return
		
	active_script_path = path
	clear_workspace()
	is_locked = false
	
	add_blank_property_row("row_id", "StringName")
	
	# Instantiating a temporary object allows us to extract default values securely
	var temp_instance = loaded_script.new()
	
	# Read all valid properties from the schema script natively
	for prop: Dictionary in loaded_script.get_script_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if prop["name"] == "row_id":
				continue
				
			var type_str: String = prop.get("class_name", "")
			if type_str.is_empty():
				type_str = _fallback_type_to_string(prop["type"])
				
			var default_val = temp_instance.get(prop["name"])
			add_blank_property_row(prop["name"], type_str, default_val)
			
	is_dirty = false
	_update_ui_state()


## Compiles layout row matrices into a strongly typed system file via FileAccess.
func _on_compile_pressed() -> void:
	if active_script_path.is_empty():
		return
		
	var open_scripts: Array[Script] = EditorInterface.get_script_editor().get_open_scripts()
	for script: Script in open_scripts:
		if script.resource_path == active_script_path:
			script_open_warning.popup_centered()
			return
			
	# PRE-COMPILE FULL VALIDATION PASS
	var user_prop_count: int = 0
	var valid_names: Array[String] = []
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	
	for card: PanelContainer in property_rows:
		var row := card.get_child(0).get_child(0) as HBoxContainer
		var name_edit := row.get_child(0) as LineEdit
		var raw_name := name_edit.text.strip_edges()
		
		if raw_name == "row_id":
			continue
			
		user_prop_count += 1
		
		if raw_name.is_empty():
			_show_validation_error("A property name cannot be empty.")
			return
			
		if not regex.search(raw_name):
			_show_validation_error("Invalid property name: '" + raw_name + "'.\nGDScript variables must only contain letters, numbers, and underscores, and cannot start with a number.")
			return
			
		var snake_name := raw_name.to_snake_case()
		if snake_name in valid_names:
			_show_validation_error("Duplicate property name found: '" + raw_name + "'.\nProperty names must be completely unique.")
			return
			
		valid_names.append(snake_name)
			
	if user_prop_count == 0:
		_show_validation_error("You must define at least one property (other than row_id) to compile a schema.")
		return
		
	# WRITE PASS
	var file := FileAccess.open(active_script_path, FileAccess.WRITE)
	if not file:
		printerr("GodotDataTables: Failed to open path for script generation: ", active_script_path)
		return
		
	var class_name_suggestion := active_script_path.get_file().get_basename().to_pascal_case()
	
	file.store_line("## AUTO-GENERATED SCHEMA SCRIPT. DO NOT EDIT MANUALLY.")
	file.store_line("@tool")
	file.store_line("class_name " + class_name_suggestion + " extends DataStructure")
	file.store_line("")
	
	for card: PanelContainer in property_rows:
		var row := card.get_child(0).get_child(0) as HBoxContainer
		var name_edit := row.get_child(0) as LineEdit
		var type_drop := row.get_child(2) as OptionButton
		var default_container := row.get_child(4) as HBoxContainer
		
		var raw_name := name_edit.text.strip_edges()
		if raw_name == "row_id":
			continue
			
		raw_name = raw_name.to_snake_case()
		var type_string := type_drop.get_item_text(type_drop.selected)
		
		if type_string.is_empty() or type_string == "Custom Resource..." or type_string == "All Native Types...":
			type_string = "Variant"
			
		# Compile context-aware default values safely
		var def_val: Variant = null
		if default_container.has_meta("default_val"):
			def_val = default_container.get_meta("default_val")
			
		var default_string := ""
		if def_val != null:
			if type_string == "String":
				if str(def_val) != "":
					default_string = " = \"%s\"" % str(def_val).replace("\"", "\\\"")
			elif type_string == "StringName":
				if str(def_val) != "":
					default_string = " = &\"%s\"" % str(def_val).replace("\"", "\\\"")
			elif type_string == "int" or type_string == "float":
				default_string = " = %s" % str(def_val)
			elif type_string == "bool":
				default_string = " = %s" % str(def_val).to_lower()
			elif type_string == "Color":
				default_string = " = Color(%f, %f, %f, %f)" % [def_val.r, def_val.g, def_val.b, def_val.a]
			elif type_string == "Vector2" or type_string == "Vector3":
				# Native Godot serialization prevents parsing crashes
				if typeof(def_val) == TYPE_VECTOR2 or typeof(def_val) == TYPE_VECTOR3:
					default_string = " = %s" % var_to_str(def_val)
			else: # Resources/Objects
				var path := ""
				if typeof(def_val) == TYPE_STRING:
					path = def_val
				elif typeof(def_val) == TYPE_OBJECT and def_val is Resource:
					path = def_val.resource_path
					
				if not path.is_empty():
					default_string = " = preload(\"%s\")" % path
		
		file.store_line("@export var %s: %s%s" % [raw_name, type_string, default_string])
		
	file.close()
	
	EditorInterface.get_resource_filesystem().scan()
	
	is_dirty = false
	_update_ui_state()
	_clear_all_row_dirty_states()
	
	success_dialog.dialog_text = "Schema successfully generated and saved to:\n" + active_script_path.get_file()
	success_dialog.popup_centered()


## Converts engine type constants to user-friendly strings for UI mapping.
func _fallback_type_to_string(type_enum: int) -> String:
	match type_enum:
		TYPE_STRING: return "String"
		TYPE_STRING_NAME: return "StringName"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_BOOL: return "bool"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_COLOR: return "Color"
		TYPE_OBJECT: return "Resource"
		_: return "Variant"
#endregion
