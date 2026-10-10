class_name ModelMeshes
extends RefCounted
## The meshes inside the project's .gltf models (assets/models/), pulled out
## with their transforms so scenery can be scattered as MultiMeshes instead
## of one node per tree. Shared by Island and Continent. The first call for
## a model loads it, so fill the cache from the main thread (warm) before
## worker threads read it.

const MODELS := "res://assets/models/"

static var _cache: Dictionary = {}


## The meshes of a model and their transforms relative to its root:
## [[Mesh, Transform3D], ...].
static func parts(scene_name: String) -> Array:
	if _cache.has(scene_name):
		return _cache[scene_name]
	var root: Node3D = (load(MODELS + scene_name + ".gltf") as PackedScene).instantiate()
	var out := []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out.append([mi.mesh, xf])
	root.free()
	_cache[scene_name] = out
	return out


## Loads several models now (call on the main thread before workers need them).
static func warm(scene_names: PackedStringArray) -> void:
	for scene_name in scene_names:
		parts(scene_name)
