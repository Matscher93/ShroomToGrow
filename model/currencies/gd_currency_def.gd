class_name CurrencyDef
extends Resource

@export var currency_name: String:
	set(value):
		currency_name = value
		emit_changed()
@export var main_color: Color:
	set(value):
		main_color = value
		emit_changed()
@export var label_color: Color:
	set(value):
		label_color = value
		emit_changed()
@export var currency_color: Color:
	set(value):
		currency_color = value
		emit_changed()
