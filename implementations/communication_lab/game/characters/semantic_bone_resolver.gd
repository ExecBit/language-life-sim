extends RefCounted
## Единый semantic-bone слой: переводит «семантическую кость» (HIPS, SPINE,
## LEFT_UPPER_ARM, …) в реальное имя кости КОНКРЕТНОГО скелета.
##
## ЭТО виртуальный compatibility layer: он НЕ переименовывает скелет и НЕ меняет
## VRM. Он позволяет system'е работать с одним semantic skeleton независимо от
## того, как назвал кости импорт:
##   VRM 0.0 – J_Bip_C_Hips / Left_arm / ...
##   VRM 1.0 – Hips / Left_leg / Shoulder_L / UpperArm_L_6 / ...
##
## Резолвинг детерминированный:
##   1) точный кандидат (в порядке списка);
##   2) canonical-normalized exact match (одна кость – одно имя), только когда
##      точный кандидат не найден;
##   при неоднозначности или отсутствии – FAIL с diagnostic-списком проверенных.

const HIPS := &"HIPS"
const SPINE := &"SPINE"
const CHEST := &"CHEST"
const UPPER_CHEST := &"UPPER_CHEST"
const NECK := &"NECK"
const HEAD := &"HEAD"
const LEFT_SHOULDER := &"LEFT_SHOULDER"
const LEFT_UPPER_ARM := &"LEFT_UPPER_ARM"
const LEFT_LOWER_ARM := &"LEFT_LOWER_ARM"
const LEFT_HAND := &"LEFT_HAND"
const RIGHT_SHOULDER := &"RIGHT_SHOULDER"
const RIGHT_UPPER_ARM := &"RIGHT_UPPER_ARM"
const RIGHT_LOWER_ARM := &"RIGHT_LOWER_ARM"
const RIGHT_HAND := &"RIGHT_HAND"
const LEFT_UPPER_LEG := &"LEFT_UPPER_LEG"
const LEFT_LOWER_LEG := &"LEFT_LOWER_LEG"
const LEFT_FOOT := &"LEFT_FOOT"
const LEFT_TOES := &"LEFT_TOES"
const RIGHT_UPPER_LEG := &"RIGHT_UPPER_LEG"
const RIGHT_LOWER_LEG := &"RIGHT_LOWER_LEG"
const RIGHT_FOOT := &"RIGHT_FOOT"
const RIGHT_TOES := &"RIGHT_TOES"
const ROOT := &"ROOT"

## Канонический порядок (говорит: в какой паре порядок semantic-bone-scan).
const SEMANTIC_ORDER: Array[StringName] = [
	ROOT, HIPS, SPINE, CHEST, UPPER_CHEST, NECK, HEAD,
	LEFT_SHOULDER, LEFT_UPPER_ARM, LEFT_LOWER_ARM, LEFT_HAND,
	RIGHT_SHOULDER, RIGHT_UPPER_ARM, RIGHT_LOWER_ARM, RIGHT_HAND,
	LEFT_UPPER_LEG, LEFT_LOWER_LEG, LEFT_FOOT, LEFT_TOES,
	RIGHT_UPPER_LEG, RIGHT_LOWER_LEG, RIGHT_FOOT, RIGHT_TOES,
]

## Кандидаты фактически обнаружены в test pool (VRM 0.0 + все VRM 1.0):
## J_Bip_* (VRM 0.0), H_ips/Left_*/Shoulder_*/…_6/_6_… (VRM 1.0), + суфф.
const CANDIDATES := {
	ROOT: ["Root", "root"],
	HIPS: ["J_Bip_C_Hips", "Hips", "Hips_9", "Pelvis", "pelvis"],
	SPINE: ["J_Bip_C_Spine", "Spine", "Spine_9"],
	CHEST: ["J_Bip_C_Chest", "Chest", "Chest_9"],
	UPPER_CHEST: ["J_Bip_C_UpperChest", "UpperChest"],
	NECK: ["J_Bip_C_Neck", "Neck", "Neck_9"],
	HEAD: ["J_Bip_C_Head", "Head", "Head_10"],
	LEFT_SHOULDER: ["J_Bip_L_Shoulder", "Left_shoulder", "LeftShoulder", "Shoulder_L", "Shoulder_L_8"],
	RIGHT_SHOULDER: ["J_Bip_R_Shoulder", "Right_shoulder", "RightShoulder", "Shoulder_R", "Shoulder_R_8"],
	LEFT_UPPER_ARM: ["J_Bip_L_UpperArm", "Left_arm", "Left_upper_arm", "LeftUpperArm", "left_upper_arm", "UpperArm_L", "UpperArm_L_6"],
	RIGHT_UPPER_ARM: ["J_Bip_R_UpperArm", "Right_arm", "Right_upper_arm", "RightUpperArm", "right_upper_arm", "UpperArm_R", "UpperArm_R_6"],
	LEFT_LOWER_ARM: ["J_Bip_L_LowerArm", "Left_elbow", "Left_lower_arm", "LeftLowerArm", "Left_forearm", "left_lower_arm", "LowerArm_L", "LowerArm_L_6"],
	RIGHT_LOWER_ARM: ["J_Bip_R_LowerArm", "Right_elbow", "Right_lower_arm", "RightLowerArm", "Right_forearm", "right_lower_arm", "LowerArm_R", "LowerArm_R_6"],
	LEFT_HAND: ["J_Bip_L_Hand", "Left_wrist", "Left_hand", "LeftHand", "Hand_L", "Hand_L_8"],
	RIGHT_HAND: ["J_Bip_R_Hand", "Right_wrist", "Right_hand", "RightHand", "Hand_R", "Hand_R_8"],
	LEFT_UPPER_LEG: ["J_Bip_L_UpperLeg", "Left_leg", "LeftUpperLeg", "Left_upper_leg", "UpperLeg_L", "UpperLeg_L_6"],
	RIGHT_UPPER_LEG: ["J_Bip_R_UpperLeg", "Right_leg", "RightUpperLeg", "Right_upper_leg", "UpperLeg_R", "UpperLeg_R_6"],
	LEFT_LOWER_LEG: ["J_Bip_L_LowerLeg", "Left_knee", "Left_lower_leg", "LeftLowerLeg", "Left_shin", "LowerLeg_L", "LowerLeg_L_6"],
	RIGHT_LOWER_LEG: ["J_Bip_R_LowerLeg", "Right_knee", "Right_lower_leg", "RightLowerLeg", "Right_shin", "LowerLeg_R", "LowerLeg_R_6"],
	LEFT_FOOT: ["J_Bip_L_Foot", "Left_ankle", "Left_foot", "LeftFoot", "Foot_L", "Foot_L_8"],
	RIGHT_FOOT: ["J_Bip_R_Foot", "Right_ankle", "Right_foot", "RightFoot", "Foot_R", "Foot_R_8"],
	LEFT_TOES: ["J_Bip_L_ToeBase", "Left_Toe", "Left_toes", "LeftToes", "Toe_L", "Toe_L_7"],
	RIGHT_TOES: ["J_Bip_R_ToeBase", "Right_Toe", "Right_toes", "RightToes", "Toe_R", "Toe_R_7"],
}

## Canonical VRM 0.0 (J_бип) имя для semantic ID — используется как SOURCE-имя в
## ретаргет-парах (rig после ренейма имеет именно такие имена).
const VRM0_BONE_NAME := {
	ROOT: "Root",
	HIPS: "J_Bip_C_Hips", SPINE: "J_Bip_C_Spine", CHEST: "J_Bip_C_Chest",
	UPPER_CHEST: "J_Bip_C_UpperChest", NECK: "J_Bip_C_Neck", HEAD: "J_Bip_C_Head",
	LEFT_SHOULDER: "J_Bip_L_Shoulder", LEFT_UPPER_ARM: "J_Bip_L_UpperArm",
	LEFT_LOWER_ARM: "J_Bip_L_LowerArm", LEFT_HAND: "J_Bip_L_Hand",
	RIGHT_SHOULDER: "J_Bip_R_Shoulder", RIGHT_UPPER_ARM: "J_Bip_R_UpperArm",
	RIGHT_LOWER_ARM: "J_Bip_R_LowerArm", RIGHT_HAND: "J_Bip_R_Hand",
	LEFT_UPPER_LEG: "J_Bip_L_UpperLeg", LEFT_LOWER_LEG: "J_Bip_L_LowerLeg",
	LEFT_FOOT: "J_Bip_L_Foot", LEFT_TOES: "J_Bip_L_ToeBase",
	RIGHT_UPPER_LEG: "J_Bip_R_UpperLeg", RIGHT_LOWER_LEG: "J_Bip_R_LowerLeg",
	RIGHT_FOOT: "J_Bip_R_Foot", RIGHT_TOES: "J_Bip_R_ToeBase",
}

const REQUIRED: Array[StringName] = [
	HIPS, SPINE, HEAD,
	LEFT_SHOULDER, LEFT_UPPER_ARM, LEFT_LOWER_ARM, LEFT_HAND,
	RIGHT_SHOULDER, RIGHT_UPPER_ARM, RIGHT_LOWER_ARM, RIGHT_HAND,
	LEFT_UPPER_LEG, LEFT_LOWER_LEG, LEFT_FOOT,
	RIGHT_UPPER_LEG, RIGHT_LOWER_LEG, RIGHT_FOOT,
]


## Разрешить один semantic bone в скелете. Детерминированный порядок:
## 1) точный кандидат из списка; 2) canonical-normalized exact match (только
## когда ровно одна кость подходит; неоднозначность = FAIL -1).
static func find(skel: Skeleton3D, semantic: StringName) -> int:
	if skel == null or not CANDIDATES.has(semantic):
		return -1
	for cand in CANDIDATES[semantic]:
		var idx := skel.find_bone(cand)
		if idx >= 0:
			return idx
	# Нормализованный fallback: lower + разделители убраны (Left_arm == leftArm).
	var want := {}
	for cand in CANDIDATES[semantic]:
		want[normalized(cand)] = true
	var found := -1
	for i in skel.get_bone_count():
		if want.has(normalized(String(skel.get_bone_name(i)))):
			if found >= 0:
				return -1  # неоднозначность: два разных имени нормализуются одинаково
			found = i
	return found


## lowercase + удалить разделители/пробелы (для детерминированного сравнения).
static func normalized(name: String) -> String:
	return name.to_lower().replace("_", "").replace("-", "").replace(".", "").replace(" ", "")


## Имя (реальная кость) для semantic, или "".
static func name(skel3: Skeleton3D, semantic) -> String:
	var idx := find(skel3, semantic)
	return String(skel3.get_bone_name(idx)) if idx >= 0 else ""


## Полная retarget-пара «источник (J_Bip на риге) -> реальная кость target».
static func build_retarget_pairs(skel: Skeleton3D, ids: Array[StringName]) -> Dictionary:
	var out := {}
	for id: StringName in ids:
		var idx := find(skel, id)
		if idx >= 0 and VRM0_BONE_NAME.has(id):
			out[str(VRM0_BONE_NAME[id])] = String(skel.get_bone_name(idx))
	return out


## Проверить обязательные semantic bones. Возвращает список missing semantic ids.
static func missing_required(skel: Skeleton3D, ids: Array = []) -> Array:
	var want: Array = ids if not ids.is_empty() else REQUIRED
	var missing: Array = []
	for id in want:
		if find(skel, id) < 0:
			missing.append(id)
	return missing


## Полный отчёт резолва (для диагностики): id -> реальное имя.
static func resolved_map(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for id in SEMANTIC_ORDER:
		out[id] = name(skel, id)
	return out
