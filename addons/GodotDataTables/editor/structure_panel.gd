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
var property_rows: Array[HBoxContainer] = []
var active_row_for_deletion: HBoxContainer = null
var active_row_for_duplication: HBoxContainer = null
var active_dropdown_for_custom: OptionButton = null
var current_search_mode: SearchMode = SearchMode.CUSTOM
var is_dirty: bool = false

# Dynamic UI Elements generated in code
var delete_confirm: ConfirmationDialog
var duplicate_confirm: ConfirmationDialog
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
@onready var btn_add_field: Button = %BtnAddField
@onready var btn_compile: Button = %BtnCompile


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
		
	_initialize_dynamic_dialogs()
	
	# Apply Native Editor Icons & Tooltips
	btn_new_schema.icon = _get_safe_theme_icon("New")
	btn_load_schema.icon = _get_safe_theme_icon("Load")
	btn_add_field.icon = _get_safe_theme_icon("Add")
	btn_compile.icon = _get_safe_theme_icon("Script")
	
	btn_new_schema.tooltip_text = "Create a new DataStructure schema."
	btn_load_schema.tooltip_text = "Load an existing DataStructure schema from disk."
	btn_add_field.tooltip_text = "Add a new property field to the active schema."
	btn_compile.tooltip_text = "Compile and save the schema to a strongly-typed .gd script."
	
	btn_new_schema.pressed.connect(_on_new_schema_pressed)
	btn_load_schema.pressed.connect(_on_load_schema_pressed)
	btn_add_field.pressed.connect(func(): add_blank_property_row())
	btn_compile.pressed.connect(_on_compile_pressed)
	
	_update_ui_state()


func _initialize_dynamic_dialogs() -> void:
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.dialog_text = "Are you sure you want to remove this property?"
	delete_confirm.confirmed.connect(_execute_row_deletion)
	add_child(delete_confirm)
	
	duplicate_confirm = ConfirmationDialog.new()
	duplicate_confirm.dialog_text = "Duplicate this property?"
	duplicate_confirm.confirmed.connect(_execute_row_duplication)
	add_child(duplicate_confirm)
	
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


func _get_safe_theme_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control.has_theme_icon(icon_name, "EditorIcons"):
		return base_control.get_theme_icon(icon_name, "EditorIcons")
	return base_control.get_theme_icon("Object", "EditorIcons")


func add_blank_property_row(prop_name: String = "", prop_type_string: String = "String") -> void:
	var row := HBoxContainer.new()
	var is_core_identifier: bool = (prop_name == "row_id")
	
	if is_core_identifier:
		row.tooltip_text = "Default row key identifier. Cannot be modified or moved."
		
	# 1. Property Name Input
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "property_name"
	name_edit.text = prop_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if is_core_identifier:
		name_edit.editable = false
	else:
		name_edit.text_changed.connect(func(_text: String): _mark_dirty())
		name_edit.focus_exited.connect(func(): _validate_real_time(name_edit))
		name_edit.text_submitted.connect(func(_text: String): _validate_real_time(name_edit))
		
	row.add_child(name_edit)
	
	# 2. Property Type Dropdown Selector
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
		type_dropdown.add_icon_item(_get_safe_theme_icon(prop_type_string), prop_type_string)
		var new_idx := type_dropdown.item_count - 1
		type_dropdown.selected = new_idx
		
	type_dropdown.item_selected.connect(func(idx: int):
		_mark_dirty()
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
	)
	row.add_child(type_dropdown)
	
	# 3. Move Up Action Button
	var up_btn := Button.new()
	up_btn.icon = _get_safe_theme_icon("MoveUp")
	up_btn.tooltip_text = "Move Property Up"
	up_btn.pressed.connect(func(): _move_row_up(row))
	row.add_child(up_btn)
	
	# 4. Move Down Action Button
	var down_btn := Button.new()
	down_btn.icon = _get_safe_theme_icon("MoveDown")
	down_btn.tooltip_text = "Move Property Down"
	down_btn.pressed.connect(func(): _move_row_down(row))
	row.add_child(down_btn)
	
	# 5. Duplicate Action Button
	var duplicate_btn := Button.new()
	duplicate_btn.icon = _get_safe_theme_icon("ActionCopy")
	if is_core_identifier:
		duplicate_btn.disabled = true
	else:
		duplicate_btn.tooltip_text = "Duplicate Property"
		duplicate_btn.pressed.connect(func():
			active_row_for_duplication = row
			duplicate_confirm.popup_centered()
		)
	row.add_child(duplicate_btn)
	
	# 6. Row Removal Action Button
	var delete_btn := Button.new()
	delete_btn.icon = _get_safe_theme_icon("Remove")
	if is_core_identifier:
		delete_btn.disabled = true
	else:
		delete_btn.tooltip_text = "Remove Property"
		delete_btn.pressed.connect(func():
			active_row_for_deletion = row
			delete_confirm.popup_centered()
		)
	row.add_child(delete_btn)
	
	fields_container.add_child(row)
	property_rows.append(row)
	
	_update_button_states()
	_mark_dirty()


func _move_row_up(row: HBoxContainer) -> void:
	var idx: int = property_rows.find(row)
	if idx <= 1: return # Cannot move row_id (0) or the row immediately below it (1) up
	
	var swap_row: HBoxContainer = property_rows[idx - 1]
	property_rows[idx] = swap_row
	property_rows[idx - 1] = row
	
	fields_container.move_child(row, idx - 1)
	_update_button_states()
	_mark_dirty()


func _move_row_down(row: HBoxContainer) -> void:
	var idx: int = property_rows.find(row)
	if idx <= 0 or idx >= property_rows.size() - 1: return # Cannot move row_id (0) or the last row down
	
	var swap_row: HBoxContainer = property_rows[idx + 1]
	property_rows[idx] = swap_row
	property_rows[idx + 1] = row
	
	fields_container.move_child(row, idx + 1)
	_update_button_states()
	_mark_dirty()


## Iterates through all rows and safely disables up/down movement on boundary items
func _update_button_states() -> void:
	for i: int in property_rows.size():
		var row: HBoxContainer = property_rows[i]
		
		# Based on our injection order: Up is child 2, Down is child 3
		var up_btn := row.get_child(2) as Button
		var down_btn := row.get_child(3) as Button
		
		if i == 0:
			up_btn.disabled = true
			down_btn.disabled = true
		else:
			up_btn.disabled = (i == 1) # First editable row cannot go up
			down_btn.disabled = (i == property_rows.size() - 1) # Last row cannot go down


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
	active_dropdown_for_custom = null
	_mark_dirty()


func _on_class_picker_canceled() -> void:
	if is_instance_valid(active_dropdown_for_custom):
		active_dropdown_for_custom.selected = BASE_TYPES.find("String")
		active_dropdown_for_custom = null
		_mark_dirty()


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
	for row: HBoxContainer in property_rows:
		var other_edit := row.get_child(0) as LineEdit
		if other_edit.text.strip_edges() == raw_name:
			duplicate_count += 1
			
	if duplicate_count > 1:
		_show_validation_error("Duplicate property name found: '" + raw_name + "'.\nProperty names must be completely unique.")
		edit.text = ""


func _execute_row_deletion() -> void:
	if is_instance_valid(active_row_for_deletion):
		property_rows.erase(active_row_for_deletion)
		active_row_for_deletion.queue_free()
		active_row_for_deletion = null
		_update_button_states()
		_mark_dirty()


func _execute_row_duplication() -> void:
	if is_instance_valid(active_row_for_duplication):
		var name_edit := active_row_for_duplication.get_child(0) as LineEdit
		var type_drop := active_row_for_duplication.get_child(1) as OptionButton
		
		var original_name: String = name_edit.text
		var new_name: String = _get_unique_property_name(original_name)
		var type_string: String = type_drop.get_item_text(type_drop.selected)
		
		add_blank_property_row(new_name, type_string)
		active_row_for_duplication = null


func _get_unique_property_name(base_name: String) -> String:
	var existing_names: Array[String] = []
	for row: HBoxContainer in property_rows:
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


func clear_workspace() -> void:
	for row: HBoxContainer in property_rows:
		if is_instance_valid(row):
			row.queue_free()
	property_rows.clear()


func _mark_dirty() -> void:
	if not is_dirty and not active_script_path.is_empty():
		is_dirty = true
		_update_ui_state()


func _update_ui_state() -> void:
	var baseline_active := not active_script_path.is_empty()
	btn_add_field.disabled = not baseline_active
	btn_compile.disabled = not baseline_active
	
	if baseline_active:
		if is_dirty:
			current_schema_label.text = active_script_path.get_file() + " (Unsaved Changes)"
			current_schema_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		else:
			current_schema_label.text = active_script_path.get_file()
			current_schema_label.remove_theme_color_override("font_color")
	else:
		current_schema_label.text = "None Loaded (Create or Load a Schema Script)"
		current_schema_label.remove_theme_color_override("font_color")


func _on_new_schema_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.gd", "GDScript File")
	dialog.current_dir = "res://addons/GodotDataTables/data/data_structures/"
	
	dialog.file_selected.connect(func(path: String):
		active_script_path = path
		clear_workspace()
		add_blank_property_row("row_id", "StringName") 
		is_dirty = true
		_update_ui_state()
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


func _on_load_schema_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.gd", "GDScript File")
	dialog.current_dir = "res://addons/GodotDataTables/data/data_structures/"
	
	dialog.file_selected.connect(func(path: String):
		var loaded_script := load(path) as Script
		if not loaded_script or not loaded_script.can_instantiate():
			printerr("GodotDataTables: Selected file is not a valid instantiable script.")
			return
			
		active_script_path = path
		clear_workspace()
		
		add_blank_property_row("row_id", "StringName")
		
		for prop: Dictionary in loaded_script.get_script_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				if prop["name"] == "row_id":
					continue
					
				var type_str: String = prop.get("class_name", "")
				if type_str.is_empty():
					type_str = _fallback_type_to_string(prop["type"])
				add_blank_property_row(prop["name"], type_str)
				
		is_dirty = false
		_update_ui_state()
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


func _show_validation_error(msg: String) -> void:
	validation_dialog.dialog_text = msg
	validation_dialog.popup_centered()


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
	
	for row: HBoxContainer in property_rows:
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
	
	for row: HBoxContainer in property_rows:
		var name_edit := row.get_child(0) as LineEdit
		var type_drop := row.get_child(1) as OptionButton
		
		var raw_name := name_edit.text.strip_edges()
		if raw_name == "row_id":
			continue
			
		raw_name = raw_name.to_snake_case()
		var type_string := type_drop.get_item_text(type_drop.selected)
		
		if type_string.is_empty() or type_string == "Custom Resource..." or type_string == "All Native Types...":
			type_string = "Variant"
			
		file.store_line("@export var %s: %s" % [raw_name, type_string])
		
	file.close()
	
	EditorInterface.get_resource_filesystem().scan()
	
	is_dirty = false
	_update_ui_state()
	
	success_dialog.dialog_text = "Schema successfully generated and saved to:\n" + active_script_path.get_file()
	success_dialog.popup_centered()


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
