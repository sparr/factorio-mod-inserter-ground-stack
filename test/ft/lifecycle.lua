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
  it("is not heard about, because nothing was removed", function()
    -- A car parked where an inserter puts things down is a drop target like any other, and
    -- the inserter is left alone accordingly. When it drives off nothing is destroyed, mined
    -- or built, so not one of the events this mod listens to fires, and the inserter quietly
    -- starts putting things on the ground with nobody watching it.
    --
    -- This is the case the background reading of the map exists for, and the one that says
    -- most plainly why it cannot be dropped: being found here is a matter of when the
    -- reading comes round, not of hearing about anything.
    world.stacking(3)
    world.capacity(3)
    local car = world.place("car", 1, world.ROW)
    local inserter = world.rig(1)
    after_ticks(30, function()
      assert.is_not_nil(inserter.drop_target, "the car is not what it aims at")
      assert.are.equal("car", inserter.drop_target.name)
      assert.is_nil(storage.droppers[inserter.unit_number],
        "an inserter loading a car is being watched")
      -- driven off, as a player would; nothing is raised by that
      car.teleport(world.at(20, world.ROW))
      -- Nothing was removed, so nothing queued this inserter to be looked at again. That is
      -- the whole point: the queue is how the mod hears about things, and it is empty.
      assert.is_nil(storage.pending[inserter.unit_number],
        "a car driving away queued the inserter, so some event did fire after all")
    end)
    after_ticks(120, function()
      assert.is_nil(inserter.drop_target, "the car is somehow still its target")
      -- Found all the same, by the reading coming past its chunk rather than by any event.
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the reading of the map never noticed the car had gone")
    end)
    after_ticks(120 + world.SETTLE, function()
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
