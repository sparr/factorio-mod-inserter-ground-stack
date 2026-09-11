--- Where the topping up stops.
---
--- The mod asks the engine to move the items and takes the answer it gets, so every rule
--- the game already has about what will stack with what is still in force: a pile holds a
--- stack of that item and no more, it will not take a different item, and it will not take
--- the same item of a different quality. None of that is written down in the mod, which is
--- the point of these: they are here to catch the mod growing an opinion of its own.
---
--- Each fixture is left to jam with the research switched off, so that what is lying on the
--- ground can be changed out from under a stopped inserter before the mod is allowed near
--- it. Doing it the other way round is a race with the mod's own first look.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

describe("a pile that is already as big as the item stacks", function()
  it("takes no more, and the inserter stops on it for good", function()
    -- Barrels stack ten deep, which a fixture reaches in three swings. Iron plates stack a
    -- hundred deep and would still be filling when the test ran out of patience.
    local size = prototypes.item["barrel"].stack_size
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1, { item = "barrel", count = 100 })
    after_ticks(world.SETTLE, function()
      assert.are.equal(size, world.piled(inserter),
        ("%d barrels on the ground against a stack of %d"):format(
          world.piled(inserter), size))
      assert.are.equal(defines.entity_status.waiting_for_space_in_destination,
        inserter.status, "the inserter carried on past a full stack")
    end)
    after_ticks(world.SETTLE * 2, function()
      assert.are.equal(size, world.piled(inserter),
        "the pile went on growing past a full stack")
    end)
  end)
end)

describe("a pile of something else", function()
  it("is left alone, and the inserter waits on it as it always did", function()
    world.stacking(0)
    local inserter = world.rig(1, { item = "iron-plate" })
    after_ticks(world.JAM, function()
      local pile = world.pile(inserter)
      assert.is_not_nil(pile, "nothing was put down to swap out")
      pile.stack.set_stack{ name = "copper-plate", count = 1 }
      world.stacking(3)
    end)
    after_ticks(world.JAM + world.SETTLE, function()
      local pile = world.pile(inserter)
      assert.is_not_nil(pile, "the pile vanished")
      assert.are.equal("copper-plate", pile.stack.name,
        "iron plates were poured onto a pile of copper")
      assert.are.equal(1, pile.stack.count, "the copper pile grew")
      local held = inserter.held_stack
      assert.is_true(held.valid_for_read and held.name == "iron-plate",
        "the inserter is not still holding its iron")
    end)
  end)
end)

if prototypes.quality and prototypes.quality["uncommon"] then
  describe("a pile of the same item at another quality", function()
    it("is left alone, because the game would not stack those either", function()
      world.stacking(0)
      local inserter = world.rig(1, { item = "iron-plate" })
      after_ticks(world.JAM, function()
        local pile = world.pile(inserter)
        assert.is_not_nil(pile, "nothing was put down to swap out")
        pile.stack.set_stack{ name = "iron-plate", count = 1, quality = "uncommon" }
        world.stacking(3)
      end)
      after_ticks(world.JAM + world.SETTLE, function()
        local pile = world.pile(inserter)
        assert.is_not_nil(pile, "the pile vanished")
        assert.are.equal("uncommon", pile.stack.quality.name)
        assert.are.equal(1, pile.stack.count,
          "normal plates were poured onto an uncommon pile")
      end)
    end)
  end)
end

describe("a pile that is not quite where the inserter aims", function()
  -- An inserter's own pile lands exactly where it aims. Everything else on the ground --
  -- what a player dropped by hand, what spilled out of a wreck, what another mod shed off
  -- the end of a belt -- lands wherever it landed, and stops an inserter just as dead while
  -- sitting a fraction of a tile off. What counts as in the way is two collision boxes
  -- overlapping, which for items on the ground is a little over a quarter of a tile, so the
  -- offsets below walk from dead centre out to the edge of that.
  for _, offset in pairs({
    { dx = 0.00, dy = 0.00, label = "dead on the spot" },
    { dx = 0.15, dy = 0.00, label = "a sixth of a tile to one side" },
    { dx = 0.00, dy = 0.25, label = "a quarter of a tile along" },
    { dx = 0.18, dy = 0.18, label = "off diagonally, which is the furthest it can be" },
  }) do
    it(("is topped up when it is %s, because it is still in the way"):format(offset.label),
      function()
        world.stacking(0)
        local inserter = world.rig(1)
        local beside = world.surface().create_entity{
          name = "item-on-ground",
          position = { x = inserter.drop_position.x + offset.dx,
                       y = inserter.drop_position.y + offset.dy },
          stack = { name = "iron-plate", count = 1 },
        }
        assert.is_not_nil(beside, "could not put a pile down beside the drop position")
        after_ticks(world.JAM, function()
          assert.are.equal(defines.entity_status.waiting_for_space_in_destination,
            inserter.status,
            "the pile was not in the way after all, so this proves nothing")
          assert.are.equal(1, beside.stack.count, "it grew before it was allowed to")
          world.stacking(3)
        end)
        after_ticks(world.JAM + world.SETTLE, function()
          assert.is_true(beside.valid and beside.stack.count > 1,
            "the inserter stayed stopped on a pile a fraction of a tile off its aim")
        end)
      end)
  end

  it("is left alone when it is far enough out not to be in the way", function()
    -- Far enough that the inserter can put its own item down beside it. Two piles then sit
    -- within a whisker of each other, and the items have to go on the one the inserter is
    -- actually aimed at rather than on whichever the engine happened to list first.
    world.stacking(0)
    local inserter = world.rig(1)
    local beside = world.surface().create_entity{
      name = "item-on-ground",
      position = { x = inserter.drop_position.x + 0.36, y = inserter.drop_position.y },
      stack = { name = "copper-plate", count = 1 },
    }
    assert.is_not_nil(beside, "could not put a pile down beside the drop position")
    after_ticks(world.JAM, function()
      assert.are.equal(defines.entity_status.waiting_for_space_in_destination,
        inserter.status, "it never jammed on its own pile")
      world.stacking(3)
    end)
    after_ticks(world.JAM + world.SETTLE, function()
      assert.is_true(beside.valid, "the pile beside it was consumed")
      assert.are.equal(1, beside.stack.count,
        "items went onto the pile beside the drop spot rather than the one on it")
      local own = world.pile(inserter)
      assert.is_not_nil(own, "the inserter's own pile is gone")
      assert.are.equal("iron-plate", own.stack.name)
      assert.is_true(own.stack.count > 1,
        ("the inserter's own pile stood at %d"):format(own.stack.count))
    end)
  end)
end)

describe("an item that hatches when it spoils", function()
  it("is left to jam, because a pile of it is a pile of biters", function()
    -- The engine leaves one egg on a tile and stops. How many hatch is worked out from how
    -- many are lying there, so a pile the mod built is a bigger bang than the game would
    -- ever have arranged, and this is the one place the mod declines to help.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1, { item = "igs-hatching-thing", count = 200 })
    after_ticks(world.SETTLE, function()
      assert.are.equal(1, world.piled(inserter),
        ("%d of them piled up on one tile"):format(world.piled(inserter)))
      assert.are.equal(defines.entity_status.waiting_for_space_in_destination,
        inserter.status, "the inserter is not stopped, so something moved its items")
    end)
  end)

  it("is judged by what it turns into, not by whether it spoils at all", function()
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1, { item = "igs-spoiling-thing", count = 200 })
    after_ticks(world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        "an item that merely rots was refused along with the ones that hatch")
    end)
  end)
end)

describe("bare ground", function()
  it("is still the engine's business, and still takes one item", function()
    -- Nothing here needs the mod: the first swing lands on ground nobody has taken, which
    -- the engine handles by itself. What it leaves is the one item the mod then builds on.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    after_ticks(20, function()
      assert.is_true(world.piled(inserter) >= 1,
        "nothing reached the ground at all")
    end)
  end)
end)
