class_name TimeFormat
extends RefCounted
## MODEL: wall-clock values as strings someone can read. Pure formatting, no
## clock of its own - the caller passes the seconds or the timestamp, which is
## what keeps a test from having to wait for one.
##
## Lives here rather than on the balance simulator because both the sim's pacing
## table and the statistics overlay print the same spans, and two spellings of
## "2h 14m" is one too many.


## Seconds as a span someone can judge: "2h 14m" rather than 8040. Two units is
## enough - the minutes matter next to the hours, the seconds do not.
static func duration(seconds: float) -> String:
	var total := int(round(seconds))
	if total < 60:
		return "%ds" % total
	if total < 3600:
		return "%dm %ds" % [total / 60, total % 60]
	if total < 86400:
		return "%dh %dm" % [total / 3600, (total % 3600) / 60]
	return "%dd %dh" % [total / 86400, (total % 86400) / 3600]


## A unix timestamp as local date and time, "2026-08-25 14:03".
##
## Zero reads as "-" rather than as 1970: an unset timestamp means the save
## predates stats recording, and printing the epoch would look like a real date.
static func stamp(unix: float) -> String:
	if unix <= 0.0:
		return "-"
	var d := Time.get_datetime_dict_from_unix_time(
		int(unix) + Time.get_time_zone_from_system()["bias"] * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]
