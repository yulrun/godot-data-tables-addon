## A core database container that stores and organizes strongly-typed DataStructure rows.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
class_name DataTable extends Resource


#region Core Properties
## The structural blueprint that dictates the variables each row in this table possesses.
@export var row_schema: DataStructure

## Maintains the exact visual/insertion order of rows for .tres serialization.
@export var row_order: Array[StringName] = [] 

## The actual data payload. Key = Row ID (StringName), Value = DataStructure instance.
@export var rows: Dictionary = {}
#endregion


#region Data Access Methods
## Retrieves a specific row instance by its unique StringName ID.
func get_row(id: StringName) -> DataStructure:
	return rows.get(id)


## Checks if the table currently contains a row with the specified ID.
func has_row(id: StringName) -> bool:
	return rows.has(id)


## Returns all instantiated row data strictly ordered by the visual layout array.
func get_all_rows() -> Array:
	var ordered_rows: Array = []
	for id: StringName in row_order:
		if rows.has(id):
			ordered_rows.append(rows[id])
	return ordered_rows
#endregion


#region Row Manipulation (CRUD)
## Injects a new row into the table, pushing its ID into the layout array.
func add_row(id: StringName, row: DataStructure) -> void:
	rows[id] = row
	
	if not id in row_order:
		row_order.append(id)
		
	# Trigger the context injection so the row knows its own ID
	if row.has_method("_on_row_added"):
		row._on_row_added(id)
		
	emit_changed()


## Safely removes a row from both the active dictionary and the layout array.
func remove_row(id: StringName) -> void:
	if rows.has(id):
		rows.erase(id)
		
	if id in row_order:
		row_order.erase(id)
		
	emit_changed()


## Wipes all data and layout states from the table.
func clear_table() -> void:
	rows.clear()
	row_order.clear()
	emit_changed()


## Deep copies an existing row and inserts it directly below the original in the visual layout.
func duplicate_row(original_id: StringName, new_id: StringName) -> void:
	if rows.has(original_id):
		# Create a deep copy so nested resources don't share memory references
		var new_row: DataStructure = rows[original_id].duplicate(true)
		rows[new_id] = new_row
		
		# Insert the new row directly below the original item in the visual array
		var original_idx: int = row_order.find(original_id)
		if original_idx != -1:
			row_order.insert(original_idx + 1, new_id)
		else:
			row_order.append(new_id)
			
		if new_row.has_method("_on_row_added"):
			new_row._on_row_added(new_id)
			
		emit_changed()
#endregion


#region Validation & Sanitization
## Iterates over all rows and aggregates any custom warnings thrown by the user's '_validate_row()' overrides.
func validate_all_rows() -> Dictionary:
	var warnings: Dictionary = {}
	
	for id: StringName in rows:
		if rows[id].has_method("_validate_row"):
			var result = rows[id]._validate_row()
			
			if typeof(result) == TYPE_PACKED_STRING_ARRAY and result.size() > 0:
				warnings[id] = result
				
	return warnings


## The core evolution engine. Safely adds, removes, or re-types properties on live data to match the schema blueprint.
func sanitize_all_rows() -> void:
	if not is_instance_valid(row_schema):
		return
		
	var schema_script: Script = row_schema.get_script()
	var valid_props: Array[String] = []
	var default_values: Dictionary = {}
	
	# Extract valid structural properties from the blueprint
	for prop: Dictionary in schema_script.get_script_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			valid_props.append(prop["name"])
			default_values[prop["name"]] = _get_default_for_type(prop["type"])
			
	for id: StringName in rows:
		var row: DataStructure = rows[id]
		var row_props: Array[Dictionary] = row.get_property_list()
		
		# 1. Pruning Phase: Erase properties that no longer exist in the schema
		for prop: Dictionary in row_props:
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var p_name: String = prop["name"]
				if not p_name in valid_props and p_name != "row_id":
					row.set(p_name, null)
					
		# 2. Injection Phase: Provide zero-state defaults for newly added columns
		for vp: String in valid_props:
			if vp != "row_id" and row.get(vp) == null:
				row.set(vp, default_values[vp])
				
	# 3. Layout Sync Phase: Clean the array structure of any dead manual modifications
	var cleaned_order: Array[StringName] = []
	
	for id: StringName in row_order:
		if rows.has(id):
			cleaned_order.append(id)
			
	for id: StringName in rows:
		if not id in cleaned_order:
			cleaned_order.append(id)
			
	row_order = cleaned_order


## Helper utility resolving strictly-typed zero-states for new column generations.
func _get_default_for_type(p_type: int) -> Variant:
	match p_type:
		TYPE_INT: return 0
		TYPE_FLOAT: return 0.0
		TYPE_BOOL: return false
		TYPE_STRING, TYPE_STRING_NAME: return ""
		TYPE_VECTOR2: return Vector2.ZERO
		TYPE_VECTOR3: return Vector3.ZERO
		TYPE_COLOR: return Color(0, 0, 0, 1)
		_: return null
#endregion
