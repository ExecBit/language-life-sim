extends RefCounted

## Locally generated Kimodo clips are kept separate from licensed Motifect packs.
const SCENES := {
	"a02_breakfast_routine": preload("res://assets/animations/generated/prologue/a02_breakfast_routine_66ee3bdb61fd485a.glb"),
	"a02_breakfast_attention": preload("res://assets/animations/generated/prologue/a02_breakfast_attention_983063387a090de8.glb"),
	"a02_breakfast_resume": preload("res://assets/animations/generated/prologue/a02_breakfast_resume_22e7929576616f91.glb"),
	"a01_room_invitation": preload("res://assets/animations/generated/prologue/a01_room_invitation_52a754c0347d221a.glb"),
	"a01_key_setdown": preload("res://assets/animations/generated/prologue/a01_key_setdown_e1e121f3e9719d8b.glb"),
}

const LABELS := {
	"a02_breakfast_routine": "A-02 / 1. Завтрак — обычное движение",
	"a02_breakfast_attention": "A-02 / 2. Обратить внимание и указать",
	"a02_breakfast_resume": "A-02 / 3. Вернуться к завтраку",
	"a01_room_invitation": "A-01 / 1. Пригласить в комнату",
	"a01_key_setdown": "A-01 / 2. Положить ключ",
}

const PACKS := {
	"Generated — A-01 / Комната": [
		"a01_room_invitation",
		"a01_key_setdown",
	],
	"Generated — A-02 / Завтрак": [
		"a02_breakfast_routine",
		"a02_breakfast_attention",
		"a02_breakfast_resume",
	],
}
