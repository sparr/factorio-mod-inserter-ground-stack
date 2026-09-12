--- How the map gets read in the background.
---
--- The reading is the mod's backstop: everything that announces itself is dealt with when
--- it happens, and this is what catches what nothing announced. It reads a surface two
--- different ways and these are about the difference.
---
--- The first time round a surface is crawled -- its chunks asked for one at a time, and
--- where they lie noted. After that the surface is read by blocks: squares of ground taken
--- straight from the rectangle those chunks turned out to fill, with no chunk list
--- involved. That is worth having because most of what a query costs is the asking, so
--- asking once about sixteen chunks beats asking sixteen times, and because walking the
--- chunk list was itself nearly half of what a pass cost.
---
--- What it risks is coverage. A rectangle is a guess about where the ground is, made once
--- and then relied on, so the tests here are mostly about the ways that guess can go stale:
--- ground appearing outside it, ground disappearing inside it, and ground so scattered that
--- the rectangle is mostly gap and crawling would have been better.
local world = require("test.ft.world")

before_each(function()
  world.prepare()
  world.clear()
  world.power()
end)
after_each(world.clear)

---What the mod will say about itself.
---@return table
local function report()
  return remote.call("inserter-ground-stack", "report")
end

---Whether every surface there is has been crawled and is now read by blocks.
---
---Every one rather than any one: a fixture stood on a surface that is still being crawled
---would be found by the crawl, and a test meaning to exercise the blocks would pass
---without ever reaching them.
---@return boolean
local function all_by_blocks()
  local surfaces = 0
  for _ in pairs(game.surfaces) do surfaces = surfaces + 1 end
  return report().blocked == surfaces
end

---Every chunk a surface has, and the box they sit in.
---@param surface LuaSurface
---@return { n: integer, x0: integer, y0: integer, x1: integer, y1: integer }
local function ground(surface)
  local seen
  for chunk in surface.get_chunks() do
    if seen == nil then
      seen = { n = 0, x0 = chunk.x, y0 = chunk.y, x1 = chunk.x, y1 = chunk.y }
    end
    seen.n = seen.n + 1
    if chunk.x < seen.x0 then seen.x0 = chunk.x end
    if chunk.x > seen.x1 then seen.x1 = chunk.x end
    if chunk.y < seen.y0 then seen.y0 = chunk.y end
    if chunk.y > seen.y1 then seen.y1 = chunk.y end
  end
  assert.is_not_nil(seen, "the test surface has no chunks at all")
  return seen--[[@as table]]
end

---Long enough for the reading to go round every surface once, with room to spare.
---
---Worked out from the map the test is actually standing on rather than guessed, since a
---pass costs a budget unit for every chunk and one for every inserter found, and how many
---of either there are is up to whoever made the save.
---@return integer ticks
local function a_pass()
  local total = 0
  for _, surface in pairs(game.surfaces) do
    for _ in surface.get_chunks() do total = total + 1 end
  end
  -- the idle budget, which is the slower of the two the mod uses
  return math.ceil((total + 500) / 64) + 60
end

---Put an inserter down without telling anybody, the way a script that forgets to raise its
---events does. Nothing but the reading can find one of these.
---@param surface LuaSurface
---@param at MapPosition
---@return LuaEntity
local function quietly(surface, at)
  local inserter = surface.create_entity{ name = "inserter", position = at,
    direction = defines.direction.west, force = "player", raise_built = false }
  assert.is_not_nil(inserter, ("could not put an inserter at %.0f,%.0f"):format(at.x, at.y))
  return inserter--[[@as LuaEntity]]
end

---Make ground where there was none, and hand back the chunks that appeared.
---@param surface LuaSurface
---@param at MapPosition
---@return ChunkPosition[]
local function make_ground(surface, at)
  local before = {}
  for chunk in surface.get_chunks() do before[chunk.x .. ":" .. chunk.y] = true end
  surface.request_to_generate_chunks(at, 1)
  surface.force_generate_chunk_requests()
  local fresh = {}
  for chunk in surface.get_chunks() do
    if not before[chunk.x .. ":" .. chunk.y] then
      fresh[#fresh + 1] = { x = chunk.x, y = chunk.y }
    end
  end
  assert.is_true(#fresh > 0, "no new ground was generated, so this proves nothing")
  return fresh
end

---Take ground away again, so one test does not leave the map bigger for the next.
---@param surface LuaSurface
---@param chunks ChunkPosition[]
local function unmake_ground(surface, chunks)
  for _, at in pairs(chunks) do surface.delete_chunk(at) end
end

describe("reading a surface", function()
  it("crawls it the first time and reads it by blocks after that", function()
    world.stacking(3)
    assert.are.equal(0, report().blocked,
      "a surface was already being read by blocks before anything had been crawled")
    after_ticks(a_pass(), function()
      local now = report()
      assert.is_true(now.passes >= 1,
        ("the reading has been round %d times, so nothing has been crawled yet")
          :format(now.passes))
      assert.is_true(now.blocked >= 1,
        "a surface has been crawled and is still not being read by blocks")
    end)
  end)

  it("finds an inserter nothing announced, while reading by blocks", function()
    -- The whole point of the reading, done the new way. Built after the crawl has been and
    -- gone, so what finds it can only be a block.
    world.stacking(3)
    world.capacity(3)
    local pass = a_pass()
    local inserter, rounds
    after_ticks(pass, function()
      assert.is_true(all_by_blocks(),
        "not every surface is read by blocks yet, so this could be testing the crawl")
      inserter = world.rig(1, { quiet = true })
      assert.is_nil(storage.droppers[inserter.unit_number],
        "something announced it after all, so finding it proves nothing")
      rounds = report().passes
    end)
    after_ticks(pass * 2 + 30, function()
      assert.is_true(report().passes > rounds,
        "the reading never came round again, so it cannot have found anything")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "reading by blocks did not find an inserter the crawl would have")
    end)
    after_ticks(pass * 2 + 30 + world.SETTLE, function()
      assert.is_true(world.piled(inserter) > 1,
        ("only %d items on the ground: it was found but never topped up")
          :format(world.piled(inserter)))
    end)
  end)

  it("reads ground that appeared after the rectangle was worked out", function()
    -- A rectangle is worked out once and then relied on, so ground generated afterwards is
    -- outside it and would never be read again if nothing widened it.
    world.stacking(3)
    local surface = world.surface()
    local pass = a_pass()
    local fresh, inserter, rounds
    after_ticks(pass, function()
      assert.is_true(all_by_blocks(), "it is not reading by blocks, so this is moot")
      local was = ground(surface)
      -- a few chunks past the eastern edge: outside the rectangle, but not so far out that
      -- the rectangle stops being worth using
      fresh = make_ground(surface, { x = (was.x1 + 4) * 32 + 16, y = 16 })
      inserter = quietly(surface, { x = (was.x1 + 4) * 32 + 16.5, y = 16.5 })
      assert.is_nil(storage.droppers[inserter.unit_number],
        "something announced it, so finding it proves nothing")
      assert.is_true(all_by_blocks(),
        "a little more ground put the surface back to crawling")
      rounds = report().passes
    end)
    after_ticks(pass * 3 + 60, function()
      assert.is_true(report().passes > rounds, "the reading never came round again")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "an inserter on ground made after the rectangle was never read")
      if inserter.valid then inserter.destroy() end
      unmake_ground(surface, fresh)
    end)
  end)

  it("goes back to crawling when the rectangle becomes mostly gap", function()
    -- One chunk generated a long way off -- a journey, an outpost, a script having a look
    -- round -- turns a solid rectangle into one that is almost all gap. Reading that by
    -- blocks means reading a great deal of nothing, so the surface goes back to crawling,
    -- and what is out there still has to be found.
    world.stacking(3)
    local surface = world.surface()
    local pass = a_pass()
    local fresh, inserter, rounds
    after_ticks(pass, function()
      assert.is_true(report().blocked >= 1, "it is not reading by blocks, so this is moot")
      fresh = make_ground(surface, { x = 5000 * 32 + 16, y = 16 })
      assert.are.equal(0, report().blocked,
        "a rectangle five thousand chunks wide round one chunk of ground is still "
          .. "being read by blocks")
      inserter = quietly(surface, { x = 5000 * 32 + 16.5, y = 16.5 })
      rounds = report().passes
    end)
    after_ticks(pass * 3 + 60, function()
      assert.is_true(report().passes > rounds, "the reading never came round again")
      assert.is_not_nil(storage.droppers[inserter.unit_number],
        "the surface went back to crawling and still did not find what was out there")
      if inserter.valid then inserter.destroy() end
      unmake_ground(surface, fresh)
    end)
    after_ticks(pass * 5 + 90, function()
      -- and taking the far ground away puts it back to blocks, which is the other half of
      -- keeping the rectangle honest
      assert.is_true(report().blocked >= 1,
        "the far ground is gone and the surface never went back to reading by blocks")
    end)
  end)
end)
