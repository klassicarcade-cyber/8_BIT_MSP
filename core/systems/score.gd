extends Node

signal changed(cents: int)

var cents: int = 0


func reset() -> void:
	cents = 0
	emit_signal("changed", cents)


func add_pickup(value_cents: int = 10) -> void:
	cents += value_cents
	if cents < 0:
		cents = 0
	emit_signal("changed", cents)
func dollars_string_from_cents(cents: int) -> String:
	return "$%.2f" % (cents / 100.0)

# Explicit helper for enemies stealing (optional but clear)
func steal(value_cents: int) -> void:
	if cents <= 0:
		return
	cents -= value_cents
	if cents < 0:
		cents = 0
	emit_signal("changed", cents)


func dollars_string() -> String:
	return "$%.2f" % (cents / 100.0)
