## Draws a custom, searchable Row ID picker in the Godot Inspector.
##
## Replaces the native text box with an uneditable LineEdit and a search button.
## Spawns a dedicated fuzzy-search dialog, safely handling tables with 1,000+ rows.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (https://yulrun.dev)
## @meta_license: MIT

@tool
class_name DataTableRowEditorProperty extends EditorProperty


#region Variables
var hbox: HBoxContainer
var path_label: LineEdit
var btn_search: Button

var picker_dialog: ConfirmationDialog
var search_bar: LineEdit
var item_list: ItemList

var current_handle: DataTableRowHandle
var current_table: DataTable
var is_updating: bool = false
#endregion


#region Initialization
func _init() -> void:
	# 1. Main Inspector UI
	hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)
	
	path_label = LineEdit.new()
	path_label.editable = false
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(path_label)
	
	btn_search = Button.new()
	btn_search.tooltip_text = "Select Row ID"
	hbox.add_child(btn_search)
	
	btn_search.pressed.connect(_on_open_picker)
	add_focusable(path_label)
	
	# 2. Custom Picker Dialog (Hidden until clicked)
	picker_dialog = ConfirmationDialog.new()
	picker_dialog.title = "Select Row ID"
	add_child(picker_dialog)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_dialog.add_child(vbox)
	
	search_bar = LineEdit.new()
	search_bar.placeholder_text = "Search rows..."
	search_bar.clear_button_enabled = true
	search_bar.text_changed.connect(_populate_list)
	vbox.add_child(search_bar)
	
	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_activated.connect(_on_item_double_clicked)
	vbox.add_child(item_list)
	
	picker_dialog.confirmed.connect(_on_picker_confirmed)


func _enter_tree() -> void:
	# Safely fetch native icons once the node enters the editor tree
	btn_search.icon = _get_safe_theme_icon("Search")
	search_bar.right_icon = _get_safe_theme_icon("Search")


func _exit_tree() -> void:
	if is_instance_valid(current_handle) and current_handle.changed.is_connected(_on_handle_changed):
		current_handle.changed.disconnect(_on_handle_changed)
	if is_instance_valid(current_table) and current_table.changed.is_connected(_on_table_changed):
		current_table.changed.disconnect(_on_table_changed)


func _get_safe_theme_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control.has_theme_icon(icon_name, "EditorIcons"):
		return base_control.get_theme_icon(icon_name, "EditorIcons")
	return base_control.get_theme_icon("Object", "EditorIcons")
#endregion


#region State Syncing (The Inspector Hook)
func _update_property() -> void:
	var handle := get_edited_object() as DataTableRowHandle
	if not is_instance_valid(handle):
		return
		
	# 1. Resource State Hooking (Table cleared/assigned)
	if handle != current_handle:
		if is_instance_valid(current_handle) and current_handle.changed.is_connected(_on_handle_changed):
			current_handle.changed.disconnect(_on_handle_changed)
			
		current_handle = handle
		
		if is_instance_valid(current_handle) and not current_handle.changed.is_connected(_on_handle_changed):
			current_handle.changed.connect(_on_handle_changed)
			
	var table: DataTable = handle.table
	var current_row_id: StringName = handle.row_id
	
	# 2. Table State Hooking (New row added via Dock)
	if table != current_table:
		if is_instance_valid(current_table) and current_table.changed.is_connected(_on_table_changed):
			current_table.changed.disconnect(_on_table_changed)
			
		current_table = table
		
		if is_instance_valid(current_table) and not current_table.changed.is_connected(_on_table_changed):
			current_table.changed.connect(_on_table_changed)
			
	# 3. Visual Syncing
	is_updating = true
	
	if is_instance_valid(current_table):
		btn_search.disabled = false
		if current_row_id.is_empty():
			path_label.text = "<none>"
		elif current_table.has_row(current_row_id):
			path_label.text = str(current_row_id)
		else:
			path_label.text = str(current_row_id) + " (Invalid)"
	else:
		btn_search.disabled = true
		path_label.text = "<no table selected>"
			
	is_updating = false
#endregion


#region Custom Search Window Engine
func _on_open_picker() -> void:
	if not is_instance_valid(current_table): 
		return
		
	search_bar.text = ""
	_populate_list("")
	picker_dialog.popup_centered(Vector2(400, 500))
	search_bar.grab_focus() # Automatically let the user start typing!


func _populate_list(filter: String = "") -> void:
	item_list.clear()
	
	# Guarantee <None> is always available at the top for safety
	item_list.add_item("<none>")
	item_list.set_item_metadata(0, &"")
	
	var query := filter.to_lower()
	var idx := 1
	
	for row_key: StringName in current_table.row_order:
		var str_key := str(row_key)
		# Fuzzy matching
		if query.is_empty() or query in str_key.to_lower():
			item_list.add_item(str_key)
			item_list.set_item_metadata(idx, row_key)
			idx += 1


func _on_handle_changed() -> void:
	_update_property()


func _on_table_changed() -> void:
	# If the designer adds a row while the popup is actively open, refresh it live!
	if picker_dialog.visible:
		_populate_list(search_bar.text)
	_update_property()


func _on_item_double_clicked(idx: int) -> void:
	picker_dialog.hide()
	_apply_selection(idx)


func _on_picker_confirmed() -> void:
	var selected := item_list.get_selected_items()
	if selected.is_empty(): 
		return
	_apply_selection(selected[0])


func _apply_selection(idx: int) -> void:
	if is_updating: return
	var selected_id: StringName = item_list.get_item_metadata(idx)
	emit_changed(get_edited_property(), selected_id)
#endregion
