# Разломы

Roblox-кликер. Дизайн-документ — «Плейс «Разломы» — полное описание (рабочее название).md».

## Как начать (один раз)

1. Установи [Roblox Studio](https://create.roblox.com/), [Git](https://git-scm.com/download/win), [Rojo 7.7](https://github.com/rojo-rbx/rojo/releases) (`rojo.exe` положи в папку из PATH) и плагин Rojo в Studio (`rojo plugin install`).
2. Склонируй: `git clone https://github.com/cloudyrr809/razlom.git`
3. В папке проекта: `rojo serve` (порт 34873).
4. Открой `Razlom.rbxl` в Studio → вкладка Plugins → Rojo → порт 34873 → Connect.
5. Если карты нет: в командной строке Studio выполни
   `loadstring(game.ServerScriptService.MapTools.BuildMap.Source)()`

Для работы с Claude Code: открой папку проекта в Claude Code, включи в Studio MCP-сервер (Assistant → Manage MCP Servers → Enable Studio as MCP server). Правила для Claude — в `CLAUDE.md`, скиллы — в `.claude/skills`.

## Как работаем вдвоём

- Перед работой: `git pull`.
- Каждая задача — своя ветка: `git switch -c имя-задачи`, потом Pull Request на GitHub, второй смотрит и мёржит.
- Скрипты (`src/`) и карта-скрипт (`tools/build_map.luau`) сливаются нормально.
- `Razlom.rbxl` — двоичный файл, git не умеет сливать его изменения. Карту меняем только через `tools/build_map.luau`; руками в Studio — не строим. Если `.rbxl` поменялся у обоих — берём любой и перезапускаем скрипт карты.
- Не работайте одновременно над одним и тем же файлом — договоритесь, кто что делает.
