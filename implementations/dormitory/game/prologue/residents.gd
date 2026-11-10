extends RefCounted
## Scenario vocabulary and actor knowledge, shared by physical pointing and speech resolution.
const OBJECTS := {"key":"room_key","bag":"bag","cup":"cup","water":"bottle","bread":"bread","bell":"bell","room":"bedroom","door":"room_door","lamp":"room_lamp"}
const SEMANTICS := {"room_key":"key","bag":"bag","cup":"cup","bottle":"water","bread":"bread","bell":"bell","bedroom":"room","room_door":"door","room_lamp":"lamp"}
const IDENTIFY := {"room_key":"Ein Schlüssel.","bag":"Eine Tasche.","cup":"Eine Tasse.","bottle":"Wasser.","bread":"Brot.","bell":"Eine Glocke.","bedroom":"Dein Zimmer.","room_door":"Eine Tür.","room_lamp":"Eine Lampe."}
const PEOPLE := {
	"lena":{"name":"Лена","greeting":"Hallo!","known":["room_key","bag","cup","bottle","bread","bell","bedroom","room_door","room_lamp"]},
	"anna":{"name":"Анна","greeting":"Hallo! Ich bin Anna.","known":["cup","bottle","bread","bell"]},
}
