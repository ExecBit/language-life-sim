extends RefCounted
## Translations are only rendered by the on-demand note, never by the composer.
const BASE := [
	["hallo","Hallo","Привет / здравствуйте"], ["tschuss","Tschüss","Пока / до свидания"],
	["ja","Ja","Да"], ["nein","Nein","Нет"], ["danke","Danke","Спасибо"],
	["bitte","Bitte","Пожалуйста / не за что"], ["entschuldigung","Entschuldigung","Извините"],
	["komm","Komm","Иди сюда / пойдём"], ["nimm","Nimm","Возьми"], ["gib","Gib","Дай / передай"],
	["hier","Hier","Здесь / сюда"], ["was_ist_das","Was ist das?","Что это?"],
	["wo_ist","Wo ist …?","Где находится …?"], ["ich_verstehe_nicht","Ich verstehe nicht","Я не понимаю"],
	["noch_einmal","Noch einmal, bitte","Ещё раз, пожалуйста"]
]
const NEW := {
	"water":["Wasser","Вода"],"cup":["Tasse","Чашка"],"key":["Schlüssel","Ключ"],
	"bag":["Tasche","Сумка"],"room":["Zimmer","Комната"],"bread":["Brot","Хлеб"],
	"bell":["Glocke","Колокольчик"],"market":["Supermarkt","Супермаркет"]}

static func rows(flags: Dictionary) -> Array:
	var result := BASE.duplicate(true)
	for id in NEW:
		if flags.get("comm_seen_"+id,false): result.append([id,NEW[id][0],NEW[id][1]])
	return result
