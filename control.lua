---What the mod keeps in the save.
---
---@class InserterGroundStackStorage
---@field droppers { [uint]: LuaEntity } every inserter that puts things down on bare ground, by unit number
---@field busy { [uint]: uint } the tick each of those was last topped up on, for the ones that recently were
---@field due { [uint]: uint } the soonest tick each of those could possibly want looking at again
---@field pending { [uint]: LuaEntity } inserters to look at again once whatever was in their way has finished going
---@field active boolean whether anybody in this game has researched belt stacking yet

--- What an inserter says about itself when it has swung out, found the spot it puts things
--- down on already taken, and stopped. The hand is parked on the drop position by then:
--- the engine does not report this until the swing has finished, so there is no separate
--- test for whether the hand has arrived.
local JAMMED = defines.entity_status.waiting_for_space_in_destination

--- How long after its last success an inserter goes on being looked at every tick.
---
--- An inserter that is feeding a pile jams again a swing later, and a swing is tens of
--- ticks, so the ones that are working stay in this set and never wait on the sweep. Two
--- seconds of nothing is a line that has stopped or a pile that has filled up, and either
--- way there is no hurry about it any more.
local BUSY_TICKS = 120

--- What fraction of an inserter's own swing to wait before looking at it again.
---
--- An inserter whose hand has just been emptied over its drop position cannot be back with
--- the next handful until it has turned to its pickup and turned out again, and how long
--- that takes is arithmetic rather than a guess. Looking at it before then can only ever
--- find it halfway through the turn.
---
--- Short of the whole swing because the arithmetic runs a little long: the engine turns in
--- whole ticks and the putting down happens on the tick the hand arrives. Measured on
--- 2.1.17 against every vanilla inserter, the swing the prototype implies overshot the real
--- one by between one and two ticks, at every speed from a burner inserter's seventy six to
--- a legendary bulk inserter's eight, and it overshot by the same small margin on inserters
--- built to look like a fake loader's: turning ten times a tick, or barely turning at all
--- and reaching instead. Three quarters clears that at every size, and erring early costs
--- one wasted look where erring late would cost throughput.
local SOON = 0.75

--- How often everything else is looked at.
---
--- This is the wait before an inserter that has only just jammed is noticed, and it is paid
--- once: from then on it is in the busy set. A sixth of a second is below noticing and a
--- tenth of what looking every tick would cost.
local SWEEP_TICKS = 10

--- Things an inserter can put items into that the game does not count as buildings. Asked
--- by type, because what matters is that a wagon or a car can be the thing an inserter was
--- loading, and nothing about the particular prototype changes that.
local VEHICLES = {
  ["car"] = true,
  ["spider-vehicle"] = true,
  ["cargo-wagon"] = true,
  ["artillery-wagon"] = true,
  ["locomotive"] = true,
}

--- Whether an inserter could have been putting things into this kind of thing, remembered
--- by prototype name.
---
--- Every entity that dies or is mined anywhere on the map comes past here, which during a
--- biter wave or a forest fire is a great many of them, so the answer has to be cheap. A
--- biter, a tree, a fish and an ore patch are none of them buildings, and that is most of
--- the traffic gone for one table lookup.
local catches_items = {}

--- Whether an item turns into something alive when it spoils, remembered by name.
---
--- Three items in Space Age do: a biter egg hatches one big biter for every twenty five in
--- the stack, a pentapod egg one premature wriggler each, and a captive biter spawner one
--- spawner -- though that last stacks one deep and so was never a pile in the first place.
local hatches = {}

--- How far from itself an inserter can put something down, in tiles.
---
--- The engine's own answer across every inserter prototype in the game, so a mod's long
--- inserter is covered without this one knowing anything about it. A tile of slack on top,
--- because an inserter whose prototype allows custom vectors can be aimed a little further
--- out than its prototype says, by a blueprint or by another mod.
local drop_reach

---The furthest any inserter in this game can put something down.
---@return number
local function reach()
  drop_reach = drop_reach or (prototypes.max_inserter_reach_distance + 1)
  return drop_reach
end

--- How far from the spot an inserter is aiming at a pile can lie and still be in its way.
---
--- What stops an inserter is not a pile sitting exactly where it aims but a pile whose
--- collision box overlaps the box of the item it is trying to put down, and two boxes can
--- overlap corner to corner while their middles are a box diagonal apart. Anything a player
--- dropped by hand, anything spilled out of a wreck, anything another mod shed off the end
--- of a belt lands wherever it lands rather than on the middle of a tile, so the difference
--- is the difference between helping and doing nothing.
---
--- Asked of the prototype, so a mod that resizes what an item lying on the ground takes up
--- is followed rather than guessed at. Erring wide costs nothing: an inserter is only ever
--- looked at once it has already stopped, so the worst a pile half a tile out can do is
--- take items that were going to land beside it.
local blocking_radius

---How near a pile has to be to the spot an inserter aims at to be in its way.
---@return number
local function blocking()
  if not blocking_radius then
    local box = prototypes.entity["item-on-ground"].collision_box
    -- the width of one box is the two half widths of two boxes side by side
    local across = box.right_bottom.x - box.left_top.x
    local down = box.right_bottom.y - box.left_top.y
    blocking_radius = math.sqrt((across * across) + (down * down))
  end
  return blocking_radius
end

---The soonest an inserter that has just put something down could be back with more.
---
---An inserter turns and reaches at the same time, so a swing takes whichever of the two is
---slower, and the journey there and back is twice that. Both halves have to be worked out:
---on every vanilla inserter the turn is far the longer, but an inserter is only obliged to
---turn as far as its two ends are apart, and a mod is free to put them next to each other.
---A fake loader built out of an invisible inserter does exactly that, and reading the turn
---alone would say such a thing is back in no time when reaching is what it spends its life
---doing.
---
---Worked out from where the hand actually goes rather than from the prototype's own
---vectors, so an inserter a blueprint has aimed somewhere unusual is measured as it stands.
---@param inserter LuaEntity
---@return uint ticks
local function swing_ticks(inserter)
  local proto = inserter.prototype
  local quality = inserter.quality
  local here = inserter.position
  local pickup, drop = inserter.pickup_position, inserter.drop_position
  local px, py = pickup.x - here.x, pickup.y - here.y
  local dx, dy = drop.x - here.x, drop.y - here.y

  local turning = 0
  local spin = proto.get_inserter_rotation_speed(quality)
  if spin and spin > 0 then
    local turn = math.abs(math.atan2(dy, dx) - math.atan2(py, px)) / (2 * math.pi)
    -- the short way round, since an inserter never takes the long one
    if turn > 0.5 then turn = 1 - turn end
    turning = turn / spin
  end

  local reaching = 0
  local stretch = proto.get_inserter_extension_speed(quality)
  if stretch and stretch > 0 then
    reaching = math.abs(math.sqrt((dx * dx) + (dy * dy)) - math.sqrt((px * px) + (py * py)))
      / stretch
  end

  return math.max(1, math.floor(2 * math.max(turning, reaching) * SOON))--[[@as uint]]
end

---Stop watching an inserter.
---
---Kept by unit number rather than by where it stands, since every planet and every space
---platform has its own tile at any given coordinates.
---@param unit_number uint
local function forget(unit_number)
  storage.droppers[unit_number] = nil
  storage.busy[unit_number] = nil
  storage.due[unit_number] = nil
end

---Look at an inserter again on the next tick.
---
---Never in the event itself. The engine settles what an inserter is aimed at during its own
---update, so while a build or a mining event is running, drop_target still describes the
---tick before it: a new inserter reads as aimed at nothing whatever is standing in front of
---it, and one whose chest is going still reads as aimed at that chest. Waiting a tick is
---what makes the answer the world's rather than the event's.
---
---Kept by unit number rather than in a list, so that pulling down a wall of chests queues
---each inserter beside it once rather than once per chest.
---@param entity LuaEntity?
local function later(entity)
  if not storage.active then return end
  if entity and entity.valid and entity.type == "inserter" then
    storage.pending[entity.unit_number--[[@as uint]]] = entity
  end
end

---Start or stop watching an inserter, according to where its items land.
---
---An inserter with somewhere to put things -- a chest, a belt, a wagon -- is no business of
---this mod, and the great majority are. What is left is the ones whose items land on the
---ground, which is the whole of what is watched.
---@param entity LuaEntity?
local function watch(entity)
  if not (entity and entity.valid and entity.type == "inserter") then return end
  local unit_number = entity.unit_number--[[@as uint]]
  if entity.drop_target then
    forget(unit_number)
  else
    storage.droppers[unit_number] = entity
    -- Looked at on the next tick rather than when its old swing was going to be over.
    -- Anything that brings an inserter back through here has changed something about it,
    -- and turning one round moves both the spot it aims at and how far it has to turn to
    -- get there, so what was worked out for the old arrangement is worth nothing.
    storage.due[unit_number] = nil
  end
end

---Whether piling this item up on the ground would be stacking a bomb.
---
---An item that hatches when it spoils hatches in proportion to how many of it are lying
---there, and the engine only ever leaves one of anything on a tile, so a pile of them is a
---thing this mod would be inventing. One egg on the ground going off is the game as it
---ships; a hundred going off at once, because an egg line was pointed at bare ground and
---never backed up, is not. These are left to jam exactly as they always did.
---@param name string
---@return boolean
local function hatches_when_it_spoils(name)
  local answer = hatches[name]
  if answer == nil then
    local proto = prototypes.item[name]
    answer = (proto and proto.spoil_to_trigger_result) ~= nil
    hatches[name] = answer
  end
  return answer
end

---Add what an inserter is holding to the stack it is stuck behind.
---
---Everything about whether the two will stack at all is left to the engine: transfer_stack
---moves what fits and refuses what does not, so a pile of one quality will not take items
---of another, food of one freshness will not silently take on food of a different one, and
---nothing ever grows past what a stack of that item holds. The mod's part is to ask.
---@param unit_number uint
---@param inserter LuaEntity
---@return boolean moved whether anything moved
---@return boolean emptied whether the hand came away with nothing left in it
local function top_up(unit_number, inserter)
  if not inserter.valid then forget(unit_number) return false, false end
  -- something has been built where its items used to land, so it is somebody else's problem
  if inserter.drop_target then forget(unit_number) return false, false end
  if inserter.status ~= JAMMED then return false, false end

  local held = inserter.held_stack
  if not held.valid_for_read then return false, false end
  if hatches_when_it_spoils(held.name) then return false, false end

  -- Asked of this inserter's own force rather than of the cached answer for the game,
  -- because two forces can be at different points in the tech tree and this is only ever
  -- reached for an inserter that has already stopped, which is a small enough set to pay
  -- for the truth. Taking the research away therefore stops a factory at once, where
  -- granting it takes effect on the next look.
  if inserter.force.belt_stack_size_bonus < 1 then return false, false end

  local before = held.count
  local drop = inserter.drop_position
  local piles = inserter.surface.find_entities_filtered{
    type = "item-entity", position = drop, radius = blocking() }

  -- Nearly always one, and then there is nothing to choose between. Where there is more
  -- than one -- a pile the inserter put down and another that a player dropped or a wreck
  -- spilled beside it -- the nearest is the one it is aimed at, and the one its items
  -- should join. Ordered only when ordering can matter, since sorting a list of one is
  -- work for nothing.
  if piles[2] then
    -- Keyed by the entity itself. An item lying on the ground has no unit number, and
    -- within one answer from the engine each of these is its own distinct object.
    local away = {}
    for _, pile in pairs(piles) do
      local dx, dy = pile.position.x - drop.x, pile.position.y - drop.y
      away[pile] = (dx * dx) + (dy * dy)
    end
    table.sort(piles, function(a, b) return away[a] < away[b] end)
  end

  for _, pile in pairs(piles) do
    local stack = pile.stack
    if stack.valid_for_read then
      stack.transfer_stack(held)
      local left = held.valid_for_read and held.count or 0
      if left < before then return true, left == 0 end
    end
  end
  return false, false
end

---@param event EventData.on_tick
local function onTick(event)
  if not storage.active then return end
  local tick = event.tick

  -- Everything that was built, turned round, mined or blown up last tick. By now the
  -- engine has settled what each of these inserters is aimed at, which it had not when the
  -- event came in.
  if next(storage.pending) then
    for _, entity in pairs(storage.pending) do watch(entity) end
    storage.pending = {}
  end

  -- The ones that were feeding a pile a moment ago, so that a line already running keeps the
  -- pace its inserters can manage rather than the pace of the sweep. Each is left alone
  -- until its own swing could possibly have brought it back, which on a plain inserter is
  -- seventy ticks it would otherwise have been asked about seventy times.
  for unit_number, last in pairs(storage.busy) do
    local inserter = storage.droppers[unit_number]
    if not inserter then
      storage.busy[unit_number] = nil
      storage.due[unit_number] = nil
    elseif tick >= (storage.due[unit_number] or 0) then
      local moved, emptied = top_up(unit_number, inserter)
      if moved then
        storage.busy[unit_number] = tick
        -- A hand that did not come away empty is a hand the pile had no room for, and
        -- nothing about waiting a swing would change that; it is looked at again at once in
        -- case something takes from the pile, and falls to the sweep when nothing does.
        storage.due[unit_number] = emptied and (tick + swing_ticks(inserter)) or (tick + 1)
      elseif tick - last > BUSY_TICKS then
        storage.busy[unit_number] = nil
        storage.due[unit_number] = nil
      end
    end
  end

  -- And everything else now and then, which is how an inserter that has only just jammed
  -- is found.
  if tick % SWEEP_TICKS == 0 then
    for unit_number, inserter in pairs(storage.droppers) do
      if not storage.busy[unit_number] then
        local moved, emptied = top_up(unit_number, inserter)
        if moved then
          storage.busy[unit_number] = tick
          storage.due[unit_number] = emptied and (tick + swing_ticks(inserter)) or (tick + 1)
        end
      end
    end
  end
end

---Everything on every surface matching the filter, a chunk at a time.
---
---Walking the chunks is most of what this costs -- fifty thousand of them on a large map --
---so it is only ever done when what is stored cannot be trusted.
---@param args LuaSurface.find_entities_filtered_param
---@return LuaEntity[]
local function find_all_entities(args)
  ---@type LuaEntity[]
  local entities = {}
  for _, surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do
      local left, top = chunk.x * 32, chunk.y * 32
      args.area = {{left, top}, {left + 32, top + 32}}
      for _, entity in pairs(surface.find_entities_filtered(args)) do
        entities[#entities + 1] = entity
      end
    end
  end
  return entities
end

---Read the world again and build the list of watched inserters from scratch.
local function refreshData()
  storage.droppers = {}
  storage.busy = {}
  storage.due = {}
  storage.pending = {}
  for _, inserter in pairs(find_all_entities{type = "inserter"}) do
    watch(inserter)
  end
end

---Decide whether this game has any use for the mod at all, and start or stop accordingly.
---
---Nothing here can happen before somebody has researched belt stacking: an inserter that
---puts things down on ground that is taken waits on it, exactly as it always did. So until
---then the mod does not watch anything, does not hear a build event, and does not tick. A
---save that never researches it pays nothing at all, and one that has not got there yet
---pays nothing until it does.
---
---The reading of the world that starting costs is paid once, at the moment the research
---lands, which is the one moment it is worth paying: the list has to come from somewhere
---and every build event up to then was deliberately ignored.
---
---Asked of the forces rather than of a technology, and asked again now and then rather than
---only when a technology finishes, because the bonus can be handed out by a console command
---or by another mod without any research being done at all.
local function reconsider()
  local active = false
  for _, force in pairs(game.forces) do
    if force.belt_stack_size_bonus >= 1 then
      active = true
      break
    end
  end
  if active == storage.active then return end
  storage.active = active
  if active then
    refreshData()
  else
    storage.droppers = {}
    storage.busy = {}
    storage.due = {}
    storage.pending = {}
  end
end

---Forget everything and work it all out again from the world as it stands.
---
---What the mod's own remote interface offers, and what it does on a new game and after an
---update. Settling whether to be active at all is part of it: "read the world again" has to
---include reading whether anybody can stack things, or a save whose bonus arrived by
---console command would be told to rebuild a list it had decided not to keep.
local function rebuild()
  storage.active = nil
  reconsider()
end

---@param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_player_rotated_entity
local function onPlaceEntity(event)
  later(event.entity)
end

---@param event EventData.on_entity_died|EventData.on_player_mined_entity
local function onRemoveEntity(event)
  if not storage.active then return end
  local entity = event.entity
  if not (entity and entity.valid) then return end

  if entity.type == "inserter" then
    forget(entity.unit_number--[[@as uint]])
    return
  end

  local name = entity.name
  local worth_a_look = catches_items[name]
  if worth_a_look == nil then
    worth_a_look = entity.prototype.is_building or VEHICLES[entity.type] or false
    catches_items[name] = worth_a_look
  end
  if not worth_a_look then return end

  -- An inserter that was loading this has nowhere to put things now, and nothing tells it
  -- so: there is no event for an inserter whose target went away, only one for the target.
  -- Which inserters those are cannot be settled yet, because the thing in their way is
  -- still standing here while this event runs, so they are looked at again next tick.
  local box = entity.bounding_box
  local slack = reach()
  for _, inserter in pairs(entity.surface.find_entities_filtered{
      type = "inserter",
      area = {{box.left_top.x - slack, box.left_top.y - slack},
              {box.right_bottom.x + slack, box.right_bottom.y + slack}}}) do
    later(inserter)
  end
end

local function onInit()
  storage.droppers = {}
  storage.busy = {}
  storage.due = {}
  storage.pending = {}
  rebuild()
end

local function onConfigurationChanged()
  -- read the world again rather than trusting what was stored, since an update may have
  -- changed the shape of what is stored -- but only if there is any reason to have a list
  rebuild()
end

script.on_init(onInit)
script.on_configuration_changed(onConfigurationChanged)

script.on_event(defines.events.on_built_entity, onPlaceEntity)
script.on_event(defines.events.on_robot_built_entity, onPlaceEntity)
script.on_event(defines.events.on_space_platform_built_entity, onPlaceEntity)

-- an inserter another mod put down or revived from a ghost is as real as one a player
-- built, and these are how a script says it has done so
script.on_event(defines.events.script_raised_built, onPlaceEntity)
script.on_event(defines.events.script_raised_revive, onPlaceEntity)
script.on_event(defines.events.on_entity_cloned, function(event) later(event.destination) end)

-- turning an inserter round, or pasting settings onto one, moves where its items land
script.on_event(defines.events.on_player_rotated_entity, onPlaceEntity)
script.on_event(defines.events.on_entity_settings_pasted, function(event) later(event.destination) end)

-- and a teleported inserter takes its drop position with it, but not what was standing
-- under it
script.on_event(defines.events.script_raised_teleported, onPlaceEntity)

-- Before removal rather than after, because the entity has to still be there to be asked
-- where it stood and how big it was. What is done about it waits for the next tick, by
-- which time it is gone.
script.on_event(defines.events.on_pre_player_mined_item, onRemoveEntity)
script.on_event(defines.events.on_robot_pre_mined, onRemoveEntity)
script.on_event(defines.events.on_space_platform_pre_mined, onRemoveEntity)
script.on_event(defines.events.on_entity_died, onRemoveEntity)
script.on_event(defines.events.script_raised_destroy, onRemoveEntity)

script.on_event(defines.events.on_tick, onTick)

-- Whether anybody can stack things at all, looked at about once a second. That is a handful
-- of attribute reads on a handful of forces, which is the whole cost of having this mod
-- installed in a game that has not researched belt stacking.
script.on_nth_tick(67, reconsider)

-- and at once when a research lands, so the first inserter does not sit there for a second
-- wondering what happened
script.on_event(defines.events.on_research_finished, reconsider)
script.on_event(defines.events.on_technology_effects_reset, reconsider)
script.on_event(defines.events.on_force_created, reconsider)
script.on_event(defines.events.on_forces_merged, reconsider)

---What the mod currently thinks, in a form another mod or a command can read.
---
---Read only, and a summary rather than the tables themselves: handing out the real ones
---would let anything holding the reference change what the mod is doing. Useful for asking
---a running game why nothing is happening, and it is how the save round trip test sees
---across the boundary between two sessions, since a mod's storage is its own.
---@return { active: boolean, watched: integer, busy: integer, pending: integer }
local function report()
  local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
  end
  return {
    active = storage.active or false,
    watched = count(storage.droppers),
    busy = count(storage.busy),
    pending = count(storage.pending),
  }
end

remote.add_interface("inserter-ground-stack",
                      {refreshData = rebuild, report = report}
                    )

-- igs-tests is never published, so this can never fire on a player's machine -- which
-- matters, because the fixtures build inserters and leave items lying on the ground.
if script.active_mods["factorio-test"] and script.active_mods["igs-tests"] then
  require("__factorio-test__/init")({
    "test.ft.stacking",
    "test.ft.research",
    "test.ft.limits",
    "test.ft.lifecycle",
    "test.ft.platforms",
    "test.ft.aquilo",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
