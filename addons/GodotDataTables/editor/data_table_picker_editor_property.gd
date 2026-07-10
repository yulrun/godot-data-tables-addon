## Draws a custom Godot QuickOpen resource picker for DataTables.
##
## Replaces the clunky native Resource dropdown with a direct fuzzy-search
## interface specifically locked to DataTable databases.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (https://yulrun.dev)
## @meta_license: MIT

@tool
class_name DataTablePickerEditorProperty extends EditorProperty


#region Variables
var hbox: HBoxContainer

var path_label: LineEdit

var btn_quick_load: Button
#endregion


#region Initialization
func _init() -> void:
	hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)
	
	path_label = LineEdit.new()
	path_label.editable = false
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(path_label)
	
	btn_quick_load = Button.new()
	btn_quick_load.tooltip_text = "Quick Load DataTable"
	hbox.add_child(btn_quick_load)
	
	btn_quick_load.pressed.connect(_on_quick_load_pressed)
	
	add_focusable(path_label)


func _ready() -> void:
	# Safe icon fetching using native editor theme
	btn_quick_load.icon = _get_safe_theme_icon("LoadQuick")


## Safely fetches an icon from the editor theme, falling back to "Object" if broken/missing.
func _get_safe_theme_icon(icon_name: String) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control.has_theme_icon(icon_name, "EditorIcons"):
		return base_control.get_theme_icon(icon_name, "EditorIcons")
	return base_control.get_theme_icon("Object", "EditorIcons")
#endregion


#region State Syncing
## Called automatically by the Inspector whenever the object's state might have changed.
func _update_property() -> void:
	var handle := get_edited_object() as DataTableRowHandle
	if not is_instance_valid(handle):
		return
		
	var table: DataTable = handle.table
	
	if is_instance_valid(table) and not table.resource_path.is_empty():
		path_label.text = table.resource_path.get_file()
		path_label.tooltip_text = table.resource_path
	else:
		path_label.text = "<empty>"
		path_label.tooltip_text = ""


## Launches the native Godot fuzzy search explicitly filtered for DataTables.
func _on_quick_load_pressed() -> void:
	EditorInterface.popup_quick_open(_on_file_selected, PackedStringArray(["DataTable"]))


## Handles the callback from the fuzzy search.
func _on_file_selected(path: String) -> void:
	if path.is_empty():
		return
		
	var loaded_table := load(path) as DataTable
	if loaded_table:
		emit_changed(get_edited_property(), loaded_table)
#endregion
