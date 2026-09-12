--- Building inserters in a real game, and looking at what they left on the ground.
---
--- Every fixture is the same shape: a chest full of something, an inserter beside it
--- taking from the chest, and bare ground on the far side for it to put things down on.
--- That is the whole of what this mod is about, so the only thing a test varies is what is
--- in the chest, what is already lying on the ground, and what the force has researched.
---
--- The inserters are electric, so the arena carries its own power: one interface making
--- current out of nothing and one substation handing it round, both far enough from the
--- fixture rows that nothing an inserter does can reach them.
local world = {}

--- Where fixtures are built. Far enough from the origin of the test save that nothing else
--- is standing there.
world.ORIGIN = { x = 100.5, y = 100.5 }

--- How far a row of fixtures sits from the next. One tile of fixture and one of gap, which
--- is enough that nothing a row does lands in another.
world.ROW = 2

--- Long enough for an inserter to swing out, find the ground taken, be topped up, swing
--- back, and do it again several times over. A bulk inserter's swing is a few dozen ticks.
world.SETTLE = 300

--- Long enough for a single swing to finish and the inserter to be sitting on its jam.
world.JAM = 90

---@return LuaSurface
function world.surface() return game.surfaces[1] end

---Absolute position from an offset in tiles.
---@param dx number
---@param dy number
---@return MapPosition
function world.at(dx, dy)
  return { x = world.ORIGIN.x + dx, y = world.ORIGIN.y + dy }
end

---Put something down.
---
---raise_built matters: the mod learns which inserters put things on the ground from build
---events, and an entity made by a script raises none of them by default. A test that wants
---to know what the mod does about an inserter it never saw built asks for it explicitly.
---@param name string
---@param dx number
---@param dy number
---@param direction defines.direction?
---@param extra table? anything else create_entity should be told
---@return LuaEntity
function world.place(name, dx, dy, direction, extra)
  local args = {
    name = name,
    position = world.at(dx, dy),
    direction = direction or defines.direction.north,
    force = "player",
    raise_built = true,
  }
  for key, value in pairs(extra or {}) do args[key] = value end
  local entity = world.surface().create_entity(args)
  assert.is_not_nil(entity, ("could not place a %s at %d,%d"):format(name, dx, dy))
  return entity--[[@as LuaEntity]]
end

---Make the arena's power, once.
---
---The interface is a generator that needs no fuel and the substation reaches nine tiles in
---every direction, which covers every row a fixture is built in. Both stand west of the
---chests, where no inserter is pointing.
function world.power()
  if world.surface().find_entities_filtered{
      name = "substation", position = world.at(-5, 0), radius = 2 }[1] then
    return
  end
  local interface = world.place("electric-energy-interface", -9, 0)
  interface.power_production = 1000000
  world.place("substation", -5, 0)
end

---Build a fixture: a chest of something, and an inserter taking from it onto bare ground.
---
---The inserter faces the chest, which is to say west, and so puts things down to the east.
---@param row integer which row of the arena to build in, counting out from the middle.
---Rows -4 to 4 are within the substation's reach; further out is dark.
---@param opts { item: string?, count: integer?, inserter: string?, quiet: boolean? }?
---quiet builds the inserter without telling anybody, the way a script that forgets to
---raise_built does, so that a test can ask what the mod does about one it never saw.
---@return LuaEntity inserter
---@return LuaEntity chest
function world.rig(row, opts)
  opts = opts or {}
  local dy = row * world.ROW
  local chest = world.place("steel-chest", -1, dy)
  chest.insert{ name = opts.item or "iron-plate", count = opts.count or 1000 }
  local inserter = world.place(opts.inserter or "bulk-inserter", 0, dy,
    defines.direction.west, opts.quiet and { raise_built = false } or nil)
  return inserter, chest
end

---Build a fixture that carries its own power, anywhere at all.
---
---The arena on Nauvis has one substation for every row, which is cheaper but only works
---where the arena is. A platform and a planet each have their own surface and their own
---coordinates, so a fixture standing on one brings its own supply.
---@param surface LuaSurface
---@param at MapPosition where the inserter goes; it takes from the west and puts down east
---@param opts { item: string?, count: integer?, inserter: string?, force: string? }?
---@return LuaEntity inserter
---@return LuaEntity chest
function world.rig_on(surface, at, opts)
  opts = opts or {}
  -- Whose factory this is. It matters more than it looks: an electric network belongs to a
  -- force, so a fixture built for anyone but the player cannot draw on the arena's
  -- substation and has to bring the interface and substation below along with it.
  local force = opts.force or "player"
  local function put(name, dx, dy, direction)
    return surface.create_entity{ name = name, position = { at.x + dx, at.y + dy },
      direction = direction or defines.direction.north, force = force, raise_built = true }
  end
  local interface = put("electric-energy-interface", -6, 0)
  assert.is_not_nil(interface, "no power interface")
  interface.power_production = 10000000
  assert.is_not_nil(put("substation", -3, 0), "no substation")
  local chest = put("steel-chest", -1, 0)
  assert.is_not_nil(chest, "no chest")
  chest.insert{ name = opts.item or "iron-plate", count = opts.count or 1000 }
  local inserter = put(opts.inserter or "bulk-inserter", 0, 0, defines.direction.west)
  assert.is_not_nil(inserter, "no inserter")
  return inserter--[[@as LuaEntity]], chest--[[@as LuaEntity]]
end

---Everything lying within reach of a spot on any surface.
---@param surface LuaSurface
---@param at MapPosition
---@param radius number?
---@return integer
function world.loose_on(surface, at, radius)
  local total = 0
  for _, thing in pairs(surface.find_entities_filtered{
      type = "item-entity", position = at, radius = radius or 4 }) do
    if thing.valid and thing.stack.valid_for_read then total = total + thing.stack.count end
  end
  return total
end

---The one player the headless test save has.
---@return LuaPlayer
function world.player()
  local player = game.players[1]
  assert.is_not_nil(player, "the test save has no player to mine with")
  return player
end

---Mine something the way a player does, which is the path that raises the mining events.
---
---The player is put beside it first and sent home afterwards, since mining checks reach and
---a character left standing in the arena blocks the next test's fixtures.
---@param entity LuaEntity
function world.mine(entity)
  local player = world.player()
  world.home = world.home or (player.character and player.character.position)
  player.teleport{ x = entity.position.x, y = entity.position.y + 1 }
  local mined = player.mine_entity(entity, true)
  if world.home then player.teleport(world.home) end
  assert.is_true(mined, "the player could not mine it")
end

---Whatever is lying on the spot an inserter puts things down on.
---
---A radius rather than the exact spot, because a pile only has to be near enough for its
---collision box to overlap to be in the way, and a test that puts one down by hand puts it
---where it likes.
---@param inserter LuaEntity
---@return LuaEntity?
function world.pile(inserter)
  for _, thing in pairs(world.surface().find_entities_filtered{
      type = "item-entity", position = inserter.drop_position, radius = 0.4 }) do
    if thing.valid and thing.stack.valid_for_read then return thing end
  end
  return nil
end

---How many items are lying on the spot an inserter puts things down on.
---@param inserter LuaEntity
---@return integer
function world.piled(inserter)
  local pile = world.pile(inserter)
  return pile and pile.stack.count or 0
end

---Everything lying on the ground anywhere in the arena.
---@param item string?
---@return integer
function world.loose(item)
  local total = 0
  for _, thing in pairs(world.surface().find_entities_filtered{
      type = "item-entity", position = world.ORIGIN, radius = 40 }) do
    if thing.valid and thing.stack.valid_for_read
        and (not item or thing.stack.name == item) then
      total = total + thing.stack.count
    end
  end
  return total
end

---Everything an inserter and its chest between them still account for: what is in the
---chest, what is in the hand, and what is lying in front of it.
---@param inserter LuaEntity
---@param chest LuaEntity
---@param item string
---@return integer
function world.accounted(inserter, chest, item)
  local held = inserter.held_stack
  return chest.get_item_count(item)
    + ((held.valid_for_read and held.name == item) and held.count or 0)
    + world.piled(inserter)
end

---Let items stack, the way the research does.
---
---Set on the force rather than researched, because what the mod asks about is the bonus and
---not how a factory came by it, and because the research itself only exists with Space Age
---while the bonus is part of the base game.
---The mod is told afterwards, because handing a force the bonus from a script raises none
---of the events a finished research does, and the mod otherwise waits for its own once a
---second look to notice. Tests that are about that wait use world.stacking_quietly.
---@param bonus integer how many extra items ride in a stack, so 3 makes stacks of four
function world.stacking(bonus)
  game.forces.player.belt_stack_size_bonus = bonus
  world.refresh()
end

---Let items stack without telling the mod, the way a console command does.
---@param bonus integer
function world.stacking_quietly(bonus)
  game.forces.player.belt_stack_size_bonus = bonus
end

---How much a bulk inserter picks up in one go.
---@param bonus integer
function world.capacity(bonus)
  game.forces.player.bulk_inserter_capacity_bonus = bonus
end

---Tell the mod to look at the world again, for inserters it did not see being built.
function world.refresh()
  remote.call("inserter-ground-stack", "refreshData")
end

---Clear the arena so one test cannot see another's fixtures, and put the research back.
function world.clear()
  for _, thing in pairs(world.surface().find_entities_filtered{
      position = world.ORIGIN, radius = 40 }) do
    if thing.valid and thing.type ~= "character" then thing.destroy() end
  end
  local player = game.players[1]
  if player and world.home then player.teleport(world.home) end
  -- Every force, not just the player's: a test that gives a second force the research
  -- would otherwise leave the mod switched on for every test after it, since it is switched
  -- on by anybody at all having belt stacking.
  for _, force in pairs(game.forces) do
    force.belt_stack_size_bonus = 0
    force.bulk_inserter_capacity_bonus = 0
  end
  -- and tell the mod, so its list does not keep pointing at what has gone
  world.refresh()
end

---Make the ground the arena stands on, once, since the test save's world may not reach
---this far out on its own.
function world.prepare()
  local surface = world.surface()
  surface.request_to_generate_chunks(world.ORIGIN, 4)
  surface.force_generate_chunk_requests()
end

return world
