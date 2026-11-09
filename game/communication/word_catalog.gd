extends RefCounted
## Single source of lexical readings for the parser and prefix composer.
const ENTRIES := [
	{"lemma_id":"lamp","surface":"Lampe","pos":"noun","features":{"gender":"feminine"},"semantic_id":"lamp","availability":"available"},
	{"lemma_id": "ich", "surface": "ich", "pos": "pronoun", "features": {"person": 1, "number": "singular", "case": "nominative"}, "semantic_id": "player", "availability": "available"},
	{"lemma_id": "du", "surface": "du", "pos": "pronoun", "features": {"person": 2, "number": "singular", "case": "nominative"}, "semantic_id": "addressee", "availability": "available"},
	{"lemma_id": "ich", "surface": "mir", "pos": "pronoun", "features": {"person": 1, "case": "dative"}, "semantic_id": "player", "availability": "available"},
	{"lemma_id": "du", "surface": "dir", "pos": "pronoun", "features": {"person": 2, "case": "dative"}, "semantic_id": "addressee", "availability": "available"},
	{"lemma_id": "anna", "surface": "Anna", "pos": "proper_noun", "features": {"person": 3, "number": "singular"}, "semantic_id": "anna", "availability": "available"},
	{"lemma_id": "wollen", "surface": "will", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "want", "persons": [1, 3]}, "semantic_id": "want", "availability": "available"},
	{"lemma_id": "wollen", "surface": "willst", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "want", "persons": [2]}, "semantic_id": "want", "availability": "available"},
	{"lemma_id": "wollen", "surface": "wollen", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "want"}, "semantic_id": "want", "availability": "available"},
	{"lemma_id": "brauchen", "surface": "brauche", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "need", "persons": [1]}, "semantic_id": "need", "availability": "available"},
	{"lemma_id": "brauchen", "surface": "brauchst", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "need", "persons": [2]}, "semantic_id": "need", "availability": "available"},
	{"lemma_id": "brauchen", "surface": "brauchen", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "need"}, "semantic_id": "need", "availability": "available"},
	{"lemma_id": "können", "surface": "kann", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "can", "persons": [1, 3]}, "semantic_id": "can", "availability": "available"},
	{"lemma_id": "können", "surface": "kannst", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "can", "persons": [2]}, "semantic_id": "can", "availability": "available"},
	{"lemma_id": "können", "surface": "können", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "can"}, "semantic_id": "can", "availability": "available"},
	{"lemma_id": "haben", "surface": "habe", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [1]}, "semantic_id": "have", "availability": "available"},
	{"lemma_id": "haben", "surface": "hast", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [2]}, "semantic_id": "have", "availability": "available"},
	{"lemma_id": "haben", "surface": "hat", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [3]}, "semantic_id": "have", "availability": "available"},
	{"lemma_id": "sein", "surface": "ist", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [3]}, "semantic_id": "be", "availability": "available"},
	{"lemma_id": "öffnen", "surface": "öffnen", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "none"}, "semantic_id": "open", "availability": "available"},
	{"lemma_id": "öffnen", "surface": "öffne", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [1]}, "semantic_id": "open", "availability": "available"},
	{"lemma_id": "öffnen", "surface": "öffnet", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [3]}, "semantic_id": "open", "availability": "available"},
	{"lemma_id": "geben", "surface": "geben", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "none"}, "semantic_id": "give", "availability": "available"},
	{"lemma_id": "geben", "surface": "gib", "pos": "verb", "features": {"verb_form": "imperative", "number": "singular", "modality": "none", "persons": [2]}, "semantic_id": "give", "availability": "available"},
	{"lemma_id": "helfen", "surface": "helfen", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "none"}, "semantic_id": "help", "availability": "available"},
	{"lemma_id": "helfen", "surface": "hilf", "pos": "verb", "features": {"verb_form": "imperative", "number": "singular", "modality": "none", "persons": [2]}, "semantic_id": "help", "availability": "available"},
	{"lemma_id": "wissen", "surface": "wissen", "pos": "verb", "features": {"verb_form": "infinitive", "modality": "none"}, "semantic_id": "know", "availability": "available"},
	{"lemma_id": "wissen", "surface": "weiß", "pos": "verb", "features": {"verb_form": "finite", "number": "singular", "modality": "none", "persons": [1, 3]}, "semantic_id": "know", "availability": "available"},
	{"lemma_id": "öffnen", "surface": "öffne", "pos": "verb", "features": {"verb_form": "imperative", "number": "singular", "persons": [2]}, "semantic_id": "open", "availability": "available"},
	{"lemma_id": "key", "surface": "Schlüssel", "pos": "noun", "features": {"gender": "masculine", "number": "singular"}, "semantic_id": "key", "availability": "available"},
	{"lemma_id": "door", "surface": "Tür", "pos": "noun", "features": {"gender": "feminine", "number": "singular"}, "semantic_id": "door", "availability": "available"},
	{"lemma_id": "room", "surface": "Zimmer", "pos": "noun", "features": {"gender": "neuter", "number": "singular"}, "semantic_id": "room", "availability": "available"},
	{"lemma_id": "definite_article", "surface": "der", "pos": "determiner", "features": {"cases": ["nominative", "dative", "genitive"]}, "semantic_id": "article", "availability": "available"},
	{"lemma_id": "definite_article", "surface": "die", "pos": "determiner", "features": {"cases": ["nominative", "accusative"]}, "semantic_id": "article", "availability": "available"},
	{"lemma_id": "definite_article", "surface": "den", "pos": "determiner", "features": {"cases": ["accusative", "dative"]}, "semantic_id": "article", "availability": "available"},
	{"lemma_id": "definite_article", "surface": "das", "pos": "determiner", "features": {"cases": ["nominative", "accusative"]}, "semantic_id": "article", "availability": "available"},
	{"lemma_id": "indefinite_article", "surface": "ein", "pos": "determiner", "features": {"genders": ["masculine", "neuter"]}, "semantic_id": "article", "availability": "available"},
	{"lemma_id": "indefinite_article", "surface": "eine", "pos": "determiner", "features": {"gender": "feminine"}, "semantic_id": "article", "availability": "available"},
	{"lemma_id": "kein", "surface": "kein", "pos": "determiner", "features": {"negative": true, "genders": ["masculine", "neuter"]}, "semantic_id": "no", "availability": "available"},
	{"lemma_id": "kein", "surface": "keinen", "pos": "determiner", "features": {"negative": true, "case": "accusative"}, "semantic_id": "no", "availability": "available"},
	{"lemma_id": "kein", "surface": "keine", "pos": "determiner", "features": {"negative": true, "gender": "feminine"}, "semantic_id": "no", "availability": "available"},
	{"lemma_id": "das", "surface": "das", "pos": "pronoun", "features": {"pronoun_type": "demonstrative"}, "semantic_id": "reference", "availability": "available"},
	{"lemma_id": "nicht", "surface": "nicht", "pos": "negation", "features": {}, "semantic_id": "not", "availability": "available"},
	{"lemma_id": "wo", "surface": "wo", "pos": "interrogative", "features": {}, "semantic_id": "where", "availability": "available"},
	{"lemma_id": "warum", "surface": "warum", "pos": "interrogative", "features": {}, "semantic_id": "why", "availability": "available"},
	{"lemma_id": "was", "surface": "was", "pos": "interrogative", "features": {}, "semantic_id": "what", "availability": "available"},
	{"lemma_id": "bitte", "surface": "bitte", "pos": "politeness", "features": {}, "semantic_id": "please", "availability": "available"},
	{"lemma_id": "zu", "surface": "zu", "pos": "particle", "features": {}, "semantic_id": "closed", "availability": "available"},
	{"lemma_id": "ja", "surface": "ja", "pos": "response", "features": {}, "semantic_id": "accept", "availability": "available"},
	{"lemma_id": "nein", "surface": "nein", "pos": "response", "features": {}, "semantic_id": "refuse", "availability": "available"},
	{"lemma_id": "danke", "surface": "danke", "pos": "social", "features": {}, "semantic_id": "thanks", "availability": "available"},
	{"lemma_id": "hallo", "surface": "Hallo", "pos": "social", "features": {}, "semantic_id": "greeting", "availability": "available"},
	{"lemma_id": "dass", "surface": "dass", "pos": "conjunction", "features": {}, "semantic_id": "subordinate", "availability": "available"},
	{"lemma_id": "weil", "surface": "weil", "pos": "conjunction", "features": {}, "semantic_id": "subordinate", "availability": "available"},
	{"lemma_id": "hier", "surface": "hier", "pos": "adverb", "features": {}, "semantic_id": "here", "availability": "available"},
	{"lemma_id": "später", "surface": "später", "pos": "adverb", "features": {}, "semantic_id": "later", "availability": "available"},
	{"lemma_id": "lena", "surface": "Lena", "pos": "proper_noun", "features": {"person": 3}, "semantic_id": "lena", "availability": "available"},
	{"lemma_id": "tschüss", "surface": "Tschüss", "pos": "social", "features": {}, "semantic_id": "farewell", "availability": "available"},
	{"lemma_id": "entschuldigung", "surface": "Entschuldigung", "pos": "social", "features": {}, "semantic_id": "apology", "availability": "available"},
	{"lemma_id": "verstehen", "surface": "verstehe", "pos": "verb", "features": {"persons": [1], "verb_form": "finite"}, "semantic_id": "understand", "availability": "available"},
	{"lemma_id": "noch", "surface": "noch", "pos": "adverb", "features": {}, "semantic_id": "again", "availability": "available"},
	{"lemma_id": "einmal", "surface": "einmal", "pos": "adverb", "features": {}, "semantic_id": "once", "availability": "available"},
	{"lemma_id": "komm", "surface": "Komm", "pos": "verb", "features": {"persons": [2], "verb_form": "imperative"}, "semantic_id": "approach", "availability": "available"},
	{"lemma_id": "nimm", "surface": "Nimm", "pos": "verb", "features": {"persons": [2], "verb_form": "imperative"}, "semantic_id": "take", "availability": "available"},
	{"lemma_id": "water", "surface": "Wasser", "pos": "noun", "features": {}, "semantic_id": "water", "availability": "available"},
	{"lemma_id": "cup", "surface": "Tasse", "pos": "noun", "features": {}, "semantic_id": "cup", "availability": "available"},
	{"lemma_id": "bag", "surface": "Tasche", "pos": "noun", "features": {}, "semantic_id": "bag", "availability": "available"},
	{"lemma_id": "bread", "surface": "Brot", "pos": "noun", "features": {}, "semantic_id": "bread", "availability": "available"},
	{"lemma_id": "bell", "surface": "Glocke", "pos": "noun", "features": {}, "semantic_id": "bell", "availability": "available"},
	{"lemma_id": "market", "surface": "Supermarkt", "pos": "noun", "features": {}, "semantic_id": "market", "availability": "available"},
	{"lemma_id": "mein", "surface": "mein", "pos": "determiner", "features": {}, "semantic_id": "possessive", "availability": "available"},
	{"lemma_id": "mein", "surface": "meine", "pos": "determiner", "features": {}, "semantic_id": "possessive", "availability": "available"}
]

static func available_for_input(surface: String) -> bool:
	for entry in lookup(surface):
		if entry.availability == "available": return true
	return false

static func lookup(surface: String) -> Array:
	var result: Array = []
	for entry in ENTRIES:
		if entry.surface.to_lower() == surface.to_lower(): result.append(entry.duplicate(true))
	return result

static func suggestions(prefix: String) -> Array[String]:
	var result: Array[String] = []
	for entry in ENTRIES:
		if entry.availability == "available" and entry.surface.to_lower().begins_with(prefix.to_lower()) and entry.surface not in result:
			result.append(entry.surface)
	result.sort()
	return result
