"""Cumulative curriculum opportunities. No story input, mastery score or repetition quota."""
from __future__ import annotations
import argparse
import copy
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from calculate_language_days import PROFILES, STAGES

DOCS = Path(__file__).resolve().parents[1] / "docs"
GROUP_CONTRACT = dict(enumerate((1,2,3,3,2,4,5,5,7,6,6,8,7,15,10,11,12,10,13,15,14,16,17,18,19,20,18,21,22), 1))
PRODUCTIVE_AFTER = dict(enumerate(("M01","M12","M03","M07","M06","M15","M29","M32","M14","M20","M21","M17","M36","M33","M23","M18","M31","M24","M17","M34","M21","M45","M46","M28","M15","M07","M26","M51","M52"),1))

def read(name):
    return json.loads((DOCS / name).read_text(encoding="utf-8"))

def pair(q):
    return (q.get("example_A_de", q.get("example_A")), q.get("example_B_de", q.get("example_B")))

def tokens(s):
    return re.findall(r"[^\W_]+", s.casefold(), re.UNICODE)

def source_model():
    program, lex, grammar = (read(n) for n in ("LANGUAGE_PRACTICE_UNITS.json", "LANGUAGE_LEXICAL_CATALOG.json", "LANGUAGE_GRAMMAR_CONTRASTS.json"))
    contracts = {x["id"]: x for x in lex["lexical_competency_contracts"]}
    gmap = {g["id"]: g for g in grammar["items"]}
    extensions = read("LANGUAGE_NUMBER_TIME_CONTRACTS.json")["contracts"]
    revisit_evidence = read("LANGUAGE_REVISIT_SEMANTIC_AUDIT.json")["entries"]
    family = lambda m: next((k for k,c in contracts.items() if m in c["functions"]), m)
    items, activities, sequence, assigned = {}, {}, {s: [] for s in STAGES}, set()
    productive = {c["M"]: c for u in program["items"] for c in u["independent_production_checks"]}
    for u in program["items"]:
        for m in u["introduce_m"]:
            items[m] = dict(kind="M", mode="P" if m in productive else "R", family=family(m),
                            source_unit=u["id"], meaning=productive[m]["semantic_goal_ru"] if m in productive else u["contrast"])
    for g in grammar["items"]:
        items[g["id"]] = dict(kind="G", mode="R", family=family(g["semantic_M"]), source_unit=g["unit"],
                               meaning=g["meaning_difference"], productive_M=g["semantic_M"] if g["minimum"]=="P" else None)
    for i,e in enumerate(lex["entries"], 1):
        track = e["learning_scope"]["track"]
        items[f"LX{i:03}"] = dict(kind="lex", expression=e["text"], track=track,
            mode="R" if track in ("receptive_core","contextual") or PRODUCTIVE_AFTER[e["occurrences"][0]["group"]] not in productive else "P", meaning=e["draft_ru_meanings"],
            family=f'L{GROUP_CONTRACT[e["occurrences"][0]["group"]]:02}',
            productive_after=PRODUCTIVE_AFTER[e["occurrences"][0]["group"]],
            production_policy="meaning_not_mandatory_surface_or_tense_paradigm",
            focus_band=e["learning_scope"]["focus_band"], selected_choice=track=="productive_choice")
    lexical = {it["expression"]: k for k,it in items.items() if it["kind"]=="lex"}
    aliases = defaultdict(set)
    for a in lex["program_form_alias_candidates"]:
        if a["target_entry"] in lexical:
            aliases[a["observed_form"].casefold()].add(lexical[a["target_entry"]])

    def add(stage, uid, suffix, kind, targets=(), fm=(), fg=(), fp=(), **kw):
        aid = uid+":"+suffix
        a = dict(id=aid, unit=uid, kind=kind, mode="P" if fp else "R", targets=list(targets),
                 first_m=list(fm), first_g=list(fg), first_p=list(fp), reused_targets=[], early_lo=[], assess_lo=[], **kw)
        activities[aid] = a
        sequence[stage].append(aid)
        return a

    def add_lex(stage, uid, needed):
        groups = defaultdict(list)
        for k in sorted(set(needed)-assigned):
            groups[items[k]["family"]].append(k)
        for f, keys in groups.items():
            add(stage, uid, "lex-"+f, "lexical", targets=keys, contract=f,
                purpose=contracts[f]["semantic_acceptance_rule_ru"])
            assigned.update(keys)

    for u in program["items"]:
        s, uid = u["stage"], u["id"]
        if s=="P6":
            for lo in u["outcome_candidates"]:
                a=add(s,uid,lo,"assessment",purpose="Независимая проба "+lo)
                a["assess_lo"]=[lo]
                a["mode"]="P" if lo.startswith("LO-W") else "R"
            continue
        needed = {lexical[a["expression"]] for a in u["lexical_anchors"] if a["obligation"]=="functional_candidate"}
        texts = [t for q in u["language_example_checks"] for t in pair(q)]
        texts += [t for gid in u["introduce_g"] for t in pair(gmap[gid])]
        extras = [q for q in extensions if q["unit"] == uid]
        texts += [t for q in extras for t in pair(q)]
        ts = set(tokens(" ".join(texts)))
        for word,k in lexical.items():
            wt = tokens(word)
            if wt and wt[0] in ("der","die","das"):
                wt=wt[1:]
            if wt and all(t in ts for t in wt):
                needed.add(k)
        for t in ts:
            needed.update(aliases[t])
        # Matching is only a first-support dependency, not semantic evidence.
        add_lex(s,uid,needed)
        covered=set()
        for n,q in enumerate(u["language_example_checks"]):
            shared=[gid for gid in u["introduce_g"] if pair(gmap[gid])==pair(q)]
            covered.update(shared)
            a=add(s,uid,f"R{n+1}","reception",fm=u["introduce_m"] if n==0 else [],fg=shared,
                grammar_contacts=int(bool(shared)), purpose=q["critical_meaning_ru"], stimulus=q,
                candidate_revisit_m=u["revisit_m"] if n==0 else [])
            evidenced=[r["M"] for r in revisit_evidence if r["unit"]==uid
                       and r["status"]=="plausible_in_main_AB_candidate_not_user_test"
                       and r["primary_example_de"]==pair(q)[0]]
            a["reused_targets"]=sorted(set(evidenced+q.get("reused_m",[])))
        for gid in u["introduce_g"]:
            if gid not in covered:
                add(s,uid,gid,"grammar",fg=[gid],grammar_contacts=1,purpose=gmap[gid]["meaning_difference"],stimulus=gmap[gid])
        for q in extras:
            add(s,uid,q["id"],"extension",purpose=q["purpose"],stimulus=q,contract=q["family"])
        for q in u["independent_production_checks"]:
            add(s,uid,q["M"]+"-P","production",fp=[q["M"]],purpose=q["semantic_goal_ru"],production_contract=q)
        activities[sequence[s][-1]]["early_lo"]=u["outcome_candidates"]
    for s in STAGES[:-1]:
        add_lex(s,s+"-lexical-extension",[k for k,it in items.items() if it["kind"]=="lex" and it["focus_band"]==s])
    if assigned!=set(lexical.values()):
        raise ValueError("Lexical target without introduction")
    return items,activities,sequence,contracts

def caps_for(profile,stage):
    return {**PROFILES[profile]["default"],**PROFILES[profile].get(stage,{})}

def pack(profile,items,activities,sequence,policy):
    b=policy["profiles"][profile]
    days,seen,last,visits,p_seen,late=[],{},{},Counter(),set(),set()
    for s in STAGES:
        caps=caps_for(profile,s)
        queue=[copy.deepcopy(activities[a]) for a in sequence[s]]
        closing=s=="P6"
        while queue or (closing and late!=set(items)):
            n=len(days)+1
            d=dict(day=n,stage=s,slot=1+sum(x["stage"]==s for x in days),needs_contract=False,contacts=[])
            for f in ("unit_start","unit_activity","first_m","first_g","first_p","revisit_m","revisit_g","lex_A","lex_R","lex_choice","reuse_lex_R","reuse_lex_P","early_lo","assess_lo","semantic_probes"):
                d[f]=[]
            used=Counter()
            limit=b["new_contacts"] if seen else b["contacts"]
            if closing and late!=set(items):
                limit=0
            for _ in range(limit):
                if not queue: break
                a=queue[0]
                if a["kind"]=="lexical":
                    take=[]
                    for k in a["targets"]:
                        fld="R" if items[k]["mode"]=="R" else "A"
                        if used[fld]>=caps[fld] or used["lex"]>=b["new_lex"]: break
                        take.append(k);used[fld]+=1;used["lex"]+=1
                    if not take: break
                    c=dict(activity=a["id"],phase="introduction",mode="R",targets=take,family=a["contract"])
                    a["targets"]=[k for k in a["targets"] if k not in take]
                    if not a["targets"]: queue.pop(0)
                    for k in take:
                        it=items[k]
                        fld="lex_choice" if it["selected_choice"] else "lex_R" if it["mode"]=="R" else "lex_A"
                        d[fld].append(it["expression"])
                else:
                    demand=dict(M=len(a["first_m"]),G=a.get("grammar_contacts",0),P=len(a["first_p"]),LO=len(a["early_lo"]+a["assess_lo"]))
                    if any(used[k]+v>caps[k] for k,v in demand.items()): break
                    used.update(demand);queue.pop(0)
                    c=dict(activity=a["id"],phase=a["kind"],mode=a["mode"],targets=a["first_m"]+a["first_g"]+a["first_p"]+a["reused_targets"])
                    for f in ("first_m","first_g","first_p","early_lo","assess_lo"): d[f].extend(a[f])
                    d["revisit_m"].extend(a["reused_targets"])
                    visits.update(a["reused_targets"])
                    p_seen.update(a["first_p"])
                uid=a["unit"]
                if uid not in d["unit_start"] and uid not in d["unit_activity"]:
                    (d["unit_activity"] if any(uid in x["unit_start"] for x in days) else d["unit_start"]).append(uid)
                d["contacts"].append(c)
                for k in c["targets"]: seen.setdefault(k,n);last[k]=n
            while len(d["contacts"])<b["contacts"]:
                eligible=[k for k in seen if last[k]<n]
                if not eligible: break
                oldest=min(eligible,key=lambda k:(last[k],seen[k],k))
                fam=items[oldest]["family"]
                same=sorted((k for k in eligible if items[k]["family"]==fam),key=lambda k:(last[k],seen[k],k))
                take=[];counts=Counter()
                for k in same:
                    kind=items[k]["kind"]
                    if counts[kind]<(b["reuse_lex"] if kind=="lex" else 1): take.append(k);counts[kind]+=1
                modes={}
                late_contact=closing and any(k not in late for k in take)
                for k in take:
                    it=items[k];mode=it["mode"]
                    if it["kind"]=="M" and mode=="P" and k not in p_seen: mode="R"
                    if it["kind"]=="lex" and mode=="P" and it["productive_after"] not in p_seen: mode="R"
                    if it["kind"]=="G" and k!="G24" and it.get("productive_M") in p_seen: mode="P-meaning"
                    # Clarification must never force a false claim of not
                    # understanding. Read another person's repair request,
                    # or make one's own request only when actually needed.
                    if k=="M05" or it.get("expression") in ("ich verstehe nicht","noch einmal","Wie bitte?"):
                        mode="R"
                    modes[k]=mode;visits[k]+=1;last[k]=n
                    if closing: late.add(k)
                    fld="revisit_m" if it["kind"]=="M" else "revisit_g" if it["kind"]=="G" else "reuse_lex_"+mode
                    d[fld].append(it.get("expression",k))
                d["contacts"].append(dict(phase="late_integration" if late_contact else "reuse",family=fam,targets=take,modes=modes,
                    context_variant=1+(max(visits[k] for k in take)-1)%3,assist="F1_allowed_no_current_answer",
                    clarification_is_voluntary=True,
                    production_policy="meaning_not_exact_surface_or_paradigm",
                    semantic_validation="required_in_situation_design_not_proven"))
            if not d["contacts"]: raise ValueError(f"Cannot pack {profile}:{s}")
            d["cumulative"]=dict(introduced=dict(Counter(items[k]["kind"] for k in seen)),first_independent_P=len(p_seen),
                reused=dict(Counter(items[k]["kind"] for k in visits)),pending_late=len(set(items)-late),
                longest_unpractised_slots=max((n-last[k] for k in seen),default=0))
            days.append(d)
    trajectory={k:[] for k in items}
    for d in days:
        for c in d["contacts"]:
            for k in c["targets"]:
                trajectory[k].append(dict(day=d["day"],phase=c["phase"],mode=c.get("modes",{}).get(k,c.get("mode","R"))))
    return dict(total_days=len(days),stages={s:dict(proposed_days=sum(d["stage"]==s for d in days),
        lexical_focus_only_days=sum(d["stage"]==s and all(items[k]["kind"]=="lex" for c in d["contacts"] for k in c["targets"])
                                    and not d["assess_lo"] for d in days)) for s in STAGES},days=days,trajectories=trajectory)

def build():
    items,activities,sequence,contracts=source_model()
    policy=read("LANGUAGE_CUMULATIVE_POLICY.json")
    return dict(version="2.1",status="preliminary_complete_catalogue_practice_not_learner_mastery",baseline_profile="baseline",
        policy=policy,learning_items=items,activities=activities,semantic_contracts=contracts,
        profiles={p:pack(p,items,activities,sequence,policy) for p in PROFILES})

def validate(plan):
    items,activities,sequence,_=source_model()
    if plan["learning_items"]!=items or plan["activities"]!=activities: raise ValueError("Source model changed")
    catalogue={e['text'] for e in read('LANGUAGE_LEXICAL_CATALOG.json')['entries']}
    if {it['expression'] for it in items.values() if it['kind']=='lex'} != catalogue:
        raise ValueError('A catalogue expression was excluded from cumulative practice')
    expected=[a for s in STAGES for a in sequence[s]]
    for profile,p in plan["profiles"].items():
        first,late,order,p_seen={},set(),[],set()
        previous=-1
        for n,d in enumerate(p["days"],1):
            if n!=d["day"] or STAGES.index(d["stage"])<previous: raise ValueError("Day/stage order")
            previous=STAGES.index(d["stage"])
            b=plan["policy"]["profiles"][profile];caps=caps_for(profile,d["stage"])
            if not d["contacts"] or len(d["contacts"])>b["contacts"]: raise ValueError("Contact budget")
            if len(d["lex_A"]+d["lex_R"]+d["lex_choice"])>b["new_lex"]: raise ValueError("Joint lexical budget")
            introduced=[k for c in d['contacts'] if c['phase']=='introduction' for k in c['targets']]
            if sum(items[k]['mode']=='P' for k in introduced)>caps['A'] or sum(items[k]['mode']=='R' for k in introduced)>caps['R']:
                raise ValueError("Lexical axis budget")
            if len(d["first_m"])>caps["M"] or len(d["first_p"])>caps["P"]: raise ValueError("M/P budget")
            gc=0
            for c in d["contacts"]:
                aid=c.get("activity")
                if aid:
                    if not order or order[-1]!=aid: order.append(aid)
                    a=activities[aid];gc+=a.get("grammar_contacts",0)
                    if a["kind"]!="lexical" and set(c["targets"])!=set(a["first_m"]+a["first_g"]+a["first_p"]+a["reused_targets"]): raise ValueError("Atomic contrast split")
                    if any(k not in first for k in a["reused_targets"]): raise ValueError("Source reuse before introduction")
                    if a["kind"]=="production" and any(k not in first for k in a["first_p"]): raise ValueError("P before R")
                    if a["kind"]=="assessment" and late!=set(items): raise ValueError("Exam before integration")
                else:
                    if any(first.get(k,n)>=n for k in c["targets"]): raise ValueError("Reuse before introduction")
                    if any(items[k]["family"]!=c["family"] for k in c["targets"]): raise ValueError("Unrelated contact targets")
                    counts=Counter(items[k]["kind"] for k in c["targets"])
                    if counts["lex"]>b["reuse_lex"] or counts["G"]>1 or counts["M"]>1: raise ValueError("Reuse budget")
                    if c["phase"]=="late_integration": late.update(c["targets"])
                for k in c["targets"]:
                    if k not in items: raise ValueError("Unknown target")
                    first.setdefault(k,n)
                p_seen.update(d["first_p"])
            if gc>caps["G"]: raise ValueError("New grammar contact budget")
            if d["stage"]=="P6" and (d["first_m"]+d["first_g"]+d["first_p"]+d["lex_A"]+d["lex_R"]+d["lex_choice"]): raise ValueError("New material in P6")
        if order!=expected or set(first)!=set(items) or late!=set(items) or len(p_seen)!=42: raise ValueError("Incomplete cumulative repertoire")
        if p!=pack(profile,items,activities,sequence,plan["policy"]): raise ValueError("Stale plan/counters/trajectories")

def render(plan):
    items=plan["learning_items"]
    lines=["# Накопительная языковая программа по дням","",
        "**Проект возможностей практики, не измерение усвоения.** Входы полностью независимы от сюжета. Прежние 48/65/83 учитывали неполный объём; новая длительность включает продолжающуюся практику.","",
        "## Состав и метод","",
        f"В репертуаре весь каталог: {sum(x['kind']=='lex' for x in items.values())} выражений/форм, 55 M и 34 G. Каждой записи назначены знакомство и дальнейшее применение. Активные роли практикуются через собственный смысловой ответ с учётом продуктивного минимума M/G; рецептивные и контекстные — через понимание. Например, личные отношения M36 сохраняют R-минимум. Роль не исключает запись из практики. Это не леммы и не выученные слова; точное воспроизведение каждой формы по памяти не требуется.","",
        "Первая необходимая лексика готовится до использующего её контакта. Совместная G-пара не разрывается; отдельный G-контраст и самостоятельный P идут последовательно. Ранний LO привязан к завершению единицы.","",
        "Прежний репертуар остаётся в очереди: дольше не использованные цели получают приоритет. Контакты нового и прежнего делят общую вместимость дня. На P6 весь репертуар участвует в поддержанной интеграции до независимых LO. Это критерий охвата, не число повторений для запоминания и не экзамен по каждому слову.","",
        "Каждый возврат связан с конкретным смысловым семейством и R/P. Вариант 1 требует изменить факты, 2 — адресата, 3 — жанр. Значение каждой отмеченной цели должно менять понимание/сообщение. Фоновое упоминание не засчитывается. Это требования к ситуациям: их семантическая реализация ещё не проверена.","",
        "## Длительность","","| Профиль | Дни | Контактов/день | Новых контактов максимум | Новых лексических фокусов | Лексических целей в возврате |","|---|---:|---:|---:|---:|---:|"]
    for name,p in plan["profiles"].items():
        b=plan["policy"]["profiles"][name]
        lines.append(f"| {name} | {p['total_days']} | {b['contacts']} | {b['new_contacts']} | {b['new_lex']} | {b['reuse_lex']} |")
    lines += ["","Бюджеты в LANGUAGE_CUMULATIVE_POLICY.json — редактируемые гипотезы, не педагогические нормативы. Минуты, работа F1, исправления, реальная трудность и интервалы проверяются на A0. Число возвратов получается из потока и вместимости; фиксированной квоты на слово нет.","",
        "Продуктивная лексическая практика начинается после соответствующего первого P, а не сразу после знакомства со словом. P проверяет смысл, допускает перефразирование и не требует точной временной формы: например, наличие ist gekommen в активном слое не делает продуктивный Perfekt с sein обязательным. Просьба уточнить остаётся добровольной; в обязательном возврате можно понять просьбу другого человека.","",
        "### Чувствительность базового профиля", "",
        "Меняется только совместный бюджет новой лексики; отдельные A/R-лимиты и весь состав языка сохранены. Это эксперимент с параметром, не рекомендуемая норма.", "",
        "| Совместный лексический бюджет | Слоты |", "|---|---:|"]
    model_items, model_activities, model_sequence, _ = source_model()
    for multiplier in (0.5, 1, 2):
        policy = copy.deepcopy(plan['policy'])
        amount = max(1, int(policy['profiles']['baseline']['new_lex'] * multiplier))
        policy['profiles']['baseline']['new_lex'] = amount
        result = pack('baseline', model_items, model_activities, model_sequence, policy)
        lines.append(f"| {amount} | {result['total_days']} |")
    lines += ["",
        "## Базовый календарь","","Накоплено = впервые введённые записи/G/M и первые самостоятельные P, а не знания учащегося.","",
        "| День | Этап | Новое M/G/P | Новая лексика A/R/выбор | Возврат лексики R/P | Возврат G/M | Накоплено лекс/G/M/P | Макс. пауза, слоты | LO |","|---:|---|---|---|---|---|---|---:|---|"]
    for d in plan["profiles"]["baseline"]["days"]:
        c=d["cumulative"];n=c["introduced"]
        join=lambda f: ','.join(d[f]) or '—'
        lines.append(f"| {d['day']} | {d['stage']} | {join('first_m')}/{join('first_g')}/{join('first_p')} | {len(d['lex_A'])}/{len(d['lex_R'])}/{len(d['lex_choice'])} | {len(d['reuse_lex_R'])}/{len(d['reuse_lex_P'])} | {join('revisit_g')}/{join('revisit_m')} | {n.get('lex',0)}/{n.get('G',0)}/{n.get('M',0)}/{c['first_independent_P']} | {c['longest_unpractised_slots']} | {','.join(d['early_lo']+d['assess_lo']) or '—'} |")
    lines += ["","## Содержание каждого дня",""]
    for d in plan["profiles"]["baseline"]["days"]:
        lines += [f"### День {d['day']} · {d['stage']}",""]
        for c in d["contacts"]:
            a=plan["activities"].get(c.get("activity"))
            target=', '.join(items[k].get('expression',k) for k in c['targets'])
            if a:
                lines.append(f"- {c['phase']} {c['mode']}: {target or ', '.join(a['assess_lo'])} — {a['purpose']} [{a['id']}].")
            else:
                contract=plan["semantic_contracts"].get(c["family"])
                meaning=contract["semantic_acceptance_rule_ru"] if contract else items[c["targets"][0]]["meaning"]
                modes=', '.join(f"{items[k].get('expression',k)}:{v}" for k,v in c['modes'].items())
                lines.append(f"- {c['phase']} · {c['family']}, вариант {c['context_variant']}: {modes}. {meaning}")
        lines.append("")
    lines += ["## Траектории и граница результата","",
        "JSON содержит learning_items, activities, контакты всех профилей и trajectories каждой цели: дни, роль и режим. Никакие цели не выключаются из очереди после N встреч. Паузы — игровые слоты, не реальные интервалы памяти.","",
        "PASS означает целостность плана. Семантическая необходимость всех целей контакта, F1, свободный ввод и отложенное применение требуют прототипа и реальных начинающих. Длительность полного сюжета до этого не фиксируется."]
    return '\n'.join(lines)+'\n'

def serialize(plan):
    """Keep generated records individually readable without 130k boilerplate lines."""
    compact = lambda value: json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    lines = ['{']
    for field in ('version','status','baseline_profile','policy','learning_items','activities','semantic_contracts'):
        value = plan[field]
        if field in ('learning_items','activities','semantic_contracts'):
            lines.append('  '+compact(field)+':{')
            rows = ['    '+compact(k)+':'+compact(v) for k,v in value.items()]
            lines.append(',\n'.join(rows))
            lines.append('  },')
        else:
            lines.append('  '+compact(field)+':'+compact(value)+',')
    lines.append('  "profiles":{')
    profiles = []
    for name,p in plan['profiles'].items():
        block = ['    '+compact(name)+':{', '      "total_days":'+str(p['total_days'])+',',
                 '      "stages":'+compact(p['stages'])+',', '      "days":[',
                 ',\n'.join('        '+compact(d) for d in p['days']), '      ],',
                 '      "trajectories":{', ',\n'.join('        '+compact(k)+':'+compact(v) for k,v in p['trajectories'].items()),
                 '      }', '    }']
        profiles.append('\n'.join(block))
    lines += [',\n'.join(profiles),'  }','}']
    return '\n'.join(lines)+'\n'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group();mode.add_argument('--write',action='store_true');mode.add_argument('--check',action='store_true')
    args=parser.parse_args();plan=build();validate(plan);report=render(plan)
    if args.write:
        (DOCS/'LANGUAGE_DAY_SCHEDULE.json').write_text(serialize(plan),encoding='utf-8')
        (DOCS/'LANGUAGE_DAY_SCHEDULE.md').write_text(report,encoding='utf-8')
    elif args.check:
        old=read('LANGUAGE_DAY_SCHEDULE.json');validate(old)
        if old!=plan or (DOCS/'LANGUAGE_DAY_SCHEDULE.md').read_text(encoding='utf-8')!=report: raise ValueError('Cumulative schedule/report outdated')
    for name,p in plan['profiles'].items(): print(f"{name}: {p['total_days']} cumulative opportunity slots")

if __name__=='__main__': main()
