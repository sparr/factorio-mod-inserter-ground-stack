--- A row of worked examples, built once on a new game.
---
--- Each station is the same shape -- a chest, an inserter taking from it, and bare ground on
--- the far side -- and differs only in what is in the chest and what is already lying on the
--- ground. Read from north to south, they go from the plain case to the ones where the mod
--- deliberately does nothing.
---
--- Everything is placed with raise_built, so the mod hears about it the way it would hear
--- about anything a player built.
local SPACE_AGE = script.active_mods["space-age"] ~= nil
local QUALITY = script.active_mods["quality"] ~= nil

--- Where the row starts, and how far apart the stations stand.
local START = { x = -6, y = -18 }
local APART = 5

--- What to put in the player's pockets, so the row is a starting point rather than the whole
--- of what can be tried.
local POCKETS = {
  { "inserter", 50 }, { "long-handed-inserter", 50 }, { "fast-inserter", 50 },
  { "bulk-inserter", 50 }, { "burner-inserter", 50 },
  { "steel-chest", 100 }, { "transport-belt", 200 }, { "underground-belt", 50 },
  { "splitter", 50 }, { "substation", 50 }, { "small-electric-pole", 50 },
  { "iron-plate", 1000 }, { "copper-plate", 1000 }, { "iron-gear-wheel", 1000 },
  { "barrel", 500 }, { "coal", 500 }, { "electric-mining-drill", 20 },
}

local function label(surface, at, text, colour)
  rendering.draw_text{
    text = text, surface = surface, target = { x = at.x - 1, y = at.y - 1.9 },
    color = colour or { r = 1, g = 1, b = 1 }, scale = 1.4, alignment = "left",
  }
end

---One station: a chest of something, an inserter, and bare ground beyond it.
---@return LuaEntity inserter
local function station(surface, at, opts)
  local chest = surface.create_entity{ name = "steel-chest", position = { at.x - 1, at.y },
    force = "player", raise_built = true }
  chest.insert{ name = opts.item, count = opts.count or 400, quality = opts.quality }
  local inserter = surface.create_entity{ name = opts.inserter or "bulk-inserter",
    position = { at.x, at.y }, direction = defines.direction.west,
    force = "player", raise_built = true }
  label(surface, at, opts.label, opts.colour)
  return inserter
end

local function build(surface)
  -- power for the whole row, well clear of everything it feeds
  local interface = surface.create_entity{ name = "electric-energy-interface",
    position = { START.x - 10, START.y }, force = "player" }
  interface.power_production = 1000000000
  for n = 0, 10 do
    surface.create_entity{ name = "substation",
      position = { START.x - 6, START.y + n * APART * 2 }, force = "player" }
  end

  local row = 0
  local function next_spot()
    local at = { x = START.x, y = START.y + row * APART }
    row = row + 1
    return at
  end

  -- 1. the plain case
  station(surface, next_spot(), {
    inserter = "inserter", item = "iron-plate",
    label = "1. Plain inserter, bare ground: the pile grows one item at a time" })

  -- 2. a whole hand at once
  station(surface, next_spot(), {
    inserter = "bulk-inserter", item = "iron-plate",
    label = "2. Bulk inserter: the whole hand goes onto the pile every swing" })

  -- 3. the pile stops at a full stack
  station(surface, next_spot(), {
    inserter = "bulk-inserter", item = "barrel", count = 200,
    label = "3. Barrels stack ten deep, so this pile stops at ten and the inserter waits" })

  -- 4. the same item at another quality will not join
  if QUALITY then
    local at = next_spot()
    local inserter = station(surface, at, {
      inserter = "bulk-inserter", item = "iron-plate",
      label = "4. An uncommon pile will not take normal plates: this one stays at one" })
    surface.create_entity{ name = "item-on-ground", position = inserter.drop_position,
      stack = { name = "iron-plate", count = 1, quality = "uncommon" } }
  end

  -- 5. eggs are left alone
  if SPACE_AGE then
    station(surface, next_spot(), {
      inserter = "bulk-inserter", item = "biter-egg", count = 200,
      colour = { r = 1, g = 0.6, b = 0.4 },
      label = "5. Eggs hatch in proportion to the pile, so the mod leaves them jammed" })
  end

  -- 6. and none of it is stranded
  do
    -- No feeder on this one. A pile already as deep as copper plates go, and an inserter
    -- taking it back a handful at a time onto a belt that runs into a chest. Feeding it as
    -- well would only produce a race: the drain takes each item the moment it lands, the
    -- pile never builds, and there is nothing to watch.
    local at = next_spot()
    label(surface, at, "6. Nothing is stranded: an inserter picks a deep pile back up")
    surface.create_entity{ name = "item-on-ground", position = { at.x - 0.5, at.y + 0.5 },
      stack = { name = "copper-plate", count = 100 } }
    surface.create_entity{ name = "bulk-inserter", position = { at.x, at.y },
      direction = defines.direction.west, force = "player", raise_built = true }
    -- The belt has to sit under the drop position, which is a shade over one tile out, not
    -- two. A belt one tile further away leaves the inserter dropping onto bare ground, and
    -- then this station quietly demonstrates the mod instead of the recovery.
    for n = 0, 3 do
      surface.create_entity{ name = "transport-belt", position = { at.x + 1, at.y + n },
        direction = defines.direction.south, force = "player", raise_built = true }
    end
    -- and an inserter at the end of it, because a belt pointed into a chest does not load
    -- the chest; something has to lift the items across
    surface.create_entity{ name = "inserter", position = { at.x + 1, at.y + 4 },
      direction = defines.direction.north, force = "player", raise_built = true }
    surface.create_entity{ name = "steel-chest", position = { at.x + 1, at.y + 5 },
      force = "player", raise_built = true }
  end

  -- 7. an inserter with somewhere to put things is no business of the mod
  do
    local at = next_spot()
    station(surface, at, {
      inserter = "bulk-inserter", item = "iron-gear-wheel",
      label = "7. An inserter with a chest in front of it is never watched at all" })
    surface.create_entity{ name = "steel-chest", position = { at.x + 1, at.y },
      force = "player", raise_built = true }
  end

  return { x = START.x + 6, y = START.y + (row - 1) * APART / 2 }
end

script.on_init(function()
  remote.call("freeplay", "set_disable_crashsite", true)
  remote.call("freeplay", "set_skip_intro", true)
  storage.built = false
  storage.equipped = false
end)

script.on_event(defines.events.on_tick, function()
  -- The row is built first and on its own, so that a headless run with nobody in the game
  -- still builds it and can be checked. Handing out pockets and standing somebody in front
  -- of it waits for there to be somebody.
  if not storage.built then
    local surface = game.surfaces[1]
    local force = game.forces.player
    -- everything researched, so the row can use whatever it likes and so can the player
    force.research_all_technologies()
    -- and if this is a game without the belt stacking technologies in it at all, the bonus
    -- they grant is still what the mod asks about, so grant it directly
    if force.belt_stack_size_bonus < 1 then force.belt_stack_size_bonus = 3 end

    surface.request_to_generate_chunks({ x = START.x, y = START.y + 20 }, 6)
    surface.force_generate_chunk_requests()
    surface.always_day = true

    storage.stand = build(surface)
    storage.built = true
    log("IGSDEMO built the row; standing spot " .. serpent.line(storage.stand))
    return
  end

  if storage.equipped then return end
  local player = game.players[1]
  if not (player and player.valid) then return end
  for _, entry in pairs(POCKETS) do
    if prototypes.item[entry[1]] then player.insert{ name = entry[1], count = entry[2] } end
  end
  player.teleport(storage.stand)
  player.print("Inserter Ground Stack demo: seven stations, north to south. "
    .. "Belt stacking is researched, so the mod is on.")
  player.print("The mod does nothing until belt stacking is researched: "
    .. "/c game.player.force.belt_stack_size_bonus = 0 turns it off again.")
  storage.equipped = true
end)
