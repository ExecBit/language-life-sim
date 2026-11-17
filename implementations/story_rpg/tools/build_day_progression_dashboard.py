#!/usr/bin/env python3
"""Build the current language dashboard. Story archives are retained in Git only."""
from __future__ import annotations
import argparse
import html as html_stdlib
import json
import re
import sys
from pathlib import Path
DOCS = Path(__file__).resolve().parents[1] / "docs"
DASHBOARD = DOCS / "ACT_DAY_PROGRESSION_DASHBOARD.html"

def independent_duration_html() -> str:
    """Only this section reads the cumulative curriculum; story DATA is unchanged."""
    plan = json.loads((DOCS / "LANGUAGE_DAY_SCHEDULE.json").read_text(encoding="utf-8"))
    items = plan["learning_items"]
    esc = lambda v: html_stdlib.escape(str(v), quote=True)
    def row(vals, header=False):
        tag = "th" if header else "td"
        return "<tr>" + "".join(f"<{tag}>{esc(v)}</{tag}>" for v in vals) + "</tr>"
    def table(headers, rows):
        return '<div class="heatwrap"><table class="load-table"><thead>' + row(headers, True) + '</thead><tbody>' + ''.join(row(r) for r in rows) + '</tbody></table></div>'
    profiles = plan["profiles"]
    daily = profiles["baseline"]["days"]
    totals = table(("Профиль", "Дни", "Контактов/день", "Новых максимум", "Новая лексика", "Лексика в возврате"),
        [(name, p["total_days"], plan["policy"]["profiles"][name]["contacts"],
          plan["policy"]["profiles"][name]["new_contacts"], plan["policy"]["profiles"][name]["new_lex"],
          plan["policy"]["profiles"][name]["reuse_lex"]) for name,p in profiles.items()])
    stages = table(("Этап", "compact", "baseline", "gentle"),
        [(stage, *(profiles[n]["stages"][stage]["proposed_days"] for n in ("compact", "baseline", "gentle"))) for stage in profiles["baseline"]["stages"]])
    rows, details = [], []
    for d in daily:
        c = d["cumulative"]; acc = c["introduced"]
        rows.append((d["day"], d["stage"], ','.join(d["first_m"]) or '—', ','.join(d["first_g"]) or '—',
          ','.join(d["first_p"]) or '—', f'{len(d["lex_A"])}/{len(d["lex_R"])}/{len(d["lex_choice"])}',
          f'{len(d["reuse_lex_R"])}/{len(d["reuse_lex_P"])}', ','.join(d["revisit_g"]) or '—', ','.join(d["revisit_m"]) or '—',
          f'{acc.get("lex",0)}/{acc.get("G",0)}/{acc.get("M",0)}/{c["first_independent_P"]}',
          c["longest_unpractised_slots"], ','.join(d["early_lo"]+d["assess_lo"]) or '—'))
        contacts = []
        for contact in d["contacts"]:
            activity = plan["activities"].get(contact.get("activity"))
            target = ', '.join(items[k].get("expression",k) for k in contact["targets"])
            if activity:
                text = contact["phase"] + ' ' + contact["mode"] + ': ' + target + ' — ' + activity["purpose"]
            else:
                modes = ', '.join(items[k].get("expression",k)+':'+v for k,v in contact["modes"].items())
                meanings = '; '.join(str(items[k]["meaning"]) for k in contact["targets"])
                text = contact["phase"]+' · '+contact["family"]+' · вариант '+str(contact["context_variant"])+': '+modes+' — '+meanings
            contacts.append('<li>'+esc(text)+'</li>')
        details.append('<details class="vocab-more"><summary>День '+str(d["day"])+' · '+esc(d["stage"])+
            '</summary><ul>'+''.join(contacts)+'</ul></details>')
    grid = table(("День","Этап","Новое M","Новая G","Первое P","Новая лексика A/R/выбор","Возврат лексики R/P","Возврат G","Возврат M","Накоплено лекс/G/M/P","Макс. пауза","LO"),rows)
    charts = []
    for kind, title in (("lex","Лексические записи"),("G","Грамматические цели"),("M","Коммуникативные цели")):
        def amount(d, old):
            if kind == "lex":
                return len(d["reuse_lex_R"]+d["reuse_lex_P"]) if old else len(d["lex_A"]+d["lex_R"]+d["lex_choice"])
            return len(d["revisit_g" if kind=="G" else "revisit_m"]) if old else len(d["first_g" if kind=="G" else "first_m"])
        peak = max(1,*(amount(d,False) for d in daily),*(amount(d,True) for d in daily))
        points = lambda old: ' '.join(f'{20+i*920/max(1,len(daily)-1):.1f},{130-amount(d,old)*110/peak:.1f}' for i,d in enumerate(daily))
        charts.append('<h4>'+title+'</h4><svg class="graph" viewBox="0 0 960 150" role="img" aria-label="Новые и возвращающиеся цели по дням">'
            '<text x="2" y="16" font-size="12">'+str(peak)+'</text><text x="20" y="148" font-size="12">1</text>'
            '<text x="915" y="148" font-size="12">'+str(len(daily))+'</text>'
            '<line x1="20" y1="130" x2="940" y2="130" stroke="#778"/>'
            '<polyline fill="none" stroke="#dc914b" stroke-width="2" points="'+points(False)+'"/>'
            '<polyline fill="none" stroke="#5faeae" stroke-width="2" points="'+points(True)+'"/></svg>')
    return ('<h2>Накопительный языковой календарь</h2>'
        '<p>Новый и прежний материал делят вместимость дня. Первые появления, возвращения лексики R/P, G и M учитываются отдельно. '
        'Прежние 48/65/83 — историческая неполная модель. Новый расчёт также не доказывает длительность обучения.</p>'
        + totals + '<h3>Распределение по горизонтам</h3>' + stages
        + '<h3>Продолжающаяся практика по дням</h3><p>Оранжевый — новые цели; бирюзовый — возвращающиеся. '
        'По горизонтали игровые слоты, по вертикали количество целей в контактах; не выученные слова и не единая шкала трудности.</p>'
        + ''.join(charts) + '<h3>Подневный состав и накопленные введения</h3>'+grid
        + '<details><summary>Все контакты базового профиля</summary>'+''.join(details)+'</details>'
        '<p>Цели не выводятся из очереди после N встреч. Варианты требуют новых фактов, адресата или жанра; '
        'семантическую необходимость каждого значения нужно выполнить в прототипе. На P6 есть поддержанная интеграция '
        'всего репертуара до независимых LO. Бюджеты, паузы, время F1 и перенос не проверены на A0.</p>'
        '<p><a href="LANGUAGE_DAY_SCHEDULE.md">Подневный отчёт</a> · <a href="LANGUAGE_DAY_SCHEDULE.json">Траектории каждой цели</a> · '
        '<a href="LANGUAGE_CUMULATIVE_POLICY.json">Гипотезы нагрузки</a></p>')


def build(html: str) -> str:
    plan = json.loads((DOCS / "LANGUAGE_DAY_SCHEDULE.json").read_text(encoding="utf-8"))
    overview = ('<header><div><div class="eyebrow">Language Life Sim · Языковая программа</div>'
                '<h1>Накопление языка и нагрузка по дням</h1>'
                '<p>Независимый план лексики, грамматики и коммуникативных R/P. '
                'Ни один срок пока не подтверждён на учащихся. Старый сюжет доступен отдельно в свёрнутом архиве внизу.</p>'
                '</div></header><div class="stats">')
    for name, label in (("compact", "Компактный"), ("baseline", "Базовый"), ("gentle", "Бережный")):
        overview += '<div class="stat"><strong>'+str(plan['profiles'][name]['total_days'])+'</strong><span>'+label+' · проектные языковые слоты</span></div>'
    count = sum(it['kind']=='lex' for it in plan['learning_items'].values())
    overview += '<div class="stat"><strong>'+str(count)+'</strong><span>выбранных выражений/форм · не выученных слов</span></div></div>'
    head = html.split('</head>', 1)[0]
    head = re.sub(r'<title>.*?</title>', '<title>Language Life Sim — накопительная языковая программа</title>', head, flags=re.DOTALL)
    return head + '</head><body><main class="wrap">' + overview + '<section class="panel" id="language-duration">' + independent_duration_html() + '</section></main></body></html>\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    old = DASHBOARD.read_text(encoding='utf-8')
    fresh = build(old)
    if args.check:
        if old != fresh:
            print('Dashboard stale; run build_day_progression_dashboard.py', file=sys.stderr)
            return 1
        print('Dashboard matches the current language curriculum.')
    elif old != fresh:
        DASHBOARD.write_text(fresh, encoding='utf-8')
        print('Rebuilt curriculum-only dashboard.')
    else:
        print('Dashboard already current.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
