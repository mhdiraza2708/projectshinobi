class_name HeadbandShape
extends RefCounted
## Geometry for headbands, fitted to a measured head. Everything is in the
## canonical character frame (facing -Z). Angles run around the head from
## the front: 0 at the forehead, PI at the back.

const BINS := 48
const SAMPLES := 96

## The band's centre line: where it crosses the forehead (`y_front`), how
## far lower it sits at the back (`drop`), and its radius at each angle.
var center := Vector2.ZERO   # (x, z) of the head's vertical axis
var y_front := 0.0
var drop := 0.0
var radii := PackedFloat32Array()


## Fits the band around the head and hair: in each slice of angle, the
## distance that most of the surface at band height lies within (a little
## hair may poke over the band, as it does on a real one).
static func fit(points: PackedVector3Array, axis: Vector2, y: float, back_drop: float, slab: float,
		fallback: Vector2, percentile := 0.82) -> HeadbandShape:
	var s := HeadbandShape.new()
	s.center = axis
	s.y_front = y
	s.drop = back_drop
	var bins: Array[PackedFloat32Array] = []
	bins.resize(BINS)
	for i in BINS:
		bins[i] = PackedFloat32Array()
	for p in points:
		var dx := p.x - axis.x
		var dz := p.z - axis.y
		var ang := fposmod(atan2(dx, -dz), TAU)
		if absf(p.y - s.height_at(ang)) > slab:
			continue
		bins[int(ang / TAU * BINS) % BINS].append(sqrt(dx * dx + dz * dz))
	var raw := PackedFloat32Array()
	raw.resize(BINS)
	for i in BINS:
		var b := bins[i]
		if b.size() < 6:
			raw[i] = -1.0
			continue
		b.sort()
		raw[i] = b[mini(int(b.size() * percentile), b.size() - 1)]
	# Empty slices (gaps in the mesh) take the ellipse of the head's bounds.
	for i in BINS:
		if raw[i] < 0.0:
			var ang := (i + 0.5) / BINS * TAU
			raw[i] = _ellipse(fallback, ang)
	# Smooth round the loop so single strands don't dent or spike the band.
	for pass_i in 3:
		var next := PackedFloat32Array()
		next.resize(BINS)
		for i in BINS:
			next[i] = (raw[(i + BINS - 1) % BINS] + 2.0 * raw[i] + raw[(i + 1) % BINS]) * 0.25
		raw = next
	s.radii = raw
	return s


## An elliptical band for models without a measured head.
static func ellipse(axis: Vector2, y: float, back_drop: float, half_size: Vector2) -> HeadbandShape:
	var s := HeadbandShape.new()
	s.center = axis
	s.y_front = y
	s.drop = back_drop
	s.radii.resize(BINS)
	for i in BINS:
		s.radii[i] = _ellipse(half_size, (i + 0.5) / BINS * TAU)
	return s


static func _ellipse(half_size: Vector2, ang: float) -> float:
	var c := sin(ang) / maxf(half_size.x, 1e-4)
	var d := cos(ang) / maxf(half_size.y, 1e-4)
	return 1.0 / sqrt(c * c + d * d)


static func direction(ang: float) -> Vector3:
	return Vector3(sin(ang), 0.0, -cos(ang))


## Band height at an angle: level across the forehead, lower at the back.
func height_at(ang: float) -> float:
	return y_front - drop * (1.0 - cos(ang)) * 0.5


func radius_at(ang: float) -> float:
	var f := fposmod(ang, TAU) / TAU * BINS - 0.5
	var i := floori(f)
	var t := f - i
	var a := radii[posmod(i, BINS)]
	var b := radii[posmod(i + 1, BINS)]
	# Smoothstep between slices: no visible facets.
	return lerpf(a, b, t * t * (3.0 - 2.0 * t))


func point(ang: float, extra := 0.0, dy := 0.0) -> Vector3:
	var r := radius_at(ang) + extra
	var d := direction(ang)
	return Vector3(center.x + d.x * r, height_at(ang) + dy, center.y + d.z * r)


## The cloth band: a closed loop `height` tall and `thickness` thick whose
## inner face rests on the fitted surface, with a slight roundness and
## darker hems.
func band_mesh(height: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Cross-section rows: (radial offset, vertical offset, normal-up mix, shade).
	var rows := [
		[0.0, -0.5, -1.0, 0.7], [thickness * 0.8, -0.5, -0.6, 0.72], [thickness, -0.3, -0.15, 0.9],
		[thickness * 1.12, 0.0, 0.0, 1.0], [thickness, 0.3, 0.15, 0.92], [thickness * 0.8, 0.5, 0.6, 0.74],
		[0.0, 0.5, 1.0, 0.7]]
	var ring: Array = []
	for k in SAMPLES + 1:
		var ang := TAU * k / SAMPLES
		var d := direction(ang)
		var col: Array = []
		for row: Array in rows:
			var out: float = row[0]
			var up: float = row[1]
			var tilt: float = row[2]
			var p := point(ang, out, up * height)
			var nrm := (d * (1.0 - absf(tilt)) + Vector3.UP * tilt).normalized()
			col.append([p, nrm, row[3]])
		# The inner face closes the loop's cross-section.
		col.append([point(ang, 0.0, -0.5 * height), -d, 0.5])
		ring.append(col)
	for k in SAMPLES:
		# Round the outside, then back down the inner wall.
		for r in ring[k].size() - 1:
			_quad(st, ring[k][r], ring[k][r + 1], ring[k + 1][r], ring[k + 1][r + 1])
	return st.commit()


## A plate following the band across the forehead, from -half_angle to
## +half_angle, `height` tall, standing `gap` off the band, slightly curved
## top to bottom. UV spans the front face (x across, y down); the rim and
## back map to the UV border so the shader draws them as bevel.
func plate_mesh(half_angle: float, height: float, thickness: float, gap: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 28
	var rows := 8
	var front: Array = []
	var back: Array = []
	for i in cols + 1:
		var u := float(i) / cols
		var ang := lerpf(-half_angle, half_angle, u)
		var d := direction(ang)
		var fcol: Array = []
		var bcol: Array = []
		for j in rows + 1:
			var v := float(j) / rows
			var dy := (0.5 - v) * height
			var bulge := sin(v * PI) * thickness * 0.6
			var fp := point(ang, gap + thickness + bulge, dy)
			var bp := point(ang, gap, dy)
			var nrm := (d + Vector3.UP * (0.5 - v) * 0.6).normalized()
			fcol.append([fp, nrm, Vector2(u, v)])
			bcol.append([bp, -d, Vector2(clampf(u, 0.02, 0.98), clampf(v, 0.02, 0.98))])
		front.append(fcol)
		back.append(bcol)
	# Rows run top to bottom here (the band's run bottom to top), so each
	# quad lists its lower edge first to face outward.
	for i in cols:
		for j in rows:
			_quad_uv(st, front[i][j + 1], front[i][j], front[i + 1][j + 1], front[i + 1][j])
			_quad_uv(st, back[i][j], back[i][j + 1], back[i + 1][j], back[i + 1][j + 1])
	# Rim: top and bottom edges, then the two ends.
	for i in cols:
		_quad_uv(st, front[i][0], back[i][0], front[i + 1][0], back[i + 1][0], Vector3.UP)
		_quad_uv(st, back[i][rows], front[i][rows], back[i + 1][rows], front[i + 1][rows], Vector3.DOWN)
	for j in rows:
		_quad_uv(st, back[0][j + 1], back[0][j], front[0][j + 1], front[0][j])
		_quad_uv(st, front[cols][j + 1], front[cols][j], back[cols][j + 1], back[cols][j])
	st.generate_tangents()
	return st.commit()


static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	for v: Array in [a, c, b, b, c, d]:
		st.set_normal(v[1])
		st.set_color(Color(v[2], v[2], v[2]))
		st.add_vertex(v[0])


static func _quad_uv(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array, normal := Vector3.ZERO) -> void:
	for v: Array in [a, c, b, b, c, d]:
		st.set_normal(normal if normal != Vector3.ZERO else v[1])
		st.set_uv(v[2])
		st.add_vertex(v[0])
