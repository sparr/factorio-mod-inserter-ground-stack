--- Inserters on a space platform.
---
--- A platform is a surface like any other as far as this mod is concerned -- it watches by
--- unit number, not by position, so the tile at 0,0 on a platform is nothing to do with the
--- tile at 0,0 on Nauvis. What is different is the edge: past the foundation there is
--- nothing, and an inserter aimed over the side throws what it is holding clear rather than
--- putting it down, so there is never a pile there to add to.
---
--- None of this exists without Space Age, so every test here stands aside when it is not
--- loaded, and the suite has to be run with IGS_SPACE_AGE=1 for any of them to mean
--- anything.
local world = require("test.ft.world")

local SPACE_AGE = script.active_mods["space-age"] ~= nil

if not SPACE_AGE then
  describe("inserters on a space platform", function()
    it("needs Space Age, which is not loaded", function() end)
  end)
  return
end

--- How far the foundation reaches either side of the middle. The fixtures stand well inside
--- it and the one aimed overboard stands on its last tile.
local FLOOR = 14

---Make a platform with a patch of floor on it, and hand back its surface.
---
---Built rather than wished into being: a platform starts as a hub on a scrap of foundation,
---and the floor these tests stand on has to be laid.
---@return LuaSurface
local function platform_with_floor()
  local force = game.forces.player
  force.unlock_space_platforms()
  local existing = game.surfaces["igs-platform"]
  if existing and existing.platform then return existing end
  local platform = force.create_space_platform{
    name = "igs-platform", planet = "nauvis",
    starter_pack = "space-platform-starter-pack" }
  assert.is_not_nil(platform, "no platform was made")
  platform.apply_starter_pack()
  local surface = platform.surface
  assert.is_not_nil(surface, "the platform has no surface yet")
  local tiles = {}
  for x = -FLOOR, FLOOR do
    for y = -FLOOR, FLOOR do
      tiles[#tiles + 1] = { name = "space-platform-foundation", position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
  return surface
end

local platform

before_each(function()
  platform = platform_with_floor()
  -- Everything but the hub, which is what the platform is built around and cannot be
  -- replaced. It sits at the middle, so the fixtures stand well away from it.
  for _, thing in pairs(platform.find_entities_filtered{ position = { 0, 0 }, radius = 40 }) do
    if thing.valid and thing.type ~= "character" and thing.name ~= "space-platform-hub" then
      thing.destroy()
    end
  end
  world.stacking(0)
  world.capacity(0)
  world.refresh()
end)

after_each(function()
  if platform and platform.valid then
    for _, thing in pairs(platform.find_entities_filtered{ position = { 0, 0 }, radius = 40 }) do
      if thing.valid and thing.type ~= "character" and thing.name ~= "space-platform-hub" then
        thing.destroy()
      end
    end
    if platform.platform then platform.platform.clear_ejected_items() end
  end
  world.clear()
end)

describe("an inserter on a platform aimed at bare floor", function()
  it("is topped up exactly as one standing on a planet is", function()
    world.stacking(3)
    world.capacity(3)
    local spot = { x = -8.5, y = 8.5 }
    local inserter = world.rig_on(platform, spot)
    after_ticks(world.SETTLE, function()
      local piled = world.loose_on(platform, inserter.drop_position, 1)
      assert.is_true(piled > 1,
        ("%d items on the platform floor: the inserter dropped one and stopped"):format(piled))
    end)
  end)

  it("is told apart from the inserter on the tile of the same name back home", function()
    -- Every planet and every platform has its own tile at any coordinates. Watching by unit
    -- number is what keeps two fixtures standing at the same numbers from being taken for
    -- one another.
    world.stacking(3)
    world.capacity(3)
    local spot = { x = -8.5, y = 8.5 }
    local aloft = world.rig_on(platform, spot)
    local home = world.rig_on(world.surface(), world.at(spot.x - world.ORIGIN.x + 0.0,
                                                        spot.y - world.ORIGIN.y + 0.0))
    assert.are_not.equal(aloft.unit_number, home.unit_number)
    after_ticks(world.SETTLE, function()
      assert.is_not_nil(storage.droppers[aloft.unit_number], "the one aloft was not watched")
      assert.is_not_nil(storage.droppers[home.unit_number], "the one at home was not watched")
      assert.is_true(world.loose_on(platform, aloft.drop_position, 1) > 1,
        "the inserter on the platform never got going")
      assert.is_true(world.loose_on(world.surface(), home.drop_position, 1) > 1,
        "the inserter at home never got going")
    end)
  end)
end)

describe("an inserter aimed over the side of a platform", function()
  it("is left alone, because what it drops never lands", function()
    -- Nothing is put down out there, so there is no pile for this mod to find. The inserter
    -- goes on throwing things overboard exactly as it would without the mod.
    world.stacking(3)
    world.capacity(3)
    -- One tile further out than looks right: set_tiles names a tile by its top left corner,
    -- so laying tiles up to FLOOR gives floor all the way to FLOOR + 1.
    local inserter = world.rig_on(platform, { x = FLOOR + 0.5, y = -6.5 })
    local drop = inserter.drop_position
    local under = platform.get_tile(drop.x, drop.y)
    assert.is_true(not under.valid or under.name ~= "space-platform-foundation",
      ("the drop position %.2f,%.2f is still over %s, so this proves nothing"):format(
        drop.x, drop.y, under.valid and under.name or "nothing"))
    after_ticks(world.SETTLE, function()
      assert.are.equal(0, world.loose_on(platform, drop, 2),
        "something is lying in space")
      assert.are.equal(0, world.loose_on(platform, drop, 6),
        "something landed near the edge after all")
    end)
  end)
end)
