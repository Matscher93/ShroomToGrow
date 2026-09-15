class_name DailyTrackList
extends Resource
## MODEL: the authored daily-reward track, in day order. Slot 0 is day 1.
##
## A list resource rather than a folder of files, matching GrowthProducerList:
## the track is read start to finish and its length *is* the design, so the
## fourteen days belong in one place where the curve across them can be read.

@export var slots: Array[DailyTrackSlotDef] = []

func count() -> int:
	return slots.size()
