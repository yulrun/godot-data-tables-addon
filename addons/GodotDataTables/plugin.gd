## Main initialization and lifecycle management script for the GodotGAS DataTable addon.
##
## Registers custom resource types with the editor inspector and handles the setup,
## positioning, and safe removal of the primary DataTable management workspace.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
extends EditorPlugin


const DOCK_SCENE: PackedScene = preload("res://addons/GodotDataTables/editor/data_table_dock.tscn")
var dock_instance: Control = null


## Executed when the plugin is enabled or when the project reloads.
func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
		
	# Instantiate the composite layout workspace
	dock_instance = DOCK_SCENE.instantiate()
	
	# Add to the Right-Lower dock slot by default. This can be moved manually by developers.
	add_control_to_dock(DOCK_SLOT_BOTTOM, dock_instance)
	
	# Explicitly register custom types to ensure custom icons populate in the inspector
	var base_icon: Texture2D = get_editor_interface().get_base_control().get_theme_icon("Object", "EditorIcons")
	var table_icon: Texture2D = get_editor_interface().get_base_control().get_theme_icon("Spreadsheet", "EditorIcons")
	
	add_custom_type("DataTable", "Resource", preload("res://addons/GodotDataTables/core/data_table.gd"), table_icon)
	add_custom_type("DataStructure", "Resource", preload("res://addons/GodotDataTables/core/data_structure.gd"), base_icon)
	
	print("GodotDataTables Module: Successfully initialized and docked.")


## Executed when the plugin is disabled or when the engine is shutting down.
## Must explicitly free controls to prevent editor memory leaks.
func _exit_tree() -> void:
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.queue_free()
		dock_instance = null
		
	remove_custom_type("DataTable")
	remove_custom_type("DataStructure")
	
	print("GodotDataTables Module: Successfully cleaned up resources and un-docked.")


## Tells the Godot Editor that this plugin possesses a valid UI state.
func _has_main_screen() -> bool:
	return false


## If you prefer this as a wide spreadsheet next to 2D/3D/Script view instead of a Dock,
## you can swap out the layout functions. However, standard DOCK_SLOT placement allows
## the designer to drag it into the bottom debugger window for an ultra-wide layout.
func _get_plugin_name() -> String:
	return "GAS DataTables"
