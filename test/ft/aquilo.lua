--- Inserters that have frozen solid.
---
--- Aquilo freezes everything that is not being kept warm, and a frozen inserter does not
--- swing, does not pick anything up and does not put anything down. What matters here is
--- that it says so: its status is `frozen` rather than the `waiting_for_space_in_destination`
--- that this mod acts on, so a frozen inserter is watched and never touched.
---
--- That distinction is the whole of the mod's Aquilo story, and it is worth a test because
--- it is an accident of which status the engine reports rather than anything the mod does
--- deliberately. An inserter that thaws is simply an inserter, and every other test in the
--- suite is about those.
---
--- Freezing cannot be asked for from a script -- LuaEntity::frozen is read only -- so the
--- fixture is stood on Aquilo with nothing to warm it and left to freeze on its own. Every
--- other thing the mod looks for is put in place by hand: a pile on the ground where the
--- inserter aims, and a handful in the inserter's own hand. The only reason it is not
--- topped up is the status.
---
--- Thawing is arranged the way a factory arranges it: a heating tower, and heat pipe run
--- from it to a tile orthogonally next to the thing that is to be kept warm. Standing a hot
--- tower nearby is not enough, however hot it is. Of everything in the fixture only the
--- inserter is freezable at all -- the chest, the substation and the power interface all
--- report that they are not -- so the pipe only has to reach the one.
local world = require("test.ft.world")

local SPACE_AGE = script.active_mods["space-age"] ~= nil

if not SPACE_AGE then
  describe("inserters that have frozen solid", function()
    it("needs Space Age, which is not loaded", function() end)
  end)
  return
end

local SPOT = { x = 40.5, y = 40.5 }

--- How far around the fixture to lay solid ground.
---
--- Aquilo is mostly ammoniacal ocean, and an inserter aimed at liquid cannot put anything
--- down at all: it jams holding everything, with nothing on the ground and nothing for this
--- mod to add to. That is its own case and has its own test below, but it is not the case
--- these tests are about, so the fixtures stand on ice platform that is laid for them.
local SOLID = 12

---Aquilo, made once and kept.
---@return LuaSurface
local function aquilo()
  local existing = game.surfaces["aquilo"]
  if existing then return existing end
  local surface = game.planets["aquilo"].create_surface()
  assert.is_not_nil(surface, "Aquilo could not be made")
  return surface--[[@as LuaSurface]]
end

---Keep a spot on Aquilo warm: a tower, fuelled and forced hot so the test does not wait for
---it to burn up to temperature, and heat pipe running along the row above the fixture.
---@param surface LuaSurface
---@param at MapPosition the inserter's spot; the pipe runs past the tile above it
local function heat(surface, at)
  local tower = surface.create_entity{ name = "heating-tower",
    position = { at.x + 4, at.y - 1 }, force = "player" }
  assert.is_not_nil(tower, "no heating tower")
  tower.insert{ name = "coal", count = 100 }
  tower.temperature = 500
  local laid = 0
  for x = at.x + 2, at.x - 2, -1 do
    if surface.create_entity{ name = "heat-pipe", position = { x, at.y - 1 },
        force = "player" } then
      laid = laid + 1
    end
  end
  assert.is_true(laid >= 4, ("only %d heat pipes went down"):format(laid))
end

local cold

before_each(function()
  cold = aquilo()
  cold.request_to_generate_chunks(SPOT, 3)
  cold.force_generate_chunk_requests()
  for _, thing in pairs(cold.find_entities_filtered{ position = SPOT, radius = 30 }) do
    if thing.valid and thing.type ~= "character" then thing.destroy() end
  end
  local tiles = {}
  for x = -SOLID, SOLID do
    for y = -SOLID, SOLID do
      tiles[#tiles + 1] = { name = "ice-platform", position = { SPOT.x + x, SPOT.y + y } }
    end
  end
  cold.set_tiles(tiles)
  world.stacking(0)
  world.capacity(0)
  world.refresh()
end)

after_each(function()
  if cold and cold.valid then
    for _, thing in pairs(cold.find_entities_filtered{ position = SPOT, radius = 30 }) do
      if thing.valid and thing.type ~= "character" then thing.destroy() end
    end
  end
  world.clear()
end)

describe("an inserter frozen on Aquilo", function()
  it("says so, rather than saying its target is full", function()
    local inserter = world.rig_on(cold, SPOT)
    after_ticks(60, function()
      assert.is_true(inserter.is_freezable, "an inserter on Aquilo is not freezable")
      assert.is_true(inserter.frozen, "it never froze, so this proves nothing")
      assert.are.equal(defines.entity_status.frozen, inserter.status,
        "a frozen inserter reports something other than frozen")
      assert.are_not.equal(defines.entity_status.waiting_for_space_in_destination,
        inserter.status)
    end)
  end)

  it("is left holding what it holds, with the pile in front of it untouched", function()
    local inserter = world.rig_on(cold, SPOT)
    local held
    after_ticks(60, function()
      assert.is_true(inserter.frozen, "it never froze, so this proves nothing")
      -- everything the mod looks for, put there by hand: a pile where it aims, and a
      -- handful in its hand
      local pile = cold.create_entity{ name = "item-on-ground", position = inserter.drop_position,
        stack = { name = "iron-plate", count = 1 } }
      assert.is_not_nil(pile, "could not put a pile down in front of it")
      -- However much this inserter's hand holds, which with no capacity research is one
      inserter.held_stack.set_stack{ name = "iron-plate", count = 4 }
      assert.is_true(inserter.held_stack.valid_for_read, "could not fill its hand")
      held = inserter.held_stack.count
      world.stacking(3)
    end)
    after_ticks(60 + world.SETTLE, function()
      assert.is_true(inserter.frozen, "it thawed part way through")
      assert.are.equal(1, world.loose_on(cold, inserter.drop_position, 1),
        "the pile in front of a frozen inserter grew")
      assert.is_true(inserter.held_stack.valid_for_read,
        "a frozen inserter's hand was emptied")
      assert.are.equal(held, inserter.held_stack.count,
        "something took items out of a frozen inserter's hand")
    end)
  end)

  it("goes back to work once heat pipe reaches it, and is topped up", function()
    -- The other half of the story, and the one that matters: frozen is a pause, not a
    -- disqualification. Nothing tells the mod when an inserter thaws, so if it had stopped
    -- watching this one it would never pick it up again.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig_on(cold, SPOT)
    after_ticks(60, function()
      assert.is_true(inserter.frozen, "it never froze, so the thaw proves nothing")
      assert.are.equal(0, world.loose_on(cold, inserter.drop_position, 1),
        "it was working before it was warmed")
      heat(cold, SPOT)
    end)
    after_ticks(60 + 180, function()
      assert.is_false(inserter.frozen,
        "the heat pipe did not thaw it, so the rest of this proves nothing")
    end)
    after_ticks(60 + 180 + world.SETTLE, function()
      local piled = world.loose_on(cold, inserter.drop_position, 1)
      assert.is_true(piled > 1,
        ("%d items on the ground: a thawed inserter was not picked back up"):format(piled))
    end)
  end)

  it("is left alone when it is aimed at the ocean, having nothing to put down", function()
    -- Not about freezing at all, but Aquilo is where it is easiest to arrange: liquid takes
    -- nothing, so the inserter jams holding its whole hand with bare water in front of it.
    -- There is no pile, so there is nothing for the mod to add to, and it stays jammed
    -- exactly as it would without the mod.
    world.stacking(3)
    world.capacity(3)
    local wet = { x = SPOT.x, y = SPOT.y - SOLID - 6 }
    local inserter = world.rig_on(cold, wet)
    assert.are.equal("ammoniacal-ocean", cold.get_tile(inserter.drop_position.x,
                                                       inserter.drop_position.y).name,
      "the spot it aims at is not water, so this proves nothing")
    -- and it has to be warm, or it would be doing nothing for the other reason
    heat(cold, wet)
    after_ticks(240, function()
      assert.is_false(inserter.frozen, "it never thawed, so this proves nothing")
    end)
    after_ticks(240 + world.SETTLE, function()
      assert.are.equal(defines.entity_status.waiting_for_space_in_destination,
        inserter.status, "it is not stopped over the water")
      assert.are.equal(0, world.loose_on(cold, inserter.drop_position, 2),
        "something is lying on the ocean")
    end)
  end)

  it("is still watched, so it works the moment it thaws", function()
    -- Frozen is a thing that stops, not a thing that disqualifies. The mod keeps it on the
    -- list, because an inserter whose heating comes back is an ordinary inserter again and
    -- nothing will tell the mod when that happens.
    local inserter = world.rig_on(cold, SPOT)
    world.stacking(3)
    after_ticks(60, function()
      world.refresh()
      assert.is_true(inserter.frozen, "it never froze, so this proves nothing")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "a frozen inserter was dropped from the list and would never be picked up again")
    end)
  end)
end)
