extends TestCase
## Trimming a Mixamo sword clip to its swing (SwingClip): found from how fast
## the sword arm and the spine turn, on clips made here with a slow wind-up, a
## fast cut and a slow recovery.

const ARM := "%GeneralSkeleton:RightUpperArm"
const FPS := 30.0


## A clip of `seconds` with the right arm turning about Z through `angle`
## radians in the cut at `at` (taking `over` seconds), crawling `crawl` radians
## a second before and after.
func _clip(seconds: float, at: float, over: float, angle: float, crawl: float) -> Animation:
	var anim := Animation.new()
	anim.length = seconds
	var track := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(track, NodePath(ARM))
	var frames := int(seconds * FPS)
	for f in frames + 1:
		var t := f / FPS
		var turned := crawl * t
		if t > at:
			turned = crawl * at + angle * clampf((t - at) / over, 0.0, 1.0) + crawl * maxf(0.0, t - at - over)
		anim.rotation_track_insert_key(track, t, Quaternion(Vector3.BACK, turned))
	return anim


func test_the_window_is_the_fast_part_not_the_wind_up() -> void:
	var anim := _clip(2.0, 1.2, 0.2, 2.4, 0.5)
	var found := SwingClip.window(anim)
	var span: Vector2 = found["span"]
	assert_true(span.x > 1.0 and span.x < 1.3, "starts with the cut, not the wind-up (%.2f)" % span.x)
	assert_true(span.y > 1.3 and span.y < 1.6, "ends soon after it (%.2f)" % span.y)
	assert_true(float(found["peak"]) > 1.2 and float(found["peak"]) < 1.4, "the peak is inside the cut")


func test_a_clip_that_never_turns_fast_has_no_swing() -> void:
	var anim := _clip(2.0, 1.0, 1.0, 0.2, 0.05)
	assert_eq(SwingClip.window(anim)["span"], Vector2.ZERO, "nothing to find")
	var trimmed := SwingClip.trim(anim, 0.2)
	assert_near(trimmed.length, anim.length / SwingClip.MAX_SPEED, 0.2, "only sped up to fit")
	assert_eq(trimmed.get_meta(SwingClip.META_SWING), Vector2(0.0, trimmed.length), "all of it is the swing")


func test_trim_keeps_the_swing_with_a_lead_in_and_a_settle() -> void:
	var anim := _clip(2.0, 1.2, 0.2, 2.4, 0.5)
	var trimmed := SwingClip.trim(anim, 0.2)
	var speed: float = trimmed.get_meta(SwingClip.META_SPEED)
	var swing: Vector2 = trimmed.get_meta(SwingClip.META_SWING)
	assert_true(trimmed.length < 0.8, "seconds of wind-up are gone (%.2f s)" % trimmed.length)
	assert_true(speed >= 1.0 and speed <= SwingClip.MAX_SPEED, "never slowed, never frantic (%.2fx)" % speed)
	assert_near(swing.x, SwingClip.LEAD, 0.04, "the lead-in before the cut")
	assert_near(trimmed.length - swing.y, SwingClip.SETTLE, 0.05, "the settle after it")
	assert_true(swing.y - swing.x < 0.3, "the cut itself is quick (%.2f s)" % (swing.y - swing.x))
	assert_eq(trimmed.loop_mode, Animation.LOOP_NONE)
	# The pose at the start is the one the source has that long before the cut.
	var track := trimmed.find_track(NodePath(ARM), Animation.TYPE_ROTATION_3D)
	assert_true(track >= 0, "the arm's track is kept")
	var source := anim.find_track(NodePath(ARM), Animation.TYPE_ROTATION_3D)
	var span: Vector2 = SwingClip.window(anim)["span"]
	var from := span.x - SwingClip.LEAD * speed
	var want := anim.rotation_track_interpolate(source, from)
	assert_true(trimmed.rotation_track_interpolate(track, 0.0).angle_to(want) < 0.05, "it starts where the source was")
	# And the cut is the same turn: the source's, over less time.
	var turned_src := anim.rotation_track_interpolate(source, span.x).angle_to(anim.rotation_track_interpolate(source, span.y))
	var turned := trimmed.rotation_track_interpolate(track, swing.x).angle_to(trimmed.rotation_track_interpolate(track, swing.y))
	assert_near(turned, turned_src, 0.05, "the same cut")


func test_a_swing_already_quicker_than_the_game_is_not_slowed() -> void:
	var anim := _clip(2.0, 1.2, 0.1, 2.4, 0.5)
	var trimmed := SwingClip.trim(anim, 0.4)
	assert_near(float(trimmed.get_meta(SwingClip.META_SPEED)), 1.0, 0.001, "played as it is")


func test_a_slow_swing_is_sped_up_to_the_cut_time_within_reason() -> void:
	var slow := _clip(3.0, 1.0, 0.8, 2.4, 0.3)
	var swing: Vector2 = SwingClip.trim(slow, 0.26).get_meta(SwingClip.META_SWING)
	var speed: float = SwingClip.trim(slow, 0.26).get_meta(SwingClip.META_SPEED)
	assert_near(speed, SwingClip.MAX_SPEED, 0.001, "as fast as readable, no faster")
	assert_true(swing.y - swing.x > 0.26, "so it takes a little longer than the cut time")
	var fits := SwingClip.trim(_clip(2.0, 1.2, 0.4, 2.4, 0.3), 0.26)
	var fit: Vector2 = fits.get_meta(SwingClip.META_SWING)
	assert_near(fit.y - fit.x, 0.26, 0.08, "a swing that can be sped up to fit is")
