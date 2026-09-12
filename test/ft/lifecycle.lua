--- Which inserters the mod is watching, and how that list keeps up with the world.
---
--- Nearly every inserter in a factory has somewhere to put things, and those are no concern
--- of this mod. Keeping them out of the list is what keeps the cost of looking down to the
--- handful that put things on the ground, so the list has to be right: an inserter that has
--- just lost its chest belongs in it, and one that has just been handed a chest does not.
---
--- The list is read directly out of storage here rather than inferred from what the mod
--- does, because the difference between "not watched" and "watched but with nothing to do"
--- is invisible from outside and is exactly what these are about.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

describe("an inserter the mod never saw being built", function()
  it("is found by the reading that goes round the map anyway", function()
    -- A script may build an inserter and raise nothing, which is allowed and which mods do.
    -- Nothing tells this mod about such a one, so what finds it is the background reading
    -- coming past its chunk. That is the whole reason the reading never stops.
    world.stacking(3)
    local inserter = world.rig(1, { quiet = true })
    after_ticks(world.SETTLE * 6, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the reading went round the map and never found it")
    end)
    after_ticks(world.SETTLE * 8, function()
      assert.is_true(world.piled(inserter) > 1,
        "it was found but never topped up")
    end)
  end)

  it("is found at once when the mod is asked to read the world again", function()
    world.stacking(3)
    local inserter = world.rig(1, { quiet = true })
    world.refresh()
    assert.is_not_nil(storage.droppers[inserter.unit_number],
      "reading the world again did not find it")
  end)
end)

describe("an inserter with somewhere to put things", function()
  it("is not watched at all", function()
    world.stacking(3)
    world.place("steel-chest", 1, world.ROW)
    local inserter = world.rig(1)
    -- A tick, because the engine settles what an inserter is aimed at in its own update
    -- and not while the build event that created it is still running.
    after_ticks(5, function()
      assert.is_not_nil(inserter.drop_target, "the fixture is not aimed at the chest")
      assert.is_nil(storage.droppers[inserter.unit_number],
        "an inserter loading a chest is being watched")
    end)
  end)

  it("starts being watched once that chest is mined away", function()
    world.stacking(3)
    local target = world.place("steel-chest", 1, world.ROW)
    local inserter = world.rig(1)
    after_ticks(30, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "it was watched while it still had a chest to load")
      world.mine(target)
    end)
    after_ticks(60, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the inserter lost its chest and nobody noticed")
    end)
    after_ticks(60 + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground where the chest used to be"):format(
          world.piled(inserter)))
    end)
  end)

  it("is dropped again when a chest is built where it had been piling", function()
    -- The way round the other three do not cover, and the one that no event tells the mod
    -- about at all. Build events are filtered to inserters, and were only ever acted on for
    -- inserters, so a chest appearing in front of one says nothing to this mod: what
    -- notices is top_up, which reads the drop target before anything else every time the
    -- sweep comes past, and lets go the moment there is one.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    after_ticks(world.JAM, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "it was never watched, so being dropped proves nothing")
      assert.is_true(world.piled(inserter) > 1,
        "it was never piling, so being dropped proves nothing")
      local chest = world.place("steel-chest", 1, world.ROW)
      assert.is_not_nil(chest)
    end)
    after_ticks(world.JAM + 5, function()
      assert.is_not_nil(inserter.drop_target,
        "the chest did not become what it aims at, so this proves nothing")
      assert.are.equal("steel-chest", inserter.drop_target.name)
    end)
    after_ticks(world.JAM + 90, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "a chest was built in front of it and it is still being watched")
      assert.is_nil(storage.busy[inserter.unit_number],
        "it was let go of but left in the busy set")
    end)
    after_ticks(world.JAM + 90 + world.SETTLE, function()
      assert.is_true(inserter.drop_target.get_item_count("iron-plate") > 0,
        "it never got on with loading the chest")
    end)
  end)

  it("starts being watched when a script takes that chest away", function()
    world.stacking(3)
    local target = world.place("steel-chest", 1, world.ROW)
    local inserter = world.rig(1)
    after_ticks(30, function()
      target.destroy{ raise_destroy = true }
    end)
    after_ticks(60, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "a chest destroyed by script left the inserter unwatched")
    end)
  end)
end)

describe("an inserter whose target drives away", function()
  it("is kept on the list while the car sits there, so nothing has to find it again",
     function()
    -- A car parked where an inserter puts things down is a drop target like any other, and
    -- an inserter with somewhere to put things is normally let go of. This one is not.
    --
    -- When a car drives off nothing is destroyed, mined or built -- the car still exists,
    -- it is simply not there any more -- so not one of the events this mod listens to
    -- fires, and there is no event in the game for the thing under an inserter's hand
    -- moving. Letting go would therefore mean waiting on the background reading. Keeping
    -- it means there is nothing to find: it is on the list while the car stands there and
    -- still on it once the car has gone.
    --
    -- That continuity is what this measures, by looking before as well as after, and it is
    -- the only thing that can be measured here. Timing would prove nothing -- the arena is
    -- a few hundred chunks, so the reading goes round it several times over in the span of
    -- this test, and on a map that size it could always be credited with the find.
    world.stacking(3)
    world.capacity(3)
    local car = world.place("car", 1, world.ROW)
    local inserter = world.rig(1)
    after_ticks(30, function()
      assert.is_not_nil(inserter.drop_target, "the car is not what it aims at")
      assert.are.equal("car", inserter.drop_target.name)
      -- before: on the list although it has a drop target, which nothing else in the suite
      -- is allowed to be
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "an inserter loading something that can drive away was let go of")
      assert.are.equal(0, world.piled(inserter),
        "it put something on the ground with a car standing on the spot")
      -- driven off, as a player would; nothing is raised by that
      car.teleport(world.at(20, world.ROW))
      assert.is_nil(storage.pending[inserter.unit_number],
        "a car driving away queued the inserter, so some event did fire after all")
    end)
    after_ticks(30 + 60, function()
      assert.is_nil(inserter.drop_target, "the car is somehow still its target")
      -- after: the same entry, never taken out and so never needing to be found
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "it was dropped from the list the moment the car left")
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground where the car used to be"):format(
          world.piled(inserter)))
    end)
  end)
end)

describe("an inserter that is given somewhere to put things", function()
  it("is let go of again", function()
    world.stacking(3)
    local inserter = world.rig(1)
    after_ticks(world.JAM, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "it was never watched to begin with")
      world.place("steel-chest", 1, world.ROW)
    end)
    -- Let go of on the next look rather than the moment the chest goes up: a swarm of bots
    -- building a blueprint would otherwise have every inserter within reach of every new
    -- wall and lamp looked up, and nothing is lost by waiting a tenth of a second.
    after_ticks(world.JAM + 30, function()
      assert.is_not_nil(inserter.drop_target, "the chest is not where its items were going")
      assert.is_nil(storage.droppers[inserter.unit_number],
        "the inserter is still being watched with a chest in front of it")
    end)
  end)
end)

describe("an inserter that is mined", function()
  it("is let go of at once", function()
    world.stacking(3)
    local inserter = world.rig(1)
    local unit_number = inserter.unit_number
    after_ticks(world.JAM, function()
      assert.is_not_nil(storage.droppers[unit_number])
      world.mine(inserter)
      assert.is_nil(storage.droppers[unit_number],
        "a mined inserter is still on the list")
      assert.is_nil(storage.busy[unit_number])
    end)
  end)
end)

describe("a factory full of fake loaders", function()
  it("costs nothing, because a loader has somewhere to put things", function()
    -- The loader mods build their loaders out of invisible inserters that turn a half circle
    -- in a tick, and a big factory has thousands of them. Every one of them is aimed at the
    -- belt or the chest it serves, which is the first thing the mod asks about and the end
    -- of its interest.
    world.stacking(3)
    local fakes = {}
    for row = 1, 4 do
      world.place("transport-belt", 1, row * world.ROW, defines.direction.north)
      fakes[row] = select(1, world.rig(row, { inserter = "igs-fake-loader" }))
    end
    after_ticks(30, function()
      for row, fake in pairs(fakes) do
        assert.is_not_nil(fake.drop_target,
          ("loader %d is not aimed at its belt, so this proves nothing"):format(row))
        assert.is_nil(storage.droppers[fake.unit_number],
          ("loader %d is being watched despite having a belt to unload onto"):format(row))
      end
      assert.are.equal(0, table_size(storage.droppers),
        "something is being watched in a factory made entirely of loaders")
    end)
  end)

  it("is still helped when one of them is aimed at bare ground", function()
    -- And when one is pointed at nothing, the arithmetic that decides how long to leave an
    -- inserter alone has to cope with one that is back before the next tick. It cannot wait
    -- less than a tick, so it waits a tick, and the fixture runs at full speed.
    world.stacking(3)
    local fake = world.rig(1, { inserter = "igs-fake-loader" })
    after_ticks(world.SETTLE, function()
      assert.is_not_nil(storage.droppers[fake.unit_number], "it was never watched")
      local piled = world.piled(fake)
      assert.is_true(piled > 1,
        ("a fake loader aimed at bare ground still stopped at %d"):format(piled))
      assert.is_true(piled >= 50,
        ("%d items in %d ticks from something that swings every tick: the mod is dawdling")
          :format(piled, world.SETTLE))
    end)
  end)
end)

describe("a surface that is deleted", function()
  -- A space platform being blown up, or any mod that makes a surface and later throws it
  -- away. Everything standing on it becomes invalid at once, without a mining or a dying
  -- event for any of it, and the mod is left holding references to things that no longer
  -- exist. Two separate things have to survive that: the list of watched inserters, and the
  -- background reading, which may be part way through walking the very surface that went.
  local doomed

  local function make_doomed()
    if game.surfaces["igs-doomed"] then game.delete_surface("igs-doomed") end
    local surface = game.create_surface("igs-doomed")
    surface.request_to_generate_chunks({ x = 0, y = 0 }, 2)
    surface.force_generate_chunk_requests()
    return surface
  end

  after_each(function()
    if game.surfaces["igs-doomed"] then game.delete_surface("igs-doomed") end
  end)

  it("takes its inserters off the list, and the mod carries on", function()
    world.stacking(3)
    world.capacity(3)
    doomed = make_doomed()
    local aloft = world.rig_on(doomed, { x = 0.5, y = 0.5 })
    local unit_number = aloft.unit_number
    after_ticks(60, function()
      assert.is_not_nil(storage.droppers[unit_number],
        "the inserter on the new surface was never watched, so losing it proves nothing")
      game.delete_surface("igs-doomed")
    end)
    after_ticks(180, function()
      assert.is_nil(game.surfaces["igs-doomed"], "the surface is still here")
      assert.is_nil(storage.droppers[unit_number],
        "an inserter on a surface that no longer exists is still on the list")
      assert.is_nil(storage.busy[unit_number])
      assert.is_nil(storage.due[unit_number])
    end)
  end)

  it("does not stop the reading of the map", function()
    -- The reading keeps where it had got to as a surface index and a count of chunks. If
    -- the surface it was walking is deleted underneath it, it has to pick up on another one
    -- rather than sit there for ever, or everything the reading is the backstop for stops
    -- being caught.
    world.stacking(3)
    world.capacity(3)
    doomed = make_doomed()
    world.rig_on(doomed, { x = 0.5, y = 0.5 })
    local rounds
    after_ticks(60, function()
      rounds = storage.rescan.passes
      game.delete_surface("igs-doomed")
    end)
    after_ticks(300, function()
      assert.is_true(storage.rescan.passes > rounds,
        ("the reading has been round %d times and was %d when the surface went: it stopped")
          :format(storage.rescan.passes, rounds))
    end)
  end)

  it("leaves the inserters on every other surface alone", function()
    world.stacking(3)
    world.capacity(3)
    doomed = make_doomed()
    world.rig_on(doomed, { x = 0.5, y = 0.5 })
    local home = world.rig(1)
    after_ticks(60, function()
      assert.is_not_nil(storage.droppers[home.unit_number], "the one at home was not watched")
      game.delete_surface("igs-doomed")
    end)
    after_ticks(180 + world.SETTLE, function()
      assert.is_not_nil(storage.droppers[home.unit_number],
        "deleting one surface took an inserter off another one")
      assert.is_true(world.piled(home) > 1,
        ("the inserter at home stopped working, %d on the ground"):format(world.piled(home)))
    end)
  end)
end)

describe("the list", function()
  it("does not grow without bound as fixtures come and go", function()
    world.stacking(3)
    local inserters = {}
    for row = 1, 4 do inserters[row] = world.rig(row) end
    after_ticks(world.JAM, function()
      local watched = 0
      for _ in pairs(storage.droppers) do watched = watched + 1 end
      assert.are.equal(4, watched,
        ("%d inserters watched for four fixtures"):format(watched))
      for _, inserter in pairs(inserters) do inserter.destroy{ raise_destroy = true } end
    end)
    after_ticks(world.JAM + 30, function()
      local watched = 0
      for _ in pairs(storage.droppers) do watched = watched + 1 end
      assert.are.equal(0, watched,
        ("%d inserters still watched after all four were destroyed"):format(watched))
    end)
  end)
end)
