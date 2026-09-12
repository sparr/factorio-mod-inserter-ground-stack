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

describe("the removals the mod asks the engine not to tell it about", function()
  -- Every removal event is registered with a filter naming a few kinds of thing that are
  -- never worth looking at, so that a map full of them -- asteroids off the bows of
  -- platforms, a forest on fire, a wave of biters -- does not pay to cross into Lua only to
  -- be thrown away. A filter is fixed when the mod loads, so nothing at runtime can notice
  -- if what entitles it stops being true, which is what these two check.
  --
  -- Two checks rather than one because there are two different entitlements, and the first
  -- draft of this ran them together and was wrong about trees.
  it("could not have been in an inserter's way, for the ones filtered on that", function()
    -- Two prototype facts, asked of the game as it stands rather than of what was true when
    -- the list was written: none of them is a building, so none could have been catching an
    -- inserter's items, and none shares a collision layer with an item lying on the ground,
    -- so none could have been stopping an item from being put down.
    local kinds = {}
    for _, kind in pairs(remote.call("inserter-ground-stack", "report").never_in_the_way) do
      kinds[kind] = true
    end
    assert.is_true(next(kinds) ~= nil, "the mod says it filters nothing out on those grounds")

    local blocking = prototypes.entity["item-on-ground"].collision_mask.layers
    local checked = 0
    for name, proto in pairs(prototypes.entity) do
      if kinds[proto.type] then
        checked = checked + 1
        assert.is_not_true(proto.is_building,
          ("%s is a building now, so an inserter could have been loading one and the "
            .. "filter is losing that"):format(name))
        for layer in pairs(proto.collision_mask.layers) do
          assert.is_nil(blocking[layer],
            ("%s now blocks an item from being put down, on the %s layer, so one of them "
              .. "going away can matter and the filter is losing that"):format(name, layer))
        end
      end
    end
    assert.is_true(checked > 0,
      "not one of those kinds has a prototype in this game, so this checked nothing")
  end)

  it("leave an inserter they stop still on the list, for the ones filtered on that",
     function()
    -- The other entitlement, and the one that cannot be read off a prototype. A tree does
    -- stop an inserter putting something down. What makes the removal not worth hearing is
    -- that the inserter is never let go of while the tree stands there, so nothing has to
    -- find it again when the tree falls -- it simply starts working.
    --
    -- Checked on a real tree in a real inserter's way, with the mod told nothing: the
    -- filter means the event never arrives, so if the reasoning were wrong this inserter
    -- would sit there for ever.
    local kinds = remote.call("inserter-ground-stack", "report").never_let_go_of
    assert.is_true(#kinds > 0, "the mod says it filters nothing out on those grounds")
    local growth
    for _, kind in pairs(kinds) do
      for name, proto in pairs(prototypes.entity) do
        if proto.type == kind and growth == nil and proto.collision_box then growth = name end
      end
    end
    assert.is_not_nil(growth, "this game has no tree or plant to stand in the way")

    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local surface = world.surface()
    local drop = inserter.drop_position
    -- Exactly where it aims, not the middle of the tile: a tree is small and a fixture that
    -- misses tests bare ground while looking like it tests a tree.
    local tree = surface.create_entity{ name = growth, position = drop, force = "neutral",
                                        raise_built = true }
    assert.is_not_nil(tree, ("could not put a %s in the way"):format(growth))
    local covers = false
    for _, thing in pairs(surface.find_entities_filtered{ position = drop }) do
      if thing.valid and thing == tree then covers = true end
    end
    assert.is_true(covers,
      ("the %s does not cover %.2f,%.2f, where the inserter aims"):format(
        growth, drop.x, drop.y))

    after_ticks(world.SETTLE, function()
      assert.are.equal(0, world.piled(inserter),
        ("items landed under a %s, so it was never in the way and this proves nothing")
          :format(growth))
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        ("an inserter stopped by a %s was let go of, so its going does need hearing about")
          :format(growth))
      tree.destroy{ raise_destroy = true }
      assert.is_nil(storage.pending[inserter.unit_number],
        ("a %s going raised something the mod acted on, so the filter is not applying and "
          .. "this proves nothing"):format(growth))
    end)
    after_ticks(world.SETTLE * 2, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground once the %s was gone: the mod never picked it back up")
          :format(world.piled(inserter), growth))
    end)
  end)
end)
