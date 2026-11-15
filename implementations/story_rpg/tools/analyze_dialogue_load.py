#!/usr/bin/env python3
"""Validate authored R/P reference contacts and regenerate their pilot load report.

Run:
  python implementations/story_rpg/tools/analyze_dialogue_load.py
  python implementations/story_rpg/tools/analyze_dialogue_load.py --check

The reference corpus is a small authored sample, NOT final in-game dialogue.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CORPUS = DOCS / "ACT_DIALOGUE_REFERENCE_CORPUS.json"
LEXICON = DOCS / "LANGUAGE_LEXICON.md"
REPORT = DOCS / "ACT_DIALOGUE_PILOT_REPORT.md"

WORD = re.compile(r"[^\W_]+", re.UNICODE)


def words(text: str) -> int:
    return len(WORD.findall(text))


def group_names() -> dict[str, str]:
    names = {}
    for line in LEXICON.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\|\s*(\d{1,2})\s*\|", line)
        if match:
            cells = [part.strip() for part in line.split("|")[1:-1]]
            if len(cells) >= 3:
                names[f"{int(match.group(1)):02}"] = cells[2]
    if set(names) != {f"{n:02}" for n in range(1, 30)}:
        raise ValueError(f"Expected 29 lexical groups, got {len(names)}")
    return names


def analyze(data: dict) -> dict:
    days = data["days"]
    if data.get("exam_day") != 22 or [d["day"] for d in days] != list(range(1, 22)):
        raise ValueError("Expected D01-D21 reference practice; D22 is an exam, not practice.")
    group_stats = defaultdict(lambda: {"r": 0, "p": 0, "r_days": set(), "p_days": set(), "contexts": set()})
    seen_ids = set()
    day_stats = []
    totals = Counter()
    for day in days:
        day_num = day["day"]
        day_row = {"day": day_num, "r_events": 0, "r_words": 0, "r_marked": 0,
                   "p_dialog": 0, "p_form": 0, "p_slots": 0, "p_optional": 0}
        if not day["r"]:
            raise ValueError(f"D{day_num:02} has no R sample.")
        for event in day["r"]:
            identifier = event["id"]
            if identifier in seen_ids:
                raise ValueError(f"Duplicate event ID {identifier}")
            seen_ids.add(identifier)
            if not identifier.startswith(f"D{day_num:02}-R"):
                raise ValueError(f"Malformed R ID {identifier}")
            text = event["de"]
            day_row["r_events"] += 1
            day_row["r_words"] += words(text)
            occupied = []
            for tag in event["tags"]:
                group = tag["group"]
                form = tag["form"]
                if group not in group_names_cached:
                    raise ValueError(f"Unknown group {group} in {identifier}")
                pattern = re.compile(r"(?<!\w)" + re.escape(form) + r"(?!\w)", re.IGNORECASE)
                match = pattern.search(text)
                if not match:
                    raise ValueError(f"{identifier}: tag {form!r} is absent from German text")
                if any(match.start() < end and match.end() > start for start, end in occupied):
                    raise ValueError(f"{identifier}: overlapping tags")
                occupied.append(match.span())
                count = words(form)
                day_row["r_marked"] += count
                stat = group_stats[group]
                stat["r"] += count
                stat["r_days"].add(day_num)
                stat["contexts"].add(event["context"])
            if day_row["r_marked"] > day_row["r_words"]:
                raise ValueError(f"Too many tagged words on D{day_num:02}")
        for event in day["p"]:
            identifier = event["id"]
            if identifier in seen_ids:
                raise ValueError(f"Duplicate event ID {identifier}")
            seen_ids.add(identifier)
            if not identifier.startswith(f"D{day_num:02}-P"):
                raise ValueError(f"Malformed P ID {identifier}")
            if event["kind"] not in ("dialog", "form"):
                raise ValueError(f"Unknown P kind in {identifier}")
            if not event["slots"]:
                raise ValueError(f"No semantic slots in {identifier}")
            if not event["required"]:
                day_row["p_optional"] += 1
                continue
            day_row["p_" + event["kind"]] += 1
            for slot in event["slots"]:
                group = slot["group"]
                if group not in group_names_cached:
                    raise ValueError(f"Unknown group {group} in {identifier}")
                day_row["p_slots"] += 1
                stat = group_stats[group]
                stat["p"] += 1
                stat["p_days"].add(day_num)
                stat["contexts"].add(event["context"])
        day_stats.append(day_row)
        totals.update({k: day_row[k] for k in ("r_events", "r_words", "r_marked", "p_dialog", "p_form", "p_slots", "p_optional")})
    return {"days": day_stats, "totals": totals, "groups": group_stats}


def render(data: dict, a: dict, names: dict[str, str]) -> str:
    t = a["totals"]
    lines = [
        "# Пробная нагрузка немецкого по 21 дню",
        "",
        "**Статус: расчёт v0.1 на авторских коротких примерах, не оценка полного акта или достаточности закрепления.** "
        "Источник: [ACT_DIALOGUE_REFERENCE_CORPUS.json](ACT_DIALOGUE_REFERENCE_CORPUS.json). "
        "Расчёт: \`python implementations/story_rpg/tools/analyze_dialogue_load.py\`. "
        "**D22 — экзамен, не подготовительная практика.**",
        "",
        f"**Пилот:** дневных слотов: {len(data['days'])}; R-сообщений: {t['r_events']}; "
        f"немецких словоупотреблений: {t['r_words']}; тематически размеченных: {t['r_marked']}; "
        f"обязательных P-ходов (свободный ввод): {t['p_dialog']}; заполнений формы: {t['p_form']}; "
        f"смысловых P-слотов: {t['p_slots']}; необязательных P-возможностей: {t['p_optional']}.",
        "",
        "Важно: **R-доля — процент только вручную размеченных тематических слов (не всего немецкого текста); "
        "P-доля — процент обязательных смысловых слотов (не введённых игроком слов)**. "
        "Неразмеченные универсальные слова не раздаются темам произвольно. "
        "Групповые проценты R и P имеют **разные знаменатели** и не сравниваются как равные единицы усилия.",
        "",
        "## 1. Нагрузка по дням",
        "",
        "| День | R-сообщения | R-слова | R-размеченные | P-диалог | P-форма | P-слоты | P-доп. |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for d in a["days"]:
        lines.append(f"| D{d['day']:02} | {d['r_events']} | {d['r_words']} | {d['r_marked']} | "
                     f"{d['p_dialog']} | {d['p_form']} | {d['p_slots']} | {d['p_optional']} |")
    lines += [
        "",
        "## 2. Тематический удельный вес пилотного корпуса",
        "",
        "| Группа | Тема | R-размеченные | R-доля | P-слоты | P-доля | Дни R/P |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    absent = []
    for g in sorted(names):
        stat = a["groups"].get(g)
        r = stat["r"] if stat else 0
        p = stat["p"] if stat else 0
        if not (r or p):
            absent.append(g)
        days = sorted((stat["r_days"] | stat["p_days"]) if stat else ())
        rpct = r / t["r_marked"] * 100 if t["r_marked"] else 0
        ppct = p / t["p_slots"] * 100 if t["p_slots"] else 0
        lines.append(f"| {g} | {names[g]} | {r} | {rpct:.1f}% | {p} | {ppct:.1f}% | "
                     f"{', '.join(f'D{d:02}' for d in days) or '—'} |")
    lines += [
        "",
        f"**Группы без контактов в этом пробном минимуме:** {', '.join(absent) or 'нет'}. "
        "Отсутствие в пилоте **не** доказывает, что темы надо превратить в обязательные сюжетные квесты.",
        "",
        "## 3. Пограничные группы",
        "",
        "| Группа | Первая R-встреча | Обязательные P-дни | Контексты P | Вывод |",
        "|---|---|---|---|---|",
    ]
    for g in ("28", "29"):
        first_r = sorted(a["groups"][g]["r_days"])
        p_days = sorted(a["groups"][g]["p_days"])
        contexts = sorted({e["context"] for d in data["days"] for e in d["p"]
                           if e["required"] and any(slot["group"] == g for slot in e["slots"])})
        lines.append(f"| {g} | {f'D{first_r[0]:02}' if first_r else '—'} | "
                     f"{', '.join(f'D{n:02}' for n in p_days) or '—'} | "
                     f"{', '.join(contexts) or '—'} | "
                     "Пробные возвраты есть, но реальная достаточность практики и доступность A0 не проверены |")
    lines += [
        "",
        "## 4. Конкретные R/P-контракты (авторские образцы, не строки whitelist)",
        "",
    ]
    for d in data["days"]:
        lines += [f"### D{d['day']:02} — {d['goal']}", ""]
        for event in d["r"]:
            lines.append(f"- **{event['id']} / R**: \`{event['de']}\` — {event['need']}. "
                         f"Контраст: {event['contrast']}.")
        for event in d["p"]:
            modality = "форма" if event["kind"] == "form" else "свободный ввод"
            required = "обязательно" if event["required"] else "необязательно"
            lines.append(f"- **{event['id']} / P, {modality}, {required}**: {event['goal']}. "
                         f"Пример: \`{event['example']}\`. "
                         f"Слоты: {', '.join(slot['meaning'] for slot in event['slots'])}. "
                         f"Контраст: {event['contrast']}.")
        lines.append("")
    lines += [
        "## 5. Границы интерпретации",
        "",
        "- Это **минимальные авторские примеры**, а не полный сценарий NPC, не фактически прочитанный игроком корпус и не реальные данные прохождения.",
        "- Разметка R задаёт лишь выбранные *тематические* словоупотребления, остальные слова учитываются в общем объёме без принудительного тематического тега. P измеряет необходимые смыслы, а **не размер свободного ответа игрока**.",
        "- R- и P-потребности надо проверить на абсолютном A0: ключевой смысл не может выдаваться русским UI или очевидностью единственного действия; F1 доступна, но не подставляет готовую фразу.",
        "- До внедрения конкретных сцен подтвердить, что \`Lampe\`, \`Sensor\`, \`prüfen/geprüft\`, \`Biologe\`, \`Liste\` и другие нужные предметные слова и формы действительно представлены в F1; текущий лексический каталог — опорный, не полный F1.",
        "- Данные ранних R-контактов с жильём/помещениями (до P2) и с рабочими списками (до P4) требуется сверить с предполагаемым порядком знакомства с лексикой; **привязка тематической группы к горизонту не жёсткая блокировка чтения**, но не должна создавать неподготовленную обязательную P-продукцию.",
        "- **D17:** игрок наблюдает конфликт биолога и снабженца. Высказывание собственного мнения помечено дополнительным, поскольку заставлять героя вмешиваться в сцену нельзя.",
        "- **D16:** самостоятельное заполнение полей — отдельная форма P и не засчитывается как свободный текстовый диалог.",
        "- **D22:** ни один итоговый ответ не используется как доказательство того, что новый материал был заранее закреплён.",
        "- Чтобы решать вопрос о длине акта, после проверки образцов необходимо добавить полноценные реплики, альтернативные обязательные ветви, разные контексты и смысловые возвраты, а затем повторить расчёт.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify generated report and corpus semantics.")
    args = parser.parse_args()
    data = json.loads(CORPUS.read_text(encoding="utf-8"))
    global group_names_cached
    group_names_cached = group_names()
    report = render(data, analyze(data), group_names_cached)
    if args.check:
        if not REPORT.is_file() or REPORT.read_text(encoding="utf-8") != report:
            print("Dialogue pilot report is stale; regenerate it.", file=sys.stderr)
            return 1
        print("Dialogue corpus validates and report is current.")
        return 0
    if not REPORT.is_file() or REPORT.read_text(encoding="utf-8") != report:
        REPORT.write_text(report, encoding="utf-8")
        print(f"Updated {REPORT}")
    else:
        print("Dialogue pilot report already current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
