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

--- What an inserter says when the spot it aims at is rail and a train is expected there.
---
--- It holds everything and puts nothing down, however long the wait, so it can never be the
--- inserter this mod is for. On a factory built around trains this is the great majority of
--- the inserters that have no drop target at all: measured on a real megabase, 5,397 of
--- 6,020. They are let go of rather than carried, and found again by the ordinary means when
--- the rail under them goes away.
local WAITING_FOR_TRAIN = defines.entity_status.waiting_for_train

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

--- Things an inserter can be aimed at that may move off the spot under their own power,
--- with no event of any kind to say they have.
---
--- An inserter loading one of these is normally let go of, the way every inserter with
--- somewhere to put things is. But when a car drives away nothing is built, mined or
--- destroyed -- the car still exists, it is simply not there any more -- and there is no
--- event in the game for the thing under an inserter's hand moving. So these are kept on
--- the list while they wait, and top_up finds them the moment the ground clears.
---
--- Rolling stock is deliberately not here, although it moves and moves often. A train can
--- only stand on rail, and an item can never be put down on rail, so the ground under a
--- wagon is no more use to an inserter than the wagon was: when the train pulls out the
--- inserter goes to waiting_for_train and is let go of again, which is where it started.
--- Keeping them would have been the expensive half too -- on a megabase, 3,409 inserters
--- were loading rolling stock against none at all loading a car.
---
--- A cargo pod is here on suspicion rather than on evidence. Nothing in the game aims an
--- inserter at one -- a rocket is loaded through its silo and a platform through its hub --
--- and one has no inventory this mod could find. But it flies away by itself, so if some
--- mod ever does aim an inserter at one, this is the answer that would be right, and since
--- there are never any of them to carry it costs nothing to be ready.
local MOVABLE = {
  ["car"] = true,
  ["spider-vehicle"] = true,
  ["cargo-pod"] = true,
}

--- Things that stand in for something that will catch items. A ghost of anything that
--- receives them is an inserter's drop target in its own right: the inserter says
--- `waiting_for_target_to_be_built` and puts nothing down at all, so cancelling the ghost is
--- the moment the ground becomes fair game.
local STAND_INS = { ["entity-ghost"] = true }

--- Kinds of thing that can never have been in an inserter's way, turned away at the
--- engine's door rather than in this mod's own code.
---
--- An entity being removed costs something before a line of Lua runs: the engine builds the
--- event and hands over an object for the entity, once for every mod listening. That is
--- paid whatever the answer turns out to be, and on a busy map the answer is nearly always
--- no. Measured on a Space Age megabase, 170,984 of the 171,004 entities that died in a
--- thousand ticks were asteroids, shot off the bows of platforms in flight, and this mod
--- threw away every one of them. Naming them in the event filter means they are never
--- offered in the first place.
---
--- A filter is fixed when the mod is loaded, so it is only safe where the type settles the
--- question on its own, without asking the prototype:
---
--- An asteroid is not a building, cannot be the thing an inserter was loading, and shares
--- no collision layer with an item lying on the ground -- checked on all sixteen asteroid
--- prototypes in Space Age, every one of them is_building = false with nothing in common
--- with an item's mask.
---
--- Trees and plants come and go in their thousands as well: a forest burning, a field on
--- Gleba being harvested. An item cannot be put down on a tree, so one is in an inserter's
--- way while it stands there, but an inserter aimed at a tree is watched the whole time it
--- stands there -- nothing about a tree makes the mod let go of it -- so there is nothing
--- to re-find when it falls.
---
--- A unit is a biter or a pentapod. Nothing puts items into one, nothing is stopped from
--- putting an item down by one, and on a map under attack they die in great numbers.
local NEVER_IN_THE_WAY = { "asteroid", "unit" }

--- And the kinds that are in the way, but whose going still tells this mod nothing.
---
--- A tree does block an item from being put down -- it shares the is_lower_object layer
--- with an item lying on the ground, which the first draft of this got wrong -- and so does
--- a plant. But blocking is only half of what makes a removal worth hearing. The other half
--- is whether the inserter was let go of while the thing stood there, and an inserter aimed
--- at a tree never is: it has no drop target and it is not waiting for a train, so it stays
--- on the list the whole time, jammed, being offered a pile that is not there yet. The
--- moment the tree falls it puts something down and the mod picks up from there, without
--- anyone having had to tell it.
---
--- Which is worth filtering because they come and go in their thousands: a forest burning,
--- a field on Gleba being harvested by agricultural towers.
local NEVER_LET_GO_OF = { "plant", "tree" }

--- Both lists at once, to ask about one entity at a time.
---
--- Nothing on either should ever reach here, since the filter means the events never
--- arrive. It is kept anyway: a filter that quietly stopped applying -- a new version of
--- the game, a type renamed -- should cost this mod a little time rather than its
--- correctness.
local not_worth_hearing = {}
for _, kind in pairs(NEVER_IN_THE_WAY) do not_worth_hearing[kind] = true end
for _, kind in pairs(NEVER_LET_GO_OF) do not_worth_hearing[kind] = true end

--- And both in the shape the engine wants them: any of these, no thank you.
---
--- `invert` on each and `and` between them, which reads as none of them rather than not all
--- of them. The mode on the first is ignored, and giving them all the same one saves a
--- reader wondering whether the order matters.
local WORTH_HEARING = {}
for _, list in pairs({ NEVER_IN_THE_WAY, NEVER_LET_GO_OF }) do
  for i = 1, #list do
    WORTH_HEARING[#WORTH_HEARING + 1] = { filter = "type", type = list[i],
                                          invert = true, mode = "and" }
  end
end

--- What the mod wants to hear when something is built: only that it was an inserter.
---
--- This takes nothing away. Building a chest in front of an inserter has never brought that
--- inserter through here -- it is noticed the next time the inserter itself is looked at
--- and found to have a drop target -- and later() already refuses everything that is not an
--- inserter. The filter is the same refusal, made before the event is built.
local INSERTERS_ONLY = { { filter = "type", type = "inserter" } }

--- Whether taking this away could change where an inserter's items land, remembered by
--- prototype name.
---
--- Three ways it can, and the first version of this described only the first.
---
--- It was catching them: a chest, a machine, a wagon. Take it away and the inserter has
--- nowhere to put them but the ground.
---
--- It was standing in for something that would, which is a ghost.
---
--- It was in the way: an item cannot be put down on a rail at all, because rails and items
--- lying on the ground share a collision layer. That is the one this mod leans on hardest,
--- since an inserter aimed at rail is let go of on purpose and the rail going away is the
--- only thing that brings it back. Asked of the collision masks rather than of is_building,
--- which rails happen to satisfy: resting the whole of that on a coincidence would be
--- resting it on luck, and it is not true of every rail -- an elevated one does not block an
--- item at all, because you can drop things underneath it.
---
--- Every entity that dies or is mined anywhere on the map comes past here, which during a
--- biter wave is a great many of them, so the answer has to be cheap. A biter, a fish and an
--- ore patch are none of these things, and that is most of the traffic gone for one table
--- lookup.
---
--- Keyed by name rather than by type because prototypes of one type disagree: simple-entity
--- covers a rock, which is in the way, beside things that are not. It holds no more than
--- what has already been worked out once, and it is a file local rather than anything kept
--- in the save, so it is built again from nothing every session: a prototype renamed or
--- redefined between one version and the next cannot leave a stale answer behind.
local remembered = {}

--- What an item lying on the ground collides with, worked out once.
local item_layers

---Whether this kind of thing could have been in an inserter's way at all.
---
---The question underneath the whole of the above, asked of the prototype on its own and of
---nothing else. Separate from the answer the mod acts on so that a test can put every
---prototype in the game through it and check the kinds the event filter refuses really are
---kinds this would have refused anyway; run together, that check asks the filter about the
---filter and passes whatever the filter says.
---@param proto LuaEntityPrototype
---@return boolean
local function blocks_or_catches(proto)
  local kind = proto.type
  if STAND_INS[kind] or VEHICLES[kind] then return true end
  if proto.is_building then return true end
  if not item_layers then
    item_layers = prototypes.entity["item-on-ground"].collision_mask.layers
  end
  for layer in pairs(proto.collision_mask.layers) do
    if item_layers[layer] then return true end
  end
  return false
end

---Whether one of these going away is worth looking round for.
---@param proto LuaEntityPrototype
---@return boolean
local function worth_a_look_when_gone(proto)
  if not_worth_hearing[proto.type] then return false end
  return blocks_or_catches(proto)
end

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
  local target = entity.drop_target
  if (target and not MOVABLE[target.type])
      or (not target and entity.status == WAITING_FOR_TRAIN) then
    -- Turned away at the door rather than taken on and dropped at the next look. The
    -- background reading comes past every inserter on the map again and again, and an
    -- inserter aimed at rail that were let go of only afterwards would be taken on and
    -- dropped once a pass for ever, which on a factory built around trains is thousands of
    -- them churning in and out of the list to no purpose.
    forget(unit_number)
  else
    storage.droppers[unit_number] = entity
    -- Looked at on the next tick rather than when its old swing was going to be over.
    -- Anything that brings an inserter back through here has changed something about it,
    -- and turning one round moves both the spot it aims at and how far it has to turn to
    -- get there, so what was worked out for the old arrangement is worth nothing.
    --
    -- No settling wait before judging it, either. Taking the rail out from under an inserter
    -- changes what it says about itself within the same tick, which test.ft.rails checks on
    -- every phase of the sweep in turn, including the phase where it is found and judged in
    -- one tick.
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
  -- Something has been built where its items used to land, so it is somebody else's
  -- problem -- unless that something can drive away again, in which case this inserter is
  -- kept and simply has nothing to do until it does.
  local target = inserter.drop_target
  if target then
    if not MOVABLE[target.type] then forget(unit_number) end
    return false, false
  end
  local status = inserter.status
  -- Rail with a train coming to it. Nothing will ever be put down here, so this is not an
  -- inserter worth carrying; the rail going away is what brings it back.
  if status == WAITING_FOR_TRAIN then forget(unit_number) return false, false end
  if status ~= JAMMED then return false, false end

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

---Look at every inserter in an area, however big it is.
---@param surface LuaSurface
---@param area BoundingBox?
---@return integer how many were found
local function read_area(surface, area)
  local found = 0
  for _, inserter in pairs(surface.find_entities_filtered{ area = area, type = "inserter" }) do
    found = found + 1
    watch(inserter)
  end
  return found
end

---Forget every inserter and work the whole list out again from the world as it stands.
---
---One question to each surface rather than one to each chunk of each surface:
---find_entities_filtered with no area at all hands back every inserter on a surface in a
---single call. On a Space Age megabase that is fifty-nine calls against two hundred and
---twenty-eight thousand, and it is why this can be a single tick rather than a cursor
---creeping over the map for a minute and a half.
---
---A long tick, all the same, and it happens at three moments: a new game, an update to
---this mod, and the tick belt stacking is researched. The first two are a load, where a
---pause goes unnoticed. The third is a research finishing, where it does not -- but it
---happens once in a save, and the alternative was several hundred lines of cursor.
local function read_everything()
  storage.droppers = {}
  storage.busy = {}
  storage.due = {}
  storage.pending = {}
  for _, surface in pairs(game.surfaces) do
    read_area(surface, nil)
  end
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
      if not storage.busy[unit_number] and tick >= (storage.due[unit_number] or 0) then
        local moved, emptied = top_up(unit_number, inserter)
        if moved then
          storage.busy[unit_number] = tick
          storage.due[unit_number] = emptied and (tick + swing_ticks(inserter)) or (tick + 1)
        end
      end
    end
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
    read_everything()
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

---Read the whole world again, now.
---
---What the mod's own remote interface and its console command offer, and the way out of
---anything this mod failed to hear about: a script that built an inserter without raising
---an event, a mod that re-aimed one in a way nothing here knows to listen for. It is the
---same work the mod does for itself when belt stacking is researched, so it costs the same
---long tick and no more.
local function refreshData()
  rebuild()
end

---@param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_player_rotated_entity
local function onPlaceEntity(event)
  later(event.entity)
end

---@param event EventData.on_entity_died|EventData.on_player_mined_entity
local function onRemoveEntity(event)
  if not storage.active then return end
  -- a ghost being deconstructed comes as `ghost`; everything else comes as `entity`
  local entity = event.entity or event.ghost
  if not (entity and entity.valid) then return end

  if entity.type == "inserter" then
    forget(entity.unit_number--[[@as uint]])
    return
  end

  -- The name and a table lookup, and nothing else, for the great majority that turn out not
  -- to matter. Only the first of each kind pays for the prototype to be fetched and asked.
  local name = entity.name
  local worth_a_look = remembered[name]
  if worth_a_look == nil then
    worth_a_look = worth_a_look_when_gone(entity.prototype)
    remembered[name] = worth_a_look
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

--- Mods that re-aim an inserter after it has been built, and the events they say so with.
---
--- An inserter's drop position can be moved from a GUI, and several popular mods do it:
--- swinging one from a chest round to bare ground is exactly the change this mod has to
--- know about, and writing drop_position raises nothing the game defines. Each mod that
--- announces it at all does so with an event of its own.
---
--- Surveyed rather than guessed at. Of the 111 inserter and loader mods on the portal
--- built for 2.x with more than two thousand downloads, 56 publish source that could be
--- read; 15 of those write drop_position or pickup_position, and three of the 15 raise
--- anything at all when they do. These are those three. The other twelve say nothing
--- whatever, and neither can anything be said about the 55 whose source is not published,
--- which between them are why the console command exists.
---
--- Two of the three declare a custom-event prototype in their data stage, so the id is
--- sitting in defines.events by the time this file is read and a name is all that is
--- needed.
local ADJUSTERS_BY_PROTOTYPE = {
  "on_bobs_inserter_adjusted",             -- Bob's Adjustable Inserters
  "on_qai_inserter_vectors_changed",       -- Quick Adjustable Inserters
  "on_qai_inserter_direction_changed",
  "on_qai_inserter_adjustment_finished",
}

--- And the one whose id is made at run time and handed out by a remote interface.
---
--- Asked for on load rather than here, because nothing may be asked of another mod while
--- this file is still being read. Taking up a handler that depends on which mods are
--- present is one of the few things on_load is for.
local ADJUSTERS_BY_INTERFACE = {
  { mod = "Smart_Inserters", asking = "on_inserter_arm_changed" },
}

---An inserter somebody has re-aimed.
---
---Looked at again next tick, exactly as a newly built one is: where an inserter's items
---land is settled during the engine's own update and not while the event that moved it is
---still running.
---@param event table
local function onAimed(event)
  -- Bob's and Smart Inserters call it `entity`; Quick Adjustable Inserters calls it
  -- `entity` in one of its three and `inserter` in the other two.
  later(event.entity or event.inserter)
end

for _, name in pairs(ADJUSTERS_BY_PROTOTYPE) do
  local id = defines.events[name]
  if id then script.on_event(id, onAimed) end
end

---Take up the events whose ids have to be asked for.
local function listen_for_adjusters()
  for _, who in pairs(ADJUSTERS_BY_INTERFACE) do
    local offered = remote.interfaces[who.mod]
    if offered and offered[who.asking] then
      script.on_event(remote.call(who.mod, who.asking), onAimed)
    end
  end
end

local function onInit()
  -- on_load does not run on a new game, so the same taking-up has to happen here
  listen_for_adjusters()
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
script.on_load(listen_for_adjusters)
script.on_configuration_changed(onConfigurationChanged)

script.on_event(defines.events.on_built_entity, onPlaceEntity, INSERTERS_ONLY)
script.on_event(defines.events.on_robot_built_entity, onPlaceEntity, INSERTERS_ONLY)
script.on_event(defines.events.on_space_platform_built_entity, onPlaceEntity, INSERTERS_ONLY)

-- an inserter another mod put down or revived from a ghost is as real as one a player
-- built, and these are how a script says it has done so
script.on_event(defines.events.script_raised_built, onPlaceEntity, INSERTERS_ONLY)
script.on_event(defines.events.script_raised_revive, onPlaceEntity, INSERTERS_ONLY)
script.on_event(defines.events.on_entity_cloned,
                function(event) later(event.destination) end, INSERTERS_ONLY)

-- Turning an inserter round, or pasting settings onto one, moves where its items land.
-- Neither of these takes a filter, so later() does the refusing; both are a player's own
-- doing and arrive a handful at a time rather than in their thousands.
script.on_event(defines.events.on_player_rotated_entity, onPlaceEntity)
script.on_event(defines.events.on_entity_settings_pasted, function(event) later(event.destination) end)

-- and a teleported inserter takes its drop position with it, but not what was standing
-- under it
script.on_event(defines.events.script_raised_teleported, onPlaceEntity, INSERTERS_ONLY)

-- Before removal rather than after, because the entity has to still be there to be asked
-- where it stood and how big it was. What is done about it waits for the next tick, by
-- which time it is gone.
script.on_event(defines.events.on_pre_player_mined_item, onRemoveEntity, WORTH_HEARING)
script.on_event(defines.events.on_robot_pre_mined, onRemoveEntity, WORTH_HEARING)
script.on_event(defines.events.on_space_platform_pre_mined, onRemoveEntity, WORTH_HEARING)
script.on_event(defines.events.on_entity_died, onRemoveEntity, WORTH_HEARING)
script.on_event(defines.events.script_raised_destroy, onRemoveEntity, WORTH_HEARING)

-- A ghost is not mined and does not die; cancelling one has events of its own, and they
-- name the thing `ghost` rather than `entity`. Unfiltered, because a ghost's own type is
-- `entity-ghost` whatever it stands for, so the list above would say nothing about it, and
-- because cancelling ghosts is something a player does rather than something a map does
-- every tick.
script.on_event(defines.events.on_pre_ghost_deconstructed, onRemoveEntity)
script.on_event(defines.events.on_pre_ghost_upgraded, onRemoveEntity)

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
---@return { active: boolean, watched: integer, busy: integer, pending: integer, listening_for: string[], never_in_the_way: string[], never_let_go_of: string[] }
local function report()
  local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
  end
  -- Copied rather than handed over, for the same reason as the rest: what comes back here
  -- is an answer, not a handle on the mod's own furniture.
  local filtered = {}
  for i = 1, #NEVER_IN_THE_WAY do filtered[i] = NEVER_IN_THE_WAY[i] end
  local blocked = {}
  for i = 1, #NEVER_LET_GO_OF do blocked[i] = NEVER_LET_GO_OF[i] end
  local heard = {}
  for i = 1, #ADJUSTERS_BY_PROTOTYPE do heard[i] = ADJUSTERS_BY_PROTOTYPE[i] end
  return {
    active = storage.active or false,
    watched = count(storage.droppers),
    busy = count(storage.busy),
    pending = count(storage.pending),
    -- the events of other mods it has taken up, for re-aiming an inserter
    listening_for = heard,
    -- What the mod has told the engine not to bother telling it about, kept apart by the
    -- reason it is entitled to say so, since the two claims are checked differently: these
    -- could never have been in an inserter's way at all...
    never_in_the_way = filtered,
    -- ...and these could, but an inserter they stop is never let go of, so there is nothing
    -- to find again when they go
    never_let_go_of = blocked,
  }
end

---What the mod makes of one kind of thing, asked by prototype name.
---
---A question worth being able to ask from outside, and the one a mod author debugging an
---interaction actually has: when my entity goes away, will you notice? The answer is the
---two decisions the mod draws and the fact underneath them, so it is possible to see which
---step went the way it did rather than only that the outcome was wrong.
---
---By name because that is how prototypes are addressed everywhere else -- it is the
---argument, not anything the mod keeps. Nothing here is remembered between calls and
---nothing is read from the save.
---
---It is also the seam the prototype sweep in test.ft.removals goes through, which is the
---point of it existing rather than the reasoning being written out twice: a test that
---re-implements the rule proves the copy right, not the mod.
---@param name string a prototype name, as prototypes.entity is keyed
---@return { type: string, blocks_or_catches: boolean, heard_about: boolean, matters_when_gone: boolean, movable: boolean }? nil if this game has no prototype of that name
local function about(name)
  local proto = prototypes.entity[name]
  if proto == nil then return nil end
  return {
    type = proto.type,
    -- could one of these ever have been catching an inserter's items, or stopping one from
    -- being put down
    blocks_or_catches = blocks_or_catches(proto),
    -- whether the mod asked the engine to mention it at all when one is removed
    heard_about = not not_worth_hearing[proto.type],
    -- and what it makes of the removal once it hears
    matters_when_gone = worth_a_look_when_gone(proto),
    -- whether an inserter aimed at one is kept on the list against its moving off
    movable = MOVABLE[proto.type] or false,
  }
end

remote.add_interface("inserter-ground-stack",
                      {refreshData = refreshData, report = report, about = about}
                    )

-- The same thing without writing Lua, for a player who finds an inserter the mod never
-- heard about.
--
-- Which can happen, and the mod does not pretend otherwise. Everything it knows it was
-- told, and a script may build an inserter or re-aim one without saying so: raising the
-- events is a convention rather than a rule, and the flags that raise them are off by
-- default. This reads the factory again from scratch and puts all of it right.
--
-- Deterministic, so it is safe in a game with other people in it: a command typed by one
-- player runs on every peer, and this does the same work on each.
commands.add_command("igs-rescan",
  "Inserter Ground Stack: read the whole factory again, for inserters the mod never heard "
    .. "about being built or re-aimed. Takes a moment on a large save.",
  function(event)
    refreshData()
    local said = report()
    local message = said.active
      and ("inserter-ground-stack: %d inserters put things down on bare ground")
            :format(said.watched)
      or "inserter-ground-stack: nobody has researched belt stacking, so there is nothing to do"
    local player = event.player_index and game.get_player(event.player_index)
    if player then player.print(message) else log(message) end
  end)

-- igs-tests is never published, so this can never fire on a player's machine -- which
-- matters, because the fixtures build inserters and leave items lying on the ground.
if script.active_mods["factorio-test"] and script.active_mods["igs-tests"] then
  require("__factorio-test__/init")({
    "test.ft.stacking",
    "test.ft.research",
    "test.ft.limits",
    "test.ft.lifecycle",
    "test.ft.removals",
    "test.ft.aiming",
    "test.ft.rails",
    "test.ft.ghosts",
    "test.ft.platforms",
    "test.ft.aquilo",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
