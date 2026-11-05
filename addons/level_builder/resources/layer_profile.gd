@tool
extends Resource

# A named layer role: which physics layer(s) a thing lives on, what it checks,
# and the human sentence that explains the combo. Ships as .tres in defaults/
# so users can edit the matrix without touching code.

@export var profile_name := ""
@export_multiline var summary := ""
@export_flags_3d_physics var layers := 1
@export_flags_3d_physics var mask := 1
