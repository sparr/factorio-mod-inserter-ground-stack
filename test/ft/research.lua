--- The gate.
---
--- Stacking things on top of one another is something a factory earns, and the mod earns it
--- off the same research: the belt stack size bonus. Before that bonus exists there is no
--- such thing as a stack of items in the game at all, and an inserter putting things on
--- taken ground behaves exactly as the engine makes it behave.
---
--- Asked as a bonus on the force rather than as a named technology, so that a mod which
--- moves belt stacking onto a different research, or splits it, or adds tiers beyond the
--- vanilla ones, needs no cooperation from this mod to be understood.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

describe("before belt stacking is researched", function()
  it("leaves the inserter stopped on its one item, as the engine does", function()
    world.stacking(0)
    world.capacity(3)
    local inserter = world.rig(1)
    after_ticks(world.SETTLE, function()
      assert.are.equal(1, world.piled(inserter),
        "the ground pile grew without the research that lets things stack")
      assert.are.equal(defines.entity_status.waiting_for_space_in_destination,
        inserter.status, "the inserter is not stopped, so something moved its items")
    end)
  end)

  it("leaves the rest of the handful in the hand", function()
    world.stacking(0)
    world.capacity(3)
    local inserter = world.rig(1)
    after_ticks(world.SETTLE, function()
      local held = inserter.held_stack
      assert.is_true(held.valid_for_read, "the hand emptied itself somehow")
      assert.is_true(held.count > 0, "the hand emptied itself somehow")
    end)
  end)
end)

describe("the first tier of belt stacking", function()
  it("is enough on its own", function()
    -- One extra item in a stack is what the stack inserter technology grants, and it is the
    -- whole of the gate: what a ground pile will hold is what the item's own stack holds,
    -- and not what a belt would carry.
    world.stacking(1)
    local inserter = world.rig(1)
    after_ticks(world.SETTLE, function()
      local piled = world.piled(inserter)
      assert.is_true(piled > 2,
        ("the pile stopped at %d, as though a belt's stack were the limit"):format(piled))
    end)
  end)
end)

describe("research arriving while a factory is already running", function()
  it("frees an inserter that was already stopped", function()
    world.stacking(0)
    local inserter = world.rig(1)
    after_ticks(world.JAM, function()
      assert.are.equal(1, world.piled(inserter), "it started before it was allowed to")
      world.stacking(3)
    end)
    after_ticks(world.JAM + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        "the inserter stayed stopped after the research landed")
    end)
  end)
end)

describe("a game that has not researched it", function()
  it("is not watched at all, so the mod costs it nothing", function()
    -- Nothing this mod does can happen before the research, so before the research it keeps
    -- no list, hears no build event and does no work. What it costs such a save is the once
    -- a second glance at the forces that notices when that stops being true.
    world.stacking_quietly(0)
    local inserter = world.rig(1)
    after_ticks(world.JAM, function()
      assert.is_false(storage.active, "the mod switched itself on with nothing to do")
      local watched = 0
      for _ in pairs(storage.droppers) do watched = watched + 1 end
      assert.are.equal(0, watched,
        ("%d inserters watched in a game with no belt stacking"):format(watched))
      assert.are.equal(1, world.piled(inserter), "and yet the pile grew")
    end)
  end)

  it("reads the world once when the research finally lands", function()
    world.stacking_quietly(0)
    local inserter = world.rig(1)
    after_ticks(world.JAM, function()
      assert.are.equal(0, table_size(storage.droppers),
        "it was keeping a list before there was any use for one")
      world.stacking(3)
      assert.is_true(storage.active, "it did not switch on")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "switching on did not find the inserter that was already standing there")
    end)
    after_ticks(world.JAM + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1, "it was found but never topped up")
    end)
  end)

  it("notices a bonus handed out with no research at all", function()
    -- A console command or another mod can set the bonus directly, and nothing is raised
    -- when it does. The once a second look is what catches that, so this one waits.
    world.stacking_quietly(0)
    local inserter = world.rig(1)
    after_ticks(30, function()
      world.stacking_quietly(3)
    end)
    after_ticks(30 + 70, function()
      assert.is_true(storage.active,
        "a second went by and the mod never noticed the bonus")
    end)
    after_ticks(30 + 70 + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        "it noticed but never got going")
    end)
  end)
end)

describe("research being taken away again", function()
  it("stops the inserter where it stands", function()
    world.stacking(3)
    local inserter = world.rig(1)
    local at_the_time
    after_ticks(world.SETTLE, function()
      at_the_time = world.piled(inserter)
      assert.is_true(at_the_time > 1, "it never got going in the first place")
      world.stacking(0)
    end)
    after_ticks(world.SETTLE * 2, function()
      assert.are.equal(at_the_time, world.piled(inserter),
        "the pile kept growing after the bonus was taken away")
      assert.is_false(storage.active, "and the mod is still watching for it")
    end)
  end)
end)

describe("two forces at different points in the tech tree", function()
  -- Whether the mod runs at all is settled for the game as a whole: it starts watching the
  -- moment anybody has belt stacking, because the list has to exist before it can be used
  -- and there is no sense keeping one per force. Whether an inserter is actually helped is
  -- settled for its own force, every time it is looked at.
  --
  -- Which means an inserter belonging to a force that has not researched it is carried on
  -- the list and never touched -- and starts working on the next sweep the moment that
  -- force does research it, with nothing re-read and nothing told to the mod.
  it("helps only the inserters of the force that researched it", function()
    local them = game.forces["igs-other"] or game.create_force("igs-other")
    them.belt_stack_size_bonus = 0
    world.stacking(3)
    world.capacity(3)
    local mine = world.rig(1)
    -- Far enough out to have its own ground, and self-powered: an electric network belongs
    -- to a force, so the arena's substation is no use to anybody else.
    local theirs = world.rig_on(world.surface(), world.at(0, 12), { force = "igs-other" })

    after_ticks(world.SETTLE, function()
      assert.is_true(world.piled(mine) > 1,
        ("only %d items for the force that did research it"):format(world.piled(mine)))
      -- one item, which is the game without this mod: swing, find the spot taken, stop
      assert.are.equal(1, world.loose_on(world.surface(), theirs.drop_position, 1),
        "an inserter of a force without belt stacking was helped anyway")
      assert.is_not_nil(storage.droppers[theirs.unit_number],
        "it is not even being watched, so it could not start when the research lands")
      -- and now they research it, with nothing whatever told to the mod
      them.belt_stack_size_bonus = 3
      them.bulk_inserter_capacity_bonus = 3
    end)

    after_ticks(world.SETTLE * 2, function()
      local piled = world.loose_on(world.surface(), theirs.drop_position, 1)
      assert.is_true(piled > 1,
        ("only %d items after that force researched belt stacking: the gate is being read "
          .. "once and remembered, not asked each time"):format(piled))
    end)
  end)

  it("stops when the last force with it loses it", function()
    -- The other end of the same rule. Switching off is for the game as a whole, so it only
    -- happens once nobody at all has the research.
    local them = game.forces["igs-other"] or game.create_force("igs-other")
    world.stacking(3)
    them.belt_stack_size_bonus = 3
    after_ticks(30, function()
      assert.is_true(remote.call("inserter-ground-stack", "report").active)
      game.forces.player.belt_stack_size_bonus = 0
    end)
    after_ticks(30 + 90, function()
      assert.is_true(remote.call("inserter-ground-stack", "report").active,
        "the mod switched off while another force still had belt stacking")
      them.belt_stack_size_bonus = 0
    end)
    after_ticks(30 + 90 + 90, function()
      assert.is_false(remote.call("inserter-ground-stack", "report").active,
        "nobody has belt stacking and the mod is still running")
    end)
  end)
end)
