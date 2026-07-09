class_name Screens
extends Resource

@export var screens: Dictionary[ScreenTypes.Types, ScreenDefinition]
@export var initial_screen: ScreenTypes.Types

func _validate_property(property: Dictionary) -> void:
	if property.name == "tier_defs":
		property.hint_string = "%d/%d:%s;%d/%d:%s" % [
			TYPE_INT, PROPERTY_HINT_ENUM, ",".join(ScreenTypes.Types.keys()),
			TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "ScreenDefs",
		]
