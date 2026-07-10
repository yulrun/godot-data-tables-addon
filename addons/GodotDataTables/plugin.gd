## Main initialization and lifecycle management script for the GodotDataTables addon.
##
## Handles the setup, positioning, and safe removal of the primary DataTable management workspace.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (https://yulrun.dev)
## @meta_license: MIT

@tool
extends EditorPlugin


const DOCK_SCENE: PackedScene = preload("res://addons/GodotDataTables/editor/data_table_dock.tscn")

var dock_instance: Control = null
var row_inspector_plugin: DataTableRowInspectorPlugin = null


## Executed when the plugin is enabled or when the project reloads.
func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
		
	# Instantiate the composite layout workspace
	dock_instance = DOCK_SCENE.instantiate()
	
	# Explicitly set the node name. Godot strictly uses this string as the Dock Tab's title!
	dock_instance.name = _get_plugin_name()
	
	# Enforce a default vertical footprint. 
	# Godot's Editor layout manager will respect this minimum size when drawing the dock.
	dock_instance.custom_minimum_size = Vector2(0, 500)
	
	# Add to the Right-Lower dock slot by default. This can be moved manually by developers.
	add_control_to_dock(DOCK_SLOT_BOTTOM, dock_instance)
	
	# Initialize and register the custom DataTableRowHandle inspector plugin
	row_inspector_plugin = DataTableRowInspectorPlugin.new()
	add_inspector_plugin(row_inspector_plugin)
	
	print("GodotDataTables Module: Successfully initialized and docked.")


## Executed when the plugin is disabled or when the engine is shutting down.
## Must explicitly free controls to prevent editor memory leaks.
func _exit_tree() -> void:
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.queue_free()
		dock_instance = null
		
	# Unregister and free the custom inspector plugin
	if row_inspector_plugin:
		remove_inspector_plugin(row_inspector_plugin)
		row_inspector_plugin = null
		
	print("GodotDataTables Module: Successfully cleaned up resources and un-docked.")


## Tells the Godot Editor that this plugin possesses a valid UI state.
func _has_main_screen() -> bool:
	return false


## If you prefer this as a wide spreadsheet next to 2D/3D/Script view instead of a Dock,
## you can swap out the layout functions. However, standard DOCK_SLOT placement allows
## the designer to drag it into the bottom debugger window for an ultra-wide layout.
func _get_plugin_name() -> String:
	return "Godot DataTables"
