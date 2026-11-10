# Language Life Sim

Godot-проект с несколькими **независимыми игровыми реализациями**. Общая идея — сделать иностранный язык одной из игровых механик, а не отдельным учебным режимом. Каждый вариант проверяет собственную концепцию.

## Структура

- [Реализации и правила изоляции](implementations/README.md)
- [Общежитие — запуск и управление](implementations/dormitory/README.md)
- [Документация общежития](implementations/dormitory/docs/GAME_CONCEPT.md)
- [Лицензии и происхождение общих ресурсов](assets/PROVENANCE.md)

`implementations/<variant>/` — отдельный игровой код, сцены, документация, словари и тесты. Они не импортируют друг друга. Общими остаются `addons/` (Cogito и плагины), `assets/animations/` и `assets/characters/`.

Корневой `project.godot` — техническая точка входа в один проект Godot. Сейчас **F5 запускает общежитие** (`res://implementations/dormitory/game/prologue/prologue.tscn`); сцены других вариантов можно открывать отдельно через F6. Настройки сохранений разных вариантов должны быть независимыми.

## Проверка текущей реализации

```sh
python implementations/dormitory/tools/check_repository.py
python implementations/dormitory/tools/run_regressions.py
```

Для второго скрипта нужен Godot 4.7.1 в PATH либо переменная `GODOT`. Он проверяет только общежитие, а не другие варианты.
