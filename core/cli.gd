class_name Cli
extends RefCounted
## Parses user command line arguments (those after `--`). Supports --key=value, --key value, --flag.


static func parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var value: Variant = true
			var eq := key.find("=")
			if eq >= 0:
				value = key.substr(eq + 1)
				key = key.substr(0, eq)
			elif i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				value = argv[i + 1]
				i += 1
			out[key] = value
		i += 1
	return out
