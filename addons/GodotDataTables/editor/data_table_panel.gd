## Control panel for editing, importing, and exporting DataTable (.tres) instances.
##
## Reads the schema of an active DataTable and dynamically constructs a spreadsheet
## using a Godot Tree node. Handles safe type casting and data migration.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
class_name DataTablePanel extends MarginContainer


var active_table_path: String = ""
var active_table: DataTable = null
var current_schema_properties: Array[Dictionary] = []

# Tracker for chained creation
var pending_new_table_path: String = ""

@onready var current_table_label: Label = %CurrentTableLabel
@onready var tree: Tree = %TableGrid
@onready var btn_new_table: Button = %BtnNewTable
@onready var btn_load_table: Button = %BtnLoadTable
@onready var btn_import: Button = %BtnImport
@onready var btn_export: Button = %BtnExport
@onready var btn_add_row: Button = %BtnAddRow
@onready var btn_save_table: Button = %BtnSaveTable


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
		
	btn_new_table.pressed.connect(_on_new_table_pressed)
	btn_load_table.pressed.connect(_on_load_table_pressed)
	btn_import.pressed.connect(_on_import_pressed)
	btn_export.pressed.connect(_on_export_pressed)
	btn_add_row.pressed.connect(_on_add_row_pressed)
	btn_save_table.pressed.connect(_on_save_pressed)
	
	tree.item_edited.connect(_on_cell_edited)
	tree.button_clicked.connect(_on_tree_button_clicked)
	
	_update_ui_state()


func refresh_current_table_view() -> void:
	if not is_instance_valid(active_table):
		return
		
	active_table.sanitize_all_rows()
	_rebuild_tree_grid()


func _rebuild_tree_grid() -> void:
	tree.clear()
	current_schema_properties.clear()
	
	if not is_instance_valid(active_table) or not is_instance_valid(active_table.row_schema):
		return
		
	var schema_script: Script = active_table.row_schema.get_script()
	var raw_props: Array[Dictionary] = schema_script.get_script_property_list()
	
	for prop: Dictionary in raw_props:
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			current_schema_properties.append(prop)
			
	tree.columns = 1 + current_schema_properties.size() + 1
	tree.set_column_titles_visible(true)
	
	tree.set_column_title(0, "row_id")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 150)
	
	for i: int in current_schema_properties.size():
		tree.set_column_title(i + 1, current_schema_properties[i]["name"])
		tree.set_column_expand(i + 1, true)
		
	var action_col: int = tree.columns - 1
	tree.set_column_title(action_col, "Actions")
	tree.set_column_expand(action_col, false)
	tree.set_column_custom_minimum_width(action_col, 80)
	
	var root: TreeItem = tree.create_item()
	_populate_tree_rows(root)


func _populate_tree_rows(root: TreeItem) -> void:
	var validation_results: Dictionary = active_table.validate_all_rows()
	
	for id: StringName in active_table.rows:
		var row_data: DataStructure = active_table.rows[id]
		var item: TreeItem = tree.create_item(root)
		
		item.set_metadata(0, id)
		item.set_text(0, str(id))
		item.set_editable(0, true)
		
		if validation_results.has(id):
			item.set_icon(0, get_theme_icon("NodeWarning", "EditorIcons"))
			item.set_tooltip_text(0, "\n".join(validation_results[id]))
			
		for i: int in current_schema_properties.size():
			var col_idx: int = i + 1
			var prop_name: StringName = current_schema_properties[i]["name"]
			var value: Variant = row_data.get(prop_name)
			
			if typeof(value) == TYPE_BOOL:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_CHECK)
				item.set_checked(col_idx, value as bool)
			else:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				item.set_text(col_idx, var_to_str(value))
				
			item.set_editable(col_idx, true)
			
		var action_col: int = tree.columns - 1
		item.add_button(action_col, get_theme_icon("Remove", "EditorIcons"), 0, false, "Delete Row")


func _on_cell_edited() -> void:
	var item: TreeItem = tree.get_edited()
	var col: int = tree.get_edited_column()
	var original_id: StringName = item.get_metadata(0)
	
	if col == 0:
		var new_id: StringName = StringName(item.get_text(0).strip_edges())
		if new_id.is_empty() or active_table.has_row(new_id):
			item.set_text(0, str(original_id)) 
			return
			
		var row_instance: DataStructure = active_table.get_row(original_id)
		active_table.remove_row(original_id)
		active_table.add_row(new_id, row_instance)
		item.set_metadata(0, new_id)
		refresh_current_table_view()
	else:
		var prop_idx: int = col - 1
		var prop_name: StringName = current_schema_properties[prop_idx]["name"]
		var expected_type: int = current_schema_properties[prop_idx]["type"]
		var row_instance: DataStructure = active_table.get_row(original_id)
		
		if expected_type == TYPE_BOOL:
			row_instance.set(prop_name, item.is_checked(col))
		else:
			var raw_string: String = item.get_text(col)
			var parsed_value: Variant = str_to_var(raw_string)
			
			if parsed_value != null and typeof(parsed_value) == expected_type:
				row_instance.set(prop_name, parsed_value)
			elif expected_type == TYPE_STRING:
				row_instance.set(prop_name, raw_string) 
			else:
				item.set_text(col, var_to_str(row_instance.get(prop_name)))


func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if id == 0: 
		var row_id: StringName = item.get_metadata(0)
		active_table.remove_row(row_id)
		item.free()


func _on_add_row_pressed() -> void:
	if not is_instance_valid(active_table) or not is_instance_valid(active_table.row_schema):
		return
		
	var new_id: StringName = StringName("new_row_" + str(active_table.rows.size() + 1))
	var new_instance: DataStructure = active_table.row_schema.duplicate(true)
	active_table.add_row(new_id, new_instance)
	active_table.sanitize_all_rows()
	refresh_current_table_view()


func _on_save_pressed() -> void:
	if not active_table_path.is_empty() and is_instance_valid(active_table):
		ResourceSaver.save(active_table, active_table_path)
		print("GodotDataTables: Saved ", active_table_path)


func _on_load_table_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.tres", "DataTable Resource")
	dialog.current_dir = "res://addons/GodotDataTables/data/data_tables/"
	dialog.file_selected.connect(func(path: String):
		var loaded_res := load(path)
		if loaded_res is DataTable:
			active_table_path = path
			active_table = loaded_res
			_update_ui_state()
			refresh_current_table_view()
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


## Step 1 of Creation: Choose where to save the table.
func _on_new_table_pressed() -> void:
	var save_dialog := EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.add_filter("*.tres", "DataTable Resource")
	save_dialog.current_dir = "res://addons/GodotDataTables/data/data_tables/"
	save_dialog.file_selected.connect(_on_new_table_path_selected)
	add_child(save_dialog)
	save_dialog.popup_centered_ratio(0.5)


## Step 2 of Creation: Immediately choose the schema script to bind.
func _on_new_table_path_selected(path: String) -> void:
	pending_new_table_path = path
	
	var schema_dialog := EditorFileDialog.new()
	schema_dialog.title = "Select Schema (DataStructure) for this Table"
	schema_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	schema_dialog.add_filter("*.gd", "GDScript Schema")
	schema_dialog.current_dir = "res://addons/GodotDataTables/data/data_structures/"
	
	schema_dialog.file_selected.connect(func(schema_path: String):
		var schema_script: GDScript = load(schema_path) as GDScript
		if not schema_script or not schema_script.can_instantiate():
			printerr("GodotDataTables: Invalid schema selected.")
			return
			
		var new_table: DataTable = DataTable.new()
		new_table.row_schema = schema_script.new() as DataStructure
		
		var err: Error = ResourceSaver.save(new_table, pending_new_table_path)
		if err == OK:
			active_table_path = pending_new_table_path
			active_table = new_table
			_update_ui_state()
			refresh_current_table_view()
	)
	add_child(schema_dialog)
	schema_dialog.popup_centered_ratio(0.5)


func _on_import_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.csv", "CSV Spreadsheet")
	dialog.add_filter("*.json", "JSON Data")
	dialog.current_dir = "res://"
	dialog.file_selected.connect(_route_import_file)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


func _on_export_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.csv", "CSV Spreadsheet")
	dialog.add_filter("*.json", "JSON Data")
	dialog.current_dir = "res://"
	dialog.file_selected.connect(_route_export_file)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


func _route_import_file(path: String) -> void:
	print("Routing import: ", path.get_extension())
	# TODO: Call CSV/JSON parse utility
	refresh_current_table_view()


func _route_export_file(path: String) -> void:
	print("Routing export: ", path.get_extension())
	# TODO: Call CSV/JSON write utility


func _update_ui_state() -> void:
	var has_table: bool = is_instance_valid(active_table)
	btn_add_row.disabled = not has_table
	btn_save_table.disabled = not has_table
	btn_import.disabled = not has_table
	btn_export.disabled = not has_table
	
	if has_table:
		current_table_label.text = active_table_path.get_file()
		if not is_instance_valid(active_table.row_schema):
			current_table_label.text += " (WARNING: No Schema Assigned)"
	else:
		current_table_label.text = "None Loaded"
