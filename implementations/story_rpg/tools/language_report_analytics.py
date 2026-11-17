"""Preserved language analytics for the single, self-contained reader report."""
import hashlib
import html
import json
import re
import math
from collections import Counter, defaultdict
from pathlib import Path

DOCS = Path(__file__).resolve().parents[1] / 'docs'
COLORS = ('#258375','#3c69ab','#bc7f36','#9761ad','#c15d76','#627f8a','#79a936','#b47e57','#675bb4','#df9549','#388dba','#a36685','#46705c')
ROLES = {'active_core':'Активное ядро','receptive_core':'Понимание','productive_choice':'Свободный выбор','contextual':'Контекст и справочник'}
def read(name):
    return json.loads((DOCS/name).read_text(encoding='utf8'))
def esc(value):
    return html.escape(str(value), quote=True)
def table(headers, rows, attrs=''):
    return '<div class="heatwrap"><table class="load-table" '+attrs+'><thead><tr>'+''.join('<th>'+esc(h)+'</th>' for h in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+esc(v)+'</td>' for v in row)+'</tr>' for row in rows)+'</tbody></table></div>'
def section(sid,title,body):
    return '<section class="panel" id="'+sid+'"><h2>'+title+'</h2>'+body+'</section>'
def chart(title, series, stacked=False):
    """Independent series share a count axis only when they count the same unit."""
    count=len(series[0][1]); peak=max(1,max(sum(v[i] for _,v in series) if stacked else max(v[i] for _,v in series) for i in range(count)))
    # Integer counts: readable 1/2/5/10-based ticks, never fractional targets.
    raw=max(1,peak/5);base=10**math.floor(math.log10(raw))
    step=next(v*base for v in (1,2,5,10) if v*base>=raw)
    ymax=math.ceil(peak/step)*step
    x=lambda i:55+i*885/max(1,count-1)
    y=lambda value:215-value*190/ymax
    parts=['<h3>'+esc(title)+'</h3><svg class="graph" data-days="'+str(count)+'" viewBox="0 0 960 260" role="img" aria-label="'+esc(title)+'">']
    for value in range(0,int(ymax)+1,int(step)):
        parts.append(f'<line x1="55" y1="{y(value):.2f}" x2="940" y2="{y(value):.2f}" stroke="#d9e3ed"/><text x="45" y="{y(value)+4:.2f}" text-anchor="end" font-size="12">{value}</text>')
    day_step=1 if count<=10 else 5 if count<=50 else 10 if count<=120 else 20
    ticks=sorted({1,count,*range(day_step,count,day_step)})
    for day in ticks:
        parts.append(f'<line x1="{x(day-1):.2f}" y1="25" x2="{x(day-1):.2f}" y2="215" stroke="#e6edf4"/><text x="{x(day-1):.2f}" y="238" text-anchor="middle" font-size="12">{day}</text>')
    parts.append('<text x="500" y="257" text-anchor="middle" font-size="12">Игровой день</text>')
    if stacked:
        for i in range(count):
            top=215
            for j,(name,values) in enumerate(series):
                height=values[i]*190/ymax
                if height:
                    parts.append(f'<rect x="{55+i*885/count:.2f}" y="{top-height:.2f}" width="{max(1,885/count):.2f}" height="{height:.2f}" fill="{COLORS[j%len(COLORS)]}"><title>{esc(name)} · день {i+1}: {values[i]}</title></rect>')
                top-=height
    else:
        for j,(name,values) in enumerate(series):
            points=' '.join(f'{x(i):.2f},{y(v):.2f}' for i,v in enumerate(values))
            parts.append('<polyline fill="none" stroke="'+COLORS[j%len(COLORS)]+'" stroke-width="2" points="'+points+'"><title>'+esc(name)+'</title></polyline>')
    if not stacked:
        for i in range(count):
            tooltip='День '+str(i+1)+'; '+'; '.join(name+': '+str(values[i]) for name,values in series)
            width=885/max(1,count-1)
            parts.append(f'<rect class="chart-day-hit" x="{max(55,x(i)-width/2):.2f}" y="25" width="{width:.2f}" height="190" fill="transparent"><title>{esc(tooltip)}</title></rect>')
    parts.append('</svg>')
    parts.append('<div class="legend">'+''.join('<span><i style="display:inline-block;width:12px;height:12px;background:'+COLORS[j%len(COLORS)]+'"></i> '+esc(name)+'</span>' for j,(name,_) in enumerate(series))+'</div>')
    return ''.join(parts)
def matrix(kind,items,days):
    keys=[k for k,it in items.items() if it['kind']==kind]
    body=['<div class="heatwrap"><div class="curriculum-matrix" style="grid-template-columns:100px repeat('+str(len(days))+',12px)"><b>Цель / день</b>']
    body += ['<span title="День '+str(d['day'])+'">'+(str(d['day']) if d['day']%10==0 or d['day']==1 else '·')+'</span>' for d in days]
    for key in keys:
        body.append('<b title="'+esc(items[key]['meaning'])+'">'+key+'</b>')
        for d in days:
            contacts=[c for c in d['contacts'] if key in c['targets']]
            first=key in d['first_m']+d['first_g']
            productive=any(c.get('modes',{}).get(key,c.get('mode','R')).startswith('P') for c in contacts)
            color='#c9daf1' if first else '#258375' if productive else '#bfe3d9' if contacts else '#f1f4f7'
            label='Первое знакомство' if first else 'Самостоятельное применение' if productive else 'Понимание' if contacts else 'Нет целевой практики'
            body.append('<span style="background:'+color+'" title="'+key+' · день '+str(d['day'])+' · '+label+'"></span>')
    return ''.join(body)+'</div></div>'
def markdown_rows(name,prefix):
    result={}
    for line in (DOCS/name).read_text(encoding='utf8').splitlines():
        cols=[re.sub(r'[*`]', '', x.strip()) for x in line.split('|')[1:-1]]
        if cols and re.fullmatch(prefix,cols[0]): result[cols[0]]=cols[1:]
    return result

def render_analytics():
    plan=read('LANGUAGE_DAY_SCHEDULE.json');lex=read('LANGUAGE_LEXICAL_CATALOG.json');program=read('LANGUAGE_PRACTICE_UNITS.json')
    days=plan['profiles']['baseline']['days'];items=plan['learning_items'];traj=plan['profiles']['baseline']['trajectories']
    entries={e['text']:e for e in lex['entries']};parts=[]
    newlex=[len(d['lex_A']+d['lex_R']+d['lex_choice']) for d in days]
    oldlex=[len(d['reuse_lex_R']+d['reuse_lex_P']) for d in days]
    def cumulative(kind):return [d['cumulative']['introduced'].get(kind,0) for d in days]
    selected={it['expression'] for it in items.values() if it['kind']=='lex'}
    selected_roles=Counter(e['learning_scope']['track'] for e in lex['entries'] if e['text'] in selected)
    all_roles=Counter(e['learning_scope']['track'] for e in lex['entries'])
    breakdown=table(('Роль','В полном каталоге','В текущем плане практики','Вне выбранного плана'),
        [(ROLES[role],all_roles[role],selected_roles[role],all_roles[role]-selected_roles[role]) for role in ROLES]+
        [('Всего',len(lex['entries']),len(selected),len(lex['entries'])-len(selected))])
    parts.append(section('curriculum-growth','Накопление программы',
        '<p>Введённый репертуар и продолжение его практики — разные показатели. Кривые показывают план, а не знания учащегося.</p>'+
        '<p><b>Почему '+str(len(selected))+', а не '+str(len(lex['entries']))+'?</b> '+str(len(lex['entries']))+' — полный каталог выражений/форм. '
        'На графике — '+str(len(selected))+' записей, выбранных для распределённой практики: 200 активного ядра + 254 рецептивного ядра + 13 конкретных опор свободного выбора. '
        'Оставшиеся 110 вариантов выбора и 135 контекстных выражений сохранены в каталоге, но им не назначена обязательная подневная траектория. '
        'Это граница текущего плана, а не утверждение, что остальные выражения изучены или не нужны. Все записи можно посмотреть в <a href="#lexical-catalogue">полном каталоге ниже</a>.</p>'+breakdown+
        '<p>Зелёная линия — сколько разных выбранных записей введено к этому дню; синяя — сколько из них уже получили хотя бы одно последующее применение. '
        'Наведите на график для точных значений дня. Разность зелёной линии между соседними днями — число новых фокусов.</p>'+
        chart('Накопленный выбранный словарь',[('Введено выражений/форм',cumulative('lex')),('Хотя бы раз возвращались',[d['cumulative']['reused'].get('lex',0) for d in days])])+
        '<details><summary>Точные значения роста словаря по каждому дню</summary>'+table(('День','Новых выражений/форм','Всего введено к дню','Хотя бы раз возвращались'),
        [(d['day'],newlex[i],cumulative('lex')[i],d['cumulative']['reused'].get('lex',0)) for i,d in enumerate(days)])+'</details>'+
        chart('Накопленные грамматические и коммуникативные возможности',[('Грамматика G',cumulative('G')),('Общение M',cumulative('M')),('Первое самостоятельное P',[d['cumulative']['first_independent_P'] for d in days])])))
    parts.append(section('novelty-load','Новизна и совместная нагрузка',
        '<p>Количество целей не является шкалой когнитивной трудности. Новая лексика, грамматика, общение и контакты показаны раздельно; прежняя экспертная сложность сюжетных дней сюда не переносится.</p>'+
        chart('Новая и возвращающаяся лексика',[('Новые фокусы',newlex),('Возвращающиеся фокусы',oldlex)],True)+
        chart('Новые грамматические/коммуникативные требования',[('Первое G',[len(d['first_g']) for d in days]),('Первое M',[len(d['first_m']) for d in days]),('Первое P',[len(d['first_p']) for d in days])])+
        chart('Вместимость дня: новые и прежние контакты',[('Новые/исходные',[sum('activity' in c for c in d['contacts']) for d in days]),('Возврат/интеграция',[sum('activity' not in c for c in d['contacts']) for d in days])],True)))
    parts.append(section('reuse-matrix','Возвращение знакомого языка: M и G',
        '<p>Голубой — первое знакомство; светло-зелёный — последующее понимание; тёмно-зелёный — самостоятельная передача смысла. Наведите на ячейку. Матрицы прокручиваются по горизонтали.</p><h3>Коммуникативные функции</h3>'+matrix('M',items,days)+'<h3>Грамматика</h3>'+matrix('G',items,days)))
    cohorts=defaultdict(list)
    for k,it in items.items():
        if it['kind']=='lex':cohorts[days[traj[k][0]['day']-1]['stage']].append(k)
    series=[];cohortrows=[]
    for stage,keys in cohorts.items():
        dayvalues=[len({k for c in d['contacts'] for k in c['targets'] if k in keys}) for d in days]
        series.append((stage,dayvalues))
        last_start=next(d['day'] for d in days if d['stage']=='P6')
        final=sum(any(v['day']>=last_start for v in traj[k]) for k in keys)
        cohortrows.append((stage,len(keys),final,min(traj[k][-1]['day'] for k in keys),max(traj[k][-1]['day'] for k in keys)))
    parts.append(section('lexical-cohorts','Ранний и поздний словарь в дальнейшей практике',
        '<p>Цвет обозначает этап первого появления слова. Высота — число различных лексических целей дня. Это позволяет увидеть, продолжает ли ранний материал появляться позже.</p>'+
        chart('Лексические контакты по этапу знакомства',series,True)+table(('Этап знакомства','Целей','Есть применение на P6','Самый ранний последний контакт','Самый поздний последний контакт'),cohortrows)))
    lexical_days=[[v['day'] for v in traj[k]] for k,it in items.items() if it['kind']=='lex']
    recent=chart('Сколько разных лексических целей встречается в выбранном окне',[('Окно 14 слотов',[sum(any(max(1,n-13)<=day<=n for day in visits) for visits in lexical_days) for n in range(1,len(days)+1)])])
    parts.append(section('recent-repertoire','Репертуар в недавней практике',
        '<p>Окно — инструмент просмотра расписания, не норматив повторений и не оценка забывания.</p>'
        '<label>Последние <select id="recent-window"><option>7</option><option selected>14</option><option>30</option></select> игровых слотов</label><div id="recent-chart">'+recent+'</div>'+
        '<script type="application/json" id="recent-data">'+json.dumps(lexical_days)+'</script>'+
        chart('Наибольшая пауза среди введённых целей',[('Игровых слотов без отмеченной целевой практики',[d['cumulative']['longest_unpractised_slots'] for d in days])])+
        '<p>Пауза рассчитана по отмеченным целям контактов. Она не означает, что слово не встречалось фоном, и не измеряет забывание.</p>'))
    a0=[d for d in days if d['stage']=='P0']
    risks=[(u['id'],u['a0_readiness_review']['risk'],u['a0_readiness_review']['mitigation']) for u in program['items'] if 'a0_readiness_review' in u]
    parts.append(section('a0-accessibility','Холодный старт A0',
        '<p>Показаны первые языковые слоты и сохранённые риски исходных единиц. Доступность F1 и понимание новичком пока не проверены; наличие опор не означает успешного поиска.</p>'+
        chart('Старт: новые фокусы и самостоятельные ответы',[('Новая лексика',newlex[:len(a0)]),('Первые самостоятельные M',[len(d['first_p']) for d in a0])])+
        table(('Единица','Риск для начинающего','Предусмотренное упрощение'),risks)))
    r,p,mixed=[],[],[]
    for d in days:
        counts=Counter()
        for c in d['contacts']:
            modes=set(c.get('modes',{}).values()) or {c.get('mode','R')}
            productive=any(v.startswith('P') for v in modes); receptive='R' in modes
            counts['mixed' if productive and receptive else 'P' if productive else 'R']+=1
        r.append(counts['R']);p.append(counts['P']);mixed.append(counts['mixed'])
    source_examples=sum('stimulus' in a for a in plan['activities'].values())
    parts.append(section('semantic-practice','Что требуется понять и сообщить',
        chart('План контактов чтения и собственного ответа',[('Понимание R',r),('Собственный ответ P',p),('Смешанные цели R/P',mixed)],True)+
        '<p>Смешанный контакт считается один раз. Метка цели означает требование к будущей ситуации; она ещё не доказывает смысловую необходимость.</p>'+
        table(('Показатель','Состояние'),[( 'Исходные контакты с немецкими A/B-примерами',str(source_examples)+' из '+str(len(plan['activities']))),('Реальное понимание всех отмеченных значений','Не проверено на учащихся'),('Копирование готовой реплики','Запрещено контрактом; реальный интерфейс не испытан'),('Самостоятельное письмо и уточнения','Проверяются по смыслу; неопределённость парсера не является ошибкой языка')])) )
    mdefs=markdown_rows('LANGUAGE_DESIGN.md',r'M\d{2}');gdefs=markdown_rows('LANGUAGE_DESIGN.md',r'G\d{2}')
    coverage=[]
    for k,it in items.items():
        if it['kind'] not in ('M','G'):continue
        visits=traj[k];definition=(mdefs if it['kind']=='M' else gdefs).get(k,[])
        coverage.append((k,' · '.join(definition),visits[0]['day'],sum(v['mode'].startswith('P') for v in visits),len(visits)-1,'Запланирована' if any(v['phase']=='late_integration' for v in visits) else 'Нет'))
    locards=[]
    for case in program['independent_outcome_assessments']['cases']:
        lo=case['lo'];when=[d['day'] for d in days if lo in d['assess_lo']]
        stimulus=case['stimulus'];german=''
        for key in ('variant_A_de','variant_B_de'):
            if key in stimulus:german+='<blockquote>'+esc(stimulus[key])+'</blockquote>'
        locards.append('<details><summary>'+lo+' — '+esc(case['goal_ru'])+'</summary><p>Итоговые дни: '+esc(', '.join(map(str,when)))+'</p>'+german+'<p>'+esc(case['expected_player_action'])+'</p><ul>'+''.join('<li>'+esc(e)+'</li>' for e in case['incorrect_interpretation_examples'])+'</ul></details>')
    parts.append(section('coverage-matrices','Полный состав и покрытие M / G / LO',
        '<p>55 M, 34 G и 13 LO. «Запланирована» относится к поздней практике, а не освоению. Число P-контактов не требует точной морфологии.</p>'+
        table(('ID','Содержание и языковой минимум','Первый день','P-контакты','Последующих контактов','Поздняя интеграция'),coverage)+'<h3>Итоговые результаты и критерии</h3>'+''.join(locards)))
    groupseries=[];groupcounts=[]
    for group in lex['groups']:
        gid=group['group'];counts=[]
        for d in days:
            keys={k for c in d['contacts'] for k in c['targets'] if items[k]['kind']=='lex'}
            counts.append(sum(any(o['group']==gid for o in entries[items[k]['expression']]['occurrences']) for k in keys))
        groupseries.append((str(gid),counts));groupcounts.append((gid,group['domain'],len(group['productive']),len(group['receptive']),sum(counts)))
    parts.append(section('theme-distribution','Тематическая широта и распределение',
        '<p>Все 29 групп сохранены. На графике — различные целевые выражения группы в каждом дне. Выражение может относиться к нескольким группам; суммы групп не равны размеру словаря.</p>'+
        chart('Тематические лексические контакты по дням',groupseries,True)+table(('Группа','Тема','Предложено P','Предложено R','Целевых встреч в плане'),groupcounts)))
    options=lambda values:''.join('<option value="'+esc(k)+'">'+esc(v)+'</option>' for k,v in values)
    controls=('<div class="report-controls"><label>Поиск <input id="catalog-search" type="search" placeholder="Слово или русский смысл"></label>'
        '<label>Роль <select id="catalog-role"><option value="">Все</option>'+options(ROLES.items())+'</select></label>'
        '<label>Этап <select id="catalog-band"><option value="">Все</option>'+options((s,s) for s in sorted({e['learning_scope']['focus_band'] for e in lex['entries']}))+'</select></label>'
        '<label>Тема <select id="catalog-group"><option value="">Все</option>'+options((str(g['group']),g['domain']) for g in lex['groups'])+'</select></label></div>')
    catrows=[]
    for e in lex['entries']:
        scope=e['learning_scope'];groups=sorted({o['group'] for o in e['occurrences']})
        selected=next((k for k,it in items.items() if it.get('expression')==e['text']),None)
        catrows.append('<tr data-role="'+scope['track']+'" data-band="'+scope['focus_band']+'" data-groups="'+','.join(map(str,groups))+'">'+''.join('<td>'+esc(v)+'</td>' for v in (e['text'],' / '.join(e['draft_ru_meanings']),ROLES[scope['track']],scope['focus_band'],', '.join(map(str,groups)),'В плане' if selected else 'Доступный выбор/справочник'))+'</tr>')
    roles=Counter(e['learning_scope']['track'] for e in lex['entries'])
    parts.append(section('lexical-catalogue','Полный лексический каталог',
        '<p>'+str(len(lex['entries']))+' выражений/форм, '+str(sum(len(e['occurrences']) for e in lex['entries']))+' тематических вхождений. Каталог шире выбранного репертуара практики; доступность не означает обязательного запоминания. Русские значения — редакционные кандидаты.</p>'+
        table(('Роль','Записей'),[(ROLES[k],v) for k,v in roles.items()])+controls+'<p>Показано: <strong id="catalog-count">'+str(len(catrows))+'</strong></p>'+
        '<div class="heatwrap"><table class="load-table trajectory-table" id="catalog-table"><thead><tr>'+''.join('<th>'+h+'</th>' for h in ('Выражение','Значение','Роль','Этап','Группы','Применение'))+'</tr></thead><tbody>'+''.join(catrows)+'</tbody></table></div>'))
    parts.append(section('input-output','Объём Input / Output: что известно и чего ещё нет',
        '<p>Этот раздел сохранён вместо удаления прежних графиков. Полные немецкие реплики для всех контактов новой программы ещё не написаны. Поэтому число слов реального Input/Output, их накопленный объём и долю неизвестного текста сейчас вычислить нельзя.</p>'+
        table(('Сохраняемый показатель','Состояние','Нужные данные'),[('Слова Input по дням','Нет полного актуального корпуса','Тексты всех обязательных реплик и привязка к контактам'),('Слова Output по дням','Неизвестно','Фактические ответы учащихся; пример не заменяет их'),('Накопленный объём прочитанного','Неизвестно','Реально предъявленные тексты и попытки'),('Упоминание против смысловой необходимости','Не проверено','Исполняемые контрфакты и независимые ответы'),('Реальная трудность контакта','Не измерена','Время, F1, ошибки и наблюдение A0')])+
        '<p>Выше показаны доступные сейчас заменители: плановые R/P-контакты, новые лексические фокусы, возвращения и накопленный репертуар. Они не подписаны как количество прочитанных слов.</p>'))
    parts.append(section('method-and-limits','Методика, помощь и границы результата',
        '<p>Источник программы — авторская матрица с ориентирами CEFR/Goethe; это не дословный курс одного пособия. Цель — письменное понимание и самостоятельная передача простых смыслов примерно A1. Аудирование и говорение в обязательный результат не входят.</p>'+
        '<ul>'+''.join('<li>'+esc(r)+'</li>' for r in plan['policy']['rules'])+'</ul>'+
        '<h3>F1 и самостоятельность</h3><p>Утверждённый справочник доступен с начала: поиск по немецкой форме и русскому смыслу, пояснение неоднозначностей и грамматических различий. Помощь не должна выдавать готовый ответ текущего задания. В независимых LO F1 не подсказывает решение. Реальный F1 и парсер пока не проверены.</p>'+
        '<h3>Следующий этап</h3><p>Ограниченные языковые ситуации и прототип, проверка A0, реальных затрат и отсроченного применения. Только после калибровки фиксируется длительность полного сюжета. Новые документы сами по себе не подтверждают обучение.</p>'))
    manifest=read('LANGUAGE_REPORT_SECTIONS.json')['sections']
    toc='<nav class="report-nav" aria-label="Весь отчёт">'+''.join('<a href="#'+sid+'">'+esc(title)+'</a>' for sid,title in manifest.items())+'</nav>'
    return toc+''.join(parts)

def script():
    return '''<script>
    function filterCatalogue(){
      const text=document.getElementById('catalog-search').value.trim().toLocaleLowerCase();
      const role=document.getElementById('catalog-role').value,band=document.getElementById('catalog-band').value,group=document.getElementById('catalog-group').value;
      let count=0;
      document.querySelectorAll('#catalog-table tbody tr').forEach(row=>{
        row.hidden=!(row.textContent.toLocaleLowerCase().includes(text)&&(!role||row.dataset.role===role)&&(!band||row.dataset.band===band)&&(!group||row.dataset.groups.split(',').includes(group)));
        if(!row.hidden)count++;
      });
      document.getElementById('catalog-count').textContent=count;
    }
    ['catalog-search','catalog-role','catalog-band','catalog-group'].forEach(id=>document.getElementById(id).addEventListener(id==='catalog-search'?'input':'change',filterCatalogue));
    function drawRecent(){
      const windowSize=Number(document.getElementById('recent-window').value);
      const visits=JSON.parse(document.getElementById('recent-data').textContent);
      const total=Number(document.querySelector('#recent-chart svg').dataset.days);
      const values=Array.from({length:total},(_,i)=>visits.filter(days=>days.some(d=>d>=Math.max(1,i+2-windowSize)&&d<=i+1)).length);
      const peak=Math.max(1,...values),ns='http://www.w3.org/2000/svg';
      const raw=Math.max(1,peak/5),base=10**Math.floor(Math.log10(raw)),step=[1,2,5,10].map(v=>v*base).find(v=>v>=raw),ymax=Math.ceil(peak/step)*step;
      const x=i=>55+i*885/Math.max(1,total-1),y=v=>215-v*190/ymax;
      const svg=document.createElementNS(ns,'svg');svg.setAttribute('class','graph');svg.dataset.days=total;svg.setAttribute('viewBox','0 0 960 260');svg.setAttribute('role','img');svg.setAttribute('aria-label','Репертуар в окне последних '+windowSize+' слотов');
      let grid='';
      for(let v=0;v<=ymax;v+=step)grid+=`<line x1="55" x2="940" y1="${y(v)}" y2="${y(v)}" stroke="#d9e3ed"/><text x="45" y="${y(v)+4}" text-anchor="end" font-size="12">${v}</text>`;
      const ticks=new Set([1,total]);for(let day=20;day<total;day+=20)ticks.add(day);
      [...ticks].sort((a,b)=>a-b).forEach(day=>{grid+=`<line x1="${x(day-1)}" x2="${x(day-1)}" y1="25" y2="215" stroke="#e6edf4"/><text x="${x(day-1)}" y="238" text-anchor="middle" font-size="12">${day}</text>`});
      svg.innerHTML=grid+'<text x="500" y="257" text-anchor="middle" font-size="12">Игровой день</text>';
      const line=document.createElementNS(ns,'polyline');line.setAttribute('fill','none');line.setAttribute('stroke','#258375');line.setAttribute('stroke-width','2');line.setAttribute('points',values.map((v,i)=>x(i)+','+y(v)).join(' '));svg.appendChild(line);
      document.getElementById('recent-chart').replaceChildren(svg);
    }
    document.getElementById('recent-window').addEventListener('change',drawRecent);
    </script>'''

def source_fingerprint():
    names=sorted(set(p.name for p in DOCS.glob('LANGUAGE_*') if p.suffix in ('.md','.json'))|{'LEARNING_OUTCOMES.md'})
    digest=hashlib.sha256()
    for name in names:digest.update(name.encode());digest.update((DOCS/name).read_text(encoding='utf8').encode('utf8'))
    return '<p class="foot">Единый отчёт пересобирается из актуальных языковых источников. Снимок данных: '+digest.hexdigest()[:16]+'. Все текущие данные и ограничения представлены внутри страницы; старый сюжет не является источником графиков.</p>'
