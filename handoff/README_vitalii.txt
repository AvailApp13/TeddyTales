МИШКА-МАЛЬЧИК v2 — всё для работы (обновлено: рукава, шея, скрытые зоны)
Основная копия — ветка AvailApp13/TeddyTales, claude/hero-animation-setup-exnpp8
(handoff/, rig/, tools/scripts/).

1_approved_bear/bear_boy_v2_full.png
    Утверждённый мишка (Higgsfield, без бирки, прозрачный фон, 1333×2000).

2_rig_layers/  — 11 слоёв для Rive
    foot_left, foot_right, shorts, shirt (корпус толстовки), paw_left, paw_right,
    sleeve_left, sleeve_right, ears, face, hood — порядок сзади вперёд.
    Каждый слой — полный кадр 1333×2000, ставятся одним общим трансформом.
    В покое складываются в утверждённого мишку без отличий. Под соседями у
    слоёв есть скрытые продолжения (корпус под капюшоном и рукавами, лапы под
    рукавами, стопы под шортами) — они открываются, когда части двигаются.

3_hidden_parts/  — отдельные части из Higgsfield (запас).

4_rive/
    bear_boy_v2.rev — файл редактора Rive: слои, группы рига, 6 костей,
                      группы привязаны к костям. Открывать в Rive (Import).
    bear_boy_v2.riv — тот же файл для приложения и лаборатории.
    bear_skeleton_cli.* — каркас рига из Rive CLI без арта.

5_grid_and_spec/ — сетка, спека рига (решения D12, D13), каталог клипов, id в Rive.

6_scripts/
    split_full_bear.py  — режет мишку на 11 слоёв со скрытыми продолжениями.
    simulate_pose.py    — проверка поз без редактора.
    place_layers_v3.mjs — кости, группы рукавов, слои в открытый Rive (MCP).
    pose_test.mjs       — пробные позы прямо в редакторе.
    draw_bones_guide.py — схема костей.
    measure_bear_v2.py, mac_upload_parts.py.

7_checks/ — схема костей, снимок редактора, проба поз.

Кости: root (таз -> шея), root_body (шея -> центр головы), root_arm_left/right,
root_leg_left/right; руки и ноги — внутри root.
