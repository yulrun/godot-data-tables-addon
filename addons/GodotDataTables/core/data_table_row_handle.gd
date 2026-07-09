## A specialized Resource used to reference a specific DataTable row safely.
##
## Exposes a clean, two-step dropdown in the Godot Inspector when paired
## with its EditorInspectorPlugin, eliminating string typos in gameplay code.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@icon("res://addons/GodotDataTables/icons/data_table_row_handle.svg")
@tool
class_name DataTableRowHandle extends Resource


#region Properties
## The target DataTable database resource.
@export var table: DataTable:
	set(value):
		if table != value:
			table = value
			emit_changed()
			# Forces the Godot Inspector to completely redraw all properties for this resource!
			notify_property_list_changed()

## The exact unique ID of the target row within the table.
@export var row_id: StringName = &"":
	set(value):
		if row_id != value:
			row_id = value
			emit_changed()
#endregion


#region Data Access
## Retrieves the instantiated DataStructure row from the assigned table.
## Returns null if the table is invalid or the row_id does not exist.
func get_row() -> DataStructure:
	if not is_instance_valid(table):
		return null
		
	return table.get_row(row_id)


## Validates if the current handle points to a legitimately loaded and existing row.
func is_valid() -> bool:
	if not is_instance_valid(table):
		return false
		
	return table.has_row(row_id)


## Extracts the row's properties and packages them into a generic Godot Dictionary.
## If 'numeric_only' is true, it strictly filters and casts to floats (ideal for attribute overrides in things such as our GodotGAS addon).
func get_row_as_dictionary(numeric_only: bool = true) -> Dictionary:
	var row_dict: Dictionary = {}
	var row_instance: DataStructure = get_row()
	
	if not row_instance:
		return row_dict
		
	var columns: Array[Dictionary] = row_instance.get_schema_columns()
	
	for col: Dictionary in columns:
		var prop_name: String = col["name"]
		var prop_type: int = col["type"]
		
		if numeric_only:
			if prop_type == TYPE_FLOAT or prop_type == TYPE_INT:
				row_dict[prop_name] = float(row_instance.get(prop_name))
		else:
			row_dict[prop_name] = row_instance.get(prop_name)
			
	return row_dict
#endregion
