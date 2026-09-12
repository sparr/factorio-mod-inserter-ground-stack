--- What the mod hears when something is removed, and what it makes of it.
---
--- Every removal event is registered with a filter naming a few kinds of thing that are
--- never worth looking at, so that a map full of them -- asteroids off the bows of
--- platforms, a forest on fire, a wave of biters -- does not pay to cross into Lua only to
--- be thrown away. A filter is fixed when the mod loads, so nothing at runtime can notice
--- if what entitles it stops being true.
---
--- There are two different entitlements and they are checked differently, which the first
--- draft of this ran together and was wrong about trees.
---
--- Both checks go through the mod's own reasoning, over every entity prototype this
--- installation has, rather than through a copy of the rule written out again here. A test
--- that re-implements the rule proves the copy right and says nothing about the mod; and
--- asking the mod only "does the filter agree with the filter" would pass whatever the
--- filter said. So what is asked is the question underneath the filter -- could one of
--- these ever have been in an inserter's way -- which the mod answers from prototype data
--- and nothing else.
local world = require("test.ft.world")

---@return table
local function report()
  return remote.call("inserter-ground-stack", "report")
end

---What the mod makes of one kind of thing.
---@param name string
---@return table
local function about(name)
  local said = remote.call("inserter-ground-stack", "about", name)
  assert.is_not_nil(said, ("the mod knows nothing about %s"):format(name))
  return said
end

---The kinds named on one of the mod's two lists, as a set.
---@param which string
---@return table<string, boolean>
local function listed(which)
  local kinds = {}
  for _, kind in pairs(report()[which]) do kinds[kind] = true end
  assert.is_true(next(kinds) ~= nil, ("the mod says %s is empty"):format(which))
  return kinds
end

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

describe("the removals the mod asks the engine not to tell it about", function()
  it("could not have been in an inserter's way, for the ones filtered on that", function()
    -- The first entitlement, swept over every prototype of every named kind: not one of
    -- them is a building, so not one could have been catching an inserter's items, and not
    -- one shares a collision layer with an item lying on the ground, so not one could have
    -- been stopping an item from being put down.
    local kinds = listed("never_in_the_way")
    local checked = 0
    for name, proto in pairs(prototypes.entity) do
      if kinds[proto.type] then
        checked = checked + 1
        local said = about(name)
        assert.is_false(said.blocks_or_catches,
          ("%s (a %s) could be in an inserter's way now, and the mod has told the engine "
            .. "not to mention it going"):format(name, proto.type))
        assert.is_false(said.matters_when_gone)
      end
    end
    assert.is_true(checked > 0,
      "not one of those kinds has a prototype in this game, so this checked nothing")
  end)

  it("are in the way after all, for the ones filtered on the other grounds", function()
    -- The second entitlement is not that these are harmless -- a tree does stop an item
    -- being put down, sharing the is_lower_object layer with one lying on the ground --
    -- but that an inserter one of them stops is never let go of, so nothing has to find it
    -- again when it falls. Checked positively, because if none of them were in the way
    -- they would belong on the other list and this second argument would be dead weight.
    local kinds = listed("never_let_go_of")
    local checked, in_the_way = 0, 0
    for name, proto in pairs(prototypes.entity) do
      if kinds[proto.type] then
        checked = checked + 1
        if about(name).blocks_or_catches then in_the_way = in_the_way + 1 end
        assert.is_false(about(name).matters_when_gone,
          ("%s is filtered out and acted on at the same time"):format(name))
      end
    end
    assert.is_true(checked > 0,
      "not one of those kinds has a prototype in this game, so this checked nothing")
    assert.is_true(in_the_way > 0,
      "not one of them is in an inserter's way, so they want no argument of their own and "
        .. "belong on the other list")
  end)

  it("is a sweep wide enough to be worth calling one", function()
    -- The two above are only worth anything if the game really did hand over its whole
    -- catalogue. A pairs() that came back nearly empty would pass them both in silence.
    local swept = 0
    for _ in pairs(prototypes.entity) do swept = swept + 1 end
    assert.is_true(swept > 500,
      ("only %d entity prototypes to sweep, which is too few to be the whole game")
        :format(swept))
  end)
end)

describe("a kind the mod hears nothing about because its inserter is never let go of",
         function()
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

describe("an inserter aimed at something that can move off by itself", function()
  it("is kept on the list, and only for the things that really can", function()
    -- Rolling stock moves, and moves constantly, and is deliberately not on this list: a
    -- train can only stand on rail and an item can never be put down on rail, so the
    -- ground a wagon leaves behind is no more use to the inserter than the wagon was.
    -- Keeping them would also have been the whole cost -- on a megabase, 3,409 inserters
    -- were loading rolling stock and not one was loading a car.
    assert.is_true(about("car").movable, "a car is not something that can drive away")
    assert.is_true(about("tank").movable)
    assert.is_true(about("spidertron").movable)
    assert.is_false(about("cargo-wagon").movable,
      "an inserter loading a wagon is being carried, though rail can never take an item")
    assert.is_false(about("locomotive").movable)
    assert.is_false(about("steel-chest").movable, "a chest is going somewhere?")
    local pod = remote.call("inserter-ground-stack", "about", "cargo-pod")
    if pod then
      assert.is_true(pod.movable, "a cargo pod flies off and is not being kept")
      assert.is_false(pod.blocks_or_catches,
        "a cargo pod is in an inserter's way now, so its removal wants hearing about")
    end
  end)
end)
