extends SkeletonModifier3D
const SemanticResolver = preload("res://implementations/communication_lab/game/characters/semantic_bone_resolver.gd")
## Retargets the pose of the parent Skeleton3D (source rig) onto a child
## Skeleton3D (target VRM), accounting for the fact that the two skeletons use
## OPPOSITE forward conventions (the Motifect source rig faces +Z, the VRM faces -Z).
##
## Why not RetargetModifier3D? Its rest-aware math assumes both skeletons share
## the same bone-orientation conventions. For opposite-facing skeletons the
## model-space rotation delta must be conjugated by a 180° rotation about Y
## (flips X and Z), which a rotation-only retarget cannot express. Naively
## copying the source pose produces inverted limb bends (arms that hang down on
## the rig bend up on the VRM); global-pose mode instead copies positions and
## stretches the differently-proportioned VRM.
##
## This modifier works in model space: it computes the source bone's rotation
## delta relative to its own rest, conjugates it by the mirror transform, and
## applies it on top of the target bone's own rest. Target positions are never
## written, so the VRM keeps its own proportions.

const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))

## Shared bone names (J_Bip_*) present in both skeletons. When empty, every bone
## present in both skeletons is retargeted. Legacy path: source and target share
## the SAME bone names (VRM 0.0 keeps J_Bip_* after import).
var profile_bones: PackedStringArray = PackedStringArray()

## Semantic compatibility layer: source bone name -> target actual bone name
## (VRM 1.0: "J_体_L_UpperArm" -> "Left_arm"). When set, used for pairs
## (semantically-identical to profile_bones identity names); skeleton NOT renamed.
var bone_pairs: Dictionary = {}

## Rest-pose normalization (виртуальный слой). Когда TRUE, нейтральная поза
## target строится как зеркальная source-rest (а не собственный T/rest target):
## VRM 1.0 (T-pose) переводится в ту же A-pose-базу, что и VRM 0.0. Включаем
## ТОЛЬКО для non-identity пар (т.е. VRM 1.0), чтобы VRM 0.0 не менялся.
var normalize_rest := false

## Режим зеркальной конъюгации (debug/override):
##   0 = авто-детект по handedness скелета (по умолчанию),
##   1 = принудительно ON  (классическое поведение VRM 0.0 / astera),
##   2 = принудительно OFF.
@export var mirror_override := 0

## Печатать диагностику handedness при инициализации ретаргета.
@export var debug_log := true

## Фактическая зеркальная конъюгация для ЭТОЙ пары source→target.
## Identity, когда target X-выровнен с rig (mirror NOT required).
var _mirror: Basis = MIRROR
var _mirror_required := true
var _mirror_detected := false

var _target: Skeleton3D


func _ready() -> void:
	for child in get_children():
		if child is Skeleton3D:
			_target = child
			break


func _find_target() -> Skeleton3D:
	if _target != null:
		return _target
	for child in get_children():
		if child is Skeleton3D:
			_target = child
			return _target
	return null


## Re-run handedness detection (Debug → Retarget). Call after changing
## `mirror_override` at runtime so the override takes effect immediately.
func force_redetect() -> void:
	_mirror_detected = false
	_detect_mirror()


# ---------------------------------------------------------------------------
# Deterministic mirror detection (handedness-based, NOT VRM-version based)
# ---------------------------------------------------------------------------
## Определяет, требует ли target skeleton зеркальной конъюгации относительно
## source rig. Ориентация определяется по ЛАТЕРАЛЬНОЙ оси: на какой стороне X
## находится «левая» сторона скелета. Несколько независимых landmarks
## (левое/правое плечо + бедро), не одна кость. Не использует VRM version,
## имя модели или hardcoded список. Ambiguous -> safe fallback (mirror = ON,
## legacy VRM 0.0 поведение) + диагностика.
func _detect_mirror() -> void:
	if _mirror_detected:
		return
	_mirror_detected = true
	var src := get_skeleton()
	var tgt := _find_target()

	var src_hand := _lateral_sign(src)
	var tgt_hand := _lateral_sign(tgt)
	var required := true
	var reason := ""

	match mirror_override:
		1:
			required = true
			reason = "forced ON (mirror_override=1)"
		2:
			required = false
			reason = "forced OFF (mirror_override=2)"
		_:
			if is_nan(src_hand) or is_nan(tgt_hand):
				required = true
				reason = "handedness ambiguous (missing landmarks); legacy fallback mirror=ON"
			else:
				required = src_hand != tgt_hand
				if required:
					reason = "target lateral orientation is opposite to source rig (mirror required)"
				else:
					reason = "target lateral orientation matches source rig (mirror not required)"

	_mirror_required = required
	_mirror = MIRROR if required else Basis.IDENTITY

	if debug_log:
		print("[MirrorRetarget] %s -> %s  src_handedness=%s tgt_handedness=%s mirror=%s  %s" % [
			src.get_name() if src else "?",
			tgt.get_name() if tgt else "?",
			"-1" if is_nan(src_hand) else ("+1" if src_hand > 0.0 else "-1"),
			"-1" if is_nan(tgt_hand) else ("+1" if tgt_hand > 0.0 else "-1"),
			str(required), reason])


## ЛАТЕРАЛЬНЫЙ ЗНАК скелета: +1 если «левая» сторона на +X, -1 если на -X.
## Усредняется по нескольким независимым парам (плечо + бедро). NAN если данных мало.
func _lateral_sign(skel: Skeleton3D) -> float:
	if skel == null:
		return NAN
	var left_names := [SemanticResolver.LEFT_UPPER_ARM, SemanticResolver.LEFT_UPPER_LEG]
	var right_names := [SemanticResolver.RIGHT_UPPER_ARM, SemanticResolver.RIGHT_UPPER_LEG]
	var l := Vector3.ZERO
	var ln := 0
	var r := Vector3.ZERO
	var rn := 0
	for sem in left_names:
		var idx := SemanticResolver.find(skel, sem)
		if idx >= 0:
			l += skel.get_bone_global_rest(idx).origin
			ln += 1
	for sem in right_names:
		var idx := SemanticResolver.find(skel, sem)
		if idx >= 0:
			r += skel.get_bone_global_rest(idx).origin
			rn += 1
	if ln == 0 or rn == 0:
		return NAN
	var d := (l.x / float(ln)) - (r.x / float(rn))
	if absf(d) < 0.01:
		return NAN  # landmarks почти на одной оси — неоднозначно
	return 1.0 if d > 0.0 else -1.0


func _process_modification() -> void:
	_detect_mirror()
	var source: Skeleton3D = get_skeleton()
	var target := _find_target()
	if source == null or target == null:
		return

	if not bone_pairs.is_empty():
		_process_pairs(source, target)
		return

	var use_profile := profile_bones.size() > 0

	# Both skeletons are parent-before-child ordered, so iterating in index
	# order guarantees each bone's parent pose is already set this frame.
	for bone_index in target.get_bone_count():
		var bone_name: StringName = target.get_bone_name(bone_index)
		if use_profile and not profile_bones.has(bone_name):
			continue
		var src_id := source.find_bone(bone_name)
		if src_id < 0:
			continue
		_copy_delta(source, target, src_id, bone_index)


## Semantic-путь: ретаргет идёт по парам «J_Bip-имя на риге -> реальная кость
## target». Обработка в порядке ИНДЕКСОВ target (родитель раньше потомка) —
## иначе parent-pose детей берётся неактуальной. При normalize_rest нейтральная
## поза target = зеркальная source-rest (виртуальная rest-normalization).
func _process_pairs(source: Skeleton3D, target: Skeleton3D) -> void:
	var by_target := {}
	for src_name in bone_pairs:
		var src_id := source.find_bone(String(src_name))
		if src_id < 0:
			continue
		var target_name := String(bone_pairs[src_name])
		if target_name.is_empty():
			continue
		var tgt_id := target.find_bone(target_name)
		if tgt_id < 0:
			continue
		by_target[tgt_id] = src_id
	for tgt_id in target.get_bone_count():
		if not by_target.has(tgt_id):
			continue
		var src_id: int = by_target[tgt_id]
		if normalize_rest:
			_copy_delta_normalized(source, target, src_id, tgt_id)
		else:
			_copy_delta(source, target, src_id, tgt_id)


## Rest-normalized вариант (model space, с учётом иерархии): дельта source
## глобально-модельного кадра зеркалится и применяется на виртуальный rest
## target = зеркальный source-глобальный rest. Родительские трансформы target
## уже выставлены (обход parent-before-child), поэтому цепочка согласована.
func _copy_delta_normalized(source: Skeleton3D, target: Skeleton3D, src_id: int, tgt_id: int) -> void:
	var src_rest: Basis = source.get_bone_global_rest(src_id).basis
	var src_cur: Basis = source.get_bone_global_pose(src_id).basis
	var delta: Basis = src_cur * src_rest.inverse()
	var ref: Basis = _mirror * src_rest * _mirror
	var final_global: Basis = (_mirror * delta * _mirror) * ref
	var parent_id := target.get_bone_parent(tgt_id)
	var parent_global := Basis()
	if parent_id >= 0:
		parent_global = target.get_bone_global_pose(parent_id).basis
	target.set_bone_pose_rotation(
		tgt_id, (parent_global.inverse() * final_global).get_rotation_quaternion())


func _copy_delta(source: Skeleton3D, target: Skeleton3D, src_id: int, tgt_id: int) -> void:
	var src_rest_global: Basis = source.get_bone_global_rest(src_id).basis
	var src_cur_global: Basis = source.get_bone_global_pose(src_id).basis
	# Rotation delta the source bone applies on top of its own rest, in
	# source model space.
	var delta: Basis = src_cur_global * src_rest_global.inverse()
	# Express the same model-space rotation in the target's (mirrored)
	# frame, then apply it on top of the target's own rest.
	var tgt_cur_global: Basis = _mirror * delta * _mirror
	tgt_cur_global = tgt_cur_global * target.get_bone_global_rest(tgt_id).basis

	var parent_id := target.get_bone_parent(tgt_id)
	var parent_global := Basis()
	if parent_id >= 0:
		parent_global = target.get_bone_global_pose(parent_id).basis

	target.set_bone_pose_rotation(
		tgt_id, (parent_global.inverse() * tgt_cur_global).get_rotation_quaternion())
