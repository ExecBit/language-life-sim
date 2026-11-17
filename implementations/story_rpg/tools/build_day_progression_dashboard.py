#!/usr/bin/env python3
"""Build the current language dashboard. Story archives are retained in Git only."""
from __future__ import annotations
import argparse
import html as html_stdlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from language_report_analytics import render_analytics, script as analytics_script, source_fingerprint, chart
DOCS = Path(__file__).resolve().parents[1] / "docs"
DASHBOARD = DOCS / "ACT_DAY_PROGRESSION_DASHBOARD.html"

def independent_duration_html() -> str:
    """Render a self-contained report, including every former source-file link."""
    plan = json.loads((DOCS / "LANGUAGE_DAY_SCHEDULE.json").read_text(encoding="utf-8"))
    items = plan["learning_items"]
    esc = lambda v: html_stdlib.escape(str(v), quote=True)
    def row(vals, header=False):
        tag = "th" if header else "td"
        return "<tr>" + "".join(f"<{tag}>{esc(v)}</{tag}>" for v in vals) + "</tr>"
    def table(headers, rows):
        return '<div class="heatwrap"><table class="load-table"><thead>' + row(headers, True) + '</thead><tbody>' + ''.join(row(r) for r in rows) + '</tbody></table></div>'
    profiles = plan["profiles"]
    labels = {"compact":"Компактный", "baseline":"Базовый", "gentle":"Бережный"}
    phases = {"introduction":"Знакомство со значением", "reception":"Понимание текста", "grammar":"Грамматическое различие", "production":"Самостоятельное сообщение", "extension":"Числа и время", "assessment":"Независимая проверка", "reuse":"Повторное применение", "late_integration":"Позднее применение"}
    modes_ru = {"R":"чтение", "P":"собственный ответ", "P-meaning":"собственный ответ по смыслу"}
    daily = profiles["baseline"]["days"]
    totals = table(("Профиль", "Дни", "Контактов/день", "Новых максимум", "Новая лексика", "Лексика в возврате"),
        [(labels[name], p["total_days"], plan["policy"]["profiles"][name]["contacts"],
          plan["policy"]["profiles"][name]["new_contacts"], plan["policy"]["profiles"][name]["new_lex"],
          plan["policy"]["profiles"][name]["reuse_lex"]) for name,p in profiles.items()])
    stages = table(("Этап", "Компактный", "Базовый", "Бережный"),
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
                text = phases[contact["phase"]] + ' (' + modes_ru[contact["mode"]] + '): ' + target + ' — ' + activity["purpose"]
            else:
                modes = ', '.join(items[k].get("expression",k)+' ('+modes_ru[v]+')' for k,v in contact["modes"].items())
                meanings = '; '.join(' / '.join(items[k]["meaning"]) if isinstance(items[k]["meaning"],list) else items[k]["meaning"] for k in contact["targets"])
                text = phases[contact["phase"]]+' · вариант '+str(contact["context_variant"])+': '+modes+' — '+meanings
            extra = ''
            if activity:
                stimulus = activity.get('stimulus', {})
                for letter in ('A','B'):
                    example = stimulus.get('example_'+letter+'_de',stimulus.get('example_'+letter))
                    if example:
                        extra += '<blockquote>'+esc(example)+'</blockquote>'
                production = activity.get('production_contract')
                if production:
                    extra += '<p>'+esc(production['recipient_knowledge'])+'</p>'
                if stimulus.get('support'):
                    extra += '<p>Доступная помощь: '+esc(stimulus['support'])+'</p>'
            contacts.append('<li>'+esc(text)+extra+'</li>')
        details.append('<details class="vocab-more" id="day-'+str(d["day"])+'"><summary>День '+str(d["day"])+' · '+esc(d["stage"])+
            '</summary><ul>'+''.join(contacts)+'</ul></details>')
    grid = table(("День","Этап","Новое M","Новая G","Первое P","Новая лексика A/R/выбор","Возврат лексики R/P","Возврат G","Возврат M","Накоплено лекс/G/M/P","Макс. пауза","LO"),rows)
    charts = []
    for kind, title in (("lex","Лексические записи"),("G","Грамматические цели"),("M","Коммуникативные цели")):
        def amount(d, old):
            if kind == "lex":
                return len(d["reuse_lex_R"]+d["reuse_lex_P"]) if old else len(d["lex_A"]+d["lex_R"]+d["lex_choice"])
            return len(d["revisit_g" if kind=="G" else "revisit_m"]) if old else len(d["first_g" if kind=="G" else "first_m"])
        charts.append(chart(title, [('Новые цели',[amount(d,False) for d in daily]), ('Возвращающиеся цели',[amount(d,True) for d in daily])]))
    trajectory_panels = []
    for name, profile in profiles.items():
        trows = []
        for key, visits in profile['trajectories'].items():
            item = items[key]
            title = item.get('expression',key)
            meaning = ' / '.join(item['meaning']) if isinstance(item['meaning'],list) else item['meaning']
            kind = {'lex':'Лексика','G':'Грамматика','M':'Общение'}[item['kind']]
            first = visits[0]['day']
            later = visits[1:]
            gap = max((b['day']-a['day'] for a,b in zip(visits,visits[1:])),default=0)
            timeline = ', '.join(str(v['day'])+' ('+modes_ru[v['mode']]+')' for v in later) or '—'
            trows.append(row((title,kind,meaning,first,timeline,gap)))
        trajectory_panels.append('<div class="trajectory-profile" data-profile="'+name+'"'+(' hidden' if name!='baseline' else '')+'>'
            '<p>'+labels[name]+': '+str(profile['total_days'])+' дней. Найдено целей: <strong class="match-count">'+str(len(trows))+'</strong>.</p>'
            '<div class="heatwrap"><table class="load-table trajectory-table"><thead>'+row(('Цель','Тип','Проверяемый смысл','Первый день','Последующие дни и режим','Наибольшая пауза'),True)
            +'</thead><tbody>'+''.join(trows)+'</tbody></table></div></div>')
    trajectories = ('<section class="panel" id="goal-trajectories"><h2>Траектории каждой цели</h2>'
        '<p>Найдите слово, грамматическую или коммуникативную цель. Здесь показаны дни знакомства и дальнейшего применения. '
        'Это план практики, а не измерение памяти.</p><div class="report-controls">'
        '<label>Профиль <select id="trajectory-profile"><option value="baseline">Базовый</option><option value="compact">Компактный</option><option value="gentle">Бережный</option></select></label> '
        '<label>Поиск <input id="trajectory-search" type="search" placeholder="Например: Buch, отрицание, M14" /></label></div>'
        +''.join(trajectory_panels)+'</section>')
    rules = ''.join('<li>'+esc(rule)+'</li>' for rule in plan['policy']['rules'])
    workload = ('<section class="panel" id="workload-profiles"><h2>Гипотезы нагрузки</h2>'
        '<p>«Контакт» — возможность понять или передать нужный смысл. Новые и возвращающиеся контакты делят общую вместимость дня. '
        'Лексические фокусы — выражения и формы, а не число выученных слов.</p>'+totals+
        '<ul>'+rules+'</ul><p>Число дней зависит от этих предположений. Допустимую нагрузку и реальные интервалы предстоит проверить на начинающих; '
        '138/212/404 не являются доказанными сроками достижения A1.</p></section>')
    navigation = ('<nav class="report-nav" aria-label="Разделы отчёта"><a href="#daily-report">Подневный отчёт</a>'
        '<a href="#goal-trajectories">Траектории каждой цели</a><a href="#workload-profiles">Гипотезы нагрузки</a></nav>')
    return ('<section class="panel" id="language-duration">'+navigation+'<h2>Накопительный языковой календарь</h2>'
        '<p>Новый и прежний материал делят вместимость дня. Первые появления, возвращения лексики R/P, G и M учитываются отдельно. '
        'Прежние 48/65/83 — историческая неполная модель. Новый расчёт также не доказывает длительность обучения.</p>'
        + totals + '<h3>Распределение по горизонтам</h3>' + stages
        + '<h3>Продолжающаяся практика по дням</h3><p>Оранжевый — новые цели; бирюзовый — возвращающиеся. '
        'По горизонтали игровые слоты, по вертикали количество целей в контактах; не выученные слова и не единая шкала трудности.</p>'
        + ''.join(charts) + '<div id="daily-report"><h3>Подневный отчёт — базовый профиль</h3>'
        '<p>R — понимание текста, P — собственный письменный ответ; G — грамматика, M — коммуникативная функция. '
        'Ниже можно раскрыть содержание каждого дня.</p>'+grid
        + '<details id="daily-contacts" open><summary>Содержание всех дней базового профиля</summary>'+''.join(details)+'</details></div>'
        '<p>Цели не выводятся из очереди после N встреч. Варианты требуют новых фактов, адресата или жанра; '
        'семантическую необходимость каждого значения нужно выполнить в прототипе. На P6 есть поддержанная интеграция '
        'всего репертуара до независимых LO. Бюджеты, паузы, время F1 и перенос не проверены на A0.</p>'
        +navigation+'</section>'+trajectories+workload)


def build(html: str) -> str:
    plan = json.loads((DOCS / "LANGUAGE_DAY_SCHEDULE.json").read_text(encoding="utf-8"))
    overview = ('<header><div><div class="eyebrow">Language Life Sim · Языковая программа</div>'
                '<h1>Накопление языка и нагрузка по дням</h1>'
                '<p>Независимый план лексики, грамматики и коммуникативных R/P. '
                'Ни один срок пока не подтверждён на учащихся. Все разделы отчёта открываются прямо на этой странице.</p>'
                '</div></header><div class="stats">')
    for name, label in (("compact", "Компактный"), ("baseline", "Базовый"), ("gentle", "Бережный")):
        overview += '<div class="stat"><strong>'+str(plan['profiles'][name]['total_days'])+'</strong><span>'+label+' · проектные языковые слоты</span></div>'
    count = sum(it['kind']=='lex' for it in plan['learning_items'].values())
    overview += '<div class="stat"><strong>'+str(count)+'</strong><span>выбранных выражений/форм · не выученных слов</span></div></div>'
    head = html.split('</head>', 1)[0]
    head = re.sub(r'<title>.*?</title>', '<title>Language Life Sim — накопительная языковая программа</title>', head, flags=re.DOTALL)
    if 'id="report-styles"' not in head:
        head += '<style id="report-styles">html{scroll-behavior:smooth}section,div[id]{scroll-margin-top:16px}.report-nav{display:flex;gap:10px;flex-wrap:wrap;margin:14px 0 22px}.report-nav a{padding:9px 14px;border:1px solid #b9cddd;border-radius:8px;background:#eef5fb;text-decoration:none}.report-controls{display:flex;gap:20px;flex-wrap:wrap;margin:16px 0}.report-controls label{display:flex;gap:8px;align-items:center}.report-controls input,.report-controls select{font:inherit;padding:8px;border:1px solid #b9cddd;border-radius:6px}.trajectory-table{min-width:900px}.trajectory-table td{text-align:left!important;vertical-align:top}.trajectory-table td:nth-child(3){min-width:220px}.trajectory-table td:nth-child(5){min-width:300px}[hidden]{display:none!important}</style>'
    if 'id="analytics-styles"' not in head:
        head += '<style id="analytics-styles">.curriculum-matrix{display:grid;gap:2px;font-size:9px;align-items:stretch}.curriculum-matrix>span{min-height:13px}.curriculum-matrix>b{font-size:11px}.panel h3{margin-top:22px}.panel details{padding:8px;border-bottom:1px solid #d9e3ed}.panel summary{cursor:pointer}.legend{margin-bottom:20px}.panel blockquote{padding:8px 14px;background:#f1f6fa;border-left:3px solid #258375}.load-table td{vertical-align:top}</style>'
    script = '''<script>
    function filterTrajectories(){
      const profile=document.getElementById('trajectory-profile').value;
      const query=document.getElementById('trajectory-search').value.trim().toLocaleLowerCase();
      document.querySelectorAll('.trajectory-profile').forEach(panel=>{
        panel.hidden=panel.dataset.profile!==profile;
        let matches=0;
        panel.querySelectorAll('tbody tr').forEach(row=>{
          row.hidden=!row.textContent.toLocaleLowerCase().includes(query);
          if(!row.hidden)matches++;
        });
        panel.querySelector('.match-count').textContent=matches;
      });
    }
    document.getElementById('trajectory-profile').addEventListener('change',filterTrajectories);
    document.getElementById('trajectory-search').addEventListener('input',filterTrajectories);
    </script>'''
    return head + '</head><body><main class="wrap">' + overview + render_analytics() + independent_duration_html() + source_fingerprint() + '</main>'+script+analytics_script()+'</body></html>\n'


def validate_report(html):
    """Reader navigation must resolve to rendered content, never raw source files."""
    class Navigation(HTMLParser):
        def __init__(self):
            super().__init__()
            self.ids, self.links = [], []
        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if 'id' in attrs:
                self.ids.append(attrs['id'])
            if tag == 'a':
                self.links.append(attrs.get('href', ''))
    nav = Navigation()
    nav.feed(html)
    if len(nav.ids) != len(set(nav.ids)):
        raise ValueError('Duplicate report section/control ID')
    manifest = json.loads((DOCS/'LANGUAGE_REPORT_SECTIONS.json').read_text(encoding='utf8'))
    required = set(manifest['sections'])
    required |= {'trajectory-search','trajectory-profile','catalog-search','catalog-role','catalog-band','catalog-group','recent-window'}
    if not required <= set(nav.ids):
        raise ValueError('Rendered report section/control missing')
    if not nav.links or any(not href.startswith('#') or href[1:] not in nav.ids for href in nav.links):
        raise ValueError('Report navigation must stay within rendered HTML')
    for title in manifest['charts']:
        if html_stdlib.escape(title) not in html:
            raise ValueError('Preserved analytical graph missing: '+title)
    if html.count('data-role=') != len(json.loads((DOCS/'LANGUAGE_LEXICAL_CATALOG.json').read_text(encoding='utf8'))['entries']):
        raise ValueError('Full lexical catalogue missing from reader report')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    old = DASHBOARD.read_text(encoding='utf-8')
    fresh = build(old)
    validate_report(fresh)
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
