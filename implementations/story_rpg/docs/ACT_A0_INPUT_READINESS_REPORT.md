# Холодный старт A0 и необходимый Input: проверка проектной доступности

**Статус: рабочий аудит P0–P2 (D01–D09), НЕ пользовательское тестирование, НЕ проверка реализованного F1, НЕ доказательство запоминания.** [Случаи с критериями](ACT_A0_READINESS_CASES.json), [канонический корпус](ACT_DIALOGUE_SITUATIONS.json), [смысловые R/P-аннотации](ACT_SEMANTIC_CONTACT_ANNOTATIONS.json).

## 1. Почему новый текст — не количество выученных слов

В каждой строке R-лексемы — **впервые встреченные** в обязательном немецком тексте дня, а «опоры needed_R» — только выборочные лексемы в аннотированных *кандидатах действительно необходимого понимания*. Неразмеченная R-строка не объявляется бессмысленной; R-якоря и впервые увиденные слова пересекаются и не складываются.

| Слот | Горизонт | Обязат. R строк | R словоупотреблений | Новые R-лексемы | Аннот. needed_R строк | Разные needed_R опоры | Их опоры впервые в R |
|---|---|---:|---:|---:|---:|---:|---:|
| D01 | P0 | 10 | 40 | 24 | 4 | 6 | 6 |
| D02 | P1 | 11 | 42 | 15 | 3 | 4 | 4 |
| D03 | P1 | 6 | 21 | 6 | 2 | 4 | 2 |
| D04 | P1 | 11 | 47 | 16 | 2 | 4 | 3 |
| D05 | P1 | 6 | 24 | 4 | 2 | 3 | 0 |
| D06 | P2 | 11 | 54 | 15 | 2 | 6 | 5 |
| D07 | P2 | 11 | 45 | 8 | 3 | 5 | 3 |
| D08 | P2 | 12 | 56 | 17 | 3 | 6 | 4 |
| D09 | P2 | 6 | 25 | 4 | 2 | 4 | 1 |

**Не выводить «прошёл D01 → освоил 24 слова».** Игрок видит даже те слова, которые не должен уметь объяснить на первом контакте. Уровни P0–P2 — авторские горизонты, а не реальные дни учёбы.

## 2. Четырнадцать сценарных проверок

| Проверка | День | R → P | Статус | Что нужно проверить |
|---|---|---|---|---|
| `A0-01` | D01 | `D01-S1-R1` → `D01-S1-P1` | `needs_ui_validation` | Accept Hallo, Hallo Lena, another clear greeting; do not require grammatical sentence. |
| `A0-02` | D01 | `D01-S1-R4` → `D01-S1-P2` | `needs_gameplay_validation` | Swap the named target in a counterfactual; correct physical selection must change. Taking the other object must be repairable. |
| `A0-03` | D01 | `D01-S1-R2` → `D01-S1-P3` | `needs_ui_validation` | Test both routes: player understands and proceeds without P3; player uses Noch einmal bitte / Ich verstehe nicht and gets a repeat. |
| `A0-04` | D01 | `D01-S2-R3` → `D01-S2-P2` | `needs_f1_contract` | Test A0 with empty prior knowledge: the player can ask Wo Arzt? or similar; answer in R5 comes after the question, not before. |
| `A0-05` | D01 | `D01-S2-R2` → `D01-S2-P1` | `needs_gameplay_validation` | Changing nicht should alter the safe interpretation; if visuals alone determine the route, relabel this contact as contextual, not necessary. |
| `A0-06` | D02 | `D02-S1-R3` → `D02-S1-P1` | `needs_state_contract` | Accept short Ich müde, Ich bin müde, or unambiguous negation if the game condition allows it. Do not demand a fixed medical state without evidence. |
| `A0-07` | D02 | `D02-S1-R4` → `D02-S1-P2` | `needs_state_contract` | Test yes/no symptom contrasts and clarify when ambiguous. If pain is impossible to know, do not claim that negative P proves comprehension. |
| `A0-08` | D03 | `D03-S1-R2` → `D03-S1-P1` | `needs_gameplay_validation` | Wrong object or bare Bitte must not deliver water; Wasser bitte or an equivalent short request works. |
| `A0-09` | D04 | `D04-S1-R3` → `D04-S1-P2` | `needs_gameplay_validation` | Negative meaning changes the report: Lamp kaputt vs nicht kaputt cannot both be accepted for the same observed state. |
| `A0-10` | D05 | `D05-S1-R3` → `D05-S1-P1` | `needs_f1_contract` | Compare player asking for location with merely naming Lampe. R4 supplies 'im Zimmer' only after P1. |
| `A0-11` | D06 | `D06-S1-R4` → `D06-S1-P1` | `needs_gameplay_validation` | Try counterfactual layout (if the safe exit is right, text and outcome change) and check R4 comprehension, not just whether player follows an open passage. |
| `A0-12` | D07 | `D07-S1-R6` → `D07-S1-P2` | `needs_f1_contract` | Actor ownership and site must be distinguished; learner can ask Wo Lagerverwalter? and follow understood location. |
| `A0-13` | D08 | `D08-S1-R4` → `D08-S1-P1` | `needs_medium_contract` | Check that player conveys their own local green status; copied red remote status is wrong. Verify the odd audio-language line remains just incidental. |
| `A0-14` | D09 | `D09-S1-R2` → `D09-S1-P1` | `needs_gameplay_validation` | With a different damage count, the correct usable count changes, and the requested quantity must remain player-driven. |

## 3. Приоритетные решения и открытые зависимости

### P0 · D01: обязательные решения исправлены, UI неизвестен

- Первое приветствие теперь допускает короткий ответ на приветствие. Это допустимая **имитация для старта**, но не проверка усвоения.
- Просьба повторить `Noch einmal, bitte` доступна после непонятной инструкции, однако **не обязательна**, если игрок всё понял; несколько P-ответов могут быть доступны на одной стадии.
- В `D01-S2` слово `Arzt` видно на табличке **без стрелки**, `Wo ist der Arzt?` возникает до ответа Лены `Der Arzt ist dort.`. Важный риск — умеет ли новичок найти `wo` по русскому «где» в F1. **Наличие словаря «всего акта» не доказывает наличие обратного поиска.**
- `Nein, nicht dort` и `Nimm den Schlüssel` нельзя засчитывать как понимание, если правильный путь или предмет выделены визуально.

### P1 · D02–D05: независимость смысла и состояния

- `Bist du müde?` и `Hast du Schmerzen?` требуют знания **состояния персонажа**, а не только словаря. Нельзя заставлять игрока сообщать «не больно», если игра не сообщает об этом.
- В `D05-S1` местоположение лампы больше **не известно до вопроса**: R3 обозначает потребность, P1 спрашивает где, R4 сообщает `im Zimmer`.
- В D03 различать воду и хлеб имеет смысл по цели героя; если UI подсказывает нужное немецкое слово, это перестаёт быть проверкой самостоятельной просьбы.

### P2 · D06–D09: отделить грамотную реакцию от угадывания

- D06: закрытая правая дверь сама по себе может выдать правильный маршрут, даже без понимания `links`/ `rechts`. Нужен вариант, где маршруты до прочтения остаются правдоподобны; иначе считать этот R-контакт **фоновым**, а не необходимым.
- D07: порядок `R5 → P2 → R6` сохраняет действительный вопрос о местоположении снабженца. Для A0 нужен способ обнаружить составное слово `Lagerverwalter` в F1.
- D08: `Hörst du mich?` — фраза из устного канала в игре с письменным общением. Допустима как реалистичная реплика, если не требует аудирования и не служит обязательной R-проверкой.
- D09: три лампы/одна неисправна/две исправны — проверка числа и статуса только тогда, когда нет русского автоматического пересчёта и правильного подсвеченного слота.

### Общий контракт F1 перед реальной проверкой

1. **Поиск от нужного смысла:** как A0 получает немецкие `wo`, `Arzt`, `Schlüssel` и другие значения без знания немецкого написания? Нужна навигация по родному значению или иная доказуемо доступная модель, а не просто список немецких лемм.
2. **Показ нужных форм:** `nimm` / `nehmen`, `brauche` / `brauchen` и краткие типовые ответы доступны для понимания без готовой сценарной фразы, которую можно механически копировать.
3. **Повтор и непонимание:** F1 и повтор реплики доступны в любой критический момент, не блокируют прогресс и не считают помощь признаком усвоения.
4. **Контрфакты:** подмена объекта, отрицания, направления, адресата или состояния меняет правильное действие. Визуальные подсказки не должны самостоятельно выдавать ответ.
5. **Состояние и последствия:** игроку действительно доступен факт собственного самочувствия, расположения предмета и локального показания; система не ждёт знание, которого нельзя получить.

## 4. Вывод и статус

- **Структурные дефекты D01/D05 исправлены**: необязательное уточнение, ответ на вопрос после самого вопроса.
- **14 контрфактических и интерфейсных проверок описаны, но не выполнены в запущенной игре.** Поэтому нельзя отметить P0–P2 как «доступно абсолютному A0» или назначить число дней.
- На текущем этапе блокируют **утверждение** программы: обратная доступность F1, обоснованность состояния D02, необходимость R при визуально очевидном маршруте D06, варианты ошибок и повторения. Блокирующие зависимости не равны обязательным изменениям сюжета.
- Дальнейший шаг по LP09: проверить настоящие переходы/действия и минимальные варианты ответов при A0, затем LP10 — трассировка M## / G## / LO##. Никакой механической нормы «новых слов/день» пока не устанавливать.
