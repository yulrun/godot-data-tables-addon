## Core framework container for Godot DataTables.
##
## Maps StringName IDs to strongly-typed row Resources for O(1) lookup.
## Provides the functional Dictionary-backed container for all generated data.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT 

@tool
class_name DataTable extends Resource


## The DataStructure template instance used as a schema archetype.
## The Editor UI duplicates this instance to generate perfectly typed new rows.
@export var row_schema: DataStructure


## The core dataset mapping Row IDs (StringName) to Row Data (DataStructure).
@export var rows: Dictionary = {}:
	set(value):
		rows = value
		_inject_all_ids()


## Iterates through all rows and ensures they know their assigned IDs.
## This is called automatically when the Resource is loaded from disk.
func _inject_all_ids() -> void:
	for id: StringName in rows:
		var row: DataStructure = rows[id] as DataStructure
		if is_instance_valid(row):
			row._on_row_added(id)


## Adds or updates a row in the table, instantly injecting the ID context.
func add_row(id: StringName, row: DataStructure) -> void:
	rows[id] = row
	row._on_row_added(id)
	emit_changed()


## Removes a row from the table by its unique ID.
func remove_row(id: StringName) -> void:
	if rows.erase(id):
		emit_changed()


## Retrieves a row by its unique ID. Returns null if the row does not exist.
func get_row(id: StringName) -> DataStructure:
	return rows.get(id)


## Checks if a specific row ID exists within the table.
func has_row(id: StringName) -> bool:
	return rows.has(id)


## Returns an array of all row IDs currently in the table.
func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(rows.keys())
	return ids


## Returns an array of all instantiated row DataStructures.
func get_all_rows() -> Array[DataStructure]:
	var row_values: Array[DataStructure] = []
	row_values.assign(rows.values())
	return row_values


## Safely wipes all data from the table and notifies the editor to save.
func clear_table() -> void:
	rows.clear()
	emit_changed()


## Duplicates an existing row into a new ID context.
func duplicate_row(original_id: StringName, new_id: StringName) -> void:
	if not has_row(original_id):
		push_warning("DataTable: Cannot duplicate row. Original ID does not exist: ", original_id)
		return
		
	if has_row(new_id):
		push_warning("DataTable: Cannot duplicate row. New ID already exists: ", new_id)
		return
		
	var original_row: DataStructure = get_row(original_id)
	if is_instance_valid(original_row):
		var new_row: DataStructure = original_row.duplicate(true) as DataStructure
		add_row(new_id, new_row)


## Iterates through all rows and runs their internal validation.
## Returns a dictionary mapping Row IDs (StringName) to an array of warnings (PackedStringArray).
func validate_all_rows() -> Dictionary:
	var validation_results: Dictionary = {}
	
	for id: StringName in rows:
		var row: DataStructure = rows[id] as DataStructure
		if is_instance_valid(row):
			var warnings: PackedStringArray = row._validate_row()
			if not warnings.is_empty():
				validation_results[id] = warnings
				
	return validation_results


## Validates and harmonizes all row properties with the current schema layout.
func sanitize_all_rows() -> void:
	if not is_instance_valid(row_schema):
		return
		
	var fresh_properties: Array[Dictionary] = row_schema.get_script().get_script_property_list()
	var valid_prop_names: Array[StringName] = []
	
	for prop: Dictionary in fresh_properties:
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			valid_prop_names.append(prop["name"])
			
	for id: StringName in rows:
		var row: DataStructure = rows[id] as DataStructure
		if not is_instance_valid(row): 
			continue
		
		for prop: Dictionary in fresh_properties:
			if not prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE: 
				continue
				
			var p_name: StringName = prop["name"]
			if row.get(p_name) == null:
				var p_type: int = prop["type"]
				row.set(p_name, _get_default_for_type(p_type))
				
	emit_changed()


## Returns a safe, type-strict default value based on Godot's Variant.Type.
func _get_default_for_type(type: int) -> Variant:
	match type:
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
		TYPE_BOOL:
			return false
		TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_VECTOR2:
			return Vector2.ZERO
		TYPE_VECTOR3:
			return Vector3.ZERO
		TYPE_COLOR:
			return Color(0, 0, 0, 1)
		_:
			return null
