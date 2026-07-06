## The abstract base class for all generated DataTable schemas.
##
## Exists strictly to provide a safe, base type for the framework to validate 
## against. All generated row schemas (e.g., SkillsDataStructure) will extend this class.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT 

@abstract
class_name DataStructure extends Resource


## The unique identifier assigned to this row by the DataTable.
var row_id: StringName = &""


## Called automatically by the DataTable when this row is instantiated or loaded.
func _on_row_added(id: StringName) -> void:
	row_id = id


## Override this method in generated schemas to provide custom row validation.
## Return an array of warning strings if the row contains invalid data.
func _validate_row() -> PackedStringArray:
	return []


## Helper method to retrieve only the user-defined columns, filtering out
## native Resource properties and internal script variables.
func get_schema_columns() -> Array[Dictionary]:
	var columns: Array[Dictionary] = []
	var properties: Array[Dictionary] = get_property_list()
	
	var ignored_properties: Array[String] = [
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
		"row_id"
	]
	
	for prop: Dictionary in properties:
		if prop["name"] in ignored_properties:
			continue
			
		# Ensure it's a standard editable property, filtering out categories/groups
		if prop["usage"] & PROPERTY_USAGE_EDITOR:
			columns.append(prop)
			
	return columns
