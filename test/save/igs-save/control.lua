--- A factory that has to survive being saved and loaded.
---
--- The mod keeps entity references in storage, and a reference is a thing the engine has to
--- write into a save and hand back on the way in. Nothing in the integration suite can test
--- that, because a suite runs inside one session: it has to be two, with a file in between.
---
--- The first run builds a fixture, lets the mod pick it up and start feeding a pile, writes
--- down what it saw, and saves. The second run loads that save and asks whether the mod
--- still knows the inserter, whether the pile goes on growing, and whether the answers match
--- what the first run wrote down.
local function P(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  log("SAVETEST " .. table.concat(parts, " "))
end

local O = { x = 100.5, y = 100.5 }
local ROWS = 6

local function report(line)
  P(line)
  helpers.write_file("igs-save-result.txt", line .. "\n", true)
end

--- What the mod under test thinks. Asked of it rather than read out of storage: a mod's
--- storage is its own, and this harness is a different mod.
local function mod_state()
  return remote.call("inserter-ground-stack", "report")
end

local function watched()
  return mod_state().watched
end

local function piled()
  local total = 0
  for _, thing in pairs(game.surfaces[1].find_entities_filtered{
      type = "item-entity", position = O, radius = 30 }) do
    if thing.valid and thing.stack.valid_for_read then total = total + thing.stack.count end
  end
  return total
end

script.on_init(function()
  remote.call("freeplay", "set_disable_crashsite", true)
  remote.call("freeplay", "set_skip_intro", true)
  storage.phase = "building"
end)

script.on_event(defines.events.on_tick, function()
  local surface = game.surfaces[1]
  local t = game.tick

  if storage.phase == "building" then
    surface.request_to_generate_chunks(O, 4)
    surface.force_generate_chunk_requests()
    local force = game.forces.player
    force.belt_stack_size_bonus = 3
    force.bulk_inserter_capacity_bonus = 3
    local interface = surface.create_entity{ name = "electric-energy-interface",
      position = { O.x - 9, O.y }, force = "player" }
    interface.power_production = 10000000
    surface.create_entity{ name = "substation", position = { O.x - 5, O.y }, force = "player" }
    for row = 1, ROWS do
      local y = O.y + row * 2
      local chest = surface.create_entity{ name = "steel-chest",
        position = { O.x - 1, y }, force = "player", raise_built = true }
      chest.insert{ name = "iron-plate", count = 2000 }
      surface.create_entity{ name = "bulk-inserter", position = { O.x, y },
        direction = defines.direction.west, force = "player", raise_built = true }
    end
    storage.phase = "running"
    storage.built_at = t

  elseif storage.phase == "running" and t > storage.built_at + 300 then
    storage.before = { watched = watched(), piled = piled() }
    report(("BEFORE watched=%d piled=%d"):format(storage.before.watched, storage.before.piled))
    if storage.before.watched ~= ROWS then
      report(("FAIL the mod watched %d inserters of %d before the save was written")
        :format(storage.before.watched, ROWS))
    end
    if storage.before.piled <= ROWS then
      report(("FAIL only %d items reached the ground before the save was written")
        :format(storage.before.piled))
    end
    -- No server_save here. A headless server writes the map back out when it is asked to
    -- quit, which is how the run ends, and that save is the one the second run loads.
    storage.phase = "saved"
    report("SAVED")

  elseif storage.phase == "saved" then
    -- We are in the loaded save. Everything from here is the second run.
    storage.phase = "checking"
    storage.loaded_at = t
    local now = watched()
    report(("AFTER  watched=%d piled=%d"):format(now, piled()))
    if now ~= storage.before.watched then
      report(("FAIL the mod knew %d inserters before the save and %d after")
        :format(storage.before.watched, now))
    else
      report(("PASS the mod still knows all %d inserters after loading"):format(now))
    end
    -- An entity reference that came back dead would have been swept off the list by now,
    -- so the count matching is the same thing as every reference having survived. What can
    -- be checked separately is that the mod is still switched on, which is stored rather
    -- than worked out afresh.
    if mod_state().active then
      report("PASS the mod is still switched on after loading")
    else
      report("FAIL the mod came back switched off")
    end
    storage.resume_from = piled()

  elseif storage.phase == "checking" and t > storage.loaded_at + 300 then
    local now = piled()
    if now > storage.resume_from then
      report(("PASS the piles went on growing after loading, %d to %d")
        :format(storage.resume_from, now))
    else
      report(("FAIL the piles stopped at %d after loading"):format(now))
    end
    report("DONE")
    storage.phase = "done"
  end
end)
