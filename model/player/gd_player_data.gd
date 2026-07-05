class_name PlayerData
extends RefCounted
## MODEL — pure state and game rules. Knows nothing about ViewModels or UI.

signal nutrients_changed(value: BigNumber)

var nutrients: BigNumber = BigNumber.new(1, 0):
	set(value):
		if nutrients == value:
			return
		nutrients = value
		nutrients_changed.emit(nutrients)
