# Где брать готовую графику

Эти PNG уже есть в предыдущих наборах. Они повторно не генерировались и в новый архив не копировались. Не извлекать иконки из собранного макета.

| Элемент | Предыдущий архив | Точный путь внутри архива |
| --- | --- | --- |
| Монета | `Finora_Match3_6_Tiles_1024_PNG.zip` | `Finora_Match3_6_Tiles_Final/png/match3_coin.png` |
| Кошелёк | `Finora_Match3_6_Tiles_1024_PNG.zip` | `Finora_Match3_6_Tiles_Final/png/match3_wallet.png` |
| Мишень | `Finora_Match3_6_Tiles_1024_PNG.zip` | `Finora_Match3_6_Tiles_Final/png/match3_goal.png` |
| Щит | `Finora_Match3_6_Tiles_1024_PNG.zip` | `Finora_Match3_6_Tiles_Final/png/match3_shield.png` |
| Чек | `Finora_Match3_6_Tiles_1024_PNG.zip` | `Finora_Match3_6_Tiles_Final/png/match3_receipt.png` |
| График | `Finora_Match3_6_Tiles_1024_PNG.zip` | `Finora_Match3_6_Tiles_Final/png/match3_chart.png` |
| Бомба | `Finora_Match3_Bottom_HUD_8_PNG.zip` | `Finora_Match3_Bottom_HUD/png/booster_bomb.png` |
| Перемешивание | `Finora_Match3_Bottom_HUD_8_PNG.zip` | `Finora_Match3_Bottom_HUD/png/booster_shuffle.png` |
| Ещё 5 ходов | `Finora_Match3_Bottom_HUD_8_PNG.zip` | `Finora_Match3_Bottom_HUD/png/booster_extra_moves.png` |
| Молоток | `Finora_Match3_Bottom_HUD_8_PNG.zip` | `Finora_Match3_Bottom_HUD/png/booster_hammer.png` |
| Ячейка усилителя | `Finora_Match3_Bottom_HUD_8_PNG.zip` | `Finora_Match3_Bottom_HUD/png/booster_slot.png` |
| Плашка количества | `Finora_Match3_Bottom_HUD_8_PNG.zip` | `Finora_Match3_Bottom_HUD/png/booster_counter_badge.png` |
| Основа карточки | `Finora_Match3_Out_Of_Moves_15_PNG.zip` | `Finora_Match3_Out_Of_Moves/png/out_of_moves_panel_base.png` |
| Лавандовая плашка ходов | `Finora_Match3_Out_Of_Moves_15_PNG.zip` | `Finora_Match3_Out_Of_Moves/png/out_of_moves_button_restart_base.png` |
| Мятная кнопка | `Finora_Match3_Victory_11_PNG.zip` | `Finora_Match3_Victory/png/victory_button_primary_base.png` |
| Надпись Уровень | `Finora_Match3_Top_HUD_9_PNG.zip` | `Finora_Match3_Top_HUD/png/hud_level_label.png` |
| Пустая жемчужная круглая кнопка для закрытия | `Finora_Match3_Terrace_Map_3_BG_10_UI.zip` | `Finora_Match3_Terrace_Map/png/map_node_available.png` |

В `REUSED_ASSETS.json` также приведены размеры, видимые границы и SHA-256 существующих PNG. Пути относятся к ранее выданным наборам; в Flutter-проекте сначала найди уже импортированные файлы по имени и используй их существующий asset path. Если исходного набора в проекте нет, импортируй его из соответствующего старого архива.

Для окна по умолчанию используются монета, кошелёк и щит, а в выборе усилителей — бомба, перемешивание и +5 ходов. Остальные фишки и молоток перечислены как доступные существующие элементы, а не как требование добавить их на этот экран.