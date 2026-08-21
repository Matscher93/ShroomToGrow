class_name DailyCalendar
extends RefCounted
## MODEL: pure calendar arithmetic for the daily reward. Performs no writes and
## reads no clock - the caller passes both the timestamp and the offset, which is
## what makes a day boundary testable without waiting for one.
##
## A day is an integer index rather than a year/month/day triple, so crossing one
## is a comparison and nothing has to know about month lengths or leap years.
## Time.get_datetime_dict_from_unix_time() appears nowhere as a result.
##
## The offset is the plain minutes-from-UTC bias Time.get_time_zone_from_system()
## reports. A DST shift moves it by an hour, which can only reclassify a claim
## made within an hour of local midnight - the alternative, a real timezone
## database, has no precedent anywhere in this project.

const SECONDS_PER_DAY := 86400.0

## Which local calendar day a unix timestamp falls on. Day 0 is 1970-01-01, so
## an unset last-claim day reads as "never claimed" rather than as today.
static func day_index(unix: float, tz_bias_minutes: int) -> int:
	return int(floor((unix + float(tz_bias_minutes) * 60.0) / SECONDS_PER_DAY))
