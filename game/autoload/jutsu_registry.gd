extends Node
## Loads every jutsu from res://data/jutsu/*.json and answers lookups by id or
## seal sequence. Autoloaded as `JutsuRegistry`.

const DATA_DIR := "res://data/jutsu"

var load_errors: Array[String] = []

var _by_id: Dictionary = {}
var _by_seals: Dictionary = {}
var _ordered: Array[JutsuDefinition] = []


func _ready() -> void:
	reload()
	for e in load_errors:
		push_error("[JutsuRegistry] " + e)


func reload(dir_path: String = DATA_DIR) -> void:
	_by_id.clear()
	_by_seals.clear()
	_ordered.clear()
	load_errors.clear()

	var files := Array(DirAccess.get_files_at(dir_path)).filter(
		func(f: String) -> bool: return f.get_extension() == "json")
	files.sort()
	if files.is_empty():
		load_errors.append("no jutsu files found in %s" % dir_path)
	for file_name: String in files:
		_load_file(dir_path.path_join(file_name))


func _load_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		load_errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return
	if not json.data is Array:
		load_errors.append("%s: top level must be a list of jutsu" % path)
		return
	for entry: Variant in json.data:
		if not entry is Dictionary:
			load_errors.append("%s: every entry must be an object" % path)
			continue
		var errors: Array[String] = []
		var jutsu := JutsuDefinition.from_dict(entry, errors)
		for e in errors:
			load_errors.append("%s: %s" % [path.get_file(), e])
		if jutsu:
			register(jutsu, path.get_file())


## Adds a definition, rejecting duplicate ids and duplicate seal sequences
## (two jutsu on one sequence would make casting ambiguous).
func register(jutsu: JutsuDefinition, source: String = "code") -> bool:
	if _by_id.has(jutsu.id):
		load_errors.append("%s: duplicate id '%s'" % [source, jutsu.id])
		return false
	var key := sequence_key(jutsu.seals)
	if _by_seals.has(key):
		load_errors.append("%s: '%s' uses the same seals as '%s' (%s)" % [
			source, jutsu.id, _by_seals[key].id, " > ".join(jutsu.seal_names())])
		return false
	_by_id[jutsu.id] = jutsu
	_by_seals[key] = jutsu
	_ordered.append(jutsu)
	return true


func get_jutsu(id: StringName) -> JutsuDefinition:
	return _by_id.get(id)


func find_by_seals(sequence: Array) -> JutsuDefinition:
	return _by_seals.get(sequence_key(sequence))


func all() -> Array[JutsuDefinition]:
	return _ordered.duplicate()


func count() -> int:
	return _ordered.size()


## Jutsu whose seal list starts with `prefix` (used for weaving hints).
func completions(prefix: Array) -> Array[JutsuDefinition]:
	var out: Array[JutsuDefinition] = []
	for j in _ordered:
		if j.seals.size() >= prefix.size() and j.seals.slice(0, prefix.size()) == prefix:
			out.append(j)
	return out


static func sequence_key(sequence: Array) -> String:
	return ",".join(sequence.map(func(s: int) -> String: return str(s)))
