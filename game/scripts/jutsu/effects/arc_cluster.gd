class_name ArcCluster
extends Node3D
## Little arcs of lightning crackling round a point (lightning jutsu) or up
## a body (storm auras). Each arc jumps to new ends several times a second.
## With a `tail`, one more bolt streams back from the point along the node's
## +Z, so a fast jutsu leaves a line of lightning behind it.

var radius := 0.4
## Vertical span the arcs wander over (0 for a point).
var height := 0.0
var count := 3
var width := 0.045
var color := Color(1.0, 0.9, 0.35)
## Length of the bolt streaming behind (0 for none).
var tail := 0.0

var _bolts: Array[VfxBolt] = []
var _tail_bolt: VfxBolt
var _ends: Array = []   # [local a, local b] per bolt
var _retarget := 0.0


func _init(arc_radius := 0.4, span := 0.0) -> void:
	radius = arc_radius
	height = span


func _ready() -> void:
	for i in count:
		var b := VfxBolt.new()
		b.lifetime = 0.0
		b.width = width
		b.color = color
		b.chaos = 0.35
		b.branches = 0
		add_child(b)
		_bolts.append(b)
		_ends.append([Vector3.ZERO, Vector3.UP])
	if tail > 0.0:
		_tail_bolt = VfxBolt.new()
		_tail_bolt.lifetime = 0.0
		_tail_bolt.width = width * 1.6
		_tail_bolt.color = color
		_tail_bolt.chaos = 0.12
		_tail_bolt.branches = 3
		add_child(_tail_bolt)
	_pick()


func _process(delta: float) -> void:
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.07
		_pick()
	# Ends ride along with the node every frame.
	for i in _bolts.size():
		_bolts[i].a = global_transform * _ends[i][0]
		_bolts[i].b = global_transform * _ends[i][1]
	if _tail_bolt:
		_tail_bolt.a = global_transform * Vector3(0, 0, tail)
		_tail_bolt.b = global_position


func _pick() -> void:
	for i in _ends.size():
		var base := Vector3.UP * randf() * height
		_ends[i] = [base + _dir() * radius * randf_range(0.1, 0.5), base + _dir() * radius + Vector3.UP * randf_range(-0.2, 0.2) * height]


static func _dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
