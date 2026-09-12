--- Inserters aimed at rail.
---
--- An item cannot be put down on a rail: rails and items lying on the ground share a
--- collision layer, so the engine refuses. An inserter aimed at one therefore holds
--- everything and puts nothing down for ever, and says so -- its status is
--- `waiting_for_train`, whether or not a train is coming and whether or not there is a
--- station anywhere near it.
---
--- Such an inserter can never be the one this mod is for, and on a factory built around
--- trains there are a great many of them: on a real megabase, 5,397 of the 6,020 inserters
--- with no drop target at all. So they are let go of rather than carried.
---
--- Letting go is only safe if something finds them again, and the only thing that can
--- change their mind is the rail going away. That is an event the mod already hears, which
--- is what the second half of this file is about.
local world = require("test.ft.world")

--- Rails sit on a two tile grid, so asking for one at an odd place gets one somewhere else.
--- The fixture is built around where the inserter actually aims rather than around where
--- the rail was asked for, and asserts the two really do meet: getting that wrong gives an
--- inserter aimed at bare ground beside a rail, which behaves like every other fixture in
--- the suite and would prove nothing at all.
local function rail_under(inserter)
  local surface = world.surface()
  local drop = inserter.drop_position
  local laid = {}
  for dy = -6, 6, 2 do
    local rail = surface.create_entity{ name = "straight-rail",
      position = { math.floor(drop.x / 2) * 2 + 1, math.floor(drop.y) + dy },
      direction = defines.direction.north, force = "player", raise_built = true }
    if rail then laid[#laid + 1] = rail end
  end
  local on_it = false
  for _, thing in pairs(surface.find_entities_filtered{ position = drop }) do
    if thing.valid and thing.type == "straight-rail" then on_it = true end
  end
  assert.is_true(on_it,
    ("no rail covers the spot the inserter aims at, %.2f,%.2f"):format(drop.x, drop.y))
  return laid
end

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

describe("an inserter aimed at rail", function()
  it("says it is waiting for a train, and puts nothing down", function()
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    rail_under(inserter)
    after_ticks(world.SETTLE, function()
      assert.are.equal(defines.entity_status.waiting_for_train, inserter.status,
        "an inserter aimed at rail said something other than waiting for a train")
      assert.are.equal(0, world.piled(inserter), "it put something down on the rail")
    end)
  end)

  it("is let go of rather than carried", function()
    world.stacking(3)
    local inserter = world.rig(1)
    rail_under(inserter)
    -- Registered first, the way any newly built inserter is, and dropped on a later look:
    -- the engine does not settle what an inserter is aimed at until after the build event,
    -- so there is nothing to judge at the moment it is built.
    after_ticks(world.SETTLE, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "an inserter that can never put anything down is still being watched")
    end)
  end)
end)

describe("an inserter whose rail is taken away", function()
  -- Taken away on every phase of the sweep in turn. The engine goes on calling an inserter
  -- a train waiter for a tick or two after the rail has gone, and the mod's sweep comes
  -- round every tenth tick, so on some of these ten offsets the sweep lands inside that
  -- window and on others it does not. Only one offset has to land there for letting go on a
  -- stale answer to lose the inserter for good, which is what the settling wait prevents;
  -- testing a single offset is testing whichever way the dice happened to fall.
  for offset = 0, 9 do
    it(("is found again when the rail goes on offset %d"):format(offset), function()
      world.stacking(3)
      world.capacity(3)
      local inserter = world.rig(1)
      local rails = rail_under(inserter)
      after_ticks(world.SETTLE + offset, function()
        assert.is_nil(storage.droppers[inserter.unit_number],
          "it was never let go of, so finding it again proves nothing")
        for _, rail in pairs(rails) do
          if rail.valid then rail.destroy{ raise_destroy = true } end
        end
      end)
      after_ticks(world.SETTLE + offset + 90, function()
        assert.is_not_nil(storage.droppers[inserter.unit_number],
          "the rail went and the inserter was never picked back up")
      end)
    end)
  end

  it("goes back to filling a pile once the rail is gone", function()
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local rails = rail_under(inserter)
    after_ticks(world.SETTLE, function()
      for _, rail in pairs(rails) do
        if rail.valid then rail.destroy{ raise_destroy = true } end
      end
    end)
    after_ticks(world.SETTLE * 2 + 60, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground where the rail used to be"):format(
          world.piled(inserter)))
    end)
  end)

  it("is found again when a player mines the rail", function()
    -- Mined rather than destroyed by script, which is a different pair of events:
    -- on_pre_player_mined_item rather than script_raised_destroy.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local rails = rail_under(inserter)
    after_ticks(world.SETTLE, function()
      assert.is_nil(storage.droppers[inserter.unit_number])
      for _, rail in pairs(rails) do
        if rail.valid then world.mine(rail) end
      end
    end)
    after_ticks(world.SETTLE + 60, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the rail was mined away and the inserter was never picked back up")
    end)
  end)

  it("is not found again when the rail goes with nothing announced at all", function()
    -- The events cover a player mining, a robot mining, a thing dying, and a script that
    -- says what it did. What they do not cover is a script that takes a rail away and
    -- raises nothing, which is allowed and which the flags default to: raise_destroy is
    -- off unless a mod asks for it.
    --
    -- There is no longer anything reading the map in the background, so nothing puts that
    -- right on its own, and this pins the gap rather than hiding it. What the inserter
    -- loses is the mod's help; it goes on behaving exactly as it would with the mod not
    -- installed. Asking for the world to be read again is the way out, and the second half
    -- of this checks that it is a way out.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local rails = rail_under(inserter)
    after_ticks(world.SETTLE, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "it was never let go of, so none of this proves anything")
      for _, rail in pairs(rails) do
        -- no raise_destroy: as far as every event goes, this never happened
        if rail.valid then rail.destroy() end
      end
      assert.is_nil(storage.pending[inserter.unit_number],
        "a removal that raised no event queued the inserter anyway")
    end)
    after_ticks(world.SETTLE + 120, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "something found it, so this is not the gap it is meant to describe")
      -- One item, which is the game without this mod: the inserter swings once, finds the
      -- spot taken by what it put there, and stops. Not zero -- the rail is gone, so it
      -- can put something down now -- and not a pile, which is what being helped looks
      -- like.
      assert.are.equal(1, world.piled(inserter),
        ("%d items on the ground: it is being helped, so it was found after all"):format(
          world.piled(inserter)))
      -- and here is the way out
      world.refresh()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "reading the world again did not find an inserter whose rail had gone")
    end)
    after_ticks(world.SETTLE + 120 + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground once it had been found again"):format(
          world.piled(inserter)))
    end)
  end)
end)
