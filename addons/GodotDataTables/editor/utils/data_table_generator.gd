## Static utility class for generating Godot DataTables and DataStructures.
##
## Handles all file I/O operations and GDScript string compilation for the framework,
## completely decoupled from any Editor UI logic.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT 

@tool
class_name DataTableGenerator extends RefCounted


## Generates a strongly-typed DataStructure .gd script based on the provided schema.
## Expects 'columns' as an Array of Dictionaries with keys: "name" (String), "type" (String), and optional "default" (String).
static func generate_data_structure(schema_name: String, columns: Array[Dictionary]) -> Error:
	var pascal_name: String = schema_name.to_pascal_case() + "DataStructure"
	var snake_name: String = schema_name.to_snake_case() + "_data_structure"
	var file_path: String = "res://addons/GodotDataTables/data/data_structures/" + snake_name + ".gd"
	
	var script_content: String = """## Generated DataStructure schema for {schema_name}.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@icon("res://addons/GodotDataTables/icons/data_table_structure.svg")
class_name {class_name} extends DataStructure



""".format({"schema_name": schema_name, "class_name": pascal_name})
	
	var variables_array: PackedStringArray = []
	for col: Dictionary in columns:
		var var_name: String = col.get("name", "unknown_var")
		var type_string: String = col.get("type", "Variant")
		var default_val: String = col.get("default", "")
		
		if default_val != "":
			variables_array.append("@export var %s: %s = %s" % [var_name, type_string, default_val])
		else:
			variables_array.append("@export var %s: %s" % [var_name, type_string])
			
	script_content += "\n\n".join(variables_array)
	
	script_content += """


## Custom validation rules can be added here.
## Return an array of warning strings if the row contains invalid data.
func _validate_row() -> PackedStringArray:
	return []
"""
	
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("DataTableGenerator: Failed to open file for writing: ", file_path)
		return FileAccess.get_open_error()
		
	file.store_string(script_content)
	file.close()
	
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
		
	return OK


## Generates a new, blank DataTable resource file initialized with a default schema archetype instance.
static func generate_data_table(table_name: String, structure_script: GDScript) -> Error:
	var snake_name: String = table_name.to_snake_case()
	var file_path: String = "res://addons/GodotDataTables/data/data_tables/" + snake_name + ".tres"
	
	var new_table: DataTable = DataTable.new()
	
	# Instantiate an object of our custom script schema to serve as our archetype template
	if structure_script and structure_script.can_instantiate():
		new_table.row_schema = structure_script.new() as DataStructure
		
	var error: Error = ResourceSaver.save(new_table, file_path)
	if error != OK:
		push_error("DataTableGenerator: Failed to save DataTable resource: ", file_path)
		return error
		
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(file_path)
		
	return OK
