--- Inserters that somebody re-aims after they are built.
---
--- An inserter's drop position is not fixed at build time. Several popular mods let a
--- player swing one round from a GUI, and swinging it from a chest onto bare ground is
--- exactly the change this mod has to hear about. Writing drop_position raises nothing the
--- game defines, so each of those mods raises an event of its own, and the mod takes up
--- the ones it knows by name.
---
--- None of those mods is installed here. What stands in for them is igs-tests, which
--- declares the same custom-event prototypes, so the registration under test is the real
--- one: the same names, taken up the same way at the same moment.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

---@return table
local function report()
  return remote.call("inserter-ground-stack", "report")
end

describe("the events of mods that re-aim inserters", function()
  it("are all taken up, every one the mod says it is listening for", function()
    local names = report().listening_for
    assert.is_true(#names > 0, "the mod says it listens for nothing")
    for _, name in pairs(names) do
      local id = defines.events[name]
      assert.is_not_nil(id,
        ("the mod listens for %s but nothing declares it; add it to igs-tests/data.lua "
          .. "or this tests less than it looks"):format(name))
      assert.is_not_nil(script.get_event_handler(id),
        ("%s exists and the mod took up no handler for it"):format(name))
    end
  end)

  it("start it watching an inserter that has been swung round onto bare ground",
     function()
    -- The case that matters. The inserter starts aimed at a chest, so the mod has let it
    -- go; the drop position is moved onto bare ground, which no event of the game's own
    -- reports; the mod hears the other mod's event instead and takes the inserter up.
    world.stacking(3)
    world.capacity(3)
    local chest = world.place("steel-chest", 1, world.ROW)
    local inserter = world.rig(1)
    after_ticks(30, function()
      assert.is_not_nil(inserter.drop_target, "the fixture is not aimed at the chest")
      assert.is_nil(storage.droppers[inserter.unit_number],
        "an inserter loading a chest is being watched, so this proves nothing")
      -- The chest goes without a word -- destroy() raises nothing unless asked -- and the
      -- drop position is nudged, which raises nothing either. Within reach, because an
      -- inserter cannot be aimed past the end of its own arm and a fixture that tries is
      -- a fixture that tests nothing.
      chest.destroy()
      inserter.drop_position = world.at(1.3, world.ROW)
      assert.is_nil(storage.pending[inserter.unit_number],
        "moving a drop position raised something by itself, so this proves nothing")
      assert.is_nil(storage.droppers[inserter.unit_number],
        "it was picked up without being told, so the event is not what is under test")
      -- and now the only thing that says so
      script.raise_event(defines.events.on_bobs_inserter_adjusted, { entity = inserter })
    end)
    after_ticks(30 + 30, function()
      assert.is_nil(inserter.drop_target, "it is still aimed at something")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the mod was told the inserter had been re-aimed and did nothing about it")
    end)
    after_ticks(30 + 30 + world.SETTLE, function()
      local piled = world.loose_on(world.surface(), inserter.drop_position, 1)
      assert.is_true(piled > 1,
        ("only %d items where it now aims: taken up but never topped up"):format(piled))
    end)
  end)

  it("are understood whichever way round the payload names the inserter", function()
    -- Bob's and Smart Inserters call it `entity`; Quick Adjustable Inserters calls it
    -- `entity` in one of its three events and `inserter` in the other two. Getting that
    -- wrong would mean hearing the event and doing nothing, which looks exactly like not
    -- hearing it.
    world.stacking(3)
    local one = world.rig(1, { quiet = true })
    local two = world.rig(2, { quiet = true })
    assert.is_nil(storage.droppers[one.unit_number])
    assert.is_nil(storage.droppers[two.unit_number])
    script.raise_event(defines.events.on_bobs_inserter_adjusted, { entity = one })
    script.raise_event(defines.events.on_qai_inserter_vectors_changed, { inserter = two })
    after_ticks(30, function()
      assert.is_not_nil(storage.droppers[one.unit_number],
        "an event naming the inserter `entity` was not understood")
      assert.is_not_nil(storage.droppers[two.unit_number],
        "an event naming the inserter `inserter` was not understood")
    end)
  end)
end)
