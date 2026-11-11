extends RefCounted
## Small, explicit German A0–A1 conversation grammar for this lab only.
## It deliberately does not claim to understand arbitrary German.

const LEXICON := {
	"hallo": ["greeting", "привет"], "hi": ["greeting", "привет"],
	"ich": ["pronoun", "я"], "bin": ["verb", "есть / являюсь"], "habe": ["verb", "имею"], "heiße": ["verb", "зовусь"], "heisse": ["verb", "зовусь"],
	"wie": ["interrogative", "как"], "geht": ["verb", "идёт / поживает"], "gehts": ["verb", "поживаешь"], "es": ["pronoun", "это"], "dir": ["pronoun", "тебе"], "gut": ["adjective", "хорошо"],
	"sehr": ["adverb", "очень"], "danke": ["social", "спасибо"], "und": ["conjunction", "и / а"], "müde": ["adjective", "уставший"], "mude": ["adjective", "уставший"],
	"nicht": ["negation", "не"], "so": ["adverb", "так"], "mir": ["pronoun", "мне"], "warum": ["interrogative", "почему"],
	"was": ["interrogative", "что"], "machst": ["verb", "делаешь"], "du": ["pronoun", "ты"], "arbeit": ["noun", "работа"], "arbeite": ["verb", "работаю"],
	"lerne": ["verb", "учу"], "deutsch": ["noun", "немецкий язык"], "frei": ["adjective", "свободен"], "helfen": ["verb", "помогать"], "helfe": ["verb", "помогаю"],
	"kann": ["verb", "могу"], "kannst": ["verb", "можешь"], "brauche": ["verb", "нуждаюсь"], "brauchst": ["verb", "нуждаешься"], "hilfe": ["noun", "помощь"],
	"ja": ["response", "да"], "nein": ["response", "нет"], "okay": ["adjective", "хорошо"], "bitte": ["social", "пожалуйста"], "tasse": ["noun", "чашка"], "deine": ["determiner", "твоя"],
	"ist": ["verb", "есть"], "das": ["pronoun", "это"], "wirklich": ["adverb", "правда"], "haha": ["interjection", "ха-ха"], "puh": ["interjection", "ух"],
	"tschüss": ["social", "пока"], "tschuss": ["social", "пока"], "später": ["adverb", "позже"], "bis": ["preposition", "до"],
	"langsam": ["adverb", "медленно"], "noch": ["adverb", "ещё"], "einmal": ["adverb", "один раз"], "verstehe": ["verb", "понимаю"],
	"keine": ["determiner", "никакой / не"], "ahnung": ["noun", "понятие"], "wem": ["pronoun", "кому"], "gehört": ["verb", "принадлежит"],
	"räum": ["verb", "убираю"], "auf": ["particle", "вверх / окончание глагола"], "heute": ["adverb", "сегодня"], "viel": ["adverb", "много"],
	"freut": ["verb", "радует"], "mich": ["pronoun", "меня"], "liebe": ["noun", "доброта"],
}

static func words(text: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}]+")
	for found in regex.search_all(text.to_lower().replace("'", "").replace("’", "")):
		result.append(found.get_string())
	return result

static func parse(text: String, context: Dictionary) -> Dictionary:
	var tokens := words(text)
	if tokens.is_empty(): return {}
	var semantic := ""
	var name := ""
	var compact := " " + " ".join(tokens) + " "
	var name_slot: bool = tokens.size() >= 3 and tokens[0] == "ich" and tokens[1] in ["heiße", "heisse", "bin"]
	var standalone_name: bool = tokens.size() == 1 and context.get("pending_question", "") == "player_name" and not LEXICON.has(tokens[0])
	var known_tokens := true
	for index in tokens.size():
		if (index == 2 and name_slot) or (index == 0 and standalone_name): continue
		if not LEXICON.has(tokens[index]): known_tokens = false
	if tokens.size() >= 3 and tokens[0] == "ich" and tokens[1] in ["heiße", "heisse", "bin"]:
		name = tokens[2].capitalize()
		semantic = "PLAYER_NAME"
	elif standalone_name:
		name = tokens[0].capitalize()
		semantic = "PLAYER_NAME"
	elif tokens == ["hallo"] or tokens == ["hi"]: semantic = "GREETING"
	elif tokens.has("tschüss") or tokens.has("tschuss") or (tokens.size() == 2 and tokens[0] == "bis" and tokens[1] == "später"):
		semantic = "FAREWELL"
	elif tokens.has("warum") and tokens.size() <= 3: semantic = "WHY"
	elif compact.contains(" wie geht es dir ") or compact.contains(" wie gehts dir ") or compact.contains(" wie geht dir "):
		semantic = "ASK_MOOD"
	elif tokens.size() == 2 and tokens[0] == "und" and tokens[1] == "dir": semantic = "ASK_ASTERA_MOOD"
	elif tokens.size() == 2 and tokens[0] == "und" and tokens[1] == "du": semantic = "ASK_BACK"
	elif compact.contains(" was machst du ") or tokens == ["was", "machst", "du"]: semantic = "ASK_ACTIVITY"
	elif (tokens.has("kann") and tokens.has("helfen")) or (tokens.has("brauchst") and tokens.has("hilfe")):
		semantic = "OFFER_HELP"
	elif tokens[0] == "ja" and context.get("pending_question", "") == "help_offer": semantic = "ACCEPT_HELP"
	elif tokens[0] == "nein" and context.get("pending_question", "") == "help_offer": semantic = "DECLINE_HELP"
	elif tokens[0] == "ja" and context.get("pending_question", "") == "slow_speech": semantic = "ACCEPT_SLOW"
	elif tokens[0] == "nein" and context.get("pending_question", "") == "slow_speech": semantic = "DECLINE_SLOW"
	elif tokens.has("müde") or tokens.has("mude") or compact.contains(" nicht so gut ") or tokens == ["schlecht"]:
		semantic = "PLAYER_MOOD_LOW"
	elif tokens.has("gut") and (tokens.has("mir") or tokens.has("ich") or tokens.has("danke") or tokens.has("sehr")):
		semantic = "PLAYER_MOOD_GOOD"
	elif tokens.has("frei") or tokens.has("arbeite") or tokens.has("arbeit") or (tokens.has("lerne") and tokens.has("deutsch")):
		semantic = "PLAYER_PLAN"
	elif tokens.has("tasse") and (text.contains("?") or tokens.has("deine")): semantic = "ASK_CUP_OWNER"
	elif tokens.has("wirklich") or tokens.has("haha"): semantic = "CUP_REACTION"
	elif tokens == ["ja"] and context.get("pending_question", "") in ["", "none"]: return {}
	elif tokens == ["nein"] and context.get("pending_question", "") in ["", "none"]: return {}
	else: return {}
	if not known_tokens:
		# Unknown words are never silently absorbed by this constrained grammar.
		return {}
	var status := "RECOGNIZED"
	var frame := {"speaker":"player", "subject":"player", "addressee":"anna", "predicate":semantic.to_lower(), "action":"", "object_id":"", "polarity":"positive", "modality":"none", "speech_act":"question" if text.contains("?") or semantic.begins_with("ASK_") or semantic == "WHY" else "statement", "target_id":"", "negation_scope":"", "question_type":""}
	if semantic == "PLAYER_MOOD_LOW" and tokens.has("nicht"): frame.polarity = "negative"
	return {"status":status, "intent":semantic, "semantic":semantic, "name":name,
		"ambiguity":[], "unsupported_features":[], "diagnostics":["LAB_DIALOGUE_GRAMMAR"],
		"normalized_tokens":tokens, "lexical_readings":_readings(tokens, name_slot or standalone_name), "frame":frame}

static func _readings(tokens: Array[String], has_name: bool) -> Array:
	var result: Array = []
	for index in tokens.size():
		var token := tokens[index]
		var reading: Dictionary
		if LEXICON.has(token):
			var data: Array = LEXICON[token]
			reading = {"lemma_id":token, "surface":token, "pos":data[0], "features":{}, "semantic_id":token, "availability":"available", "translation":data[1]}
		elif has_name and index == 2:
			reading = {"lemma_id":"player_name", "surface":token, "pos":"proper_noun", "features":{"person":3}, "semantic_id":"player_name", "availability":"available", "translation":"имя"}
		else:
			continue
		result.append({"token":token,"position":index,"readings":[reading]})
	return result

static func suggestions(prefix: String) -> Array[String]:
	var result: Array[String] = []
	for surface in LEXICON:
		if str(surface).begins_with(prefix.to_lower()): result.append(surface_for(str(surface)))
	result.sort()
	return result

static func vocabulary_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for surface in LEXICON:
		var data: Array = LEXICON[surface]
		result.append({"lemma_id":str(surface), "surface":surface_for(str(surface)), "pos":data[0],
			"features":{}, "semantic_id":str(surface), "availability":"available"})
	return result

static func translation_for(surface: String) -> String:
	var data: Array = LEXICON.get(surface.to_lower(), [])
	return str(data[1]) if data.size() > 1 else ""

static func surface_for(surface: String) -> String:
	return {"hallo":"Hallo", "deutsch":"Deutsch", "arbeit":"Arbeit", "hilfe":"Hilfe",
		"tasse":"Tasse", "ahnung":"Ahnung", "tschüss":"Tschüss", "tschuss":"Tschuss",
		"puh":"Puh", "haha":"Haha"}.get(surface, surface)
