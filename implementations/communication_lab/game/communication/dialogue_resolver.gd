extends RefCounted
## Small, explicit German A0–A1 conversation grammar for this lab only.
## It deliberately does not claim to understand arbitrary German.

const LEXICON := {
	"hallo": ["greeting", "привет"], "hi": ["greeting", "привет"], "oh": ["interjection", "о / ох"], "ah": ["interjection", "а / ах"], "puh": ["interjection", "ух"], "haha": ["interjection", "ха-ха"], "ach": ["interjection", "ах / вот как"],
	"ich": ["pronoun", "я"], "du": ["pronoun", "ты"], "dir": ["pronoun", "тебе"], "mir": ["pronoun", "мне"], "mich": ["pronoun", "меня"], "dich": ["pronoun", "тебя"], "es": ["pronoun", "это"], "das": ["pronoun", "это"], "alles": ["pronoun", "всё"], "euch": ["pronoun", "вам"],
	"bin": ["verb", "я есть / являюсь"], "bist": ["verb", "ты есть / являешься"], "ist": ["verb", "есть / является"], "habe": ["verb", "имею / у меня есть"], "heiße": ["verb", "меня зовут"], "heisse": ["verb", "меня зовут"], "geht": ["verb", "идёт / поживает"], "gehts": ["verb", "идёт (в выражении «как дела»)"], "machst": ["verb", "делаешь"], "macht": ["verb", "делает"], "arbeite": ["verb", "работаю"], "lerne": ["verb", "учу"], "räum": ["verb", "убираю"], "räume": ["verb", "убираю"], "raume": ["verb", "убираю"], "spreche": ["verb", "говорю"], "meinst": ["verb", "имеешь в виду"], "möchtest": ["verb", "хочешь"], "mochtest": ["verb", "хочешь"], "wissen": ["verb", "знать"], "weiß": ["verb", "знаю"], "weiss": ["verb", "знаю"], "verstehe": ["verb", "понимаю"], "tut": ["verb", "делает (в выражении «мне жаль»)"], "liegt": ["verb", "лежит"], "stellen": ["verb", "поставить"], "sehen": ["verb", "видеть"], "kann": ["verb", "могу"], "kannst": ["verb", "можешь"], "helfen": ["verb", "помогать"], "helfe": ["verb", "помогаю"], "brauche": ["verb", "нуждаюсь"], "brauchst": ["verb", "нуждаешься"], "öffnen": ["verb", "открыть"], "offnen": ["verb", "открыть"], "geben": ["verb", "дать"], "mache": ["verb", "делаю"], "frag": ["verb", "спроси"], "fragst": ["verb", "спрашиваешь"], "erzählen": ["verb", "рассказать"], "soll": ["verb", "должен"], "sagen": ["verb", "сказать"], "wünsche": ["verb", "желаю"], "wunsche": ["verb", "желаю"], "klingt": ["verb", "звучит"], "freut": ["verb", "радует"], "gehört": ["verb", "принадлежит"],
	"wie": ["interrogative", "как"], "was": ["interrogative", "что"], "warum": ["interrogative", "почему"], "wobei": ["interrogative", "в чём / с чем"], "wo": ["interrogative", "где"], "und": ["conjunction", "и / а"], "oder": ["conjunction", "или"], "aber": ["conjunction", "но"], "so": ["adverb", "так"], "auch": ["adverb", "тоже"], "heute": ["adverb", "сегодня"], "jetzt": ["adverb", "сейчас"], "viel": ["adverb", "много"], "langsam": ["adverb", "медленно"], "später": ["adverb", "позже"], "spaeter": ["adverb", "позже"], "vielleicht": ["adverb", "возможно / может быть"], "ein": ["determiner", "один / немного (в выражении)"], "bisschen": ["noun", "немного"], "still": ["adjective", "тихий / молчаливый"], "bis": ["preposition", "до"], "noch": ["adverb", "ещё"], "einmal": ["adverb", "один раз"], "hier": ["adverb", "здесь"], "dort": ["adverb", "там"], "gerade": ["adverb", "сейчас"], "genau": ["adverb", "именно"], "einfach": ["adverb", "просто"], "schon": ["adverb", "уже"], "wirklich": ["adverb", "правда"], "gern": ["adverb", "охотно / с радостью"], "sehr": ["adverb", "очень"], "nicht": ["negation", "не"],
	"gut": ["adjective", "хорошо"], "gute": ["adjective", "хороший / хорошая"], "guten": ["adjective", "хороший"], "schön": ["adjective", "приятно / красиво"], "nett": ["adjective", "милый / приятный"], "müde": ["adjective", "устал(а)"], "mude": ["adjective", "устал(а)"], "schlecht": ["adjective", "плохо"], "frei": ["adjective", "свободен / выходной"], "offen": ["adjective", "открытый"], "leid": ["adjective", "жаль"], "okay": ["adjective", "хорошо / ладно"],
	"ja": ["response", "да"], "nein": ["response", "нет"], "danke": ["social", "спасибо"], "bitte": ["social", "пожалуйста"], "tschüss": ["social", "пока"], "tschuss": ["social", "пока"], "wiedersehen": ["social", "до свидания"],
	"arbeit": ["noun", "работа"], "deutsch": ["noun", "немецкий язык"], "hilfe": ["noun", "помощь"], "moment": ["noun", "минута / момент"], "frage": ["noun", "вопрос"], "schlüssel": ["noun", "ключ"], "schlussel": ["noun", "ключ"], "tür": ["noun", "дверь"], "tur": ["noun", "дверь"], "boden": ["noun", "пол"], "tag": ["noun", "день"], "ahnung": ["noun", "понятие"], "ordnung": ["noun", "порядок / ладно"], "bescheid": ["noun", "сообщение (в выражении «дать знать»)"],
	"die": ["article", "эта (перед словом)"], "der": ["article", "этот (перед словом)"], "den": ["article", "этот (перед словом)"], "eine": ["article", "одна / некая"], "einen": ["article", "одну (в выражении «одну минуту»)"], "deine": ["determiner", "твоя"], "meine": ["determiner", "моя"], "keine": ["determiner", "никакая / не"], "kein": ["determiner", "никакой / не"], "keinen": ["determiner", "никакого / не"], "wem": ["pronoun", "кому"], "auf": ["particle", "часть выражения «убираться»"], "in": ["preposition", "в"],
}

## Whole-phrase translations let a beginner recover meaning without grammar.
const PHRASES := {
	"wie geht's dir?": "Как дела?", "wie geht es dir?": "Как дела?",
	"wie geht's mir?": "Как у меня дела?", "mir geht's gut, danke!": "У меня всё хорошо, спасибо!",
	"mir geht's auch gut.": "У меня тоже всё хорошо.", "mir geht's auch gut": "У меня тоже всё хорошо.",
	"bis später!": "До встречи!", "bis spaeter!": "До встречи!",
	"ich habe frei.": "У меня сегодня выходной.", "ich habe frei": "У меня сегодня выходной.",
	"gut, danke.": "Хорошо, спасибо!", "sehr gut!": "Очень хорошо!", "nicht gut.": "Мне нехорошо.",
	"ja, bitte!": "Да, пожалуйста!", "ja, bitte.": "Да, пожалуйста!", "nein, danke.": "Нет, спасибо!",
	"ja, ein bisschen.": "Да, немного.", "nein, ich bin müde.": "Нет, я устал(а).",
	"ich lerne deutsch.": "Я учу немецкий.", "ich arbeite.": "Я работаю.",
	"kann ich helfen?": "Могу я помочь?",
	"ich bin auch müde.": "Я тоже устал(а).", "ich arbeite heute viel.": "Я сегодня много работаю.",
	"ich arbeite heute.": "Я работаю сегодня.", "ich arbeite jetzt.": "Я сейчас работаю.",
	"ich räume auf.": "Я убираюсь.", "ich räume auf": "Я убираюсь.",
	"das tut mir leid.": "Мне жаль.", "das tut mir leid": "Мне жаль.",
	"was machst du heute?": "Чем ты занимаешься сегодня?", "und du?": "А ты?",
	"ein bisschen.": "Немного.", "ein bisschen": "Немного.",
	"vielleicht später.": "Может быть, позже.", "vielleicht später": "Может быть, позже.",
	"das ist nett!": "Это мило!", "das ist nett": "Это мило!",
	"ich bin müde.": "Я устал(а).", "ich spreche langsam.": "Я говорю медленно.",
	"ah, deutsch! schön!": "А, немецкий! Здорово!", "ich bin astera.": "Я Астера.",
	"oh… warum?": "Ох… почему?", "oh, warum?": "Ох… почему?", "oh, viel arbeit?": "О, много работы?",
	"oh! okay!": "О! Ладно!", "oh, schön!": "О, здорово!",
	"ich verstehe nicht.": "Я не понимаю.",
	"bitte noch einmal.": "Повторите, пожалуйста.", "ich weiß es nicht.": "Я этого не знаю.",
	"ich mache das nicht.": "Я этого не делаю.",
	"was brauchst du?": "Что тебе нужно?", "was möchtest du wissen?": "Что ты хочешь узнать?",
	"was meinst du?": "Что ты имеешь в виду?", "das geht nicht.": "Так нельзя / это не получится.",
	"einen moment, bitte.": "Одну минуту, пожалуйста.",
}

static func words(text: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}]+")
	for found in regex.search_all(text.to_lower().replace("'", "").replace("’", "")):
		result.append(found.get_string())
	return result

static func parse(text: String, context: Dictionary) -> Dictionary:
	var original_tokens := words(text)
	if original_tokens.size() > 1 and original_tokens[0] in ["hallo", "hi"]:
		var clause_tokens: Array[String] = []
		clause_tokens.assign(original_tokens.slice(1))
		var result := _parse_clause(" ".join(clause_tokens), context)
		# A greeting decorates one complete social clause. It never executes
		# separately, nor permits dropping an unsupported continuation.
		var complete_mood := " ".join(clause_tokens) in ["ich bin müde", "ich bin mude", "nicht gut", "nicht so gut", "sehr gut", "gut danke", "mir gehts gut", "mir geht es gut"]
		var accepted: bool = not result.is_empty() and (result.intent == "PLAYER_NAME" or (complete_mood and result.intent in ["PLAYER_MOOD_LOW", "PLAYER_MOOD_GOOD"]))
		if not accepted:
			result = {"status":"UNSUPPORTED", "intent":"", "semantic":"", "name":"", "ambiguity":[],
				"unsupported_features":["GREETING_COMBINATION"], "frame":{}}
		result.normalized_tokens = original_tokens
		result.lexical_readings = _readings(original_tokens, 3 if accepted and result.intent == "PLAYER_NAME" and clause_tokens.size() == 3 else (1 if accepted and result.intent == "PLAYER_NAME" else -1))
		result.diagnostics = [{"code":"SOCIAL_PREFIX", "greeting":original_tokens[0], "main_intent":result.intent,
			"unparsed_tokens":[] if accepted else clause_tokens}]
		return result
	return _parse_clause(text, context)

static func _parse_clause(text: String, context: Dictionary) -> Dictionary:
	var tokens := words(text)
	if tokens.is_empty(): return {}
	var semantic := ""
	var name := ""
	var compact := " " + " ".join(tokens) + " "
	var name_slot: bool = tokens.size() == 3 and tokens[0] == "ich" and tokens[1] in ["heiße", "heisse", "bin"] and not LEXICON.has(tokens[2])
	var standalone_name: bool = tokens.size() == 1 and context.get("pending_question", "") == "player_name" and not LEXICON.has(tokens[0])
	var known_tokens := true
	for index in tokens.size():
		if (index == 2 and name_slot) or (index == 0 and standalone_name): continue
		if not LEXICON.has(tokens[index]): known_tokens = false
	if name_slot:
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
	elif tokens.has("still") and tokens.has("du"): semantic = "PLAYER_QUIET_ACK"
	elif tokens.has("bisschen") and tokens.has("ja"): semantic = "PLAYER_QUIET_ACK"
	elif compact.contains(" was machst du ") or tokens == ["was", "machst", "du"]: semantic = "ASK_ACTIVITY"
	elif (tokens.has("kann") and tokens.has("helfen")) or (tokens.has("brauchst") and tokens.has("hilfe")) or tokens == ["hilfe"]:
		semantic = "OFFER_HELP"
	elif tokens[0] == "ja" and context.get("pending_question", "") == "help_offer": semantic = "ACCEPT_HELP"
	elif tokens[0] == "nein" and context.get("pending_question", "") == "help_offer": semantic = "DECLINE_HELP"
	elif tokens[0] == "ja" and context.get("pending_question", "") == "slow_speech": semantic = "ACCEPT_SLOW"
	elif tokens[0] == "nein" and context.get("pending_question", "") == "slow_speech": semantic = "DECLINE_SLOW"
	elif tokens.has("müde") or tokens.has("mude") or compact.contains(" nicht so gut ") or tokens == ["nicht", "gut"] or tokens == ["schlecht"]:
		semantic = "PLAYER_MOOD_LOW"
	elif tokens.has("gut") and (tokens.has("mir") or tokens.has("ich") or tokens.has("danke") or tokens.has("sehr")):
		semantic = "PLAYER_MOOD_GOOD"
	elif tokens.has("frei") or tokens.has("arbeite") or tokens.has("arbeit") or (tokens.has("lerne") and tokens.has("deutsch")):
		semantic = "PLAYER_PLAN"
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
		"normalized_tokens":tokens, "lexical_readings":_readings(tokens, 2 if name_slot else (0 if standalone_name else -1)), "frame":frame}

static func _readings(tokens: Array[String], name_index: int) -> Array:
	var result: Array = []
	for index in tokens.size():
		var token := tokens[index]
		var reading: Dictionary
		if LEXICON.has(token):
			var data: Array = LEXICON[token]
			reading = {"lemma_id":token, "surface":token, "pos":data[0], "features":{}, "semantic_id":token, "availability":"available", "translation":data[1]}
		elif index == name_index:
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
	for phrase in PHRASES:
		var phrase_surface := str(phrase)
		phrase_surface = phrase_surface.substr(0, 1).to_upper() + phrase_surface.substr(1)
		result.append({"lemma_id":"phrase_%s" % str(phrase), "surface":phrase_surface, "pos":"phrase",
			"features":{}, "semantic_id":"phrase_%s" % str(phrase), "availability":"available"})
	return result

static func translation_for(surface: String) -> String:
	var phrase := surface.strip_edges().to_lower()
	if PHRASES.has(phrase): return str(PHRASES[phrase])
	var data: Array = LEXICON.get(surface.to_lower(), [])
	return str(data[1]) if data.size() > 1 else ""

static func surface_for(surface: String) -> String:
	return {"hallo":"Hallo", "deutsch":"Deutsch", "arbeit":"Arbeit", "hilfe":"Hilfe",
		"tasse":"Tasse", "ahnung":"Ahnung", "tschüss":"Tschüss", "tschuss":"Tschuss",
		"puh":"Puh", "haha":"Haha"}.get(surface, surface)
