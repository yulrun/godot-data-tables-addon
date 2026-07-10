[☕ Buy me a Coffee!](https://ko-fi.com/yulrundev) | [Discord](https://discord.gg/bW5pvcdK5j)

# Godot DataTables
**A Native, Strongly-Typed DataTable Framework for Godot 4.7+**

Godot DataTables is a robust, code-generated framework written entirely in GDScript, bringing Unreal Engine's renowned "DataTable" paradigm directly into Godot. It provides a highly scalable, visual workflow for managing complex datasets like items, abilities, dialogue, and NPC stats.

While standard systems rely on generic JSON or CSV files that ruin static typing and lack engine integration, Godot DataTables allows you to seamlessly drag-and-drop native resources (like Textures or PackedScenes), utilize strict typing for perfect IDE autocomplete, and reference data safely to completely eliminate runtime typo crashes.

![Data Table Dock](/github_images/data_table_dock.png)
![Data Structure Dock](/github_images/data_structure_dock.png)

---

## Full Documentation
This README provides a high-level overview. For the complete setup guide, deep dives into the architecture, and API references, please visit the official documentation:

**[Godot DataTables Official Documentation](#)**

---

## Core Features

* **Visual Schema Generator:** Define your dataset blueprints (e.g., "ItemData") visually in the editor. The tool automatically compiles these into fully documented, strictly-typed `.gd` script files, providing massive runtime performance benefits and flawless autocomplete.
* **Native Engine Integration:** Move beyond strings and floats. Seamlessly assign native Godot types such as `Texture2D`, `PackedScene`, `Color`, `Vector3`, and custom instantiable Resources directly into your spreadsheet cells.
* **DataTableRowHandle:** A specialized Resource and Custom Inspector Plugin that draws a sleek, two-step dropdown (Table -> Row ID) directly in the Godot Inspector. It safely links your databases to your game logic without requiring designers to type out raw strings.
    * **Decoupled System Bridge:** Includes a built-in `get_row_as_dictionary(numeric_only)` helper. This dynamically unpacks your strongly-typed row into a primitive Godot Dictionary (with optional strict float casting). It is the perfect bridge for feeding base stat overrides directly into standalone systems like [GodotGAS](https://github.com/yulrun/godot-gas) without creating hard compile-time dependencies.
* **Dynamic Array Support:** Full support for editing Godot 4 strictly-typed arrays directly within the spreadsheet grid. Features a dedicated popup editor complete with data validation and drag-and-drop reordering.
* **Dedicated Editor Dock:** A polished, highly reactive spreadsheet workspace embedded natively in the Godot Editor. Includes advanced filtering, column sorting, duplicate/delete row actions, and robust lock/revert safety mechanics to prevent accidental data loss.
* **Import & Export Pipeline:** Need to balance stats in Excel? Safely bridge external data by parsing standard CSV or JSON files directly into your strongly-typed Godot tables, or export your tables for external viewing.

## Quick Start / Installation

1. Download the latest release or clone this repository.
2. Copy the `addons/GodotDataTables` folder into your Godot project's `addons/` directory.
3. Open your project in **Godot 4.7+**.
4. Navigate to `Project -> Project Settings -> Plugins` and enable **Godot DataTables**.
5. The Godot DataTables Editor Dock will automatically appear in your editor's bottom panel.

*For your first "Hello World" setup, please refer to the official documentation link above.*

## License

MIT License

Copyright (c) 2026 YulRun (https://www.yulrun.dev)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
