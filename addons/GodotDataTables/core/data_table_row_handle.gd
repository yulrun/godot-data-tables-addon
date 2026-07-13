## A specialized Resource used to reference a specific DataTable row safely.
##
## Exposes a clean, two-step dropdown in the Godot Inspector when paired
## with its EditorInspectorPlugin, eliminating string typos in gameplay code.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (https://yulrun.dev)
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


## Helper: Safely extracts a specific property's value. 
## If the property is an Array and an array_index >= 0 is provided, it safely clamps and extracts that index (useful for Level lookups).
func get_value(property_name: StringName, array_index: int = -1) -> Variant:
	var row_instance: DataStructure = get_row()
	if not row_instance:
		return null
		
	var val: Variant = row_instance.get(property_name)
	
	if val != null and typeof(val) == TYPE_ARRAY and array_index >= 0:
		var arr: Array = val as Array
		if arr.is_empty(): 
			return null
			
		# Clamp to prevent out-of-bounds crashes
		var safe_idx: int = clampi(array_index, 0, arr.size() - 1)
		return arr[safe_idx]
		
	return val


## Extracts the row's properties and packages them into a generic Godot Dictionary.
## If 'numeric_only' is true, it strictly filters and casts to floats (ideal for attribute overrides in things such as our GodotGAS addon).
## If 'array_index' >= 0, any Array properties will be flattened to the specific index (clamped to max size).
func get_row_as_dictionary(numeric_only: bool = true, array_index: int = -1) -> Dictionary:
	var row_dict: Dictionary = {}
	var row_instance: DataStructure = get_row()
	
	if not row_instance:
		return row_dict
		
	var columns: Array[Dictionary] = row_instance.get_schema_columns()
	
	for col: Dictionary in columns:
		var prop_name: String = col["name"]
		
		# Fetch the value, allowing the helper to flatten Arrays if an index was provided
		var val: Variant = get_value(prop_name, array_index)
		
		if numeric_only:
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				row_dict[prop_name] = float(val)
			elif typeof(val) == TYPE_ARRAY:
				# Auto-fallback to Index 0 (Level 1) to prevent Missing Key crashes in math dictionaries
				var arr: Array = val as Array
				if arr.size() > 0 and (typeof(arr[0]) == TYPE_FLOAT or typeof(arr[0]) == TYPE_INT):
					row_dict[prop_name] = float(arr[0])
		else:
			row_dict[prop_name] = val
			
	return row_dict
#endregion
