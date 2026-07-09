## Inspector interceptor for the DataTableRowHandle resource.
##
## Tells the Godot Editor to swap the default Inspector UI fields for
## our custom DataTableRowEditorProperty dropdowns and fuzzy searchers.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
class_name DataTableRowInspectorPlugin extends EditorInspectorPlugin


## Godot asks: "Are you responsible for drawing this object?"
func _can_handle(object: Object) -> bool:
	return object is DataTableRowHandle


## Godot asks: "How should I draw this specific property?"
func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	if name == "table":
		var table_property := DataTablePickerEditorProperty.new()
		add_property_editor(name, table_property)
		return true
		
	if name == "row_id":
		var row_property := DataTableRowEditorProperty.new()
		add_property_editor(name, row_property)
		return true
		
	return false
