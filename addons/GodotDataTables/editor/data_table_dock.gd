## Root editor dock mediator for the Godot DataTables addon.
##
## Manages the top-level TabContainer and routes contextual signals between the 
## Structure (Schema) workspace and the Data Table workspace.
##
## @meta_addon: Godot DataTables 1.0.0
## @meta_author: Matthew Janes (YulRun Dev)
## @meta_license: MIT

@tool
class_name DataTableDock extends Control


const TAB_STRUCTURE: int = 0
const TAB_TABLES: int = 1

@onready var tab_container: TabContainer = %TabContainer
@onready var structure_panel: Control = %StructurePanel
@onready var data_table_panel: Control = %DataTablePanel


func _ready() -> void:
	# Ensure this UI logic only runs within the Godot Editor environment
	if not Engine.is_editor_hint():
		return
		
	tab_container.tab_changed.connect(_on_tab_changed)


## Handles reactive UI updates when the user switches contexts.
func _on_tab_changed(tab_index: int) -> void:
	if tab_index == TAB_TABLES:
		# Trigger the schema evolution synchronization and grid rebuild
		if data_table_panel.has_method("refresh_current_table_view"):
			data_table_panel.refresh_current_table_view()
