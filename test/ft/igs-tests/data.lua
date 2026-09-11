--- Two items that spoil, for the tests that are about spoiling.
---
--- Made here rather than borrowed from Space Age, so that the suite can run on a vanilla
--- game and so that what is tested is the rule -- does this item turn into something when
--- it goes off -- rather than the name of one item that happens to follow it. They wear the
--- iron plate's icon and behave in every other respect like anything else an inserter
--- carries.
---
--- igs-tests is never published, so neither of these can reach a player's game.
local icon = data.raw.item["iron-plate"].icon


data:extend({
  {
    type = "item",
    name = "igs-hatching-thing",
    icon = icon,
    subgroup = "raw-material",
    order = "z[igs]-a[hatching]",
    stack_size = 50,
    spoil_ticks = 60 * 60,
    spoil_to_trigger_result = {
      items_per_trigger = 10,
      trigger = {
        type = "direct",
        action_delivery = {
          type = "instant",
          source_effects = { { type = "create-entity", entity_name = "small-biter" } },
        },
      },
    },
  },
  -- the control: spoils, but only into another item, the way food does
  {
    type = "item",
    name = "igs-spoiling-thing",
    icon = icon,
    subgroup = "raw-material",
    order = "z[igs]-b[spoiling]",
    stack_size = 50,
    spoil_ticks = 60 * 60,
    spoil_result = "iron-plate",
  },
})

--- Half of a fake loader.
---
--- The shape the loader mods use: invisible, needing no power, turning a full half circle
--- in a single tick, and with its two ends placed wherever the mod wanted them rather than
--- where an inserter prototype normally puts them. It exists here so the suite can ask what
--- the mod does when a factory is full of them, without depending on any of those mods.
local vanilla = data.raw.inserter["inserter"]
data:extend({
  {
    type = "inserter",
    name = "igs-fake-loader",
    icon = icon,
    flags = { "placeable-neutral", "player-creation" },
    max_health = 100,
    collision_box = { { -0.15, -0.15 }, { 0.15, 0.15 } },
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    rotation_speed = 1.0,
    extension_speed = 1.0,
    pickup_position = { 0, -1 },
    insert_position = { 0, 1 },
    allow_custom_vectors = true,
    energy_source = { type = "void" },
    energy_per_movement = "1J",
    energy_per_rotation = "1J",
    hand_base_picture = vanilla.hand_base_picture,
    hand_closed_picture = vanilla.hand_closed_picture,
    hand_open_picture = vanilla.hand_open_picture,
    hand_base_shadow = vanilla.hand_base_shadow,
    hand_closed_shadow = vanilla.hand_closed_shadow,
    hand_open_shadow = vanilla.hand_open_shadow,
    platform_picture = vanilla.platform_picture,
  },
})
