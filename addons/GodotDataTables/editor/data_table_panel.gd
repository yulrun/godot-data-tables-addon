## Control panel for editing, importing, and exporting DataTable (.tres) instances.
##
## Reads the schema of an active DataTable and dynamically constructs a spreadsheet
## using a Godot Tree node. Handles safe type casting, drag-and-drop, and data migrations.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
class_name DataTablePanel extends MarginContainer


var active_table_path: String = ""
var active_table: DataTable = null
var current_schema_properties: Array[Dictionary] = []

var pending_new_table_path: String = ""
var active_cell_item: TreeItem = null
var active_cell_column: int = -1
var active_row_for_deletion: StringName = &""
var active_row_for_duplication: StringName = &""

# State Tracking
var is_dirty: bool = false
var dirty_rows: Dictionary = {}

# Dynamic UI Elements generated in code
var delete_confirm: ConfirmationDialog
var duplicate_confirm: ConfirmationDialog
var empty_icon: ImageTexture

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
		
	_initialize_dynamic_dialogs()
	
	# Dynamically match the exact size of the Editor's warning icon to prevent column popping on high-DPI displays
	var warning_tex: Texture2D = _get_safe_theme_icon("NodeWarning")
	var icon_size: Vector2 = warning_tex.get_size()
	var empty_img := Image.create_empty(int(icon_size.x), int(icon_size.y), false, Image.FORMAT_RGBA8)
	empty_icon = ImageTexture.create_from_image(empty_img)
	
	# Apply Native Editor Icons & Tooltips
	btn_new_table.icon = _get_safe_theme_icon("New")
	btn_new_table.tooltip_text = "Create a new DataTable .tres database."
	btn_load_table.icon = _get_safe_theme_icon("Load")
	btn_load_table.tooltip_text = "Load an existing DataTable from disk."
	btn_import.icon = _get_safe_theme_icon("Load")
	btn_import.tooltip_text = "Import data from CSV/JSON into this table."
	btn_export.icon = _get_safe_theme_icon("Save")
	btn_export.tooltip_text = "Export this table to CSV/JSON."
	btn_add_row.icon = _get_safe_theme_icon("Add")
	btn_add_row.tooltip_text = "Add a new data row to the active table."
	btn_save_table.icon = _get_safe_theme_icon("Save")
	btn_save_table.tooltip_text = "Force save the current table to disk."
	
	btn_new_table.pressed.connect(_on_new_table_pressed)
	btn_load_table.pressed.connect(_on_load_table_pressed)
	btn_import.pressed.connect(_on_import_pressed)
	btn_export.pressed.connect(_on_export_pressed)
	btn_add_row.pressed.connect(_on_add_row_pressed)
	btn_save_table.pressed.connect(_on_save_pressed)
	
	tree.item_edited.connect(_on_cell_edited)
	tree.button_clicked.connect(_on_tree_button_clicked)
	
	# Override Godot Tree drag-and-drop mechanics to allow dropping files into specific columns
	tree.set_drag_forwarding(_get_drag_data_fw, _can_drop_data_fw, _drop_data_fw)
	
	_update_ui_state()


func _initialize_dynamic_dialogs() -> void:
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.dialog_text = "Are you sure you want to delete this row?"
	delete_confirm.confirmed.connect(_execute_row_deletion)
	add_child(delete_confirm)
	
	duplicate_confirm = ConfirmationDialog.new()
	duplicate_confirm.dialog_text = "Duplicate this row?"
	duplicate_confirm.confirmed.connect(_execute_row_duplication)
	add_child(duplicate_confirm)


func _get_safe_theme_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control.has_theme_icon(icon_name, "EditorIcons"):
		return base_control.get_theme_icon(icon_name, "EditorIcons")
	return base_control.get_theme_icon("Object", "EditorIcons")


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
			if prop["name"] == "row_id": continue
			current_schema_properties.append(prop)
			
	# Total cols: Warning(1) + Index(1) + RowID(1) + Properties(N) + Actions(1)
	tree.columns = 3 + current_schema_properties.size() + 1
	tree.set_column_titles_visible(true)
	
	# Col 0: Status & Warning Icons
	tree.set_column_title(0, "!")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, int(empty_icon.get_size().x) + 16)
	
	# Col 1: Standard Spreadhseet Index Row Number
	tree.set_column_title(1, "#")
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 40)
	
	# Col 2: The Core Row ID Key
	tree.set_column_title(2, "row_id")
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(2, 150)
	
	# Cols 3+: Schema Driven Data
	for i: int in current_schema_properties.size():
		var col_idx: int = 3 + i
		tree.set_column_title(col_idx, current_schema_properties[i]["name"])
		tree.set_column_expand(col_idx, true)
		
	# Final Col: Duplicate & Delete Actions
	var action_col: int = tree.columns - 1
	tree.set_column_title(action_col, "Actions")
	tree.set_column_expand(action_col, false)
	tree.set_column_custom_minimum_width(action_col, 80)
	
	var root: TreeItem = tree.create_item()
	_populate_tree_rows(root)


func _populate_tree_rows(root: TreeItem) -> void:
	var validation_results: Dictionary = active_table.validate_all_rows()
	var row_index: int = 1
	
	# Iterate over the explicit array to guarantee layout order
	for id: StringName in active_table.row_order:
		if not active_table.rows.has(id): continue
		
		var row_data: DataStructure = active_table.rows[id]
		var item: TreeItem = tree.create_item(root)
		
		# Root metadata maps to the key for lookups
		item.set_metadata(0, id)
		
		# Col 0: Status Icon Evaluation
		if validation_results.has(id):
			item.set_icon(0, _get_safe_theme_icon("NodeWarning"))
			item.set_tooltip_text(0, "\n".join(validation_results[id]))
		elif dirty_rows.has(id) and dirty_rows[id] == true:
			item.set_icon(0, _get_safe_theme_icon("StatusWarning"))
			item.set_tooltip_text(0, "Unsaved Changes on Row")
			item.set_custom_color(0, Color(1.0, 0.8, 0.4))
		else:
			# Invisible pillar enforces column width perfectly on high DPI
			item.set_icon(0, empty_icon) 
			
		# Col 1: Spreadsheet Row Number
		item.set_text(1, str(row_index))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_editable(1, false)
		item.set_custom_color(1, Color(0.6, 0.6, 0.6))
		
		# Col 2: Row ID Editor
		item.set_text(2, str(id))
		item.set_editable(2, true)
		
		# Cols 3+: Dynamic Type Casting
		for i: int in current_schema_properties.size():
			var col_idx: int = 3 + i
			var prop: Dictionary = current_schema_properties[i]
			var expected_type: int = prop["type"]
			var value: Variant = row_data.get(prop["name"])
			
			if value != null and typeof(value) != expected_type and expected_type != TYPE_OBJECT:
				value = type_convert(value, expected_type)
				row_data.set(prop["name"], value)
				_mark_row_dirty(id)
				
			if expected_type == TYPE_BOOL:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_CHECK)
				item.set_checked(col_idx, value as bool)
				item.set_editable(col_idx, true)
				
			elif expected_type == TYPE_OBJECT:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				if value and value.resource_path:
					item.set_text(col_idx, value.resource_path.get_file())
					item.set_tooltip_text(col_idx, value.resource_path)
				else:
					item.set_text(col_idx, "<empty>")
					item.set_custom_color(col_idx, Color(0.5, 0.5, 0.5))
					
				item.set_editable(col_idx, false) 
				item.add_button(col_idx, _get_safe_theme_icon("LoadQuick"), 2, false, "Assign Resource")
				item.add_button(col_idx, _get_safe_theme_icon("Reload"), 3, false, "Clear Resource")
				
			elif expected_type == TYPE_STRING or expected_type == TYPE_STRING_NAME:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				item.set_text(col_idx, str(value) if value != null else "")
				item.set_editable(col_idx, true)
				
			else:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				item.set_text(col_idx, var_to_str(value) if value != null else "")
				item.set_editable(col_idx, true)
				
		# Final Col: Inject action buttons
		var action_col: int = tree.columns - 1
		item.add_button(action_col, _get_safe_theme_icon("ActionCopy"), 0, false, "Duplicate Row")
		item.add_button(action_col, _get_safe_theme_icon("Remove"), 1, false, "Delete Row")
		
		row_index += 1


func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	var action_col: int = tree.columns - 1
	
	if column == action_col:
		if id == 0: 
			active_row_for_duplication = item.get_metadata(0)
			duplicate_confirm.popup_centered()
		elif id == 1: 
			active_row_for_deletion = item.get_metadata(0)
			delete_confirm.popup_centered()
			
	elif column >= 3 and column < action_col:
		if id == 2:
			active_cell_item = item
			active_cell_column = column
			_open_resource_picker_for_column(column)
		elif id == 3:
			var row_id: StringName = item.get_metadata(0)
			var prop_idx: int = column - 3
			var prop_name: StringName = current_schema_properties[prop_idx]["name"]
			
			var row_instance: DataStructure = active_table.get_row(row_id)
			if row_instance.get(prop_name) != null:
				row_instance.set(prop_name, null)
				active_table.emit_changed()
				_mark_row_dirty(row_id)
				refresh_current_table_view()


func _open_resource_picker_for_column(col: int) -> void:
	var prop_idx: int = col - 3
	var prop: Dictionary = current_schema_properties[prop_idx]
	var class_type: String = prop.get("class_name", "")
	
	var base_types := PackedStringArray()
	
	if class_type == "Texture2D" or class_type == "Texture":
		base_types.append("Texture2D")
	elif class_type == "PackedScene":
		base_types.append("PackedScene")
	elif not class_type.is_empty():
		base_types.append(class_type)
	else:
		base_types.append("Resource")
		
	EditorInterface.popup_quick_open(_on_resource_file_selected, base_types)


func _on_resource_file_selected(path: String) -> void:
	if path.is_empty() or not is_instance_valid(active_cell_item): 
		return
	
	var loaded_res: Resource = load(path)
	if loaded_res:
		var row_id: StringName = active_cell_item.get_metadata(0)
		var prop_idx: int = active_cell_column - 3
		var prop_name: StringName = current_schema_properties[prop_idx]["name"]
		
		var row_instance: DataStructure = active_table.get_row(row_id)
		
		if row_instance.get(prop_name) == loaded_res:
			return
			
		row_instance.set(prop_name, loaded_res)
		active_table.emit_changed()
		_mark_row_dirty(row_id)
		refresh_current_table_view()


func _on_cell_edited() -> void:
	var item: TreeItem = tree.get_edited()
	var col: int = tree.get_edited_column()
	var original_id: StringName = item.get_metadata(0)
	
	if col == 2: # Primary Key edited
		var new_id: StringName = StringName(item.get_text(2).strip_edges())
		if new_id.is_empty() or active_table.has_row(new_id) or new_id == original_id:
			item.set_text(2, str(original_id)) 
			return
			
		var row_instance: DataStructure = active_table.get_row(original_id)
		
		# Ensure we swap it into the exact same visual position in our index array
		var order_idx: int = active_table.row_order.find(original_id)
		
		active_table.remove_row(original_id)
		active_table.add_row(new_id, row_instance)
		
		if order_idx != -1:
			active_table.row_order.erase(new_id)
			active_table.row_order.insert(order_idx, new_id)
			
		item.set_metadata(0, new_id)
		
		if dirty_rows.has(original_id):
			dirty_rows.erase(original_id)
		_mark_row_dirty(new_id)
		refresh_current_table_view()
		
	elif col >= 3 and col < tree.columns - 1:
		var prop_idx: int = col - 3
		var prop: Dictionary = current_schema_properties[prop_idx]
		var prop_name: StringName = prop["name"]
		var expected_type: int = prop["type"]
		var row_instance: DataStructure = active_table.get_row(original_id)
		
		var current_value: Variant = row_instance.get(prop_name)
		var new_value: Variant = current_value
		
		if expected_type == TYPE_BOOL:
			new_value = item.is_checked(col)
		elif expected_type == TYPE_STRING or expected_type == TYPE_STRING_NAME:
			new_value = item.get_text(col)
		else:
			var raw_string: String = item.get_text(col)
			var parsed_value: Variant = str_to_var(raw_string)
			
			if parsed_value != null and typeof(parsed_value) == expected_type:
				new_value = parsed_value
			else:
				var casted_value = type_convert(raw_string, expected_type)
				if casted_value != null and str(casted_value) != "":
					new_value = casted_value
					
		if current_value == new_value:
			if expected_type != TYPE_STRING and expected_type != TYPE_STRING_NAME and expected_type != TYPE_BOOL:
				item.set_text(col, var_to_str(current_value))
			return
			
		row_instance.set(prop_name, new_value)
		active_table.emit_changed()
		_mark_row_dirty(original_id)
		
		if expected_type != TYPE_STRING and expected_type != TYPE_STRING_NAME and expected_type != TYPE_BOOL:
			item.set_text(col, var_to_str(new_value))


# ---------------------------------------------------------
# NATIVE DRAG AND DROP ENGINE
# ---------------------------------------------------------

func _get_drag_data_fw(at_position: Vector2) -> Variant:
	var item: TreeItem = tree.get_item_at_position(at_position)
	if not item or item == tree.get_root():
		return null
		
	var row_id: StringName = item.get_metadata(0)
	
	var preview := Label.new()
	preview.text = "  Moving Row: " + str(row_id) + "  "
	preview.add_theme_stylebox_override("normal", get_theme_stylebox("panel", "TooltipPanel"))
	tree.set_drag_preview(preview)
	
	return {"type": "row", "row_id": row_id}


func _can_drop_data_fw(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("type"):
		return false
		
	var item: TreeItem = tree.get_item_at_position(at_position)
	if not item: 
		tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return false
		
	if data["type"] == "files":
		tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
		var col: int = tree.get_column_at_position(at_position)
		if col < 3 or col >= tree.columns - 1:
			return false
			
		var prop_idx: int = col - 3
		if current_schema_properties[prop_idx]["type"] != TYPE_OBJECT:
			return false
		return true
		
	if data["type"] == "row":
		if item == tree.get_root():
			tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
			return false
			
		tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
		return true
		
	return false


func _drop_data_fw(at_position: Vector2, data: Variant) -> void:
	var item: TreeItem = tree.get_item_at_position(at_position)
	if not item: return
	
	if data["type"] == "files":
		var col: int = tree.get_column_at_position(at_position)
		var row_id: StringName = item.get_metadata(0)
		var prop_idx: int = col - 3
		var prop_name: StringName = current_schema_properties[prop_idx]["name"]
		var file_path: String = data["files"][0]
		
		var loaded_res: Resource = load(file_path)
		if loaded_res:
			var row_instance: DataStructure = active_table.get_row(row_id)
			if row_instance.get(prop_name) == loaded_res: return
				
			row_instance.set(prop_name, loaded_res)
			active_table.emit_changed()
			_mark_row_dirty(row_id)
			refresh_current_table_view()
		return
		
	if data["type"] == "row":
		var source_id: StringName = data["row_id"]
		var target_id: StringName = item.get_metadata(0)
		var drop_section: int = tree.get_drop_section_at_position(at_position)
		
		if source_id == target_id:
			return 
			
		_reorder_row(source_id, target_id, drop_section)


func _reorder_row(source_id: StringName, target_id: StringName, drop_section: int) -> void:
	var order: Array[StringName] = active_table.row_order
	var source_idx: int = order.find(source_id)
	var target_idx: int = order.find(target_id)
	
	if source_idx == -1 or target_idx == -1: 
		return
		
	# Adjust the layout array instead of the raw dictionary keys!
	order.remove_at(source_idx)
	target_idx = order.find(target_id) # Recalculate target post-removal
	
	if drop_section == 0: drop_section = -1 
	
	if drop_section == -1:
		order.insert(target_idx, source_id)
	else:
		order.insert(target_idx + 1, source_id)
		
	active_table.emit_changed()
	_mark_dirty()
	refresh_current_table_view()

# ---------------------------------------------------------


func _on_add_row_pressed() -> void:
	if not is_instance_valid(active_table) or not is_instance_valid(active_table.row_schema):
		return
		
	var new_id: StringName = _get_unique_row_id("new_row")
	var new_instance: DataStructure = active_table.row_schema.duplicate(true)
	active_table.add_row(new_id, new_instance)
	active_table.sanitize_all_rows()
	_mark_row_dirty(new_id)
	refresh_current_table_view()


func _execute_row_deletion() -> void:
	if active_table.has_row(active_row_for_deletion):
		active_table.remove_row(active_row_for_deletion)
		dirty_rows.erase(active_row_for_deletion)
		active_row_for_deletion = &""
		_mark_dirty()
		refresh_current_table_view()


func _execute_row_duplication() -> void:
	if active_table.has_row(active_row_for_duplication):
		var new_id: StringName = _get_unique_row_id(active_row_for_duplication)
		active_table.duplicate_row(active_row_for_duplication, new_id)
		active_row_for_duplication = &""
		_mark_row_dirty(new_id)
		refresh_current_table_view()


func _get_unique_row_id(base_name: String) -> StringName:
	var prefix: String = base_name.rstrip("0123456789")
	if prefix.is_empty(): prefix = "row_"
	
	var counter: int = 2
	var regex := RegEx.new()
	regex.compile("\\d+$")
	var result := regex.search(base_name)
	
	if result:
		counter = result.get_string().to_int() + 1
		
	var new_name: StringName = StringName(prefix + str(counter))
	while active_table.has_row(new_name):
		counter += 1
		new_name = StringName(prefix + str(counter))
		
	return new_name


func _on_save_pressed() -> void:
	if not active_table_path.is_empty() and is_instance_valid(active_table):
		var err := ResourceSaver.save(active_table, active_table_path)
		if err == OK:
			print("GodotDataTables: Saved ", active_table_path)
			EditorInterface.get_resource_filesystem().update_file(active_table_path)
			
			is_dirty = false
			dirty_rows.clear()
			_update_ui_state()
			refresh_current_table_view()
		else:
			printerr("GodotDataTables: Failed to save DataTable.")


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
			is_dirty = false
			dirty_rows.clear()
			_update_ui_state()
			refresh_current_table_view()
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


func _on_new_table_pressed() -> void:
	var save_dialog := EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.add_filter("*.tres", "DataTable Resource")
	save_dialog.current_dir = "res://addons/GodotDataTables/data/data_tables/"
	save_dialog.file_selected.connect(_on_new_table_path_selected)
	add_child(save_dialog)
	save_dialog.popup_centered_ratio(0.5)


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
			EditorInterface.get_resource_filesystem().update_file(pending_new_table_path)
			active_table_path = pending_new_table_path
			active_table = new_table
			is_dirty = false
			dirty_rows.clear()
			_update_ui_state()
			refresh_current_table_view()
	)
	add_child(schema_dialog)
	schema_dialog.popup_centered_ratio(0.5)


func _mark_row_dirty(row_id: StringName) -> void:
	dirty_rows[row_id] = true
	_mark_dirty()
	
	var root: TreeItem = tree.get_root()
	if not root: return
	
	var child: TreeItem = root.get_first_child()
	while child:
		if child.get_metadata(0) == row_id:
			if child.get_icon(0) != _get_safe_theme_icon("NodeWarning"):
				child.set_icon(0, _get_safe_theme_icon("StatusWarning"))
				child.set_tooltip_text(0, "Unsaved Changes on Row")
				child.set_custom_color(0, Color(1.0, 0.8, 0.4))
			break
		child = child.get_next()


func _mark_dirty() -> void:
	if not is_dirty and not active_table_path.is_empty():
		is_dirty = true
		_update_ui_state()


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
	refresh_current_table_view()


func _route_export_file(path: String) -> void:
	print("Routing export: ", path.get_extension())


func _update_ui_state() -> void:
	var has_table: bool = is_instance_valid(active_table)
	btn_add_row.disabled = not has_table
	btn_save_table.disabled = not has_table
	btn_import.disabled = not has_table
	btn_export.disabled = not has_table
	
	if has_table:
		if is_dirty:
			current_table_label.text = active_table_path.get_file() + " (Unsaved Changes)"
			current_table_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		else:
			current_table_label.text = active_table_path.get_file()
			current_table_label.remove_theme_color_override("font_color")
			
		if not is_instance_valid(active_table.row_schema):
			current_table_label.text += " (WARNING: No Schema Assigned)"
	else:
		current_table_label.text = "None Loaded"
		current_table_label.remove_theme_color_override("font_color")
