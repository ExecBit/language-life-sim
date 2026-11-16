#!/usr/bin/env python3
"""Read/check A0–P2 design-readiness cases against the current scene corpus.

Design cases are *not* player tests: F1 search, route variants, player state,
UI, and parser flexibility require real implementation and playtesting.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from scene_corpus import DOCS, WORD, scene_data
from analyze_semantic_contacts import semantic_data

CASES = DOCS / "ACT_A0_READINESS_CASES.json"
REPORT = DOCS / "ACT_A0_INPUT_READINESS_REPORT.md"
STATUS = {
    "needs_ui_validation", "needs_gameplay_validation", "needs_f1_contract",
    "needs_state_contract", "needs_medium_contract",
}


def a0_readiness_data() -> dict:
    corpus = scene_data()
    source = json.loads(CASES.read_text(encoding="utf-8"))
    sc = {scene["id"]: (day, scene) for day in corpus["days"]
          for scene in day["scenes"]}
    norm = corpus["normalization"]
    forms_to_lemma = norm["form_to_lexeme"]
    excluded = set(norm["excluded"])
    source_events: dict[str, tuple[dict, dict]] = {}
    for _, scene in sc.values():
        for ev in scene["r"] + scene["p"]:
            source_events[ev["id"]] = (scene, ev)

    def words(s: str) -> list[str]:
        return [f.lower() for f in WORD.findall(s)]

    annotation = semantic_data()
    semantic_by_id = {x["event_id"]: x for x in annotation["annotations"]}
    seen_r: set[str] = set()
    days = []
    for day in corpus["days"]:
        present_r: set[str] = set()
        r_words = 0
        for event in day["r"]:
            if not event["required"]:
                continue
            r_words += len(words(event["de"]))
            for form in words(event["de"]):
                if form not in excluded:
                    present_r.add(forms_to_lemma[form])
        new_lemmas = present_r - seen_r
        if day["day"] <= 9:
            marked = [a for a in annotation["annotations"]
                      if a["day"] == day["day"] and a["mode"] == "needed_R"]
            anchored = {w for a in marked for w in a["anchors"]}
            days.append({
                "day": day["day"], "phase": day["phase"],
                "required_r_events": sum(bool(x["required"]) for x in day["r"]),
                "required_p_events": sum(bool(x["required"]) for x in day["p"]),
                "r_words": r_words,
                "r_first_seen_lexemes": len(new_lemmas),
                "audited_needed_r_events": len(marked),
                "audited_needed_r_anchor_types": len(anchored),
                "first_seen_needed_r_anchor_types": len(anchored - seen_r),
            })
        seen_r |= present_r
    cases = []
    used: set[str] = set()
    for item in source["cases"]:
        if item["id"] in used:
            raise ValueError(f"Duplicate A0 case {item['id']}")
        used.add(item["id"])
        if item["assessment"] not in STATUS:
            raise ValueError(f"Unknown A0 risk status {item['assessment']}")
        scene_id = item["scene_id"]
        if scene_id not in sc:
            raise ValueError(f"Unknown A0 scene {scene_id}")
        day, scene = sc[scene_id]
        if day["day"] > 9 or not scene["required"]:
            raise ValueError(f"A0 case outside required P0–P2: {item['id']}")
        r_id, p_id = item["r_event_id"], item["p_event_id"]
        if r_id not in source_events or p_id not in source_events:
            raise ValueError(f"Unknown A0 R/P event {item['id']}")
        r_scene, r_event = source_events[r_id]
        p_scene, p_event = source_events[p_id]
        if r_scene["id"] != scene_id or p_scene["id"] != scene_id:
            raise ValueError(f"Cross-scene R/P event in {item['id']}")
        if not r_event["required"] or r_id not in {x["id"] for x in scene["r"]}:
            raise ValueError(f"Not guaranteed R {item['id']}")
        if p_id not in {x["id"] for x in scene["p"]}:
            raise ValueError(f"Not a P event {item['id']}")
        if not (isinstance(p_event["after_r"], int)
                and 1 <= p_event["after_r"] <= len(scene["r"])):
            raise ValueError(f"Invalid P placement in {item['id']}")
        if not all(item.get(k) and str(item[k]).strip()
                   for k in ("required_meaning", "context_requirement", "acceptance")):
            raise ValueError(f"Unspecified meaning/context/test at {item['id']}")
        r_turn = next(i for i, ev in enumerate(scene["r"], 1)
                      if ev["id"] == r_id)
        cases.append({
            **item, "day": day["day"], "phase": day["phase"],
            "r_text": r_event["de"], "p_example": p_event["example"],
            "p_required": p_event["required"], "p_after_r": p_event["after_r"],
            "r_turn": r_turn, "r_follows_p": r_turn > p_event["after_r"],
            "semantic_r_annotation": semantic_by_id.get(r_id, {}).get("mode", "unassessed"),
            "semantic_p_annotation": semantic_by_id.get(p_id, {}).get("mode", "unassessed"),
        })
    if len(days) != 9:
        raise ValueError("Expected nine provisional A0–P2 slots")
    return {
        "status": source["status"], "scope": source["scope"], "days": days,
        "cases": cases, "risk_counts": dict(Counter(x["assessment"] for x in cases)),
        "reviewed_p": annotation["counts"]["audited_P_events"],
        "reviewed_r": annotation["counts"]["audited_R_events"],
    }


def render_report(a: dict) -> str:
    lines = [
        "# Холодный старт A0 и необходимый Input: проверка проектной доступности",
        "",
        "**Статус: рабочий аудит P0–P2 (D01–D09), НЕ пользовательское тестирование, "
        "НЕ проверка реализованного F1, НЕ доказательство запоминания.** "
        "[Случаи с критериями](ACT_A0_READINESS_CASES.json), "
        "[канонический корпус](ACT_DIALOGUE_SITUATIONS.json), "
        "[смысловые R/P-аннотации](ACT_SEMANTIC_CONTACT_ANNOTATIONS.json).",
        "",
        "## 1. Почему новый текст — не количество выученных слов",
        "",
        "В каждой строке R-лексемы — **впервые встреченные** в обязательном "
        "немецком тексте дня, а «опоры needed_R» — только выборочные лексемы "
        "в аннотированных *кандидатах действительно необходимого понимания*. "
        "Неразмеченная R-строка не объявляется бессмысленной; "
        "R-якоря и впервые увиденные слова пересекаются и не складываются.",
        "",
        "| Слот | Горизонт | Обязат. R строк | R словоупотреблений | Новые R-лексемы | "
        "Аннот. needed_R строк | Разные needed_R опоры | Их опоры впервые в R |",
        "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    for d in a["days"]:
        lines.append(f"| D{d['day']:02} | {d['phase']} | {d['required_r_events']} | "
                     f"{d['r_words']} | {d['r_first_seen_lexemes']} | "
                     f"{d['audited_needed_r_events']} | "
                     f"{d['audited_needed_r_anchor_types']} | "
                     f"{d['first_seen_needed_r_anchor_types']} |")
    lines += [
        "",
        "**Не выводить «прошёл D01 → освоил 24 слова».** Игрок видит даже те "
        "слова, которые не должен уметь объяснить на первом контакте. "
        "Уровни P0–P2 — авторские горизонты, а не реальные дни учёбы.",
        "",
        "## 2. Четырнадцать сценарных проверок",
        "",
        "| Проверка | День | Связанные R/P | Статус | Что нужно проверить |",
        "|---|---|---|---|---|",
    ]
    for item in a["cases"]:
        lines.append(
            f"| \`{item['id']}\` | D{item['day']:02} | "
            f"\`{item['r_event_id']}\` → \`{item['p_event_id']}\` | "
            f"\`{item['assessment']}\` | {item['acceptance']} |"
        )
    lines += [
        "",
        "**Порядок событий:** связанные R/P не обязательно следуют по стрелке: "
        "иногда указанная R-реплика является **ответом после P**. "
        "Это определяется номером R и полем `after_r` у P.",
        "",
        "## 3. Приоритетные решения и открытые зависимости",
        "",
        "### P0 · D01: обязательные решения исправлены, UI неизвестен",
        "",
        "- Первое приветствие теперь допускает короткий ответ на приветствие. "
        "Это допустимая **имитация для старта**, но не проверка усвоения.",
        "- Просьба повторить \`Noch einmal, bitte\` доступна после непонятной "
        "инструкции, однако **не обязательна**, если игрок всё понял; "
        "несколько P-ответов могут быть доступны на одной стадии.",
        "- В \`D01-S2\` слово \`Arzt\` видно на табличке **без стрелки**, "
        "\`Wo ist der Arzt?\` возникает до ответа Лены \`Der Arzt ist dort.\`. "
        "Важный риск — умеет ли новичок найти \`wo\` по русскому «где» в F1. "
        "**Наличие словаря «всего акта» не доказывает наличие обратного поиска.**",
        "- \`Nein, nicht dort\` и \`Nimm den Schlüssel\` нельзя засчитывать "
        "как понимание, если правильный путь или предмет выделены визуально.",
        "",
        "### P1 · D02–D05: независимость смысла и состояния",
        "",
        "- \`Bist du müde?\` и \`Hast du Schmerzen?\` требуют знания "
        "**состояния персонажа**, а не только словаря. Нельзя заставлять "
        "игрока сообщать «не больно», если игра не сообщает об этом.",
        "- В \`D05-S1\` местоположение лампы больше **не известно до вопроса**: "
        "R3 обозначает потребность, P1 спрашивает где, R4 сообщает \`im Zimmer\`.",
        "- В D03 различать воду и хлеб имеет смысл по цели героя; "
        "если UI подсказывает нужное немецкое слово, это перестаёт быть "
        "проверкой самостоятельной просьбы.",
        "",
        "### P2 · D06–D09: отделить грамотную реакцию от угадывания",
        "",
        "- D06: закрытая правая дверь сама по себе может выдать правильный "
        "маршрут, даже без понимания \`links\`/ \`rechts\`. Нужен вариант, "
        "где маршруты до прочтения остаются правдоподобны; иначе считать "
        "этот R-контакт **фоновым**, а не необходимым.",
        "- D07: порядок \`R5 → P2 → R6\` сохраняет действительный вопрос "
        "о местоположении снабженца. Для A0 нужен способ обнаружить "
        "составное слово \`Lagerverwalter\` в F1.",
        "- D08: \`Hörst du mich?\` — фраза из устного канала в игре "
        "с письменным общением. Допустима как реалистичная реплика, "
        "если не требует аудирования и не служит обязательной R-проверкой.",
        "- D09: три лампы/одна неисправна/две исправны — проверка "
        "числа и статуса только тогда, когда нет русского автоматического "
        "пересчёта и правильного подсвеченного слота.",
        "",
        "### Общий контракт F1 перед реальной проверкой",
        "",
        "1. **Поиск от нужного смысла:** как A0 получает немецкие \`wo\`, "
        "\`Arzt\`, \`Schlüssel\` и другие значения без знания немецкого написания? "
        "Нужна навигация по родному значению или иная доказуемо доступная "
        "модель, а не просто список немецких лемм.",
        "2. **Показ нужных форм:** \`nimm\` / \`nehmen\`, \`brauche\` / \`brauchen\` "
        "и краткие типовые ответы доступны для понимания без готовой "
        "сценарной фразы, которую можно механически копировать.",
        "3. **Повтор и непонимание:** F1 и повтор реплики доступны "
        "в любой критический момент, не блокируют прогресс и не считают "
        "помощь признаком усвоения.",
        "4. **Контрфакты:** подмена объекта, отрицания, направления, "
        "адресата или состояния меняет правильное действие. Визуальные "
        "подсказки не должны самостоятельно выдавать ответ.",
        "5. **Состояние и последствия:** игроку действительно доступен "
        "факт собственного самочувствия, расположения предмета и локального "
        "показания; система не ждёт знание, которого нельзя получить.",
        "",
        "## 4. Вывод и статус",
        "",
        "- **Структурные дефекты D01/D05 исправлены**: необязательное уточнение, "
        "ответ на вопрос после самого вопроса.",
        "- **M05 (попросить повторить) остаётся целевым продуктивным навыком**. "
        "В D01 уточнение теперь факультативно, но в D15 есть обязательное "
        "`D15-S2-P2` (`Ich verstehe nicht. Noch einmal, bitte.`). "
        "**Пробел не в отсутствии обязательного P-события, а в отсутствии "
        "естественной причины для непонимания:** поздний ответ предписан "
        "сценарием. Нужна независимая проверка, что игрок сам выбирает "
        "уточнение при реальной потребности.",
        "- **14 контрфактических и интерфейсных проверок описаны, "
        "но не выполнены в запущенной игре.** Поэтому нельзя отметить P0–P2 "
        "как «доступно абсолютному A0» или назначить число дней.",
        "- На текущем этапе блокируют **утверждение** программы: "
        "обратная доступность F1, обоснованность состояния D02, "
        "необходимость R при визуально очевидном маршруте D06, "
        "варианты ошибок и повторения. Блокирующие зависимости не равны "
        "обязательным изменениям сюжета.",
        "- Дальнейший шаг по LP09: проверить настоящие переходы/действия "
        "и минимальные варианты ответов при A0, затем LP10 — трассировка "
        "M## / G## / LO##. Никакой механической нормы «новых слов/день» "
        "пока не устанавливать.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    new_report = render_report(a0_readiness_data())
    if args.check:
        if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != new_report:
            print("A0 readiness report is stale.", file=sys.stderr)
            return 1
        print("A0 readiness report is current.")
        return 0
    if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != new_report:
        REPORT.write_text(new_report, encoding="utf-8")
    print("A0 readiness report generated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
