# Регрессия LANGUAGE_PARSER_SPEC, разделы 6 и 9

Дата: 2026-11-09. Godot 4.7.1 stable, Windows, headless.

Источник: [LANGUAGE_PARSER_SPEC.md](https://github.com/ExecBit/language-life-sim/blob/docs/design-01-mvp-and-level-01/docs/LANGUAGE_PARSER_SPEC.md), актуальная версия ветки `docs/design-01-mvp-and-level-01`.

Итог: **358 unit-проверок — PASS; R01–R15 и W01–W07 — PASS (27 вариантов); все 14 тестовых скриптов — PASS.** Из них 9 скриптов проверяют существующие уровни 01–02. Изменений игрового парсера для новых случаев не потребовалось; добавлен отдельный регрессионный тест и проверка исправления собранной фразы через клавиатурные события.

## Игровая сцена: фактический автоматический прогон

Каждый независимый сценарий начинается со сброса. Проверяются status/intent/frame, отдельный ответ NPC, владение и визуальный родитель ключа, сохранение одного экземпляра, разрешение, количество открытий, состояние двери и фактическая проходимость через неё. При открытии Анной ожидается завершение её перемещения; первое мгновение распознавания не считается уже открытой дверью.

| ID | Реплика | Статус | Ответ NPC |
| --- | --- | --- | --- |
| R01 | `Ich will Schlüssel` | PASS | Hier, bitte. |
| R02/a | `Ich brauche den Schlüssel` | PASS | Hier, bitte. |
| R02/b | `Schlüssel bitte` | PASS | Hier, bitte. |
| R03 | `Wo ist der Schlüssel?` | PASS | Ich habe den Schlüssel. |
| R04 | `Ich habe keinen Schlüssel` | PASS | Soll ich dir helfen? |
| R05 | `Kannst du mir helfen?` | PASS | Wobei? |
| R06 | `Kannst du die Tür öffnen?` | PASS | Ja. Ich helfe dir. |
| R07 | `Warum ist die Tür zu?` | PASS | Das Zimmer ist privat. |
| R08 | `Kann ich die Tür öffnen?` | PASS | Ja. Du kannst das Zimmer öffnen. |
| R09 | `Schlüssel?` | PASS | Meinst du den Ort, oder möchtest du den Schlüssel? |
| R10 | `Ich brauchen Schlüssel` | PASS | Hier, bitte. |
| R11 | `Öffne die Tür nicht` | PASS | Okay. Ich mache das nicht. |
| R12 | `Ich will nicht öffnen` | PASS | Okay. Du möchtest das nicht. |
| R13 | `Anna hat keinen Schlüssel` | PASS | Verstanden. |
| R14 | `Ich will nicht, dass Anna die Tür öffnet` | PASS | Ich verstehe nicht. |
| R15/reference | `Das öffnen` | PASS | Was möchtest du genau? |
| R15/unknown | `Ich will Banane` | PASS | Ich verstehe nicht. |
| W01 | `Ich brauche den Schlüssel` | PASS | Hier, bitte. |
| W02 | `Ich brauche den Schlüssel` | PASS | Ich kann dir den Schlüssel nicht geben. |
| W03 | `Ich brauche den Schlüssel` | PASS | Später, bitte. |
| W04 | `Wo ist der Schlüssel?` | PASS | Der Schlüssel ist dort. |
| W05 | `Wo ist der Schlüssel?` | PASS | Das weiß ich nicht. |
| W06 | `Kannst du die Tür öffnen?` | PASS | Ja. Ich helfe dir. |
| W07/busy | `Kannst du die Tür öffnen?` | PASS | Später, bitte. |
| W07/no_access | `Kannst du die Tür öffnen?` | PASS | Ich kann die Tür nicht öffnen. |
| W07/no_key | `Kannst du die Tür öffnen?` | PASS | Ich kann die Tür nicht öffnen. |
| W07/no_permission | `Kannst du die Tür öffnen?` | PASS | Ich kann die Tür nicht öffnen. |

У R01 после передачи ключа проверяется возврат управления, наведение на дверь лучом и самостоятельное открытие через обработчик взаимодействия. У R06/W06 — движение Анны, открытие и повторная отправка без второго события. У R09 сначала проверяется неизменность мира при уточнении, затем возможность продолжить полной просьбой. W07 дополнительно разделён на отсутствие доступа, занятость, отсутствие ключа и отсутствие разрешения.

Машинный отчёт: `user://language_parser_regression.json`. В нём раздельно сохранены `parse`, `npc_reply`, `world_before`, `world_after_reply`, `world_at_end`; последнее состояние может включать явно проверенное продолжение сценария. Например, у R09 ключ передаётся только после последующей полной просьбы, а не после `Schlüssel?`.

## Запущенные скрипты

| Скрипт | Статус |
| --- | --- |
| `experiments/communication/test.gd` | PASS |
| `experiments/communication/test_input.gd` | PASS |
| `experiments/communication/test_world.gd` | PASS |
| `experiments/communication/test_pause.gd` | PASS |
| `game/prologue/test_story.gd` | PASS |
| `game/prologue/test_cooking.gd` | PASS |
| `game/prologue/test_day2_realtime.gd` | PASS |
| `game/prologue/test_walking.gd` | PASS |
| `game/shop/test_state.gd` | PASS |
| `game/shop/test_world.gd` | PASS |
| `game/shop/test_bridge.gd` | PASS |
| `game/shop/test_restart.gd` | PASS |
| `game/shop/test_navigation.gd` | PASS |
| `experiments/communication/test_regression.gd` | PASS |

В `test_input.gd` префиксы `ich`, `will`, `sch`, выбор слов и отправка проходят через `InputEventKey` → viewport → сфокусированный LineEdit, без прямого вызова сигнала отправки. Перед отправкой в собранную фразу добавляется ошибочный символ и удаляется Backspace; результат сохраняется. Отдельно Enter отправляет запрет, не открывая дверь.

Уровень 01: сюжетные ветки/миграция сохранений, необязательное приготовление, диалог после обращения, отказ от помощи без принудительного разговора, движение/анимация и пауза. Уровень 02: покупка в разных порядках, разговор и указание продавцу, пауза/отмена, оплата и упаковка, возврат домой, распаковка, повторное создание сцены из сохранения, переход из уровня 01, проходимость магазина. Это автоматическая регрессия; визуальное прохождение человеком не засчитывается.

## Воспроизведение

Запускать из корня Cogito; `godot` заменить именем своего исполняемого файла:

```powershell
godot --headless --path . --script res://experiments/communication/test.gd
godot --headless --path . --script res://experiments/communication/test_input.gd
godot --headless --path . --script res://experiments/communication/test_world.gd
godot --headless --path . --script res://experiments/communication/test_pause.gd
godot --headless --path . --script res://experiments/communication/test_regression.gd
# Аналогично для каждого скрипта уровней 01–02 из таблицы выше.
```

Проверка выполнена в изолированной копии `work/CogitoValidation` с актуальными скриптами/сценами проекта. APPDATA и LOCALAPPDATA перенаправлены в рабочие тестовые папки, поэтому тестовые сохранения не перезаписывают обычный прогресс пользователя. Логи: `work/parser_regression_*.log`; сводка скриптов — `work/parser_regression_suites.json` в рабочей папке Codex.

## Ручная проверка: NOT_RUN

В этом прогоне графическое окно не запускалось. Headless не проверяет реальный захват указателя, перевод OS-клавиатуры, читаемость панели и удобство камеры. Эти пункты не засчитаны как пройденные:

| Пункт | Статус | Причина и ручная проверка |
| --- | --- | --- |
| Ввод и Enter с физической клавиатуры | NOT_RUN | F6 в `COMMUNICATION_EXPERIMENT.tscn`, T рядом с Анной; набрать `ich`, Enter, `will`, Enter, `sch`, Enter, затем Enter для отправки. Проверено только через viewport-события. |
| Исправление фразы в графическом UI | NOT_RUN | До отправки добавить ошибочный символ в поле реплики, удалить Backspace, изменить слово и убедиться, что отправлена исправленная фраза. Автотест редактирования прошёл. |
| Возврат FPS и захват мыши | NOT_RUN | Закрыть разговор, проверить WASD/мышь, указание и возврат из выбора предмета, затем Esc/продолжение. Логическое снятие блокировки движения проверено автоматически. |
| Полное визуальное прохождение пути с ключом | NOT_RUN | Сброс, попросить ключ, увидеть передачу, закрыть ввод, подойти к двери и E, пройти в комнату. Headless-путь пройден. |
| Полное визуальное прохождение пути Анны | NOT_RUN | Сброс, `Kannst du die Tür öffnen?`; наблюдать подход, открытие и пройти следом. Headless-путь пройден. |
| Ручное повторение R01–R15/W01–W07 | NOT_RUN | Повторить реплики/пресеты из таблицы со сбросом между независимыми случаями; все эти случаи прошли автоматически. Поля знания/доступа/разрешения, отсутствующие в кнопках, менять в Remote Inspector у контекста либо проверять через тестовый сценарий. |
| Визуальный прогон уровней 01–02 | NOT_RUN | Запустить пролог, проверить диалог/передачу предмета, перейти к магазину и проверить разговор/покупку/возврат. Девять автоматических тестов пройдены. |

## Ограничения логов

Во время этого прогона нет ошибок GDScript или проваленных проверок. При выходе Godot остаются `ObjectDB instances were leaked` и `resources still in use`; они встречаются и в существующих тестах уровней и не исправлялись в этой задаче. Headless сообщает об отсутствии rendering device для DynamicInputIcon. В изолированной копии некоторые сцены пролога загружают скрипт по текстовому пути после предупреждения об устаревшем UID в кэше. Поэтому PASS относится к перечисленным игровым проверкам, а не к отсутствию всех диагностических сообщений движка.

Ветка проекта остаётся `feat/communication-experiment`; этот отчёт не означает создание или слияние PR.
