## Static utility class for parsing DataTable resources into external formats (CSV/JSON).
##
## Safely converts complex Godot Variants (Vector2, Color, Objects) into strings 
## via var_to_str() and reconstructs them during import via str_to_var().
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (https://yulrun.dev)
## @meta_license: MIT

@tool
class_name DataTableIO extends RefCounted


#region Export Operations
## Serializes the table's data into a JSON file, preserving keys and stringified Godot variants.
static func export_to_json(table: DataTable, file_path: String) -> Error:
	var export_dict := {}
	var schema_props := _get_schema_property_names(table)
	
	# Iterate utilizing the strict row_order array to maintain layout
	for row_id: StringName in table.row_order:
		if not table.rows.has(row_id): continue
		
		var row_data: DataStructure = table.rows[row_id]
		var row_export := {}
		
		for prop: String in schema_props:
			var value: Variant = row_data.get(prop)
			# Complex variants must be stringified to survive JSON safely
			row_export[prop] = var_to_str(value) 
			
		export_dict[str(row_id)] = row_export
		
	var json_string: String = JSON.stringify(export_dict, "\t")
	
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	
	file.store_string(json_string)
	file.close()
	return OK


## Serializes the table's data into a standard comma-separated values (CSV) file.
static func export_to_csv(table: DataTable, file_path: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	
	var schema_props := _get_schema_property_names(table)
	
	# Write headers (Column 0 is strictly 'row_id')
	var headers := PackedStringArray(["row_id"])
	headers.append_array(schema_props)
	file.store_csv_line(headers)
	
	for row_id: StringName in table.row_order:
		if not table.rows.has(row_id): continue
		
		var row_data: DataStructure = table.rows[row_id]
		var row_strings := PackedStringArray([str(row_id)])
		
		for prop: String in schema_props:
			row_strings.append(var_to_str(row_data.get(prop)))
			
		file.store_csv_line(row_strings)
		
	file.close()
	
	# Prevent Godot from auto-importing this CSV as a Translation file!
	var import_config := FileAccess.open(file_path + ".import", FileAccess.WRITE)
	if import_config:
		import_config.store_string("[remap]\n\nimporter=\"keep\"\n")
		import_config.close()
		
	return OK
#endregion


#region Import Operations
## Parses a JSON file, generating new rows or overriding existing ones based on the overwrite flag.
static func import_from_json(table: DataTable, file_path: String, overwrite: bool) -> Error:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file: return FileAccess.get_open_error()
	
	var json_string := file.get_as_text()
	file.close()
	
	var parsed_data = JSON.parse_string(json_string)
	if typeof(parsed_data) != TYPE_DICTIONARY:
		printerr("GodotDataTables: Invalid JSON format. Expected root dictionary.")
		return ERR_FILE_CORRUPT
		
	var valid_props := _get_schema_property_names(table)
	
	for row_key: String in parsed_data:
		var row_id := StringName(row_key)
		var is_duplicate: bool = table.has_row(row_id)
		
		if is_duplicate and not overwrite:
			continue
			
		var row_dict: Dictionary = parsed_data[row_key]
		var new_row: DataStructure = table.row_schema.duplicate(true)
		
		for prop: String in valid_props:
			if row_dict.has(prop):
				# Safely parse the string back into a real Godot Variant (e.g. "Vector2(0,0)" -> Vector2)
				var actual_value: Variant = str_to_var(row_dict[prop])
				if actual_value != null or row_dict[prop] == "null":
					new_row.set(prop, actual_value)
					
		if is_duplicate:
			table.remove_row(row_id)
			
		table.add_row(row_id, new_row)
		
	return OK


## Parses a CSV file, matching columns by header strings to inject data safely.
static func import_from_csv(table: DataTable, file_path: String, overwrite: bool) -> Error:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file: return FileAccess.get_open_error()
	
	var headers := file.get_csv_line()
	if headers.size() < 1 or headers[0] != "row_id":
		printerr("GodotDataTables: Invalid CSV format. First column must be 'row_id'.")
		return ERR_FILE_CORRUPT
		
	var valid_props := _get_schema_property_names(table)
	
	while not file.eof_reached():
		var row_data := file.get_csv_line()
		if row_data.size() <= 1: continue # Skip empty trailing lines
		
		var row_id := StringName(row_data[0])
		if row_id.is_empty(): continue
		
		var is_duplicate: bool = table.has_row(row_id)
		if is_duplicate and not overwrite:
			continue
			
		var new_row: DataStructure = table.row_schema.duplicate(true)
		
		# Iterate through the headers and inject the matching properties
		for i: int in range(1, headers.size()):
			if i >= row_data.size(): break
			
			var prop_name := headers[i]
			if prop_name in valid_props:
				var actual_value: Variant = str_to_var(row_data[i])
				if actual_value != null or row_data[i] == "null":
					new_row.set(prop_name, actual_value)
					
		if is_duplicate:
			table.remove_row(row_id)
			
		table.add_row(row_id, new_row)
		
	file.close()
	return OK
#endregion


#region Internal Helpers
## Extracts a clean array of property string names from the active schema to act as columns.
static func _get_schema_property_names(table: DataTable) -> Array[String]:
	var valid_props: Array[String] = []
	if not is_instance_valid(table) or not is_instance_valid(table.row_schema):
		return valid_props
		
	var schema_script: Script = table.row_schema.get_script()
	var raw_props: Array[Dictionary] = schema_script.get_script_property_list()
	
	for prop: Dictionary in raw_props:
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["name"] != "row_id":
			valid_props.append(prop["name"])
			
	return valid_props
#endregion
