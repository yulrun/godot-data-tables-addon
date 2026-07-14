## Control panel for editing, importing, and exporting DataTable (.tres) instances.
##
## Reads the schema of an active DataTable and dynamically constructs a spreadsheet
## using a Godot Tree node. Handles safe type casting, drag-and-drop, and data migrations.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (https://yulrun.dev)
## @meta_license: MIT

@tool
class_name DataTablePanel extends MarginContainer


#region Core Properties & State
## The absolute path to the currently active .tres data table file.
var active_table_path: String = ""

## The instantiated DataTable resource currently being edited in memory.
var active_table: DataTable = null

## An aggregated list of valid properties (columns) extracted from the active table's schema.
var current_schema_properties: Array[Dictionary] = []

## Temporarily holds the target path when a user creates a "New Table" but hasn't yet picked a schema.
var pending_new_table_path: String = ""

## Temporarily holds the target path when a user chooses a file to import.
var pending_import_path: String = ""

## Tracks the exact TreeItem currently undergoing a Resource selection operation.
var active_cell_item: TreeItem = null

## Tracks the specific column index undergoing a Resource selection operation.
var active_cell_column: int = -1

## Tracks which row ID is currently pending deletion to pass to the confirmation dialog.
var active_row_for_deletion: StringName = &""

## Tracks which row ID is currently pending duplication to pass to the confirmation dialog.
var active_row_for_duplication: StringName = &""

## Flags the workspace as unsaved, triggering visual warnings in the UI.
var is_dirty: bool = false

## Tracks if the table editor is currently locked to prevent accidental modifications.
var is_locked: bool = false

## A map tracking which specific rows have unsaved modifications to show the row-level warning icon.
var dirty_rows: Dictionary = {}

## Separates visual sorting from actual data order.
var visual_row_order: Array[StringName] = []

## Tracks the currently actively sorted column index. (-1 for none)
var active_sort_column: int = -1

## Tracks the direction of the visual sort (1 = Ascending, -1 = Descending, 0 = None)
var active_sort_direction: int = 0

## Dialog explicitly for editing dynamic Arrays
var array_edit_dialog: ConfirmationDialog

## Filter bar specifically for the Array Popup
var array_filter_bar: LineEdit

## Tree nested inside the Array Editor Dialog
var array_edit_tree: Tree

## Internal memory reference holding the Array data currently being edited
var active_array_ref: Array = []

## Tracks the property schema dictionary associated with the array currently being edited
var active_array_prop: Dictionary = {}

## Tracks if the user is currently editing a deep element inside the Array Popup
var is_editing_array_element: bool = false

## Tracks the specific item inside the Array Tree currently being modified via sub-dialogs
var active_array_cell_item: TreeItem = null
#endregion


#region Dynamic UI Elements
var delete_confirm: ConfirmationDialog
var duplicate_confirm: ConfirmationDialog
var clear_confirm: ConfirmationDialog
var close_confirm: ConfirmationDialog
var revert_confirm: ConfirmationDialog
var save_sort_confirm: ConfirmationDialog
var lock_dirty_warning: AcceptDialog
var import_conflict_dialog: ConfirmationDialog

var vector_edit_dialog: ConfirmationDialog
var vector_x_spin: SpinBox
var vector_y_spin: SpinBox
var vector_z_spin: SpinBox

var color_edit_dialog: ConfirmationDialog
var color_picker: ColorPicker

var cell_context_menu: PopupMenu

## A dynamically generated, transparent pillar icon used to enforce fixed column widths safely on high-DPI displays.
var empty_icon: ImageTexture

@onready var current_table_label: Label = %CurrentTableLabel
@onready var tree: Tree = %TableGrid
@onready var filter_bar: LineEdit = %FilterBar
@onready var btn_new_table: Button = %BtnNewTable
@onready var btn_load_table: Button = %BtnLoadTable
@onready var btn_import: Button = %BtnImport
@onready var btn_export: Button = %BtnExport
@onready var btn_add_row: Button = %BtnAddRow
@onready var btn_clear_table: Button = %BtnClearTable
@onready var btn_close_table: Button = %BtnCloseTable
@onready var btn_revert: Button = %BtnRevert
@onready var btn_lock_unlock: Button = %BtnLockUnlock
@onready var btn_save_table: Button = %BtnSaveTable
@onready var btn_save_sorting: Button = %BtnSaveSorting
#endregion


#region UI Initialization & Setup
func _ready() -> void:
	if not Engine.is_editor_hint():
		return
		
	_initialize_dynamic_dialogs()
	
	# Dynamically generate an invisible structural pillar for column 0 width locking
	var warning_tex: Texture2D = _get_safe_theme_icon("NodeWarning")
	var icon_size: Vector2 = warning_tex.get_size()
	var empty_img := Image.create_empty(int(icon_size.x), int(icon_size.y), false, Image.FORMAT_RGBA8)
	empty_icon = ImageTexture.create_from_image(empty_img)
	
	# Enable native Godot horizontal guides (grid lines) for clean row separation
	tree.add_theme_constant_override("draw_guides", 1)
	tree.add_theme_color_override("guide_color", Color(1.0, 1.0, 1.0, 0.10)) # 10% white lines
	
	# Force Godot to recognize right-clicks for context menus!
	tree.allow_rmb_select = true
	
	# Apply Native Editor Icons & Tooltips
	filter_bar.right_icon = _get_safe_theme_icon("Search")
	filter_bar.clear_button_enabled = true
	filter_bar.placeholder_text = "Filter Data..."
	filter_bar.text_changed.connect(_on_filter_text_changed)
	
	btn_new_table.icon = _get_safe_theme_icon("New")
	btn_load_table.icon = _get_safe_theme_icon("Load")
	btn_import.icon = _get_safe_theme_icon("MoveDown")
	btn_export.icon = _get_safe_theme_icon("MoveUp")
	btn_add_row.icon = _get_safe_theme_icon("Add")
	btn_clear_table.icon = _get_safe_theme_icon("Clear")
	btn_close_table.icon = _get_safe_theme_icon("Close")
	btn_revert.icon = _get_safe_theme_icon("UndoRedo")
	btn_lock_unlock.icon = _get_safe_theme_icon("Unlock")
	btn_save_table.icon = _get_safe_theme_icon("Save")
	btn_save_sorting.icon = _get_safe_theme_icon("Sort")
	
	btn_new_table.tooltip_text = "Create a new DataTable .tres database."
	btn_load_table.tooltip_text = "Load an existing DataTable from disk."
	btn_import.tooltip_text = "Import data from CSV/JSON into this table."
	btn_export.tooltip_text = "Export this table to CSV/JSON."
	btn_add_row.tooltip_text = "Add a new data row to the active table."
	btn_clear_table.tooltip_text = "Wipe all data rows from the active table."
	btn_close_table.tooltip_text = "Close the active table workspace."
	btn_revert.tooltip_text = "Revert all unsaved changes and reload the table from disk."
	btn_lock_unlock.tooltip_text = "Lock table to prevent accidental edits."
	btn_save_table.tooltip_text = "Force save the current table to disk."
	btn_save_sorting.tooltip_text = "Permanently overwrite the table's saved order with the current visual sort."
	
	btn_new_table.pressed.connect(_on_new_table_pressed)
	btn_load_table.pressed.connect(_on_load_table_pressed)
	btn_import.pressed.connect(_on_import_pressed)
	btn_export.pressed.connect(_on_export_pressed)
	btn_add_row.pressed.connect(_on_add_row_pressed)
	btn_clear_table.pressed.connect(func(): clear_confirm.popup_centered())
	btn_close_table.pressed.connect(_on_close_table_pressed)
	btn_revert.pressed.connect(func(): revert_confirm.popup_centered())
	btn_lock_unlock.pressed.connect(_on_lock_unlock_pressed)
	btn_save_table.pressed.connect(_on_save_pressed)
	btn_save_sorting.pressed.connect(_on_save_sorting_pressed)
	
	# Hook native editing signals
	tree.item_edited.connect(_on_cell_edited)
	tree.item_activated.connect(_on_item_activated) # Double click
	tree.item_mouse_selected.connect(_on_item_mouse_selected) # Context click
	tree.button_clicked.connect(_on_tree_button_clicked)
	tree.column_title_clicked.connect(_on_column_title_clicked)
	
	# Override Godot Tree drag-and-drop mechanics to allow dropping files into specific columns
	tree.set_drag_forwarding(_get_drag_data_fw, _can_drop_data_fw, _drop_data_fw)
	
	_update_ui_state()


## Builds native popups programmatically to keep the Scene tree clean.
func _initialize_dynamic_dialogs() -> void:
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.dialog_text = "Are you sure you want to delete this row?"
	delete_confirm.confirmed.connect(_execute_row_deletion)
	add_child(delete_confirm)
	
	duplicate_confirm = ConfirmationDialog.new()
	duplicate_confirm.dialog_text = "Duplicate this row?"
	duplicate_confirm.confirmed.connect(_execute_row_duplication)
	add_child(duplicate_confirm)
	
	clear_confirm = ConfirmationDialog.new()
	clear_confirm.dialog_text = "Are you sure you want to completely clear this table? This action will delete all rows."
	clear_confirm.confirmed.connect(_execute_clear_table)
	add_child(clear_confirm)
	
	close_confirm = ConfirmationDialog.new()
	close_confirm.dialog_text = "You have unsaved changes. Are you sure you want to close this table without saving?"
	close_confirm.confirmed.connect(_execute_close_table)
	add_child(close_confirm)
	
	revert_confirm = ConfirmationDialog.new()
	revert_confirm.title = "Revert Changes"
	revert_confirm.dialog_text = "Are you sure you want to revert all unsaved changes?\n\nThis will reload the table from disk and permanently discard your current modifications."
	revert_confirm.confirmed.connect(_execute_revert_table)
	add_child(revert_confirm)
	
	save_sort_confirm = ConfirmationDialog.new()
	save_sort_confirm.title = "Confirm Sort Save"
	save_sort_confirm.dialog_text = "Are you sure you want to permanently overwrite the data table's row order?\n\nThis will re-index all rows to match your current visual sort."
	save_sort_confirm.confirmed.connect(_execute_save_sorting)
	add_child(save_sort_confirm)
	
	lock_dirty_warning = AcceptDialog.new()
	lock_dirty_warning.title = "Cannot Lock Table"
	lock_dirty_warning.dialog_text = "You have unsaved changes.\n\nPlease save your table, or revert changes, before locking the workspace."
	add_child(lock_dirty_warning)
	
	import_conflict_dialog = ConfirmationDialog.new()
	import_conflict_dialog.title = "Import Data Conflicts"
	import_conflict_dialog.dialog_text = "How would you like to handle duplicate Row IDs during import?"
	import_conflict_dialog.ok_button_text = "Overwrite Duplicates"
	import_conflict_dialog.cancel_button_text = "Cancel Import"
	import_conflict_dialog.add_button("Skip Duplicates", false, "skip")
	import_conflict_dialog.confirmed.connect(func(): _execute_import(true))
	import_conflict_dialog.custom_action.connect(func(action: StringName):
		if action == &"skip":
			_execute_import(false)
			import_conflict_dialog.hide()
	)
	add_child(import_conflict_dialog)
	
	# Right-Click Cell Context Menu
	cell_context_menu = PopupMenu.new()
	cell_context_menu.add_icon_item(_get_safe_theme_icon("Clear"), "Clear Cell", 0)
	cell_context_menu.add_icon_item(_get_safe_theme_icon("Reload"), "Reset to Default", 1)
	cell_context_menu.id_pressed.connect(_on_cell_context_menu_id_pressed)
	add_child(cell_context_menu)
	
	# Setup Native Popups for Context Editors
	vector_edit_dialog = ConfirmationDialog.new()
	vector_edit_dialog.title = "Edit Vector"
	vector_edit_dialog.exclusive = false # Allows safe pop-ups over the Array Dialog
	var vec_vbox := VBoxContainer.new()
	vector_edit_dialog.add_child(vec_vbox)
	
	var x_hbox := HBoxContainer.new()
	var x_lbl := Label.new(); x_lbl.text = "X:"; x_lbl.custom_minimum_size = Vector2(20, 0)
	vector_x_spin = SpinBox.new(); vector_x_spin.step = 0.01; vector_x_spin.allow_greater = true; vector_x_spin.allow_lesser = true; vector_x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_hbox.add_child(x_lbl); x_hbox.add_child(vector_x_spin)
	vec_vbox.add_child(x_hbox)
	
	var y_hbox := HBoxContainer.new()
	var y_lbl := Label.new(); y_lbl.text = "Y:"; y_lbl.custom_minimum_size = Vector2(20, 0)
	vector_y_spin = SpinBox.new(); vector_y_spin.step = 0.01; vector_y_spin.allow_greater = true; vector_y_spin.allow_lesser = true; vector_y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y_hbox.add_child(y_lbl); y_hbox.add_child(vector_y_spin)
	vec_vbox.add_child(y_hbox)
	
	var z_hbox := HBoxContainer.new()
	var z_lbl := Label.new(); z_lbl.text = "Z:"; z_lbl.custom_minimum_size = Vector2(20, 0)
	vector_z_spin = SpinBox.new(); vector_z_spin.step = 0.01; vector_z_spin.allow_greater = true; vector_z_spin.allow_lesser = true; vector_z_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z_hbox.add_child(z_lbl); z_hbox.add_child(vector_z_spin)
	vec_vbox.add_child(z_hbox)
	
	vector_edit_dialog.confirmed.connect(_on_vector_edit_confirmed)
	add_child(vector_edit_dialog)
	
	color_edit_dialog = ConfirmationDialog.new()
	color_edit_dialog.title = "Edit Color"
	color_edit_dialog.exclusive = false # Allows safe pop-ups over the Array Dialog
	color_picker = ColorPicker.new()
	color_picker.edit_alpha = true
	color_edit_dialog.add_child(color_picker)
	color_edit_dialog.confirmed.connect(_on_color_edit_confirmed)
	add_child(color_edit_dialog)
	
	# Custom Array Editor Dialog
	array_edit_dialog = ConfirmationDialog.new()
	array_edit_dialog.title = "Edit Array Data"
	array_edit_dialog.exclusive = false # Prevents Window Lock clashes
	
	var array_vbox := VBoxContainer.new()
	array_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	array_edit_dialog.add_child(array_vbox)
	
	var array_toolbar := HBoxContainer.new()
	array_vbox.add_child(array_toolbar)
	
	array_filter_bar = LineEdit.new()
	array_filter_bar.placeholder_text = "Filter Elements..."
	array_filter_bar.clear_button_enabled = true
	array_filter_bar.right_icon = _get_safe_theme_icon("Search")
	array_filter_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	array_filter_bar.text_changed.connect(_on_array_filter_text_changed)
	array_toolbar.add_child(array_filter_bar)
	
	array_edit_tree = Tree.new()
	array_edit_tree.columns = 4 # We use 4 columns to bypass Godot's Tree node text-squishing bug
	array_edit_tree.set_column_title(0, "!")
	array_edit_tree.set_column_expand(0, false)
	array_edit_tree.set_column_custom_minimum_width(0, 24)
	array_edit_tree.set_column_title(1, "#")
	array_edit_tree.set_column_expand(1, false)
	array_edit_tree.set_column_custom_minimum_width(1, 40)
	array_edit_tree.set_column_title(2, "Value")
	array_edit_tree.set_column_expand(2, true)
	array_edit_tree.set_column_title(3, "Actions")
	array_edit_tree.set_column_expand(3, false)
	array_edit_tree.set_column_custom_minimum_width(3, 60)
	array_edit_tree.set_column_titles_visible(true)
	array_edit_tree.hide_root = true
	array_edit_tree.select_mode = Tree.SELECT_ROW # Whole-row selection hover matching main table
	array_edit_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Hook Array Tree Signals
	array_edit_tree.button_clicked.connect(_on_array_tree_button_clicked)
	array_edit_tree.item_edited.connect(_on_array_tree_item_edited)
	array_edit_tree.item_activated.connect(_on_array_item_activated)
	array_edit_tree.set_drag_forwarding(_get_array_drag_data_fw, _can_array_drop_data_fw, _array_drop_data_fw)
	
	array_vbox.add_child(array_edit_tree)
	
	# Add Element button locked perfectly out of the scroll zone at the bottom
	var btn_array_add := Button.new()
	btn_array_add.text = "Add Element"
	btn_array_add.icon = _get_safe_theme_icon("Add")
	btn_array_add.pressed.connect(_on_array_add_pressed)
	btn_array_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	array_vbox.add_child(btn_array_add)
	
	array_edit_dialog.confirmed.connect(_on_array_edit_confirmed)
	add_child(array_edit_dialog)


## Safely fetches an icon from the editor theme, falling back to "Object" if broken/missing.
func _get_safe_theme_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control.has_theme_icon(icon_name, "EditorIcons"):
		return base_control.get_theme_icon(icon_name, "EditorIcons")
	return base_control.get_theme_icon("Object", "EditorIcons")


## Refreshes the top label and toggles main action buttons based on whether a table is currently loaded.
func _update_ui_state() -> void:
	var has_table: bool = is_instance_valid(active_table)
	var has_unsaved_changes: bool = has_table and is_dirty
	
	btn_add_row.disabled = not has_table or is_locked
	btn_clear_table.disabled = not has_table or is_locked
	btn_import.disabled = not has_table or is_locked
	btn_close_table.disabled = not has_table
	btn_export.disabled = not has_table
	btn_lock_unlock.disabled = not has_table
	
	# Revert and Save are ONLY active if the table has unsaved changes
	btn_save_table.disabled = not has_unsaved_changes
	btn_revert.disabled = not has_unsaved_changes
	btn_save_sorting.disabled = not has_table or active_sort_direction == 0
	filter_bar.editable = has_table
	
	# Icon / Tooltip mapping for lock
	if is_locked:
		btn_lock_unlock.icon = _get_safe_theme_icon("Lock")
		btn_lock_unlock.tooltip_text = "Unlock table for editing."
	else:
		btn_lock_unlock.icon = _get_safe_theme_icon("Unlock")
		btn_lock_unlock.tooltip_text = "Lock table to prevent accidental edits."
	
	# Fetch editor colors dynamically
	var hint_color: Color = EditorInterface.get_editor_settings().get("interface/theme/accent_color")
	var warning_color: Color = Color(1.0, 0.8, 0.4)
	
	if has_table:
		if is_dirty:
			current_table_label.text = active_table_path.get_file() + " (Unsaved Changes)"
			current_table_label.add_theme_color_override("font_color", warning_color)
		else:
			var locked_text = " [LOCKED]" if is_locked else ""
			current_table_label.text = active_table_path.get_file() + locked_text
			current_table_label.add_theme_color_override("font_color", hint_color)
			
		if not is_instance_valid(active_table.row_schema):
			current_table_label.text += " (WARNING: No Schema Assigned)"
	else:
		current_table_label.text = "None Loaded"
		# Set to transparent gray to indicate "Inactive"
		current_table_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.5))
		filter_bar.text = ""


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
	refresh_current_table_view() # Rebuilding the tree safely re-applies all editable/disabled limits natively!
#endregion


#region Grid Generation & Rendering
## Wipes and completely reconstructs the Godot Tree spreadsheet to match the current data state.
func refresh_current_table_view() -> void:
	if not is_instance_valid(active_table):
		return
		
	# Ensures the data matches the blueprint before rendering to prevent crash errors
	active_table.sanitize_all_rows()
	
	# Ensures our visual array stays perfectly synced with new/deleted rows before sorting
	_apply_current_sort() 
	
	_rebuild_tree_grid()
	
	# Re-apply any active search filters after the rebuild
	if not filter_bar.text.is_empty():
		_on_filter_text_changed(filter_bar.text)


## Reads the assigned schema blueprint and builds the appropriate columns for the Tree widget.
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
	var id_arrow := ""
	if active_sort_column == 2:
		if active_sort_direction == 1:
			id_arrow = " ▲"
		elif active_sort_direction == -1:
			id_arrow = " ▼"
	tree.set_column_title(2, "row_id" + id_arrow)
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(2, 350)
	
	# Cols 3+: Schema Driven Data
	for i: int in current_schema_properties.size():
		var col_idx: int = 3 + i
		var col_arrow := ""
		if active_sort_column == col_idx:
			if active_sort_direction == 1:
				col_arrow = " ▲"
			elif active_sort_direction == -1:
				col_arrow = " ▼"
			
		tree.set_column_title(col_idx, current_schema_properties[i]["name"] + col_arrow)
		tree.set_column_expand(col_idx, true)
		
	# Final Col: Duplicate & Delete Actions
	var action_col: int = tree.columns - 1
	tree.set_column_title(action_col, "Actions")
	tree.set_column_expand(action_col, false)
	tree.set_column_custom_minimum_width(action_col, 60) # Reduced to tightly wrap the two icons
	
	var root: TreeItem = tree.create_item()
	_populate_tree_rows(root)
	_update_row_colors()


## Iterates through the table's data and visually generates the row elements.
func _populate_tree_rows(root: TreeItem) -> void:
	var validation_results: Dictionary = active_table.validate_all_rows()
	
	# Cache a fresh schema instance outside the loop to perfectly extract natively compiled typed arrays
	var temp_schema = null
	if is_instance_valid(active_table) and is_instance_valid(active_table.row_schema):
		temp_schema = active_table.row_schema.get_script().new()
	
	# Iterate over the VISUAL array to natively scramble columns without corrupting save data
	for id: StringName in visual_row_order:
		if not active_table.rows.has(id): continue
		
		var row_data: DataStructure = active_table.rows[id]
		var item: TreeItem = tree.create_item(root)
		
		# Root metadata maps to the dictionary key for all future lookups/interactions
		item.set_metadata(0, id)
		
		# Col 0: Status Icon Evaluation
		if validation_results.has(id):
			item.set_icon(0, _get_safe_theme_icon("NodeWarning"))
			item.set_tooltip_text(0, "\n".join(validation_results[id]))
		elif dirty_rows.has(id) and dirty_rows[id] == true:
			item.set_icon(0, _get_safe_theme_icon("StatusWarning"))
			item.set_tooltip_text(0, "Unsaved Changes on Row")
		else:
			item.set_icon(0, empty_icon) 
			
		# Col 1: Spreadsheet Row Number
		var true_index: int = active_table.row_order.find(id) + 1
		item.set_text(1, str(true_index))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_editable(1, false)
		
		# Col 2: Row ID Editor
		item.set_text(2, str(id))
		item.set_editable(2, not is_locked)
		item.set_tooltip_text(2, "Type: StringName (Unique Identifier)")
		
		# Cols 3+: Dynamic Type Casting
		for i: int in current_schema_properties.size():
			var col_idx: int = 3 + i
			var prop: Dictionary = current_schema_properties[i]
			var expected_type: int = prop["type"]
			var value: Variant = row_data.get(prop["name"])
			
			# Engine Type Cast: Instantly resolves schema mismatches for base vars
			if expected_type != TYPE_ARRAY and expected_type != TYPE_OBJECT:
				if value != null and typeof(value) != expected_type:
					value = type_convert(value, expected_type)
					row_data.set(prop["name"], value)
					_mark_row_dirty(id)
				
			var type_name: String = _get_type_to_string(expected_type)
			if expected_type == TYPE_OBJECT and not prop.get("class_name", "").is_empty():
				type_name = prop["class_name"]
			if prop.get("hint") == PROPERTY_HINT_ENUM:
				type_name = "Enum"
				
			if expected_type != TYPE_ARRAY:
				item.set_tooltip_text(col_idx, "Type: " + type_name)
			
			# SMART ALIGNMENT INJECTION
			match expected_type:
				TYPE_INT, TYPE_FLOAT:
					item.set_text_alignment(col_idx, HORIZONTAL_ALIGNMENT_RIGHT)
				TYPE_BOOL, TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3:
					item.set_text_alignment(col_idx, HORIZONTAL_ALIGNMENT_CENTER)
				_:
					item.set_text_alignment(col_idx, HORIZONTAL_ALIGNMENT_LEFT)
			
			if prop.get("hint") == PROPERTY_HINT_ENUM:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_RANGE)
				item.set_text(col_idx, prop.get("hint_string", ""))
				item.set_range(col_idx, float(value) if value != null else 0.0)
				item.set_editable(col_idx, not is_locked)
				item.set_text_alignment(col_idx, HORIZONTAL_ALIGNMENT_LEFT)
				
			elif expected_type == TYPE_BOOL:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_CHECK)
				item.set_checked(col_idx, value as bool)
				item.set_editable(col_idx, not is_locked)
				
			elif expected_type == TYPE_VECTOR2 or expected_type == TYPE_VECTOR3:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				if value == null:
					value = Vector2.ZERO if expected_type == TYPE_VECTOR2 else Vector3.ZERO
				if expected_type == TYPE_VECTOR2:
					item.set_text(col_idx, "X: %s, Y: %s" % [value.x, value.y])
				else:
					item.set_text(col_idx, "X: %s, Y: %s, Z: %s" % [value.x, value.y, value.z])
				item.set_editable(col_idx, false)
				
			elif expected_type == TYPE_COLOR:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				if value == null: value = Color.BLACK
				item.set_text(col_idx, " #" + value.to_html(false))
				var img := Image.create_empty(24, 16, false, Image.FORMAT_RGBA8)
				img.fill(value as Color)
				item.set_icon(col_idx, ImageTexture.create_from_image(img))
				item.set_editable(col_idx, false)
				
			elif expected_type == TYPE_OBJECT:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				if value and value.resource_path:
					item.set_text(col_idx, value.resource_path.get_file())
					item.set_tooltip_text(col_idx, "Type: " + type_name + "\nPath: " + value.resource_path)
				else:
					item.set_text(col_idx, "<empty>")
				item.set_editable(col_idx, false) 
				
			elif expected_type == TYPE_STRING or expected_type == TYPE_STRING_NAME:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				item.set_text(col_idx, str(value) if value != null else "")
				item.set_editable(col_idx, not is_locked)
				
			elif expected_type == TYPE_ARRAY:
				# 1. Parse the perfect blueprint safely from our cached script properties
				var arr_info = _get_array_info_from_prop(prop)
				var subtype_enum: int = arr_info["type"]
				var subtype_class: String = arr_info["class_name"]
				
				# 2. Extract perfect array type from a temporary schema instance
				var schema_arr: Array = temp_schema.get(prop["name"]) if temp_schema else []
				var val_arr: Array = value as Array if value != null else []
				
				if not val_arr.is_same_typed(schema_arr):
					var new_arr: Array = schema_arr.duplicate(true)
					new_arr.resize(val_arr.size())
					
					var target_type: int = new_arr.get_typed_builtin() if new_arr.is_typed() else TYPE_NIL
					for arr_i in range(val_arr.size()):
						var item_val = val_arr[arr_i]
						if target_type != TYPE_NIL and typeof(item_val) != target_type and item_val != null:
							if target_type != TYPE_OBJECT:
								new_arr[arr_i] = type_convert(item_val, target_type)
						else:
							new_arr[arr_i] = item_val
							
					value = new_arr
					row_data.set(prop["name"], value)
					_mark_row_dirty(id)
					val_arr = value
					
				# 3. Construct accurate UI Display text
				var final_type_name := "Variant"
				if subtype_enum != TYPE_NIL:
					if subtype_enum == TYPE_OBJECT and not subtype_class.is_empty():
						final_type_name = subtype_class
					else:
						final_type_name = _get_type_to_string(subtype_enum)
						
				var array_type_str = final_type_name + "[]"
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				item.set_text(col_idx, array_type_str + " (Size: " + str(val_arr.size()) + ")")
				item.set_editable(col_idx, false)
				item.set_tooltip_text(col_idx, "Type: " + array_type_str + "\nDouble-Click to Edit Elements")
				
			else:
				item.set_cell_mode(col_idx, TreeItem.CELL_MODE_STRING)
				item.set_text(col_idx, var_to_str(value) if value != null else "")
				item.set_editable(col_idx, not is_locked)
				
		var action_col: int = tree.columns - 1
		item.add_button(action_col, _get_safe_theme_icon("ActionCopy"), 0, is_locked, "Duplicate Row")
		item.add_button(action_col, _get_safe_theme_icon("Remove"), 1, is_locked, "Delete Row")


## Safely extracts exact Array typing directly from the schema property list to bypass Variant caching issues.
func _get_array_info_from_prop(prop: Dictionary) -> Dictionary:
	var info = {"type": TYPE_NIL, "class_name": ""}
	var hint_string: String = prop.get("hint_string", "")
	
	if prop.get("type") == TYPE_ARRAY and not hint_string.is_empty():
		var parts = hint_string.split(":")
		var type_parts = parts[0].split("/")
		info["type"] = type_parts[0].to_int()
		
		if info["type"] == TYPE_OBJECT:
			if parts.size() > 1:
				info["class_name"] = parts[1]
			else:
				info["class_name"] = "Resource"
				
	return info


## Sweeps through all visible rows and dynamically applies background color overrides.
func _update_row_colors() -> void:
	var root: TreeItem = tree.get_root()
	if not root: return
	
	var dirty_color: Color = Color(1.0, 0.8, 0.4, 0.15) # Clean warning orange glow
	var default_color: Color = Color(0, 0, 0, 0) # Transparent, relying natively on Godot Tree layout
	
	var child: TreeItem = root.get_first_child()
	
	while child:
		if child.visible:
			var row_id: StringName = child.get_metadata(0)
			var is_row_dirty: bool = dirty_rows.has(row_id) and dirty_rows[row_id]
			var target_bg: Color = dirty_color if is_row_dirty else default_color
			
			for col: int in tree.columns:
				child.set_custom_bg_color(col, target_bg)
				# Ensure 'empty' cells and index columns remain readable/dimmed text logic
				if col == 1 or child.get_text(col) == "<empty>":
					child.set_custom_color(col, Color(0.6, 0.6, 0.6))
				else:
					child.clear_custom_color(col)
					
		child = child.get_next()


## Instantly updates the targeted row's UI element with the warning icon and color refresh.
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
			break
		child = child.get_next()
		
	_update_row_colors()


## Flags the global workspace as dirty.
func _mark_dirty() -> void:
	if not is_dirty and not active_table_path.is_empty():
		is_dirty = true
		_update_ui_state()


## Helper enum converter for Tooltips
func _get_type_to_string(type_enum: int) -> String:
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


#region Cell Editing & Context Actions
## Handles Double-Click on protected cells to launch native Godot configuration popups.
func _on_item_activated() -> void:
	if is_locked: return # Workspace protection
	
	var item: TreeItem = tree.get_selected()
	var col: int = tree.get_selected_column()
	
	if not item or col < 3 or col >= tree.columns - 1:
		return
		
	var row_id: StringName = item.get_metadata(0)
	var prop_idx: int = col - 3
	var prop: Dictionary = current_schema_properties[prop_idx]
	var prop_name: StringName = prop["name"]
	var val: Variant = active_table.get_row(row_id).get(prop_name)
	
	if prop["type"] == TYPE_VECTOR2:
		is_editing_array_element = false
		active_cell_item = item
		active_cell_column = col
		if val == null: val = Vector2.ZERO
		vector_x_spin.value = val.x
		vector_y_spin.value = val.y
		vector_z_spin.get_parent().hide()
		vector_edit_dialog.title = "Edit Vector2"
		vector_edit_dialog.popup_centered()
		
	elif prop["type"] == TYPE_VECTOR3:
		is_editing_array_element = false
		active_cell_item = item
		active_cell_column = col
		if val == null: val = Vector3.ZERO
		vector_x_spin.value = val.x
		vector_y_spin.value = val.y
		vector_z_spin.value = val.z
		vector_z_spin.get_parent().show()
		vector_edit_dialog.title = "Edit Vector3"
		vector_edit_dialog.popup_centered()
		
	elif prop["type"] == TYPE_COLOR:
		is_editing_array_element = false
		active_cell_item = item
		active_cell_column = col
		if val == null: val = Color.BLACK
		color_picker.color = val
		color_edit_dialog.popup_centered()
		
	elif prop["type"] == TYPE_OBJECT:
		is_editing_array_element = false
		active_cell_item = item
		active_cell_column = col
		
		var class_type: String = prop.get("class_name", "")
		var base_types := PackedStringArray()
		if class_type == "Texture2D" or class_type == "Texture": base_types.append("Texture2D")
		elif class_type == "PackedScene": base_types.append("PackedScene")
		elif not class_type.is_empty() and class_type != "Resource": base_types.append(class_type)
		else: base_types.append("Resource")
		
		EditorInterface.popup_quick_open(_on_resource_file_selected, base_types)
		
	elif prop["type"] == TYPE_ARRAY:
		is_editing_array_element = false
		active_cell_item = item
		active_cell_column = col
		
		# CRITICAL: Save the actual property schema dict so the popup knows the absolute truth!
		active_array_prop = prop
		
		if val == null:
			var temp_schema = active_table.row_schema.get_script().new()
			active_array_ref = temp_schema.get(prop_name).duplicate(true)
		else:
			active_array_ref = val.duplicate(true)
			
		array_filter_bar.text = ""
		_populate_array_edit_tree()
		array_edit_dialog.popup_centered(Vector2(600, 500))


## Triggers context menu natively on Right-Click over data cells.
func _on_item_mouse_selected(position: Vector2, mouse_button_index: int) -> void:
	if is_locked: return # Workspace protection
	
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		var item := tree.get_item_at_position(position)
		var col := tree.get_column_at_position(position)
		
		if item and col >= 3 and col < tree.columns - 1:
			active_cell_item = item
			active_cell_column = col
			cell_context_menu.position = Vector2i(DisplayServer.mouse_get_position())
			cell_context_menu.popup()


## Evaluates Context Menu clicks to safely Clear or Reset cell data.
func _on_cell_context_menu_id_pressed(id: int) -> void:
	if not is_instance_valid(active_cell_item) or is_locked: return
	
	var row_id: StringName = active_cell_item.get_metadata(0)
	var prop_idx: int = active_cell_column - 3
	var prop: Dictionary = current_schema_properties[prop_idx]
	var prop_name: StringName = prop["name"]
	var row_instance: DataStructure = active_table.get_row(row_id)
	var current_val = row_instance.get(prop_name)
	
	if id == 0: # Clear Cell
		var empty_val = null
		if prop.get("hint") == PROPERTY_HINT_ENUM: empty_val = 0
		elif prop["type"] == TYPE_STRING or prop["type"] == TYPE_STRING_NAME: empty_val = ""
		elif prop["type"] == TYPE_INT or prop["type"] == TYPE_FLOAT: empty_val = 0
		elif prop["type"] == TYPE_BOOL: empty_val = false
		elif prop["type"] == TYPE_VECTOR2: empty_val = Vector2.ZERO
		elif prop["type"] == TYPE_VECTOR3: empty_val = Vector3.ZERO
		elif prop["type"] == TYPE_COLOR: empty_val = Color.BLACK
		elif prop["type"] == TYPE_ARRAY: 
			empty_val = active_table.row_schema.get_script().new().get(prop_name).duplicate(true)
		
		if typeof(current_val) != typeof(empty_val) or current_val != empty_val:
			row_instance.set(prop_name, empty_val)
			active_table.emit_changed()
			_mark_row_dirty(row_id)
			refresh_current_table_view()
			
	elif id == 1: # Reset to Default
		var schema_script: GDScript = active_table.row_schema.get_script()
		var temp_schema = schema_script.new()
		var default_val = temp_schema.get(prop_name)
		
		if typeof(current_val) != typeof(default_val) or current_val != default_val:
			row_instance.set(prop_name, default_val)
			active_table.emit_changed()
			_mark_row_dirty(row_id)
			refresh_current_table_view()


## Triggers the visual sorting engine natively via left-click.
func _on_column_title_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT: 
		return
		
	if column < 2 or column >= tree.columns - 1:
		return
		
	if active_sort_column == column:
		if active_sort_direction == 1: active_sort_direction = -1
		elif active_sort_direction == -1: active_sort_direction = 0
		elif active_sort_direction == 0: active_sort_direction = 1
	else:
		active_sort_column = column
		active_sort_direction = 1
		
	refresh_current_table_view()


## Executes the internal Godot sorting algorithm safely against arbitrary Godot variants.
func _apply_current_sort() -> void:
	visual_row_order = active_table.row_order.duplicate()
	_update_ui_state()
	
	if active_sort_direction == 0 or active_sort_column < 2 or active_sort_column >= tree.columns - 1:
		return
		
	var prop_name: StringName = &""
	if active_sort_column == 2:
		prop_name = &"row_id"
	else:
		var prop_idx: int = active_sort_column - 3
		if prop_idx < current_schema_properties.size():
			prop_name = current_schema_properties[prop_idx]["name"]
			
	if prop_name.is_empty(): return
	
	visual_row_order.sort_custom(func(a: StringName, b: StringName):
		var val_a: Variant
		var val_b: Variant
		
		if prop_name == &"row_id":
			val_a = str(a).to_lower()
			val_b = str(b).to_lower()
		else:
			val_a = active_table.rows[a].get(prop_name)
			val_b = active_table.rows[b].get(prop_name)
			
			if typeof(val_a) == TYPE_STRING or typeof(val_a) == TYPE_STRING_NAME:
				val_a = str(val_a).to_lower()
			if typeof(val_b) == TYPE_STRING or typeof(val_b) == TYPE_STRING_NAME:
				val_b = str(val_b).to_lower()
				
		return _safe_compare(val_a, val_b, active_sort_direction == 1)
	)


## Safety wrapper to prevent Godot engine crashes when sorting complex resources/objects.
func _safe_compare(a: Variant, b: Variant, asc: bool) -> bool:
	if a == null: a = ""
	if b == null: b = ""
	
	if typeof(a) != typeof(b) or typeof(a) == TYPE_OBJECT or typeof(a) == TYPE_DICTIONARY or typeof(a) == TYPE_ARRAY:
		return str(a) < str(b) if asc else str(a) > str(b)
		
	return a < b if asc else a > b


## Triggers the confirmation popup when the user wants to lock in a visual sort.
func _on_save_sorting_pressed() -> void:
	if not active_table or visual_row_order.is_empty(): return
	save_sort_confirm.popup_centered()


## Executes the permanent data re-ordering once confirmed by the user.
func _execute_save_sorting() -> void:
	active_table.row_order = visual_row_order.duplicate()
	active_sort_column = -1
	active_sort_direction = 0
	
	_mark_dirty()
	refresh_current_table_view()


## Hides or reveals rows natively in the Tree based on the search input across all columns.
func _on_filter_text_changed(new_text: String) -> void:
	var root: TreeItem = tree.get_root()
	if not root: return
	
	var query := new_text.to_lower()
	var child: TreeItem = root.get_first_child()
	
	while child:
		if query.is_empty():
			child.visible = true
		else:
			var match_found := false
			var row_id: String = str(child.get_metadata(0)).to_lower()
			if row_id.contains(query):
				match_found = true
			else:
				for col: int in tree.columns:
					var cell_text: String = child.get_text(col).to_lower()
					if child.get_cell_mode(col) == TreeItem.CELL_MODE_CHECK:
						cell_text = "true" if child.is_checked(col) else "false"
					elif child.get_cell_mode(col) == TreeItem.CELL_MODE_RANGE:
						# For enums, get the actual selected text from the string list based on the numeric value
						var options = child.get_text(col).split(",")
						var index = int(child.get_range(col))
						if index >= 0 and index < options.size():
							cell_text = options[index].to_lower()
					
					if cell_text.contains(query):
						match_found = true
						break
			child.visible = match_found
		child = child.get_next()
	_update_row_colors()


## Routes clicks on natively generated cell action buttons to their respective sub-dialogs.
func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if is_locked: return # Workspace protection
	
	var action_col: int = tree.columns - 1
	var row_id: StringName = item.get_metadata(0)
	
	if column == action_col:
		if id == 0: # Duplicate Action
			active_row_for_duplication = row_id
			duplicate_confirm.popup_centered()
		elif id == 1: # Delete Action
			active_row_for_deletion = row_id
			delete_confirm.popup_centered()


## Fires whenever a user hits enter or clicks away from an editable spreadsheet cell.
func _on_cell_edited() -> void:
	if is_locked: return # Workspace protection
	
	var item: TreeItem = tree.get_edited()
	var col: int = tree.get_edited_column()
	var original_id: StringName = item.get_metadata(0)
	
	if col == 2: # Primary Key edited
		var new_id: StringName = StringName(item.get_text(2).strip_edges())
		if new_id.is_empty() or active_table.has_row(new_id) or new_id == original_id:
			item.set_text(2, str(original_id)) 
			return
			
		var row_instance: DataStructure = active_table.get_row(original_id)
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
		
	elif col >= 3 and col < tree.columns - 1: # Standard Property edited
		var prop_idx: int = col - 3
		var prop: Dictionary = current_schema_properties[prop_idx]
		var prop_name: StringName = prop["name"]
		var expected_type: int = prop["type"]
		var is_enum: bool = prop.get("hint") == PROPERTY_HINT_ENUM
		
		var row_instance: DataStructure = active_table.get_row(original_id)
		var current_value: Variant = row_instance.get(prop_name)
		var new_value: Variant = current_value
		
		if is_enum:
			new_value = int(item.get_range(col))
		elif expected_type == TYPE_BOOL:
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
			if not is_enum and expected_type != TYPE_STRING and expected_type != TYPE_STRING_NAME and expected_type != TYPE_BOOL:
				item.set_text(col, var_to_str(current_value))
			return
			
		row_instance.set(prop_name, new_value)
		active_table.emit_changed()
		_mark_row_dirty(original_id)
		
		if not is_enum and expected_type != TYPE_STRING and expected_type != TYPE_STRING_NAME and expected_type != TYPE_BOOL:
			item.set_text(col, var_to_str(new_value))


## Applies the resource selected via the Quick Open dialog with strict schema validation.
func _on_resource_file_selected(path: String) -> void:
	if path.is_empty(): return
	var loaded_res: Resource = load(path)
	if not loaded_res: return
	
	if is_editing_array_element:
		if not is_instance_valid(active_array_cell_item): return
		var idx: int = active_array_cell_item.get_metadata(0)
		
		# Absolute Validation: Check the selected resource against the absolute truth of our stored property dictionary
		var arr_info = _get_array_info_from_prop(active_array_prop)
		var req_class = arr_info["class_name"]
		
		if not req_class.is_empty() and req_class != "Resource":
			var is_valid = false
			if loaded_res.is_class(req_class):
				is_valid = true
			else:
				var script = loaded_res.get_script()
				if script and script.get_global_name() == req_class:
					is_valid = true
			
			if not is_valid:
				printerr("GodotDataTables: Selected resource does not match schema required array type: ", req_class)
				return
				
		active_array_ref[idx] = loaded_res
		_populate_array_edit_tree()
		return
		
	# Standard Main-Table Object Routing
	if not is_instance_valid(active_cell_item): return
	var row_id: StringName = active_cell_item.get_metadata(0)
	var prop_idx: int = active_cell_column - 3
	var prop: Dictionary = current_schema_properties[prop_idx]
	var prop_name: StringName = prop["name"]
	var row_instance: DataStructure = active_table.get_row(row_id)
	
	var req_class: String = prop.get("class_name", "")
	if not req_class.is_empty() and req_class != "Resource":
		var is_valid = false
		if loaded_res.is_class(req_class):
			is_valid = true
		else:
			var script = loaded_res.get_script()
			if script and script.get_global_name() == req_class:
				is_valid = true
		
		if not is_valid:
			printerr("GodotDataTables: Selected resource does not match schema required type: ", req_class)
			return
			
	if row_instance.get(prop_name) == loaded_res: return
	row_instance.set(prop_name, loaded_res)
	active_table.emit_changed()
	_mark_row_dirty(row_id)
	refresh_current_table_view()


## Executes writing the Vector modifications back to the resource safely.
func _on_vector_edit_confirmed() -> void:
	if is_editing_array_element:
		if not is_instance_valid(active_array_cell_item): return
		var idx: int = active_array_cell_item.get_metadata(0)
		if typeof(active_array_ref[idx]) == TYPE_VECTOR2:
			active_array_ref[idx] = Vector2(vector_x_spin.value, vector_y_spin.value)
		else:
			active_array_ref[idx] = Vector3(vector_x_spin.value, vector_y_spin.value, vector_z_spin.value)
		_populate_array_edit_tree()
		return
		
	# Standard Main-Table Routing
	if not is_instance_valid(active_cell_item): return
	var row_id: StringName = active_cell_item.get_metadata(0)
	var prop_idx: int = active_cell_column - 3
	var prop: Dictionary = current_schema_properties[prop_idx]
	var prop_name: StringName = prop["name"]
	var row_instance: DataStructure = active_table.get_row(row_id)
	
	var new_val: Variant
	if prop["type"] == TYPE_VECTOR2:
		new_val = Vector2(vector_x_spin.value, vector_y_spin.value)
	else:
		new_val = Vector3(vector_x_spin.value, vector_y_spin.value, vector_z_spin.value)
		
	if row_instance.get(prop_name) != new_val:
		row_instance.set(prop_name, new_val)
		active_table.emit_changed()
		_mark_row_dirty(row_id)
		refresh_current_table_view()


## Executes writing the new Color back to the resource safely.
func _on_color_edit_confirmed() -> void:
	if is_editing_array_element:
		if not is_instance_valid(active_array_cell_item): return
		var idx: int = active_array_cell_item.get_metadata(0)
		active_array_ref[idx] = color_picker.color
		_populate_array_edit_tree()
		return
		
	# Standard Main-Table Routing
	if not is_instance_valid(active_cell_item): return
	var row_id: StringName = active_cell_item.get_metadata(0)
	var prop_idx: int = active_cell_column - 3
	var prop: Dictionary = current_schema_properties[prop_idx]
	var prop_name: StringName = prop["name"]
	var row_instance: DataStructure = active_table.get_row(row_id)
	
	var new_val: Color = color_picker.color
	
	if row_instance.get(prop_name) != new_val:
		row_instance.set(prop_name, new_val)
		active_table.emit_changed()
		_mark_row_dirty(row_id)
		refresh_current_table_view()
#endregion


#region Native Drag and Drop Engine
## Initiates a drag event when grabbing an internal row.
func _get_drag_data_fw(at_position: Vector2) -> Variant:
	if is_locked: return null # Workspace protection
	
	var item: TreeItem = tree.get_item_at_position(at_position)
	if not item or item == tree.get_root():
		return null
		
	var row_id: StringName = item.get_metadata(0)
	var preview := Label.new()
	preview.text = "  Moving Row: " + str(row_id) + "  "
	preview.add_theme_stylebox_override("normal", get_theme_stylebox("panel", "TooltipPanel"))
	tree.set_drag_preview(preview)
	
	return {"type": "row", "row_id": row_id}


## Validates whether a dragged item (external file or internal row) can be dropped at the current cursor position.
func _can_drop_data_fw(at_position: Vector2, data: Variant) -> bool:
	if is_locked: return false # Workspace protection
	
	if typeof(data) != TYPE_DICTIONARY or not data.has("type"):
		return false
		
	var item: TreeItem = tree.get_item_at_position(at_position)
	if not item: 
		tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return false
		
	# 1. External Resource File Handling
	if data["type"] == "files":
		tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
		var col: int = tree.get_column_at_position(at_position)
		if col < 3 or col >= tree.columns - 1:
			return false
		var prop_idx: int = col - 3
		if current_schema_properties[prop_idx]["type"] != TYPE_OBJECT:
			return false
		return true
		
	# 2. Internal Row Reordering Handling
	if data["type"] == "row":
		if item == tree.get_root():
			tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
			return false
			
		# Enforce UX: Disable manual reordering while a visual column sort is active
		if active_sort_direction != 0:
			tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
			return false
			
		tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
		return true
		
	return false


## Executes the data manipulation when a valid drop occurs.
func _drop_data_fw(at_position: Vector2, data: Variant) -> void:
	if is_locked: return # Workspace protection
	
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
		if source_id == target_id: return 
		_reorder_row(source_id, target_id, drop_section)


## Manipulates the specific serialization array natively to reorder the rows safely.
func _reorder_row(source_id: StringName, target_id: StringName, drop_section: int) -> void:
	var order: Array[StringName] = active_table.row_order
	var source_idx: int = order.find(source_id)
	var target_idx: int = order.find(target_id)
	
	if source_idx == -1 or target_idx == -1: return
		
	order.remove_at(source_idx)
	target_idx = order.find(target_id) 
	if drop_section == 0: drop_section = -1 
	if drop_section == -1:
		order.insert(target_idx, source_id)
	else:
		order.insert(target_idx + 1, source_id)
		
	active_table.emit_changed()
	_mark_dirty()
	refresh_current_table_view()
#endregion


#region Row CRUD Operations (Create, Read, Update, Delete)
## Injects a blank, schema-conformant row into the table.
func _on_add_row_pressed() -> void:
	if not is_instance_valid(active_table) or not is_instance_valid(active_table.row_schema):
		return
		
	var new_id: StringName = _get_unique_row_id("new_row")
	var new_instance: DataStructure = active_table.row_schema.duplicate(true)
	active_table.add_row(new_id, new_instance)
	active_table.sanitize_all_rows()
	_mark_row_dirty(new_id)
	refresh_current_table_view()


## Executes confirmed row deletion.
func _execute_row_deletion() -> void:
	if active_table.has_row(active_row_for_deletion):
		active_table.remove_row(active_row_for_deletion)
		dirty_rows.erase(active_row_for_deletion)
		active_row_for_deletion = &""
		_mark_dirty()
		refresh_current_table_view()


## Wipes all rows from the table after confirmation.
func _execute_clear_table() -> void:
	if is_instance_valid(active_table):
		active_table.clear_table()
		dirty_rows.clear()
		_mark_dirty()
		refresh_current_table_view()


## Executes confirmed row duplication and auto-naming.
func _execute_row_duplication() -> void:
	if active_table.has_row(active_row_for_duplication):
		var new_id: StringName = _get_unique_row_id(active_row_for_duplication)
		active_table.duplicate_row(active_row_for_duplication, new_id)
		active_row_for_duplication = &""
		_mark_row_dirty(new_id)
		refresh_current_table_view()


## Safely increments a row string if duplicates are found natively.
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
#endregion


#region File & Compilation (Import/Export/Save/Load)
## Triggers the closing of the active table, warning the user if unsaved changes exist.
func _on_close_table_pressed() -> void:
	if is_dirty:
		close_confirm.popup_centered()
	else:
		_execute_close_table()


## Safely unloads the active table from the workspace and resets the UI.
func _execute_close_table() -> void:
	active_table_path = ""
	active_table = null
	is_dirty = false
	is_locked = false
	dirty_rows.clear()
	filter_bar.text = ""
	active_sort_column = -1
	active_sort_direction = 0
	visual_row_order.clear()
	
	tree.clear()
	tree.columns = 1
	tree.set_column_titles_visible(false)
	current_schema_properties.clear()
	
	_update_ui_state()


## Discards all unsaved edits and completely reloads the table structure from the disk script.
func _execute_revert_table() -> void:
	if active_table_path.is_empty(): return
	is_locked = false
	
	if is_instance_valid(active_table):
		active_table.clear_table()
		
	_on_load_picker_confirmed(active_table_path)


## Force pushes the resource save to disk and explicitly triggers an Editor refresh.
func _on_save_pressed() -> void:
	if not active_table_path.is_empty() and is_instance_valid(active_table):
		var err := ResourceSaver.save(active_table, active_table_path)
		if err == OK:
			print("GodotDataTables: Saved ", active_table_path)
			EditorInterface.get_resource_filesystem().update_file(active_table_path)
			EditorInterface.get_resource_filesystem().scan()
			is_dirty = false
			dirty_rows.clear()
			_update_ui_state()
			refresh_current_table_view()
		else:
			printerr("GodotDataTables: Failed to save DataTable.")


## Opens Godot's native QuickOpen dialog to select an existing DataTable resource.
func _on_load_table_pressed() -> void:
	EditorInterface.popup_quick_open(_on_load_picker_confirmed, PackedStringArray(["DataTable"]))


## Loads the selected DataTable from the QuickOpen popup into the workspace.
func _on_load_picker_confirmed(path: String) -> void:
	if path.is_empty(): return
	
	var loaded_res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	
	if loaded_res is DataTable:
		active_table_path = path
		active_table = loaded_res
		is_dirty = false
		is_locked = false
		dirty_rows.clear()
		active_sort_column = -1
		active_sort_direction = 0
		_update_ui_state()
		refresh_current_table_view()


## Launches standard file dialog to determine the location to construct a new table.
func _on_new_table_pressed() -> void:
	var save_dialog := EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.add_filter("*.tres", "DataTable Resource")
	save_dialog.current_dir = "res://addons/GodotDataTables/data/data_tables/"
	save_dialog.file_selected.connect(_on_new_table_path_selected)
	add_child(save_dialog)
	save_dialog.popup_centered_ratio(0.5)


## Spawns a second file dialog explicitly to pick the .gd schema script since quick_open ignores them.
func _on_new_table_path_selected(path: String) -> void:
	pending_new_table_path = path
	
	var schema_dialog := EditorFileDialog.new()
	schema_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	schema_dialog.add_filter("*.gd", "GDScript Schema")
	schema_dialog.current_dir = "res://addons/GodotDataTables/data/data_structures/"
	schema_dialog.file_selected.connect(_on_schema_picker_confirmed)
	add_child(schema_dialog)
	schema_dialog.popup_centered_ratio(0.5)


## Completes table creation when the user picks a DataStructure schema from the second dialog.
func _on_schema_picker_confirmed(schema_path: String) -> void:
	if schema_path.is_empty(): return
	var schema_script: GDScript = load(schema_path) as GDScript
	
	if not schema_script or not schema_script.can_instantiate():
		printerr("GodotDataTables: Invalid schema selected.")
		return
		
	var new_table: DataTable = DataTable.new()
	new_table.row_schema = schema_script.new() as DataStructure
	
	var err: Error = ResourceSaver.save(new_table, pending_new_table_path)
	if err == OK:
		EditorInterface.get_resource_filesystem().update_file(pending_new_table_path)
		EditorInterface.get_resource_filesystem().scan()
		
		active_table_path = pending_new_table_path
		active_table = new_table
		is_dirty = false
		is_locked = false
		dirty_rows.clear()
		active_sort_column = -1
		active_sort_direction = 0
		_update_ui_state()
		refresh_current_table_view()


## Opens the unified import dialog allowing CSV or JSON selections.
func _on_import_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.csv, *.json", "DataTable Spreadsheets (CSV/JSON)")
	dialog.current_dir = "res://"
	dialog.file_selected.connect(_route_import_file)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


## Routes the selected import file to the conflict resolution dialog.
func _route_import_file(path: String) -> void:
	pending_import_path = path
	import_conflict_dialog.popup_centered()


## Intercepts the conflict dialog's choice and executes the specific I/O parsing routine.
func _execute_import(overwrite: bool) -> void:
	if pending_import_path.is_empty() or not is_instance_valid(active_table): 
		return
		
	var ext := pending_import_path.get_extension().to_lower()
	var err: Error = OK
	
	if ext == "json":
		err = DataTableIO.import_from_json(active_table, pending_import_path, overwrite)
	elif ext == "csv":
		err = DataTableIO.import_from_csv(active_table, pending_import_path, overwrite)
		
	if err == OK:
		print("GodotDataTables: Successfully imported ", pending_import_path)
		active_table.emit_changed()
		_mark_dirty()
		refresh_current_table_view()
	else:
		printerr("GodotDataTables: Import failed with error code ", err)
		
	pending_import_path = ""


## Opens the unified export dialog allowing CSV or JSON file creations.
func _on_export_pressed() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.csv, *.json", "DataTable Spreadsheets (CSV/JSON)")
	dialog.current_dir = "res://"
	dialog.file_selected.connect(_route_export_file)
	add_child(dialog)
	dialog.popup_centered_ratio(0.5)


## Evaluates the user's chosen extension and routes the active data to the correct serializing utility.
func _route_export_file(path: String) -> void:
	if not is_instance_valid(active_table): 
		return
		
	var ext := path.get_extension().to_lower()
	var err: Error = OK
	
	if ext == "json":
		err = DataTableIO.export_to_json(active_table, path)
	elif ext == "csv":
		err = DataTableIO.export_to_csv(active_table, path)
		
	if err == OK:
		print("GodotDataTables: Successfully exported to ", path)
		EditorInterface.get_resource_filesystem().scan()
	else:
		printerr("GodotDataTables: Export failed with error code ", err)
#endregion


#region Array Editor
## Generates the internal tree items for the array editor dialog, dynamically matching cell modes to element types.
func _populate_array_edit_tree() -> void:
	array_edit_tree.clear()
	var root: TreeItem = array_edit_tree.create_item()
	
	var arr_info = _get_array_info_from_prop(active_array_prop)
	var array_subtype = arr_info["type"]
	
	for i: int in active_array_ref.size():
		var val: Variant = active_array_ref[i]
		var expected_type: int = array_subtype if array_subtype != TYPE_NIL else typeof(val)
		
		var item: TreeItem = array_edit_tree.create_item(root)
		item.set_metadata(0, i)
		
		# Col 0: Padding Icon to prevent Godot from squishing Col 1 due to the Tree folding arrow
		item.set_icon(0, empty_icon)
		item.set_editable(0, false)
		
		# Col 1: Index Number
		item.set_text(1, str(i))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_editable(1, false)
		
		# Col 2: Smart Formatting exactly matching the main table logic
		match expected_type:
			TYPE_INT, TYPE_FLOAT:
				item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
			TYPE_BOOL, TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3:
				item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
			_:
				item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_LEFT)
				
		if expected_type == TYPE_BOOL:
			item.set_cell_mode(2, TreeItem.CELL_MODE_CHECK)
			item.set_checked(2, val as bool)
			item.set_editable(2, true)
			
		elif expected_type == TYPE_VECTOR2 or expected_type == TYPE_VECTOR3:
			item.set_cell_mode(2, TreeItem.CELL_MODE_STRING)
			if val == null:
				val = Vector2.ZERO if expected_type == TYPE_VECTOR2 else Vector3.ZERO
			if expected_type == TYPE_VECTOR2:
				item.set_text(2, "X: %s, Y: %s" % [val.x, val.y])
			else:
				item.set_text(2, "X: %s, Y: %s, Z: %s" % [val.x, val.y, val.z])
			item.set_editable(2, false)
			item.set_tooltip_text(2, "Double-Click to Edit Vector")
			
		elif expected_type == TYPE_COLOR:
			item.set_cell_mode(2, TreeItem.CELL_MODE_STRING)
			if val == null: val = Color.BLACK
			item.set_text(2, " #" + val.to_html(false))
			
			var img := Image.create_empty(24, 16, false, Image.FORMAT_RGBA8)
			img.fill(val as Color)
			item.set_icon(2, ImageTexture.create_from_image(img))
			item.set_editable(2, false)
			item.set_tooltip_text(2, "Double-Click to Edit Color")
			
		elif expected_type == TYPE_OBJECT:
			item.set_cell_mode(2, TreeItem.CELL_MODE_STRING)
			if val and val.resource_path:
				item.set_text(2, val.resource_path.get_file())
				item.set_tooltip_text(2, val.resource_path)
			else:
				item.set_text(2, "<empty>")
			item.set_editable(2, false)
			item.set_tooltip_text(2, "Double-Click to Load Resource")
			
		elif expected_type == TYPE_STRING or expected_type == TYPE_STRING_NAME:
			item.set_cell_mode(2, TreeItem.CELL_MODE_STRING)
			item.set_text(2, str(val) if val != null else "")
			item.set_editable(2, true)
			
		else:
			item.set_cell_mode(2, TreeItem.CELL_MODE_STRING)
			item.set_text(2, var_to_str(val) if val != null else "")
			item.set_editable(2, true)
			
		# Col 3: Row Actions
		item.add_button(3, _get_safe_theme_icon("ActionCopy"), 0, false, "Duplicate Element")
		item.add_button(3, _get_safe_theme_icon("Remove"), 1, false, "Delete Element")


## Hides or reveals rows natively in the Array Tree based on the search input.
func _on_array_filter_text_changed(new_text: String) -> void:
	var root: TreeItem = array_edit_tree.get_root()
	if not root: return
	
	var query := new_text.to_lower()
	var child: TreeItem = root.get_first_child()
	
	while child:
		if query.is_empty():
			child.visible = true
		else:
			var match_found := false
			
			if str(child.get_text(1)).contains(query):
				match_found = true
			else:
				var cell_text: String = child.get_text(2).to_lower()
				if child.get_cell_mode(2) == TreeItem.CELL_MODE_CHECK:
					cell_text = "true" if child.is_checked(2) else "false"
				if cell_text.contains(query):
					match_found = true
					
			child.visible = match_found
		child = child.get_next()


## Injects a new element into the array safely depending on Godot's internal strict typing logic.
func _on_array_add_pressed() -> void:
	var arr_info = _get_array_info_from_prop(active_array_prop)
	if arr_info["type"] != TYPE_NIL and arr_info["type"] != TYPE_OBJECT:
		active_array_ref.resize(active_array_ref.size() + 1)
	else:
		active_array_ref.append(null)
		
	_populate_array_edit_tree()


## Evaluates simple string changes directly in the popup grid for numbers/strings/untyped.
func _on_array_tree_item_edited() -> void:
	var item: TreeItem = array_edit_tree.get_edited()
	var col: int = array_edit_tree.get_edited_column()
	
	if col == 2:
		var idx: int = item.get_metadata(0)
		var arr_info = _get_array_info_from_prop(active_array_prop)
		var expected_type = arr_info["type"] if arr_info["type"] != TYPE_NIL else typeof(active_array_ref[idx])
		
		if expected_type == TYPE_BOOL:
			active_array_ref[idx] = item.is_checked(2)
		else:
			var raw_string: String = item.get_text(2)
			if expected_type == TYPE_STRING or expected_type == TYPE_STRING_NAME:
				active_array_ref[idx] = raw_string
			else:
				var parsed: Variant = str_to_var(raw_string)
				if parsed != null or raw_string == "null":
					active_array_ref[idx] = parsed
				else:
					if expected_type != TYPE_NIL:
						active_array_ref[idx] = type_convert(raw_string, expected_type)
					else:
						active_array_ref[idx] = raw_string
						
		_populate_array_edit_tree()


## Launches custom sub-dialogs for complex Types when a user double clicks an Array row.
func _on_array_item_activated() -> void:
	var item: TreeItem = array_edit_tree.get_selected()
	var col: int = array_edit_tree.get_selected_column()
	
	if not item or col != 2: return
	
	var idx: int = item.get_metadata(0)
	var val: Variant = active_array_ref[idx]
	var arr_info = _get_array_info_from_prop(active_array_prop)
	var expected_type = arr_info["type"] if arr_info["type"] != TYPE_NIL else typeof(val)
	
	is_editing_array_element = true
	active_array_cell_item = item
	
	if expected_type == TYPE_VECTOR2:
		if val == null: val = Vector2.ZERO
		vector_x_spin.value = val.x
		vector_y_spin.value = val.y
		vector_z_spin.get_parent().hide()
		vector_edit_dialog.title = "Edit Array Vector2"
		vector_edit_dialog.popup_centered()
		
	elif expected_type == TYPE_VECTOR3:
		if val == null: val = Vector3.ZERO
		vector_x_spin.value = val.x
		vector_y_spin.value = val.y
		vector_z_spin.value = val.z
		vector_z_spin.get_parent().show()
		vector_edit_dialog.title = "Edit Array Vector3"
		vector_edit_dialog.popup_centered()
		
	elif expected_type == TYPE_COLOR:
		if val == null: val = Color.BLACK
		color_picker.color = val
		color_edit_dialog.popup_centered()
		
	elif expected_type == TYPE_OBJECT:
		var base_types := PackedStringArray()
		if not arr_info["class_name"].is_empty() and arr_info["class_name"] != "Resource":
			base_types.append(arr_info["class_name"])
		else:
			base_types.append("Resource")
			
		EditorInterface.popup_quick_open(_on_resource_file_selected, base_types)


## Handles Duplication and Deletion from the inline Array Action column.
func _on_array_tree_button_clicked(item: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column == 3:
		var idx: int = item.get_metadata(0)
		if id == 0: # Duplicate Element
			var val = active_array_ref[idx]
			active_array_ref.insert(idx + 1, val)
		elif id == 1: # Delete Element
			active_array_ref.remove_at(idx)
			
		_populate_array_edit_tree()


## Closes the editor and commits the array data back to the core resource.
func _on_array_edit_confirmed() -> void:
	if not is_instance_valid(active_cell_item): return
	var row_id: StringName = active_cell_item.get_metadata(0)
	var row_instance: DataStructure = active_table.get_row(row_id)
	var prop_name: StringName = active_array_prop["name"]
	
	if row_instance.get(prop_name) != active_array_ref:
		row_instance.set(prop_name, active_array_ref)
		active_table.emit_changed()
		_mark_row_dirty(row_id)
		refresh_current_table_view()


#region Array Drag and Drop 
func _get_array_drag_data_fw(at_position: Vector2) -> Variant:
	var item: TreeItem = array_edit_tree.get_item_at_position(at_position)
	if not item or item == array_edit_tree.get_root(): return null
	
	var idx: int = item.get_metadata(0)
	var preview := Label.new()
	preview.text = " Moving Element " + str(idx) + " "
	preview.add_theme_stylebox_override("normal", get_theme_stylebox("panel", "TooltipPanel"))
	array_edit_tree.set_drag_preview(preview)
	
	return {"type": "array_element", "idx": idx}


func _can_array_drop_data_fw(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("type"): return false
	
	var item: TreeItem = array_edit_tree.get_item_at_position(at_position)
	if not item: 
		array_edit_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return false
	
	if data["type"] == "array_element":
		array_edit_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
		return true
		
	if data["type"] == "files":
		array_edit_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
		var arr_info = _get_array_info_from_prop(active_array_prop)
		if arr_info["type"] == TYPE_OBJECT or arr_info["type"] == TYPE_NIL:
			return true
			
	return false


func _array_drop_data_fw(at_position: Vector2, data: Variant) -> void:
	var item: TreeItem = array_edit_tree.get_item_at_position(at_position)
	if not item: return
	
	var target_idx: int = item.get_metadata(0)
	
	if data["type"] == "files":
		var file_path: String = data["files"][0]
		var loaded_res: Resource = load(file_path)
		if loaded_res:
			active_array_ref[target_idx] = loaded_res
			_populate_array_edit_tree()
		return
		
	if data["type"] == "array_element":
		var source_idx: int = data["idx"]
		if source_idx == target_idx: return
		
		var drop_section: int = array_edit_tree.get_drop_section_at_position(at_position)
		var element = active_array_ref[source_idx]
		active_array_ref.remove_at(source_idx)
		
		if source_idx < target_idx:
			target_idx -= 1
			
		if drop_section == 1:
			target_idx += 1
			
		active_array_ref.insert(target_idx, element)
		_populate_array_edit_tree()
#endregion
