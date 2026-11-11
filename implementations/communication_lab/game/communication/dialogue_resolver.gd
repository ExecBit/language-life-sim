extends RefCounted
## Small, explicit German A0–A1 conversation grammar for this lab only.
## It deliberately does not claim to understand arbitrary German.
const Catalog = preload("res://implementations/communication_lab/game/communication/word_catalog.gd")

const LEXICON := {
	"hallo": ["greeting", "привет"], "hi": ["greeting", "привет"], "oh": ["interjection", "о / ох"], "ah": ["interjection", "а / ах"], "puh": ["interjection", "ух"], "haha": ["interjection", "ха-ха"], "ach": ["interjection", "ах / вот как"],
	"ich": ["pronoun", "я"], "du": ["pronoun", "ты"], "dir": ["pronoun", "тебе"], "mir": ["pronoun", "мне"], "mich": ["pronoun", "меня"], "dich": ["pronoun", "тебя"], "es": ["pronoun", "это"], "das": ["pronoun", "это"], "alles": ["pronoun", "всё"], "euch": ["pronoun", "вам"], "astera": ["proper_noun", "Астера"],
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
	"möchtest du mir helfen oder brauchst du hilfe?": "Ты хочешь мне помочь или тебе нужна помощь?",
	"möchtest du, dass ich dir helfe?": "Хочешь, чтобы я тебе помогла?",
	"was soll ich wiederholen?": "Что мне повторить?",
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

## Surface morphology for the small A0–A1 conversation grammar. Each surface
## form carries the same lemma and features, so interpretation is based on
## participant/predicate structure rather than whole-utterance templates.
const VERB_MORPHOLOGY := {
	"bin":{"lemma":"sein","person":1,"form":"finite"}, "bist":{"lemma":"sein","person":2,"form":"finite"}, "ist":{"lemma":"sein","person":3,"form":"finite"}, "sein":{"lemma":"sein","person":0,"form":"infinitive"}, "gehts":{"lemma":"gehen","person":3,"form":"finite"},
	"habe":{"lemma":"haben","person":1,"form":"finite"}, "hast":{"lemma":"haben","person":2,"form":"finite"}, "hat":{"lemma":"haben","person":3,"form":"finite"},
	"heiße":{"lemma":"heißen","person":1,"form":"finite"}, "heisse":{"lemma":"heißen","person":1,"form":"finite"}, "heißt":{"lemma":"heißen","person":3,"form":"finite"}, "heißen":{"lemma":"heißen","person":0,"form":"infinitive"}, "heissen":{"lemma":"heißen","person":0,"form":"infinitive"},
	"kann":{"lemma":"können","person":1,"form":"finite"}, "kannst":{"lemma":"können","person":2,"form":"finite"}, "können":{"lemma":"können","person":0,"form":"infinitive"}, "konnen":{"lemma":"können","person":0,"form":"infinitive"},
	"möchte":{"lemma":"möchten","person":1,"form":"finite"}, "mochte":{"lemma":"möchten","person":1,"form":"finite"}, "möchtest":{"lemma":"möchten","person":2,"form":"finite"}, "mochtest":{"lemma":"möchten","person":2,"form":"finite"}, "möchten":{"lemma":"möchten","person":0,"form":"infinitive"},
	"helfe":{"lemma":"helfen","person":1,"form":"finite"}, "helfst":{"lemma":"helfen","person":2,"form":"finite"}, "hilfst":{"lemma":"helfen","person":2,"form":"finite"}, "hilft":{"lemma":"helfen","person":3,"form":"finite"}, "helfen":{"lemma":"helfen","person":0,"form":"infinitive"}, "hilf":{"lemma":"helfen","person":2,"form":"imperative"},
	"arbeite":{"lemma":"arbeiten","person":1,"form":"finite"}, "arbeitest":{"lemma":"arbeiten","person":2,"form":"finite"}, "arbeitet":{"lemma":"arbeiten","person":3,"form":"finite"}, "arbeiten":{"lemma":"arbeiten","person":0,"form":"infinitive"},
	"lerne":{"lemma":"lernen","person":1,"form":"finite"}, "lernst":{"lemma":"lernen","person":2,"form":"finite"}, "lernt":{"lemma":"lernen","person":3,"form":"finite"}, "lernen":{"lemma":"lernen","person":0,"form":"infinitive"},
	"mache":{"lemma":"machen","person":1,"form":"finite"}, "machst":{"lemma":"machen","person":2,"form":"finite"}, "macht":{"lemma":"machen","person":3,"form":"finite"}, "machts":{"lemma":"machen","person":3,"form":"finite"}, "machen":{"lemma":"machen","person":0,"form":"infinitive"},
	"gehe":{"lemma":"gehen","person":1,"form":"finite"}, "gehst":{"lemma":"gehen","person":2,"form":"finite"}, "geht":{"lemma":"gehen","person":3,"form":"finite"}, "gehen":{"lemma":"gehen","person":0,"form":"infinitive"},
	"spreche":{"lemma":"sprechen","person":1,"form":"finite"}, "sprichst":{"lemma":"sprechen","person":2,"form":"finite"}, "spricht":{"lemma":"sprechen","person":3,"form":"finite"}, "sprechen":{"lemma":"sprechen","person":0,"form":"infinitive"},
	"fühle":{"lemma":"fühlen","person":1,"form":"finite"}, "fühlst":{"lemma":"fühlen","person":2,"form":"finite"}, "fühlt":{"lemma":"fühlen","person":3,"form":"finite"}, "fühlen":{"lemma":"fühlen","person":0,"form":"infinitive"},
	"verstehe":{"lemma":"verstehen","person":1,"form":"finite"}, "verstehst":{"lemma":"verstehen","person":2,"form":"finite"}, "versteht":{"lemma":"verstehen","person":3,"form":"finite"}, "verstehen":{"lemma":"verstehen","person":0,"form":"infinitive"},
	"frage":{"lemma":"fragen","person":1,"form":"finite"}, "fragst":{"lemma":"fragen","person":2,"form":"finite"}, "fragen":{"lemma":"fragen","person":0,"form":"infinitive"},
	"sage":{"lemma":"sagen","person":1,"form":"finite"}, "sagst":{"lemma":"sagen","person":2,"form":"finite"}, "sagen":{"lemma":"sagen","person":0,"form":"infinitive"},
	"wiederhole":{"lemma":"wiederholen","person":1,"form":"finite"}, "wiederholst":{"lemma":"wiederholen","person":2,"form":"finite"}, "wiederholen":{"lemma":"wiederholen","person":0,"form":"infinitive"},
}
const PRONOUN_ROLES := {
	"ich":{"role":"player","case":"nominative","person":1}, "du":{"role":"astera","case":"nominative","person":2},
	"mir":{"role":"player","case":"dative","person":1}, "mich":{"role":"player","case":"accusative","person":1},
	"dir":{"role":"astera","case":"dative","person":2}, "dich":{"role":"astera","case":"accusative","person":2}
}
const MOOD_WORDS := {"müde":"low","mude":"low","schlecht":"low","gut":"good"}
const RECOVERY_DIAGNOSTICS := ["AGREEMENT_MISMATCH", "INFINITIVE_FOR_FINITE", "MISSING_MODAL", "OMITTED_MODAL", "OMITTED_SUBJECT", "OMITTED_COPULA", "OMITTED_PRONOUN", "WORD_ORDER", "PRONOUN_CASE", "TYPO_OR_NEAR_FORM", "REDUNDANT_INFINITIVE", "MISSING_OBJECT", "LEXICAL_CALQUE"]
const EXTRA_LEXICON := {
	"sein":["verb","быть"], "heißt":["verb","называется"], "heissen":["verb","называться"],
	"arbeiten":["verb","работать"], "arbeitest":["verb","работаешь"], "arbeitet":["verb","работает"],
	"lernen":["verb","учиться"], "lernst":["verb","учишь"], "lernt":["verb","учится"],
	"gehen":["verb","идти"], "gehe":["verb","иду"], "gehst":["verb","идёшь"],
	"sprechen":["verb","говорить"], "sprichst":["verb","говоришь"], "spricht":["verb","говорит"],
	"fühle":["verb","чувствую"], "fühlst":["verb","чувствуешь"], "fühlt":["verb","чувствует"], "fühlen":["verb","чувствовать"],
	"verstehen":["verb","понимать"], "verstehst":["verb","понимаешь"], "versteht":["verb","понимает"],
	"fragen":["verb","спрашивать"], "frage":["verb","спрашиваю"], "sagen":["verb","сказать"], "sage":["verb","говорю"],
	"wiederholen":["verb","повторить"], "wiederholst":["verb","повторяешь"], "wiederhole":["verb","повторяю"],
	"möchte":["verb","хочу / хотел(а) бы"], "mochte":["verb","хочу / хотел(а) бы"], "möchten":["verb","хотеть"],
	"uns":["pronoun","нас"], "wieso":["interrogative","почему"], "doch":["response","же / всё-таки"], "oder":["conjunction","или"], "morgen":["adverb","завтра"], "langsamer":["adverb","медленнее"]
}

static func words(text: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}]+")
	for found in regex.search_all(text.to_lower().replace("'", "").replace("’", "")):
		result.append(found.get_string())
	return result

static func parse(text: String, context: Dictionary) -> Dictionary:
	if _contains_world_interaction(words(text)):
		return {}
	var initial_tokens := words(text)
	if initial_tokens.size() == 1 and initial_tokens[0] in ["hallo", "hi"]:
		return _recognized_result("GREETING", text, "player", "player", "", "positive", "statement")
	var social_prefix := initial_tokens.size() > 1 and initial_tokens[0] in ["hallo", "hi"]
	var parse_context := context.duplicate(true)
	parse_context["allow_lowercase_name"] = social_prefix
	if social_prefix and str(parse_context.get("pending_question", "")) == "": parse_context.pending_question = "player_name"
	var parts := _split_clauses(text)
	if parts.size() > 1:
		var parsed_parts: Array[Dictionary] = []
		var clause_context := parse_context.duplicate(true)
		for part in parts:
			var parsed_clause := _parse_clause(part, clause_context)
			parsed_parts.append(parsed_clause)
			if parsed_clause.get("status", "") == "RECOGNIZED":
				if parsed_clause.get("intent", "") == "ASK_ACTIVITY": clause_context.topic = "activity"
				elif parsed_clause.get("intent", "") in ["PLAYER_MOOD_GOOD", "PLAYER_MOOD_LOW"]: clause_context.topic = "player_mood"
		return _combine_clauses(parsed_parts, text)
	var result := _parse_clause(text, parse_context)
	if social_prefix and result.get("status", "") != "RECOGNIZED":
		result.status = "UNSUPPORTED"; result.intent = ""; result.semantic = ""
		result.unsupported_features = ["GREETING_COMBINATION"]
	return result

static func _contains_world_interaction(tokens: Array[String]) -> bool:
	for token in tokens:
		for reading in Catalog.lookup(token):
			if str(reading.semantic_id) in ["door", "key", "room", "cup", "water", "bread", "bell", "lamp", "open", "give"]:
				return true
	return false

static func _split_clauses(text: String) -> Array[String]:
	var parts: Array[String] = []
	var comma_segments := text.split(",")
	if comma_segments.size() > 1:
		var all_segments_are_clauses := true
		for segment in comma_segments:
			var has_predicate := false
			for token in words(str(segment)):
				if VERB_MORPHOLOGY.has(token) or MOOD_WORDS.has(token): has_predicate = true
			if not has_predicate: all_segments_are_clauses = false
		if all_segments_are_clauses:
			for segment in comma_segments:
				var clause := str(segment).strip_edges()
				if not clause.is_empty(): parts.append(clause)
			return parts
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}]+")
	var matches := regex.search_all(text)
	var tokens: Array[String] = []
	for found in matches: tokens.append(found.get_string().to_lower())
	var segment_start := 0
	var token_start := 0
	for index in matches.size():
		var connective := tokens[index]
		if connective not in ["und", "aber"] or index == 0 or index + 1 >= tokens.size(): continue
		var left_tokens: Array[String] = []
		left_tokens.assign(tokens.slice(token_start, index))
		var right_tokens: Array[String] = []
		right_tokens.assign(tokens.slice(index + 1))
		if left_tokens.is_empty() or right_tokens.is_empty(): continue
		var right_has_clause_subject := false
		var right_has_predicate := false
		for token in right_tokens:
			if PRONOUN_ROLES.get(token, {}).get("case", "") == "nominative": right_has_clause_subject = true
			if VERB_MORPHOLOGY.has(token) or MOOD_WORDS.has(token): right_has_predicate = true
		var left_has_predicate := false
		for token in left_tokens:
			if VERB_MORPHOLOGY.has(token) or MOOD_WORDS.has(token): left_has_predicate = true
		var right_is_elliptic_interrogative := right_tokens[0] in ["warum", "wieso"] and left_has_predicate
		if connective == "aber" or (left_has_predicate and (right_has_clause_subject or right_has_predicate or right_is_elliptic_interrogative)):
			var start_pos: int = matches[index].get_start()
			var end_pos: int = matches[index].get_end()
			var first_part := text.substr(segment_start, start_pos - segment_start).strip_edges()
			if not first_part.is_empty(): parts.append(first_part)
			segment_start = end_pos
			token_start = index + 1
	var last_part := text.substr(segment_start).strip_edges()
	if not last_part.is_empty(): parts.append(last_part)
	if parts.size() > 1: return parts
	var single_part: Array[String] = [text]
	return single_part

static func _combine_clauses(clauses: Array[Dictionary], original_text: String) -> Dictionary:
	for clause in clauses:
		if clause.get("status", "") != "RECOGNIZED":
			# Never accept a clear first clause while discarding a problematic tail.
			if clauses.size() > 1 and clauses[0].get("status", "") == "RECOGNIZED":
				return {"status":"UNSUPPORTED","intent":"","semantic":"","name":"","ambiguity":[],
					"unsupported_features":["MULTIPLE_INTENTS"],"semantic_frames":[],"semantic_frame_coverage":"PARTIAL",
					"diagnostics":["MULTIPLE_INTENTS"],"normalized_tokens":words(original_text),"lexical_readings":_readings(words(original_text),-1),
					"frame":{},"semantic_recovery_status":"PARTIAL","grammatical_error_detected":_has_grammar_diagnostic(clauses[0].get("diagnostics",[])),"recovery_used":false}
			return clause
	var frames: Array[Dictionary] = []
	var intents: Array[String] = []
	var diagnostics: Array = []
	var any_recovery := false
	for clause in clauses:
		var intent := str(clause.get("intent", ""))
		intents.append(intent)
		frames.append(clause.frame.duplicate(true))
		for diagnostic in clause.get("diagnostics", []):
			if diagnostic is String and diagnostic not in diagnostics: diagnostics.append(diagnostic)
			elif diagnostic is Dictionary and diagnostic not in diagnostics: diagnostics.append(diagnostic)
		any_recovery = any_recovery or bool(clause.get("recovery_used", false))
	for left_index in frames.size():
		for right_index in range(left_index + 1, frames.size()):
			var left: Dictionary = frames[left_index]
			var right: Dictionary = frames[right_index]
			if left.get("grammatical_subject", "") == right.get("grammatical_subject", "") and left.get("intent", "") == right.get("intent", "") and left.get("polarity", "") != right.get("polarity", ""):
				return _clarification_result(original_text, "CONTRADICTORY_CLAUSES", "", frames)
	if intents.size() < 2:
		return clauses[0]
	diagnostics.append("MULTIPLE_INTENTS")
	var result := {"status":"UNSUPPORTED", "intent":"", "semantic":"", "intents":intents,
		"name":"", "ambiguity":[], "unsupported_features":["MULTIPLE_INTENTS"],
		"semantic_frames":frames, "semantic_frame_coverage":"COMPLETE", "frame":{},
		"diagnostics":diagnostics, "normalized_tokens":words(original_text),
		"lexical_readings":_readings(words(original_text), -1),
		"semantic_recovery_status":"COMPLETE", "grammatical_error_detected":_has_grammar_diagnostic(diagnostics),
		"recovery_used":any_recovery, "recovery":{"used":any_recovery,"issues":diagnostics}}
	return result

static func _clarification_result(text: String, reason: String, partial_intent: String = "", candidate_frames: Array = []) -> Dictionary:
	var subject := ""
	for token in words(text):
		if PRONOUN_ROLES.has(token) and PRONOUN_ROLES[token].case == "nominative":
			subject = PRONOUN_ROLES[token].role
			break
	return {"status":"NEEDS_CLARIFICATION", "intent":"", "semantic":"", "name":"",
		"ambiguity":[reason], "reason":reason, "candidate_interpretations":[], "unsupported_features":[],
		"semantic_frames":candidate_frames, "frame":{"speaker":"player","subject":subject,"grammatical_subject":subject,
			"actor":"","recipient":"","polarity":"unresolved","speech_act":"unresolved"},
		"diagnostics":["CLARIFY_%s" % reason], "normalized_tokens":words(text),
		"lexical_readings":_readings(words(text), -1), "semantic_recovery_status":"PARTIAL" if not subject.is_empty() else "NONE",
		"grammatical_error_detected":false,"recovery_used":false}

static func _parse_clause(text: String, context: Dictionary) -> Dictionary:
	var raw_tokens := _raw_words(text)
	var tokens := words(text)
	if tokens.is_empty(): return {}
	var diagnostics: Array = []
	var canonical_tokens: Array[String] = []
	var name_index := -1
	var verb_indexes: Array[int] = []
	for index in tokens.size():
		if index > 0 and tokens[index - 1] in ["heiße", "heisse", "heißt", "heise"] and not _is_known_token(tokens[index]):
			name_index = index
			canonical_tokens.append(tokens[index])
			continue
		if index > 0 and tokens[index - 1] == "bin" and not _is_known_token(tokens[index]) and (bool(context.get("allow_lowercase_name", false)) or raw_tokens[index].substr(0, 1) != raw_tokens[index].substr(0, 1).to_lower()):
			name_index = index
			canonical_tokens.append(tokens[index])
			continue
		if index > 0 and tokens[index - 1] == "ich" and index + 1 < tokens.size() and tokens[index + 1] in ["heißen", "heissen"] and not _is_known_token(tokens[index]):
			name_index = index
			canonical_tokens.append(tokens[index])
			continue
		var expected_pos := _expected_pos(tokens, index)
		var normalized := _normalize_token(tokens[index], expected_pos)
		canonical_tokens.append(str(normalized.token))
		if normalized.get("corrected", false): diagnostics.append("TYPO_OR_NEAR_FORM")
		if VERB_MORPHOLOGY.has(normalized.token): verb_indexes.append(index)
	var standalone_name := tokens.size() == 1 and not _is_known_token(tokens[0]) and str(context.get("pending_question", "")) == "player_name"
	if tokens.size() == 1 and not _is_known_token(tokens[0]) and not standalone_name and not raw_tokens[0].is_empty() and raw_tokens[0].substr(0, 1) != raw_tokens[0].substr(0, 1).to_lower():
		return _clarification_result(text, "NAME_OR_STATE")
	var unknown_tokens: Array[String] = []
	for index in canonical_tokens.size():
		if index == name_index or (standalone_name and index == 0): continue
		if not _is_known_token(str(canonical_tokens[index])): unknown_tokens.append(str(tokens[index]))
	if not unknown_tokens.is_empty():
		return _unknown_result(text, canonical_tokens, unknown_tokens)
	var clean_tokens := canonical_tokens.duplicate()
	while clean_tokens.has("hallo"): clean_tokens.erase("hallo")
	while clean_tokens.has("hi"): clean_tokens.erase("hi")
	var lower_text := " " + " ".join(clean_tokens) + " "
	var question := text.contains("?") or clean_tokens.has("warum") or clean_tokens.has("wieso") or clean_tokens.has("was") or clean_tokens.has("wie")
	var negative := clean_tokens.has("nicht") or clean_tokens.has("kein") or clean_tokens.has("keine")
	var pronoun_subject := ""
	var subject_index := -1
	var nominative_roles: Array[String] = []
	for index in clean_tokens.size():
		var pronoun: Dictionary = PRONOUN_ROLES.get(clean_tokens[index], {})
		if pronoun.get("case", "") == "nominative":
			if str(pronoun.role) not in nominative_roles: nominative_roles.append(str(pronoun.role))
			if subject_index < 0: subject_index = index; pronoun_subject = str(pronoun.role)
	if nominative_roles.size() > 1:
		var role_recovery := canonical_tokens.has("ich") and canonical_tokens.has("du") and canonical_tokens.has("helfen") and not canonical_tokens.has("möchtest") and canonical_tokens.find("ich") < canonical_tokens.find("helfen") and canonical_tokens.find("helfen") < canonical_tokens.find("du")
		var embedded_question_recovery := canonical_tokens.has("ich") and canonical_tokens.has("du") and canonical_tokens.has("frage") and canonical_tokens.has("wie") and (canonical_tokens.has("geht") or canonical_tokens.has("gehts") or canonical_tokens.has("fühlen"))
		if not role_recovery and not embedded_question_recovery: return _clarification_result(text, "AMBIGUOUS_ROLES")
	var main_verb: Dictionary = {}
	var main_verb_index := -1
	for index in clean_tokens.size():
		if VERB_MORPHOLOGY.has(clean_tokens[index]):
			main_verb = VERB_MORPHOLOGY[clean_tokens[index]]
			main_verb_index = index
			break
	if pronoun_subject.is_empty() and not main_verb.is_empty() and main_verb.form == "finite":
		if int(main_verb.person) == 1: pronoun_subject = "player"
		elif int(main_verb.person) == 2: pronoun_subject = "astera"
		if not pronoun_subject.is_empty(): diagnostics.append("OMITTED_SUBJECT")
	var recipient := ""
	var recipient_token := ""
	for token in clean_tokens:
		if PRONOUN_ROLES.has(token) and PRONOUN_ROLES[token].case != "nominative" and str(PRONOUN_ROLES[token].role) != pronoun_subject:
			recipient = str(PRONOUN_ROLES[token].role); recipient_token = token; break
	if recipient.is_empty() and subject_index >= 0:
		for index in range(subject_index + 1, clean_tokens.size()):
			if PRONOUN_ROLES.has(clean_tokens[index]) and PRONOUN_ROLES[clean_tokens[index]].case == "nominative" and str(PRONOUN_ROLES[clean_tokens[index]].role) != pronoun_subject:
				recipient = str(PRONOUN_ROLES[clean_tokens[index]].role); recipient_token = clean_tokens[index]; diagnostics.append("PRONOUN_CASE"); break
	var verb_lemmas: Array[String] = []
	for token in clean_tokens:
		if VERB_MORPHOLOGY.has(token) and str(VERB_MORPHOLOGY[token].lemma) not in verb_lemmas: verb_lemmas.append(str(VERB_MORPHOLOGY[token].lemma))
	var intent := ""
	var actor := pronoun_subject
	var speech_act := "statement"
	var polarity := "negative" if negative else "positive"
	var helper := ""
	var help_recipient := ""
	var experiencer := ""
	var name := ""
	var recovery_required := false
	var grammatical_subject := pronoun_subject
	var has_help := verb_lemmas.has("helfen") or clean_tokens.has("hilfe")
	var has_slow := clean_tokens.has("langsam") or clean_tokens.has("langsamer")
	var has_repeat := verb_lemmas.has("wiederholen") or verb_lemmas.has("sagen") and clean_tokens.has("noch")
	var has_mood := false
	for token in clean_tokens:
		if MOOD_WORDS.has(token): has_mood = true
	var asks_mood := (clean_tokens.has("wie") and (clean_tokens.has("geht") or clean_tokens.has("gehts") or clean_tokens.has("fühlen"))) or ((clean_tokens.has("geht") or clean_tokens.has("gehts")) and (clean_tokens.has("dir") or clean_tokens.has("du") or clean_tokens.has("dich"))) or (clean_tokens.has("fühlen") and clean_tokens.has("du"))
	var asks_activity := clean_tokens.has("was") and (verb_lemmas.has("machen") or verb_lemmas.has("arbeiten"))
	var why_question := clean_tokens.has("warum") or clean_tokens.has("wieso")
	var context_topic := str(context.get("topic", ""))
	if why_question:
		if context_topic in ["player_mood", "astera_mood", "activity", "work"] or str(context.get("pending_question", "")) in ["player_reason", "astera_mood"] or pronoun_subject == "astera" and (has_mood or asks_activity):
			intent = "WHY"; speech_act = "question"
			if clean_tokens.size() > 1 and clean_tokens[1] in ["du", "ich"]: diagnostics.append("WORD_ORDER")
		else: return _clarification_result(text, "WHY_CONTEXT")
	elif clean_tokens.size() == 2 and clean_tokens[0] == "und" and clean_tokens[1] in ["du", "dir"]:
		if context_topic == "player_mood": intent = "ASK_BACK" if clean_tokens[1] == "du" else "ASK_ASTERA_MOOD"
		else: return _clarification_result(text, "UND_DU_CONTEXT")
		speech_act = "question"
	elif clean_tokens[0] in ["ja", "nein"] and (clean_tokens.size() == 1 or clean_tokens.size() <= 3 and clean_tokens.slice(1).all(func(token: String) -> bool: return token in ["danke", "bitte"])):
		var pending := str(context.get("pending_question", context.get("pending", "")))
		if pending in ["help_offer", "offer"]: intent = "ACCEPT_HELP" if clean_tokens[0] == "ja" else "DECLINE_HELP"
		elif pending == "slow_speech": intent = "ACCEPT_SLOW" if clean_tokens[0] == "ja" else "DECLINE_SLOW"
		elif clean_tokens[0] == "ja" and str(context.get("topic", "")) == "player_plan": intent = "ACCEPT_SLOW"
		else: return _clarification_result(text, "ELLIPTIC_YES_NO")
		speech_act = "statement"
	elif clean_tokens.has("still") and clean_tokens.has("du") or clean_tokens.has("bisschen") and clean_tokens.has("ja"):
		intent = "PLAYER_QUIET_ACK"; actor = "player"
	elif clean_tokens.has("tschüss") or clean_tokens.has("tschuss") or clean_tokens.has("wiedersehen") or (clean_tokens.has("bis") and clean_tokens.has("später")):
		intent = "FAREWELL"; actor = "player"; grammatical_subject = "player"; recipient = "astera"; speech_act = "farewell"
		if clean_tokens.has("bis") and clean_tokens.has("später") and clean_tokens.find("bis") > clean_tokens.find("später"): diagnostics.append("WORD_ORDER")
		if pronoun_subject == "player" and verb_lemmas.has("gehen"):
			if main_verb.form == "infinitive": diagnostics.append("MISSING_MODAL")
			elif main_verb.person != 1: diagnostics.append("AGREEMENT_MISMATCH")
	elif name_index >= 0 or standalone_name:
		if pronoun_subject == "astera":
			intent = "ASK_BACK"; actor = "astera"; grammatical_subject = "astera"; speech_act = "question"
			if not main_verb.is_empty() and main_verb.form == "finite" and main_verb.person != 2: diagnostics.append("AGREEMENT_MISMATCH")
		else:
			name = raw_tokens[name_index if name_index >= 0 else 0].capitalize()
			intent = "PLAYER_NAME"; actor = "player"; grammatical_subject = "player"; experiencer = "player"; speech_act = "statement"
			if pronoun_subject.is_empty() and not standalone_name: diagnostics.append("OMITTED_SUBJECT")
			if not main_verb.is_empty() and main_verb.form == "infinitive": diagnostics.append("INFINITIVE_FOR_FINITE")
			if question: return _clarification_result(text, "NAME_OR_STATE")
	elif asks_mood:
		intent = "ASK_MOOD"; actor = "astera"; grammatical_subject = "astera"; recipient = ""; speech_act = "question"
		if main_verb.get("form", "") == "infinitive": diagnostics.append("INFINITIVE_FOR_FINITE")
		if clean_tokens.has("wie") and clean_tokens.has("geht") and not clean_tokens.has("es"): diagnostics.append("OMITTED_PRONOUN")
		if (clean_tokens.has("geht") or clean_tokens.has("gehts")) and (clean_tokens.has("dir") or clean_tokens.has("mir")) and not clean_tokens.has("es"): diagnostics.append("OMITTED_PRONOUN")
		if not (clean_tokens.has("wie") or clean_tokens.has("geht") or clean_tokens.has("gehts") or clean_tokens.has("fühlen")): diagnostics.append("WORD_ORDER")
		if recipient_token in ["du", "dich"] or subject_index >= 0 and clean_tokens[subject_index] == "du": diagnostics.append("PRONOUN_CASE")
	elif asks_activity:
		intent = "ASK_ACTIVITY"; actor = "astera"; grammatical_subject = "astera"; speech_act = "question"
		if main_verb.is_empty() or main_verb.form == "infinitive": diagnostics.append("INFINITIVE_FOR_FINITE")
		elif main_verb.form == "finite" and pronoun_subject == "astera" and main_verb.person != 2: diagnostics.append("AGREEMENT_MISMATCH")
		if clean_tokens.has("was") and main_verb_index != clean_tokens.find("was") + 1: diagnostics.append("WORD_ORDER")
		if verb_lemmas.has("arbeiten") and verb_lemmas.has("machen"): diagnostics.append("REDUNDANT_INFINITIVE")
	elif has_slow and (clean_tokens.has("sprechen") or verb_lemmas.has("sprechen")):
		if pronoun_subject == "player" and negative:
			intent = "PLAYER_SPEECH_RATE"; actor = "player"; polarity = "negative"; speech_act = "statement"
		elif pronoun_subject in ["astera", ""]:
			intent = "REQUEST_SLOW_SPEECH"; actor = "astera"; grammatical_subject = "astera"; speech_act = "request"
		if not intent.is_empty() and main_verb.form == "infinitive": diagnostics.append("INFINITIVE_FOR_FINITE")
		elif not intent.is_empty() and not main_verb.is_empty() and main_verb.form == "finite" and pronoun_subject != "" and main_verb.person != (1 if pronoun_subject == "player" else 2): diagnostics.append("AGREEMENT_MISMATCH")
	elif has_slow and clean_tokens.has("bitte"):
		intent = "REQUEST_SLOW_SPEECH"; actor = "astera"; grammatical_subject = "unresolved"; recipient = "player"; speech_act = "request"
		diagnostics.append("OMITTED_SUBJECT")
	elif has_repeat:
		intent = "REQUEST_REPEAT"; actor = "astera"; grammatical_subject = "astera"; speech_act = "request"
		if not verb_lemmas.has("können") and main_verb.form == "infinitive": diagnostics.append("MISSING_MODAL")
		if not clean_tokens.has("das"): diagnostics.append("MISSING_OBJECT")
	elif has_help:
		if negative:
			var not_index := clean_tokens.find("nicht")
			if not_index >= 0 and (not_index < subject_index or (main_verb_index >= 0 and not_index < main_verb_index) or clean_tokens.has("oder")):
				return _clarification_result(text, "AMBIGUOUS_NEGATION")
			if pronoun_subject == "player" and recipient in ["astera", ""]:
				intent = "PLAYER_CANNOT_HELP"; actor = "player"; grammatical_subject = "player"; helper = "player"; help_recipient = "astera" if recipient == "astera" else ""
			else:
				return _clarification_result(text, "AMBIGUOUS_NEGATION")
			polarity = "negative"; speech_act = "statement"
		elif pronoun_subject == "player" and recipient in ["astera", ""]:
			intent = "OFFER_HELP"; actor = "player"; grammatical_subject = "player"; helper = "player"; help_recipient = "astera"; speech_act = "offer"
		elif pronoun_subject == "astera" and recipient == "player":
			intent = "REQUEST_HELP"; actor = "astera"; grammatical_subject = "astera"; helper = "astera"; help_recipient = "player"; speech_act = "request"
		elif pronoun_subject == "astera" and clean_tokens.has("hilfe"):
			intent = "OFFER_HELP"; actor = "player"; grammatical_subject = "astera"; helper = "player"; help_recipient = "astera"; speech_act = "offer"
		elif pronoun_subject.is_empty() and clean_tokens == ["hilfe"]:
			intent = "OFFER_HELP"; actor = "player"; grammatical_subject = "player"; helper = "player"; help_recipient = "astera"; speech_act = "offer"
		elif pronoun_subject.is_empty() and (clean_tokens.has("hilf") or clean_tokens.has("bitte")):
			intent = "REQUEST_HELP"; actor = "astera"; grammatical_subject = "astera"; helper = "astera"; help_recipient = "player"; speech_act = "request"
		else:
			return _clarification_result(text, "AMBIGUOUS_ROLES")
		if intent == "REQUEST_HELP" and main_verb.form == "infinitive" and "?" not in text and not clean_tokens.has("bitte") and not clean_tokens.has("hilf"):
			var clarify_request := _clarification_result(text, "QUESTION_OR_STATEMENT")
			clarify_request.frame.actor = "astera"; clarify_request.frame.recipient = "player"; clarify_request.frame.grammatical_subject = "astera"
			clarify_request.candidate_interpretations = ["REQUEST_HELP", "DESCRIBE_HELP"]
			return clarify_request
		if recipient_token in ["mich", "dich"]: diagnostics.append("PRONOUN_CASE")
		if pronoun_subject == "player" and recipient_token == "du": diagnostics.append("PRONOUN_CASE")
		if pronoun_subject == "player" and recipient_token == "du" and main_verb_index >= 0 and clean_tokens.find("du") > main_verb_index: diagnostics.append("WORD_ORDER")
		if negative and recipient_token in ["mir", "dir", "mich", "dich"] and clean_tokens.find("nicht") < clean_tokens.find(recipient_token): diagnostics.append("WORD_ORDER")
		if not main_verb.is_empty() and main_verb.form == "finite" and main_verb.person not in [0, (1 if grammatical_subject == "player" else 2)]: diagnostics.append("AGREEMENT_MISMATCH")
		elif not main_verb.is_empty() and main_verb.form == "infinitive" and (pronoun_subject != "" or intent in ["REQUEST_HELP", "OFFER_HELP"]): diagnostics.append("MISSING_MODAL")
		elif main_verb.is_empty(): diagnostics.append("MISSING_MODAL")
		if intent == "REQUEST_HELP" and pronoun_subject.is_empty() and not clean_tokens.has("hilf"): diagnostics.append("OMITTED_SUBJECT")
	elif has_mood or main_verb.get("lemma", "") == "sein" or main_verb.get("lemma", "") == "gehen" and clean_tokens.has("gut"):
		var mood := ""
		for token in clean_tokens:
			if MOOD_WORDS.has(token): mood = str(MOOD_WORDS[token]); break
		if mood == "good" and negative: mood = "low"
		if pronoun_subject.is_empty() and subject_index < 0 and clean_tokens.size() == 1:
			return _clarification_result(text, "NAME_OR_STATE")
		if main_verb.get("lemma", "") == "gehen" and pronoun_subject.is_empty() and recipient.is_empty():
			return _clarification_result(text, "MISSING_SUBJECT")
		if mood.is_empty() and clean_tokens.has("gut"): mood = "low" if negative else "good"
		if mood.is_empty(): return _clarification_result(text, "MISSING_REFERENCE")
		if pronoun_subject in ["player", "astera"]:
			intent = "PLAYER_MOOD_GOOD" if mood == "good" else ("PLAYER_MOOD_LOW" if pronoun_subject == "player" else "ASTERA_MOOD_LOW")
			actor = pronoun_subject; grammatical_subject = pronoun_subject; experiencer = pronoun_subject
		elif main_verb.get("lemma", "") == "gehen" and recipient in ["player", "astera"]:
			intent = "PLAYER_MOOD_GOOD" if mood == "good" else ("PLAYER_MOOD_LOW" if recipient == "player" else "ASTERA_MOOD_LOW")
			actor = recipient; grammatical_subject = recipient; experiencer = recipient
			if clean_tokens[0] in ["gut", "schlecht"]: diagnostics.append("WORD_ORDER")
		elif not question and (clean_tokens.has("sehr") or negative or clean_tokens.has("danke")):
			intent = "PLAYER_MOOD_GOOD" if mood == "good" else "PLAYER_MOOD_LOW"; actor = "player"; grammatical_subject = "player"; experiencer = "player"; diagnostics.append("OMITTED_SUBJECT")
		elif context_topic == "player_mood" or str(context.get("pending_question", "")) == "player_mood":
			intent = "PLAYER_MOOD_GOOD" if mood == "good" else "PLAYER_MOOD_LOW"; actor = "player"; grammatical_subject = "player"; experiencer = "player"; diagnostics.append("OMITTED_SUBJECT")
		else:
			return _clarification_result(text, "MISSING_SUBJECT")
		speech_act = "question" if question else "statement"
		if main_verb.is_empty(): diagnostics.append("OMITTED_COPULA")
		elif main_verb.form == "infinitive" and pronoun_subject != "": diagnostics.append("INFINITIVE_FOR_FINITE")
		elif main_verb.form == "finite" and pronoun_subject != "" and main_verb.person not in [0, (1 if pronoun_subject == "player" else 2)]: diagnostics.append("AGREEMENT_MISMATCH")
		if mood == "good" and clean_tokens.has("danke") and lower_text.contains(" ich bin gut "): diagnostics.append("LEXICAL_CALQUE")
		if negative and question: return _clarification_result(text, "AMBIGUOUS_NEGATION")
	elif clean_tokens.has("heiße") or clean_tokens.has("heisse") or clean_tokens.has("heißt") or main_verb.get("lemma", "") == "heißen" or name_index >= 0 or standalone_name:
		if pronoun_subject == "astera" and name_index >= 0:
			intent = "ASK_BACK"; actor = "astera"; grammatical_subject = "astera"; speech_act = "question"
		else:
			if name_index >= 0:
				name = raw_tokens[name_index].capitalize()
			elif standalone_name:
				name = raw_tokens[0].capitalize()
			else:
				return _clarification_result(text, "NAME_OR_STATE")
			intent = "PLAYER_NAME"; actor = "player"; grammatical_subject = "player"; experiencer = "player"; speech_act = "statement"
			if pronoun_subject.is_empty(): diagnostics.append("OMITTED_SUBJECT")
			if question: return _clarification_result(text, "NAME_OR_STATE")
	elif verb_lemmas.has("verstehen") and negative:
		intent = "REPORT_NONUNDERSTANDING"; actor = "player"; grammatical_subject = "player"; recipient = "astera"; polarity = "negative"; speech_act = "statement"
		if main_verb.person != 1: diagnostics.append("AGREEMENT_MISMATCH")
		if clean_tokens.find("nicht") < main_verb_index: diagnostics.append("WORD_ORDER")
	elif verb_lemmas.has("arbeiten") or verb_lemmas.has("lernen") or clean_tokens.has("arbeit") or clean_tokens.has("frei"):
		if pronoun_subject != "player" and not (pronoun_subject.is_empty() and verb_lemmas.has("lernen") and clean_tokens.has("deutsch") and clean_tokens.has("ja")): return _clarification_result(text, "MISSING_SUBJECT")
		intent = "PLAYER_PLAN"; actor = "player"; grammatical_subject = "player" if pronoun_subject == "player" else "unresolved"; speech_act = "statement"
		if pronoun_subject.is_empty(): diagnostics.append("OMITTED_SUBJECT")
		if main_verb.form == "infinitive": diagnostics.append("INFINITIVE_FOR_FINITE")
		elif main_verb.person != 1: diagnostics.append("AGREEMENT_MISMATCH")
		if subject_index == 1 and main_verb_index == 2 and clean_tokens[0] in ["heute", "deutsch", "müde", "mude", "gut"]: diagnostics.append("WORD_ORDER")
	elif verb_lemmas.has("gehen") and pronoun_subject == "player":
		intent = "PLAYER_PLAN"; actor = "player"; grammatical_subject = "player"; speech_act = "statement"
		if main_verb.form == "infinitive": diagnostics.append("INFINITIVE_FOR_FINITE")
		elif main_verb.person != 1: diagnostics.append("AGREEMENT_MISMATCH")
		if subject_index == 1 and main_verb_index == 2: diagnostics.append("WORD_ORDER")
	elif clean_tokens.size() == 1 and clean_tokens[0] in ["danke", "bitte"]:
		intent = "THANKS" if clean_tokens[0] == "danke" else "POLITENESS"; actor = "player"; grammatical_subject = "player"
	else:
		return _clarification_result(text, "INSUFFICIENT_CONTEXT")
	if intent.is_empty(): return _clarification_result(text, "INSUFFICIENT_CONTEXT")
	if diagnostics.has("TYPO_OR_NEAR_FORM"): recovery_required = true
	for code in diagnostics:
		if code in RECOVERY_DIAGNOSTICS: recovery_required = true
	var frame := {"speaker":"player", "subject":grammatical_subject, "grammatical_subject":grammatical_subject,
		"actor":actor,"recipient":recipient,"predicate":intent.to_lower(),"action":"help" if intent in ["OFFER_HELP","REQUEST_HELP","PLAYER_CANNOT_HELP"] else "",
		"object_id":"","polarity":polarity,"modality":"none","speech_act":speech_act,"target_id":"",
		"negation_scope":"predicate" if negative else "","question_type":"",
		"helper":helper,"help_recipient":help_recipient,"experiencer":experiencer,"intent":intent}
	var full_recovery := true
	var grammar_detected := _has_grammar_diagnostic(diagnostics)
	var inferred_fields: Array[String] = []
	for evidence in [{"diagnostics":["OMITTED_SUBJECT", "OMITTED_PRONOUN"],"field":"grammatical_subject"}, {"diagnostics":["OMITTED_COPULA", "INFINITIVE_FOR_FINITE", "MISSING_MODAL", "OMITTED_MODAL"],"field":"finite_verb"}, {"diagnostics":["PRONOUN_CASE"],"field":"pronoun_role"}, {"diagnostics":["AGREEMENT_MISMATCH"],"field":"intended_subject"}, {"diagnostics":["WORD_ORDER"],"field":"clause_structure"}, {"diagnostics":["TYPO_OR_NEAR_FORM"],"field":"normalized_token"}]:
		for diagnostic in evidence.diagnostics:
			if diagnostics.has(diagnostic) and evidence.field not in inferred_fields: inferred_fields.append(evidence.field)
	var result := {"status":"RECOGNIZED","intent":intent,"semantic":intent,"name":name,"ambiguity":[],
		"unsupported_features":[],"diagnostics":diagnostics,"normalized_tokens":canonical_tokens,
		"lexical_readings":_readings(canonical_tokens,name_index),"frame":frame,
		"semantic_recovery_status":"COMPLETE" if full_recovery else "PARTIAL",
		"grammatical_error_detected":grammar_detected,"recovery_used":recovery_required and full_recovery,
		"recovery":{"used":recovery_required and full_recovery,"issues":diagnostics,"explicit_evidence":canonical_tokens,"inferred_fields":inferred_fields}}
	if intent == "ASK_BACK" and context_topic != "player_mood" and name_index < 0: return _clarification_result(text,"INSUFFICIENT_CONTEXT")
	if subject_index == 1 and main_verb_index == 2 and clean_tokens[0] in ["heute", "deutsch", "müde", "mude", "gut"]:
		diagnostics.append("WORD_ORDER")
		grammar_detected = _has_grammar_diagnostic(diagnostics)
		result.diagnostics = diagnostics
		result.grammatical_error_detected = grammar_detected
		result.recovery_used = true
		result.recovery.used = true
	return result

static func _unknown_result(text: String, tokens: Array[String], unknown_tokens: Array[String]) -> Dictionary:
	var diagnostics: Array = []
	for token in unknown_tokens: diagnostics.append({"code":"UNKNOWN_TOKEN","token":token})
	return {"status":"UNKNOWN","intent":"","semantic":"","name":"","ambiguity":[],
		"unsupported_features":[],"unknown_tokens":unknown_tokens,"diagnostics":diagnostics,
		"normalized_tokens":tokens,"lexical_readings":_readings(tokens,-1),"frame":{"subject":"unresolved","grammatical_subject":"unresolved","actor":"","recipient":"","polarity":"unresolved","speech_act":"unresolved"},
		"semantic_recovery_status":"NONE","grammatical_error_detected":false,"recovery_used":false}

static func _recognized_result(intent: String, text: String, actor: String, grammatical_subject: String, recipient: String, polarity: String, speech_act: String) -> Dictionary:
	var frame := {"speaker":"player","subject":grammatical_subject,"grammatical_subject":grammatical_subject,
		"actor":actor,"recipient":recipient,"predicate":intent.to_lower(),"action":"","object_id":"",
		"polarity":polarity,"modality":"none","speech_act":speech_act,"target_id":"","negation_scope":"","question_type":"","intent":intent}
	return {"status":"RECOGNIZED","intent":intent,"semantic":intent,"name":"","ambiguity":[],
		"unsupported_features":[],"diagnostics":[],"normalized_tokens":words(text),"lexical_readings":_readings(words(text),-1),
		"frame":frame,"semantic_recovery_status":"COMPLETE","grammatical_error_detected":false,"recovery_used":false}

static func _has_grammar_diagnostic(diagnostics: Array) -> bool:
	for diagnostic in diagnostics:
		var code := str(diagnostic.get("code", "")) if diagnostic is Dictionary else str(diagnostic)
		if code in RECOVERY_DIAGNOSTICS or code == "OMITTED_PRONOUN": return true
	return false

static func _is_known_token(token: String) -> bool:
	return LEXICON.has(token) or EXTRA_LEXICON.has(token) or VERB_MORPHOLOGY.has(token) or PRONOUN_ROLES.has(token)

static func _expected_pos(tokens: Array[String], index: int) -> String:
	if index > 0 and tokens[index - 1] in ["wie", "was", "warum", "wieso", "bitte", "noch", "einmal", "kann", "kannst", "möchte", "möchtest", "du", "ich", "dir", "mir", "dich", "mich"]: return "verb"
	return ""

static func _normalize_token(token: String, expected_pos: String = "") -> Dictionary:
	var spelling_variants := {"mude":"müde", "spater":"später", "heisse":"heiße", "mochtest":"möchtest", "widerholen":"wiederholen", "weiss":"weiß", "offnen":"öffnen"}
	if spelling_variants.has(token) and _is_known_token(str(spelling_variants[token])):
		return {"token":str(spelling_variants[token]),"corrected":true}
	if _is_known_token(token): return {"token":token,"corrected":false}
	if expected_pos.is_empty(): return {"token":token,"corrected":false}
	var matches_by_lemma := {}
	for candidate in LEXICON.keys() + EXTRA_LEXICON.keys() + VERB_MORPHOLOGY.keys():
		var pos := "verb" if VERB_MORPHOLOGY.has(candidate) else str(_lexicon_data(str(candidate)).get("pos", ""))
		if not expected_pos.is_empty() and pos != expected_pos: continue
		if str(candidate).length() < 3 or token.length() < 3 or not _edit_distance_one(token, str(candidate)): continue
		var lemma_key := str(VERB_MORPHOLOGY.get(candidate, {}).get("lemma", "")) if VERB_MORPHOLOGY.has(candidate) else pos + ":" + str(candidate)
		if not matches_by_lemma.has(lemma_key): matches_by_lemma[lemma_key] = str(candidate)
	if matches_by_lemma.size() == 1:
		return {"token":str(matches_by_lemma.values()[0]),"corrected":true}
	return {"token":token,"corrected":false}

static func _edit_distance_one(left: String, right: String) -> bool:
	if absi(left.length() - right.length()) > 1: return false
	var i := 0; var j := 0; var edits := 0
	while i < left.length() and j < right.length():
		if left.substr(i,1) == right.substr(j,1): i += 1; j += 1; continue
		edits += 1
		if edits > 1: return false
		if i + 1 < left.length() and j + 1 < right.length() and left.substr(i,1) == right.substr(j+1,1) and left.substr(i+1,1) == right.substr(j,1):
			i += 2; j += 2
		elif left.length() > right.length(): i += 1
		elif right.length() > left.length(): j += 1
		else: i += 1; j += 1
	if i < left.length() or j < right.length(): edits += 1
	return edits <= 1

static func _lexicon_data(token: String) -> Dictionary:
	var entry: Array = LEXICON.get(token, EXTRA_LEXICON.get(token, []))
	if entry.is_empty(): return {}
	return {"pos":entry[0],"translation":entry[1] if entry.size() > 1 else ""}

static func _raw_words(text: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}]+")
	for found in regex.search_all(text): result.append(found.get_string())
	return result

static func _readings(tokens: Array[String], name_index: int) -> Array:
	var result: Array = []
	for index in tokens.size():
		var token := tokens[index]
		var reading: Dictionary
		if _is_known_token(token):
			var data := _lexicon_data(token)
			var morphology: Dictionary = VERB_MORPHOLOGY.get(token, {})
			reading = {"lemma_id":str(morphology.get("lemma",token)), "surface":token, "pos":data.get("pos","verb"), "features":morphology, "semantic_id":str(morphology.get("lemma",token)), "availability":"available", "translation":data.get("translation","")}
		elif index == name_index:
			reading = {"lemma_id":"player_name", "surface":token, "pos":"proper_noun", "features":{"person":3}, "semantic_id":"player_name", "availability":"available", "translation":"имя"}
		else:
			continue
		result.append({"token":token,"position":index,"readings":[reading]})
	return result

static func suggestions(prefix: String) -> Array[String]:
	var result: Array[String] = []
	for surface in LEXICON.keys() + EXTRA_LEXICON.keys():
		if str(surface).begins_with(prefix.to_lower()): result.append(surface_for(str(surface)))
	result.sort()
	return result

static func vocabulary_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for surface in LEXICON.keys() + EXTRA_LEXICON.keys():
		var data := _lexicon_data(str(surface))
		result.append({"lemma_id":str(surface), "surface":surface_for(str(surface)), "pos":data.get("pos","word"),
			"features":VERB_MORPHOLOGY.get(surface,{}), "semantic_id":str(surface), "availability":"available"})
	for phrase in PHRASES:
		var phrase_surface := str(phrase)
		phrase_surface = phrase_surface.substr(0, 1).to_upper() + phrase_surface.substr(1)
		result.append({"lemma_id":"phrase_%s" % str(phrase), "surface":phrase_surface, "pos":"phrase",
			"features":{}, "semantic_id":"phrase_%s" % str(phrase), "availability":"available"})
	return result

static func translation_for(surface: String) -> String:
	var phrase := surface.strip_edges().to_lower()
	if PHRASES.has(phrase): return str(PHRASES[phrase])
	var data := _lexicon_data(surface.to_lower())
	return str(data.get("translation", ""))

static func surface_for(surface: String) -> String:
	return {"hallo":"Hallo", "deutsch":"Deutsch", "arbeit":"Arbeit", "hilfe":"Hilfe",
		"tasse":"Tasse", "ahnung":"Ahnung", "tschüss":"Tschüss", "tschuss":"Tschuss",
		"puh":"Puh", "haha":"Haha"}.get(surface, surface)

