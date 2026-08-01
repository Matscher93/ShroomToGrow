class_name ViewModel
extends RefCounted
## Base class for all ViewModels.
## Views bind to [signal property_changed] and re-read the properties they use.
## ViewModels never touch nodes, Views never touch Models.

signal property_changed(property: StringName)

## Call from setters or model signal handlers to notify bound views.
func _notify(property: StringName) -> void:
	property_changed.emit(property)

## Override in subclasses to disconnect model signals when the VM is discarded.
func dispose() -> void:
	pass
