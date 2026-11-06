# Разломы

Идея и решения — в «Плейс «Разломы» — полное описание (рабочее название).md». Новые решения записывай в его конец.

- Скрипты — только `src/`, Rojo синхронизирует (`rojo serve`, порт 34873). В Studio скрипты не правь.
- Все числа — `src/shared/Config.luau`, формулы — `src/shared/Formulas.luau`. В логике чисел нет.
- Карта строится `tools/build_map.luau` (MCP, execute_luau в Edit: `loadstring(game.ServerScriptService.MapTools.BuildMap.Source)()`), живёт в `Razlom.rbxl`. После правок карты проси сохранить место (Ctrl+S).
- Проверка кода: `.\tools\check.ps1`. Потом — консоль Studio.
- Скиллы — `.claude/skills`.
