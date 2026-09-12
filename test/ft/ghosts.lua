--- Inserters aimed at a ghost.
---
--- A ghost of anything that receives items is an inserter's drop target in its own right.
--- The inserter says `waiting_for_target_to_be_built`, holds everything and puts nothing
--- down, however long the ghost stands there -- so it is no business of this mod, and having
--- a drop target is enough to keep it off the list without anything being said about ghosts.
---
--- What does need saying about them is the other end. A ghost is not mined and does not die:
--- cancelling one raises `on_pre_ghost_deconstructed`, which names the thing `ghost` rather
--- than `entity`, and a ghost is neither a building nor anything that blocks an item from
--- being put down. So nothing about the ordinary reasoning for noticing a removal applies to
--- it, and without saying so plainly an inserter whose ghost was cancelled would go
--- unnoticed until the reading of the map came round.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

---Put a ghost of something where an inserter is aiming.
---@param inserter LuaEntity
---@param inner string
---@return LuaEntity
local function ghost_at(inserter, inner)
  local surface = world.surface()
  local drop = inserter.drop_position
  local ghost = surface.create_entity{
    name = "entity-ghost", inner_name = inner,
    position = { math.floor(drop.x) + 0.5, math.floor(drop.y) + 0.5 },
    force = "player", raise_built = true }
  assert.is_not_nil(ghost, "could not put a ghost down in front of the inserter")
  -- And it has to actually cover the spot the inserter aims at. Placing a thing on the
  -- middle of the right tile is not the same as covering a point three quarters of the way
  -- across it, and a fixture that misses is a fixture that tests bare ground while looking
  -- exactly like one that tests a ghost.
  local covers = false
  for _, thing in pairs(surface.find_entities_filtered{ position = drop }) do
    if thing.valid and thing.type == "entity-ghost" then covers = true end
  end
  assert.is_true(covers,
    ("the %s ghost does not cover %.2f,%.2f, where the inserter aims"):format(
      inner, drop.x, drop.y))
  return ghost--[[@as LuaEntity]]
end

describe("an inserter aimed at the ghost of something that takes items", function()
  it("waits for it to be built, and is not watched", function()
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    ghost_at(inserter, "steel-chest")
    after_ticks(60, function()
      assert.are.equal(defines.entity_status.waiting_for_target_to_be_built, inserter.status,
        "an inserter aimed at a chest ghost said something else")
      assert.is_not_nil(inserter.drop_target, "the ghost is not what it aims at")
      assert.are.equal("entity-ghost", inserter.drop_target.name)
      assert.is_nil(storage.droppers[inserter.unit_number],
        "an inserter waiting on a ghost is being watched")
      assert.are.equal(0, world.piled(inserter), "it put something down on the ghost")
    end)
  end)

  it("blocks even an item the finished thing could never accept", function()
    -- Whether a ghost is in the way turns on the thing having an item inventory at all, not
    -- on whether this particular item could go into it. A gun turret takes ammunition and
    -- nothing else, and its ghost still stops an inserter carrying iron plates dead.
    --
    -- This is worth pinning because the whole of watch() rests on it: an inserter with a
    -- drop target is left off the list on the understanding that it will never put anything
    -- on the ground. If blocking were decided by the item, an inserter holding the wrong one
    -- would have a drop target and be dropping on the ground at the same time, and the mod
    -- would quietly never help it.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1, { item = "iron-plate" })
    ghost_at(inserter, "gun-turret")
    after_ticks(world.SETTLE, function()
      assert.are.equal(defines.entity_status.waiting_for_target_to_be_built, inserter.status,
        "a gun turret ghost let an inserter carrying plates get on with it")
      assert.is_not_nil(inserter.drop_target)
      assert.are.equal(0, world.piled(inserter),
        "iron plates landed in front of a gun turret ghost")
      assert.is_nil(storage.droppers[inserter.unit_number],
        "it is being watched even though it has a drop target")
    end)
  end)

  it("is found again when the ghost is cancelled", function()
    -- The event for this is on_pre_ghost_deconstructed, which nothing else in the mod
    -- listens for, and it hands over the ghost under a different name.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local ghost = ghost_at(inserter, "steel-chest")
    after_ticks(60, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "it was never left off the list, so finding it again proves nothing")
      world.mine(ghost)
      assert.is_not_nil(storage.pending[inserter.unit_number],
        "cancelling a ghost did not put its inserter up to be looked at again")
    end)
    after_ticks(60 + 30, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the ghost was cancelled and the inserter was never picked up")
    end)
    after_ticks(60 + 30 + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground where the ghost used to be"):format(
          world.piled(inserter)))
    end)
  end)

  it("is found again when the ghost is marked for deconstruction", function()
    -- The other way a ghost goes, and the one that needs its own event. A ghost marked for
    -- deconstruction is removed there and then rather than mined, so none of the mining
    -- events fire and only on_pre_ghost_deconstructed says anything.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local ghost = ghost_at(inserter, "steel-chest")
    after_ticks(60, function()
      assert.is_nil(storage.droppers[inserter.unit_number],
        "it was never left off the list, so finding it again proves nothing")
      ghost.order_deconstruction(game.forces.player)
      assert.is_not_nil(storage.pending[inserter.unit_number],
        "a ghost marked for deconstruction did not put its inserter up to be looked at")
    end)
    after_ticks(60 + 30, function()
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the ghost was deconstructed and the inserter was never picked up")
    end)
    after_ticks(60 + 30 + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground where the ghost used to be"):format(
          world.piled(inserter)))
    end)
  end)

  it("keeps its target when the ghost is built for real", function()
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local ghost = ghost_at(inserter, "steel-chest")
    after_ticks(60, function()
      ghost.revive{ raise_revive = true }
    end)
    after_ticks(90, function()
      assert.is_not_nil(inserter.drop_target, "the chest it built is not its target")
      assert.are.equal("steel-chest", inserter.drop_target.name)
      assert.is_nil(storage.droppers[inserter.unit_number],
        "an inserter loading a real chest is being watched")
    end)
  end)
end)

describe("an inserter aimed at the ghost of something that does not take items", function()
  it("puts things on the ground as if the ghost were not there", function()
    -- A wall has no inventory of any kind, so its ghost is not a drop target: the inserter
    -- aims through it at the ground and this mod treats it like any other bare spot. A wall
    -- rather than a power pole because a wall fills its tile, and a pole's collision box is
    -- too small to cover the spot an inserter actually aims at.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    ghost_at(inserter, "stone-wall")
    after_ticks(world.SETTLE, function()
      assert.is_nil(inserter.drop_target, "a wall ghost became a drop target")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "an inserter putting things on the ground under a wall ghost is not watched")
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground under a wall ghost"):format(world.piled(inserter)))
    end)
  end)
end)

describe("something that blocks an item without being a building", function()
  it("is noticed when it goes, because the masks say it was in the way", function()
    -- A land mine is not a building and catches nothing, but an item cannot be put down on
    -- one: it shares a collision layer with an item lying on the ground. Rails are the case
    -- this reasoning exists for, and this is the cheap way to test the reasoning itself
    -- rather than the one entity it was written for.
    world.stacking(3)
    world.capacity(3)
    local inserter = world.rig(1)
    local drop = inserter.drop_position
    local mine = world.surface().create_entity{ name = "land-mine",
      position = { math.floor(drop.x) + 0.5, math.floor(drop.y) + 0.5 },
      force = "player", raise_built = true }
    assert.is_not_nil(mine, "could not put a land mine in the way")
    assert.is_false(prototypes.entity["land-mine"].is_building,
      "a land mine counts as a building now, so this tests nothing it meant to")
    after_ticks(60, function()
      assert.are.equal(0, world.piled(inserter), "it put something down on the mine")
      mine.destroy{ raise_destroy = true }
      assert.is_not_nil(storage.pending[inserter.unit_number],
        "something that was in the way went and its inserter was not looked at again")
    end)
  end)
end)
