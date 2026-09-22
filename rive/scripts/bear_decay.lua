-- Затухание показателей для превью в Rive Editor.
--
-- Паттерн из официального туториала Rive (Sasquatch): значение падает со
-- временем, растёт от действия и управляет blend state.
--
-- ВАЖНО: в приложении это НЕ источник истины. По КП 15.4 скорости показателей
-- настраиваются из панели управления, то есть решает сервер, а затухание между
-- синхронизациями сглаживает BearController.startDecay() на стороне Flutter.
-- Скрипт нужен, чтобы в редакторе было видно, как мишка «проседает» без ухода,
-- и чтобы отладить переходы состояний до подключения приложения.

local vm = Data.BearVM.instance()

-- Заглушки, синхронные с rig/bear_rig.json -> simulation.decayPerSecond.
-- Не согласованы с Заказчиком, см. docs/open-questions.md, Q2.
local DECAY = {
    food    = 0.6,
    hygiene = 0.35,
    sleep   = 0.45,
    play    = 0.5,
    love    = 0.4,
}

-- Безопасный предел: КП 6.3 — при долгом отсутствии показатели не падают ниже
-- заданного уровня. Конкретная цифра — открытый вопрос Q3.
local SAFE_FLOOR = 20

local METERS = { "food", "hygiene", "sleep", "play", "love" }

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function update(elapsedSeconds)
    local total = 0

    for _, meter in ipairs(METERS) do
        local current = vm[meter]
        local next = clamp(current - DECAY[meter] * elapsedSeconds, SAFE_FLOOR, 100)
        vm[meter] = next
        total = total + next
    end

    -- Общая ухоженность ведёт blend state care_level: КП 5.7 — скорость роста
    -- зависит от общего ухода, а не от одного показателя.
    vm.care_index = total / #METERS
end
