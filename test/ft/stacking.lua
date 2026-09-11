--- The whole of what the mod is for: an inserter with somewhere to put things down that is
--- already taken puts them on the stack that is there instead of standing still.
---
--- The engine drops one item on bare ground and then stops, with whatever is left in the
--- hand staying in the hand for good. That is true of a plain inserter carrying one item
--- and of a bulk inserter carrying four, and it is true however much stacking has been
--- researched, so there is nothing to compare against but a dead stop.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

describe("an inserter putting things down on ground that is taken", function()
  it("adds to the stack lying there rather than waiting on it", function()
    world.stacking(3)
    local inserter = world.rig(1)
    after_ticks(world.SETTLE, function()
      local piled = world.piled(inserter)
      assert.is_true(piled > 1,
        ("%d items on the ground: the inserter dropped one and stopped"):format(piled))
    end)
  end)

  it("keeps going, so the pile grows swing after swing", function()
    world.stacking(3)
    local inserter = world.rig(1)
    local early
    after_ticks(world.JAM, function() early = world.piled(inserter) end)
    after_ticks(world.SETTLE, function()
      local late = world.piled(inserter)
      assert.is_true(late > early,
        ("the pile stood at %d and is still %d: it was topped up once and then left")
          :format(early, late))
    end)
  end)

  it("empties the hand, so the inserter goes back for more", function()
    world.stacking(3)
    world.capacity(3)
    local inserter, chest = world.rig(1)
    after_ticks(world.SETTLE, function()
      assert.is_true(chest.get_item_count("iron-plate") < 1000,
        "the chest is untouched: nothing was ever picked up")
      assert.is_true(world.piled(inserter) >= 4,
        ("only %d items reached the ground, which is less than one handful")
          :format(world.piled(inserter)))
    end)
  end)

  it("makes nothing and loses nothing on the way", function()
    world.stacking(3)
    world.capacity(3)
    local inserter, chest = world.rig(1, { count = 400 })
    after_ticks(world.SETTLE, function()
      assert.are.equal(400, world.accounted(inserter, chest, "iron-plate"),
        ("400 went in; %d are in the chest, %d in the hand and %d on the ground"):format(
          chest.get_item_count("iron-plate"),
          inserter.held_stack.valid_for_read and inserter.held_stack.count or 0,
          world.piled(inserter)))
    end)
  end)

  it("leaves one pile rather than a scattering", function()
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    after_ticks(world.SETTLE, function()
      local piles = world.surface().find_entities_filtered{
        type = "item-entity", position = world.at(0, world.ROW), radius = 4 }
      assert.are.equal(1, #piles,
        ("%d piles on the ground, not one"):format(#piles))
      assert.are.equal(world.loose("iron-plate"), world.piled(inserter),
        "some items landed somewhere other than the spot the inserter aims at")
    end)
  end)

  it("does the same for a plain inserter carrying one item at a time", function()
    world.stacking(3)
    local inserter = world.rig(1, { inserter = "inserter" })
    after_ticks(world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        "a plain inserter still stopped at the first item")
    end)
  end)

  it("keeps up with the inserter's own swing", function()
    -- The mod does not look at a working inserter every tick; it works out from how fast
    -- that inserter turns when it could possibly be back, and leaves it alone until then.
    -- Getting that arithmetic wrong in the slow direction would cost throughput without
    -- failing anything else, so this compares what the fixture managed against what the
    -- prototype says it could manage.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    after_ticks(world.SETTLE, function()
      local swing = 1 / inserter.prototype.get_inserter_rotation_speed(inserter.quality)
      local hand = inserter.inserter_target_pickup_count
      local best = math.floor(world.SETTLE / swing) * hand
      local piled = world.piled(inserter)
      assert.is_true(piled >= best * 0.85,
        ("%d items in %d ticks, against the %d that an inserter turning this fast could "
          .. "have carried: the mod is looking at it too late"):format(
          piled, world.SETTLE, best))
    end)
  end)

  it("runs several fixtures side by side without mixing them up", function()
    world.stacking(3)
    local first = world.rig(1, { item = "iron-plate" })
    local second = world.rig(-1, { item = "copper-plate" })
    after_ticks(world.SETTLE, function()
      assert.is_true(world.piled(first) > 1, "the first inserter never got going")
      assert.is_true(world.piled(second) > 1, "the second inserter never got going")
      assert.are.equal("iron-plate", world.pile(first).stack.name)
      assert.are.equal("copper-plate", world.pile(second).stack.name)
    end)
  end)
end)
