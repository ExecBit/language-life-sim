extends RefCounted

static func build() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"id":"a_door","phase":"A","speaker":"lena","to":"player","text":"Hallo!","wait":"near","target":"entrance","ops":[["flag","door_open",true]]},
		{"id":"a_greeting","phase":"A","speaker":"lena","to":"player","text":"Hallo!","units":["hallo"],"answers":[{"id":"hello","text":"Hallo!"}]},
		{"id":"a_enter","phase":"A","speaker":"lena","to":"player","text":"Komm!","wait":"near","target":"common","point":"common","help":true,"units":["komm"]},
		{"id":"b_water","phase":"B","speaker":"lena","to":"player","text":"Wasser?","point":"cup","answers":[{"id":"yes","text":"Ja.","ops":[["move","cup","tray","player"]]},{"id":"no","text":"Nein."}]},
		{"id":"c_follow","phase":"C","speaker":"lena","to":"player","text":"Komm!","wait":"near","target":"bedroom","point":"bedroom","help":true},
		{"id":"c_bag","phase":"C","speaker":"lena","to":"player","text":"Hier.","wait":"stored","item":"bag","anchor":"bag_stand","point":"bag_stand","help":true,"units":["hier"]},
		{"id":"c_key","phase":"C","speaker":"lena","to":"player","text":"Nimm!","wait":"owned","item":"room_key","point":"room_key","help":true,"units":["nimm"],"ops":[["move","room_key","lena","key_tray"]]},
		{"id":"c_welcome","phase":"D","speaker":"lena","to":"player","text":"Bitte.","units":["bitte"],"wait":"optional"},
		{"id":"f_arrival","phase":"F","speaker":"lena","to":"player","text":"","wait":"cooking"},
		{"id":"f_offer","phase":"F","speaker":"lena","to":"player","text":"Kannst du mir helfen?","point":"bread","help":true,"answers":[{"id":"yes","text":"Ja.","ops":[["flag","breakfast_choice","yes"]]},{"id":"no","text":"Nein.","ops":[["flag","breakfast_choice","no"]],"next_id":"f_self_walk"}]},
		{"id":"f_take","phase":"F","speaker":"lena","to":"player","text":"Nimm das Brot, bitte.","wait":"owned","item":"bread","point":"bread","help":true,"units":["nimm","brot"]},
		{"id":"f_give","phase":"F","speaker":"lena","to":"player","text":"Gib es mir, bitte.","wait":"give","item":"bread","actor":"lena","point":"lena","help":true,"units":["gib"]},
		{"id":"f_place","phase":"F","speaker":"lena","to":"player","text":"Danke!","wait":"npc_place","units":["danke"],"result":"helped","next_id":"g_ready"},
		{"id":"f_self_walk","phase":"F","speaker":"lena","to":"player","text":"Okay.","wait":"npc_take","next_id":"f_self_return"},
		{"id":"f_self_return","phase":"F","speaker":"lena","to":"player","text":"","wait":"npc_place","result":"declined","next_id":"g_ready"},
		{"id":"g_ready","phase":"G","speaker":"lena","to":"player","text":"","wait":"sleep_end","target":"bed"},
		{"id":"complete","phase":"END","speaker":"","to":"player","text":"","wait":"done","ops":[["finish"]]},
	]
	var indices := {}
	for i in rows.size(): indices[rows[i].id] = i
	for row in rows:
		if row.has("next_id"): row.next = indices[row.next_id]
		for answer in row.get("answers",[]):
			if answer.has("next_id"): answer.next = indices[answer.next_id]
	return rows
