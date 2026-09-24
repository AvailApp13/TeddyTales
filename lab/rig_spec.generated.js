// GENERATED FILE - DO NOT EDIT BY HAND.
// Source of truth: rig/bear_rig.json   Regenerate: cd tools && npm run gen:dart
export const rigSpec = {
  "specVersion": 1,
  "artboards": {
    "boy": "Bear_Boy",
    "girl": "Bear_Girl"
  },
  "artboard": "Bear_Boy",
  "enums": {
    "stage": {
      "values": [
        "newborn",
        "crawler",
        "first_steps",
        "growing",
        "adult"
      ],
      "status": "spec",
      "origin": "kp:5.1-5.5",
      "labels": {
        "newborn": "Новорождённый (1 день)",
        "crawler": "Ползающий малыш (~2 дня)",
        "first_steps": "Первые шаги (1-2 дня)",
        "growing": "Подрастающий (до ~14 дня)",
        "adult": "Взрослый (постоянно)"
      }
    },
    "trait": {
      "values": [
        "active",
        "curious",
        "affectionate",
        "calm",
        "independent",
        "reserved"
      ],
      "status": "spec",
      "origin": "kp:7.1",
      "labels": {
        "active": "активный",
        "curious": "любознательный",
        "affectionate": "ласковый",
        "calm": "спокойный",
        "independent": "самостоятельный",
        "reserved": "замкнутый"
      }
    },
    "mood": {
      "values": [
        "calm",
        "happy",
        "sad",
        "hungry",
        "sleepy",
        "messy"
      ],
      "status": "spec",
      "origin": "kp:4.2",
      "labels": {
        "calm": "спокойное",
        "happy": "радостное",
        "sad": "грустное",
        "hungry": "голодное",
        "sleepy": "сонное",
        "messy": "неухоженное"
      }
    }
  },
  "stateMachine": "State Machine 1",
  "viewModel": "BearVM",
  "properties": [
    {
      "name": "food",
      "type": "number",
      "min": 0,
      "max": 100,
      "default": 80,
      "safeFloor": 20,
      "status": "spec",
      "origin": "kp:6.1",
      "doc": "Еда. 0 - голоден, 100 - сыт."
    },
    {
      "name": "hygiene",
      "type": "number",
      "min": 0,
      "max": 100,
      "default": 80,
      "safeFloor": 20,
      "status": "spec",
      "origin": "kp:6.1",
      "doc": "Гигиена. 0 - неухожен, 100 - чистый."
    },
    {
      "name": "sleep",
      "type": "number",
      "min": 0,
      "max": 100,
      "default": 80,
      "safeFloor": 20,
      "status": "spec",
      "origin": "kp:6.1",
      "doc": "Сон. 0 - истощён, 100 - выспался."
    },
    {
      "name": "play",
      "type": "number",
      "min": 0,
      "max": 100,
      "default": 80,
      "safeFloor": 20,
      "status": "spec",
      "origin": "kp:6.1",
      "doc": "Игра. 0 - скучает, 100 - наигрался."
    },
    {
      "name": "love",
      "type": "number",
      "min": 0,
      "max": 100,
      "default": 80,
      "safeFloor": 20,
      "status": "spec",
      "origin": "kp:6.1",
      "doc": "Любовь. 0 - обделён вниманием, 100 - обласкан."
    },
    {
      "name": "care_index",
      "type": "number",
      "min": 0,
      "max": 100,
      "default": 80,
      "status": "derived",
      "origin": "kp:5.7",
      "doc": "Среднее пяти показателей. Считает приложение, риг только потребляет - чтобы формула менялась с сервера (КП 15.4), а не в .riv."
    },
    {
      "name": "stage",
      "type": "enum",
      "enumName": "stage",
      "default": "newborn",
      "status": "spec",
      "origin": "kp:5.1-5.5",
      "doc": "Текущая стадия роста. Длительности настраиваются с сервера (КП 5.6)."
    },
    {
      "name": "trait",
      "type": "enum",
      "enumName": "trait",
      "default": "calm",
      "status": "spec",
      "origin": "kp:7.1",
      "doc": "Тип характера. Влияет на покой, реакции и инициативы (КП 7.4)."
    },
    {
      "name": "mood",
      "type": "enum",
      "enumName": "mood",
      "default": "calm",
      "status": "derived",
      "origin": "kp:4.2",
      "doc": "Итоговое настроение покоя. Вычисляется приложением из пяти показателей, а не хранится на сервере."
    },
    {
      "name": "outfit_body",
      "type": "number",
      "min": 0,
      "max": 8,
      "default": 0,
      "status": "derived",
      "origin": "kp:4.9+10.5",
      "doc": "Слот «комплект». 0 - пусто, 1..8 - комплекты (КП 10.5)."
    },
    {
      "name": "outfit_head",
      "type": "number",
      "min": 0,
      "max": 3,
      "default": 0,
      "status": "derived",
      "origin": "kp:4.9+10.5",
      "doc": "Слот «головной убор». 0 - пусто, 1..3."
    },
    {
      "name": "outfit_feet",
      "type": "number",
      "min": 0,
      "max": 2,
      "default": 0,
      "status": "derived",
      "origin": "kp:4.9+10.5",
      "doc": "Слот «обувь». 0 - пусто, 1..2."
    },
    {
      "name": "outfit_accessory",
      "type": "number",
      "min": 0,
      "max": 3,
      "default": 0,
      "status": "derived",
      "origin": "kp:4.9+10.5",
      "doc": "Слот «аксессуар». 0 - пусто, 1..3."
    },
    {
      "name": "feed",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.3",
      "doc": "Кормление. feedBear()"
    },
    {
      "name": "wash",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.3",
      "doc": "Умывание. washBear()"
    },
    {
      "name": "sleep_action",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.3",
      "doc": "Укладывание спать. Имя с суффиксом, чтобы не конфликтовать с показателем sleep."
    },
    {
      "name": "wake",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.3",
      "doc": "Пробуждение."
    },
    {
      "name": "play_action",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.3",
      "doc": "Игра. Суффикс по той же причине, что и у sleep_action."
    },
    {
      "name": "pet",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.3",
      "doc": "Поглаживание. petBear()"
    },
    {
      "name": "tap",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:3.1",
      "doc": "Касание питомца на главном экране."
    },
    {
      "name": "grow",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.5",
      "doc": "Переход на следующую стадию: 2-3 секунды со свечением."
    },
    {
      "name": "initiative",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:3.4",
      "doc": "Пузырь инициативы - питомец сам предлагает активность."
    },
    {
      "name": "emote_joy",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.8",
      "doc": "Радость."
    },
    {
      "name": "emote_upset",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.8",
      "doc": "Огорчение."
    },
    {
      "name": "emote_surprise",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.8",
      "doc": "Удивление."
    },
    {
      "name": "emote_love",
      "type": "trigger",
      "status": "spec",
      "origin": "kp:4.8",
      "doc": "Проявление любви."
    }
  ],
  "states": [
    "idle",
    "move",
    "care_action",
    "emotion_accent",
    "trait_behaviour",
    "growth_transition"
  ],
  "nodes": [
    {
      "name": "root",
      "kind": "bone",
      "parent": null,
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "root_body",
      "kind": "bone",
      "parent": "root",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "body",
      "kind": "art",
      "parent": "root",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "body_base",
      "kind": "art",
      "parent": "root",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "head",
      "kind": "art",
      "parent": "root_body",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "head_shadow",
      "kind": "art",
      "parent": "root_body",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "root_arm_left",
      "kind": "bone",
      "parent": "root",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "forearm_left",
      "kind": "art",
      "parent": "root_arm_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "forearm_light_left",
      "kind": "art",
      "parent": "forearm_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "hand_left",
      "kind": "art",
      "parent": "forearm_light_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "hand_light_left",
      "kind": "art",
      "parent": "hand_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "finger_1_nail_left",
      "kind": "art",
      "parent": "hand_light_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "finger_2_nail_left",
      "kind": "art",
      "parent": "hand_light_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "finger_3_nail_left",
      "kind": "art",
      "parent": "hand_light_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "root_arm_right",
      "kind": "bone",
      "parent": "root",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "forearm_right",
      "kind": "art",
      "parent": "root_arm_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "forearm_light_right",
      "kind": "art",
      "parent": "forearm_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "hand_right",
      "kind": "art",
      "parent": "forearm_light_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "hand_light_right",
      "kind": "art",
      "parent": "hand_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "finger_1_nail_right",
      "kind": "art",
      "parent": "hand_light_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "finger_2_nail_right",
      "kind": "art",
      "parent": "hand_light_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "finger_3_nail_right",
      "kind": "art",
      "parent": "hand_light_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "ear_left",
      "kind": "art",
      "parent": "head",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "root_ear_left",
      "kind": "bone",
      "parent": "ear_left",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ear_in_left",
      "kind": "art",
      "parent": "ear_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "ear_light_left",
      "kind": "art",
      "parent": "ear_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "ear_right",
      "kind": "art",
      "parent": "head",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "root_ear_right",
      "kind": "bone",
      "parent": "ear_right",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ear_in_right",
      "kind": "art",
      "parent": "ear_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "ear_light_right",
      "kind": "art",
      "parent": "ear_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "ctrl_face",
      "kind": "control",
      "parent": "head",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ctrl_eyes",
      "kind": "control",
      "parent": "ctrl_face",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ctrl_pupils",
      "kind": "control",
      "parent": "ctrl_eyes",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ctrl_mouth",
      "kind": "control",
      "parent": "ctrl_face",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ctrl_nose",
      "kind": "control",
      "parent": "ctrl_face",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ctrl_eyebrow_left",
      "kind": "control",
      "parent": "ctrl_face",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "ctrl_eyebrow_right",
      "kind": "control",
      "parent": "ctrl_face",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "eye_left",
      "kind": "art",
      "parent": "ctrl_eyes",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "pupil_left",
      "kind": "art",
      "parent": "ctrl_pupils",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "pupil_light_left",
      "kind": "art",
      "parent": "pupil_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eyelid_top_left",
      "kind": "art",
      "parent": "eye_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eyelid_bottom_left",
      "kind": "art",
      "parent": "eye_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eyebrow_left",
      "kind": "art",
      "parent": "ctrl_eyebrow_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eye_right",
      "kind": "art",
      "parent": "ctrl_eyes",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "pupil_right",
      "kind": "art",
      "parent": "ctrl_pupils",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "pupil_light_right",
      "kind": "art",
      "parent": "pupil_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eyelid_top_right",
      "kind": "art",
      "parent": "eye_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eyelid_bottom_right",
      "kind": "art",
      "parent": "eye_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "eyebrow_right",
      "kind": "art",
      "parent": "ctrl_eyebrow_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "nose",
      "kind": "art",
      "parent": "ctrl_nose",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "mouth",
      "kind": "art",
      "parent": "ctrl_mouth",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "teeth",
      "kind": "art",
      "parent": "mouth",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "tongue",
      "kind": "art",
      "parent": "mouth",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "lips",
      "kind": "art",
      "parent": "mouth",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "scarf_1",
      "kind": "art",
      "parent": "root_body",
      "artistLayer": true,
      "optional": true
    },
    {
      "name": "scarf_2",
      "kind": "art",
      "parent": "scarf_1",
      "artistLayer": true,
      "optional": true
    },
    {
      "name": "scarf_3",
      "kind": "art",
      "parent": "scarf_2",
      "artistLayer": true,
      "optional": true
    },
    {
      "name": "root_leg_left",
      "kind": "bone",
      "parent": "root",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "leg_left",
      "kind": "art",
      "parent": "root_leg_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "foot_left",
      "kind": "art",
      "parent": "leg_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "root_leg_right",
      "kind": "bone",
      "parent": "root",
      "artistLayer": false,
      "optional": false
    },
    {
      "name": "leg_right",
      "kind": "art",
      "parent": "root_leg_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "foot_right",
      "kind": "art",
      "parent": "leg_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "sleeve_left",
      "kind": "art",
      "parent": "root_arm_left",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "sleeve_right",
      "kind": "art",
      "parent": "root_arm_right",
      "artistLayer": true,
      "optional": false
    },
    {
      "name": "hood_lining",
      "kind": "art",
      "parent": "root_body",
      "artistLayer": true,
      "optional": false
    }
  ],
  "simulation": {
    "status": "draft",
    "note": "Скорости затухания настраиваются из панели управления (КП 15.4) и здесь не зафиксированы. Значения ниже - заглушки для лаборатории и стенда, в продакшен не идут. Безопасный предел (КП 6.3) берётся из safeFloor каждого показателя.",
    "decayPerSecond": {
      "food": 0.6,
      "hygiene": 0.35,
      "sleep": 0.45,
      "play": 0.5,
      "love": 0.4
    },
    "actionBoost": {
      "feed": {
        "food": 30,
        "love": 3
      },
      "wash": {
        "hygiene": 35
      },
      "sleep_action": {
        "sleep": 40
      },
      "wake": {
        "sleep": 5,
        "play": 5
      },
      "play_action": {
        "play": 30,
        "love": 5
      },
      "pet": {
        "love": 25
      },
      "tap": {
        "love": 2
      },
      "emote_love": {
        "love": 5
      }
    }
  },
  "riveAsset": "assets/rive/bear.riv"
};
