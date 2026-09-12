---What the mod keeps in the save.
---
---Where the background reading of the map stands.
---
---`at` counts chunks into a surface being crawled; `bx`/`by` are the corner of the next
---block of one being read by blocks; only one of the two is ever in use. `survey` is what a
---crawl in progress has learnt about where the surface's chunks lie, and becomes its entry
---in `rect` when the crawl reaches the end.
---@class RescanState
---@field surface uint? the surface being read
---@field at uint how many chunks into it a crawl has got
---@field bx integer? the next block's left edge, in chunks
---@field by integer? the next block's top edge, in chunks
---@field passes uint how many times the reading has been round every surface
---@field rect { [uint]: { x0: integer, y0: integer, x1: integer, y1: integer, n: integer } } the rectangle each surface's chunks fill, for the ones read by blocks
---@field survey { x0: integer, y0: integer, x1: integer, y1: integer, n: integer }? what the crawl in progress has seen so far

---@class InserterGroundStackStorage
---@field droppers { [uint]: LuaEntity } every inserter that puts things down on bare ground, by unit number
---@field busy { [uint]: uint } the tick each of those was last topped up on, for the ones that recently were
---@field due { [uint]: uint } the soonest tick each of those could possibly want looking at again
---@field pending { [uint]: LuaEntity } inserters to look at again once whatever was in their way has finished going
---@field rescan RescanState? how far the background reading of the map has got
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

--- How much the background reading does in a tick, counted in both chunks looked at and
--- inserters found in them.
---
--- Reading a whole factory is the one expensive thing this mod does: on a megabase, doing it
--- in a single tick took 4.9 seconds, which is a freeze rather than a hitch. A fixed amount
--- of work a tick means the cost does not depend on the size of the map at all. What varies
--- instead is how long a pass takes to come round -- about a minute on a large map, moments
--- on a small one -- and that is the thing that can afford to vary.
---
--- Counted in entities as well as chunks because the two are not the same expense. A chunk
--- of open ground is nothing; a chunk of a bus is hundreds of inserters, and a budget that
--- counted only chunks would take all of them in one tick.
local FIRST_PASS_BUDGET = 256

--- And how much it does once it has been round once.
---
--- A crawl, because by then it is only a backstop. Everything that announces itself is dealt
--- with the moment it happens: an inserter built, turned round or taken away, and a few
--- tiles looked at again around anything else that is removed, which is how an inserter
--- whose rail has gone is found. What is left for the reading to catch is a script that
--- changed the map and said nothing, which is rare and never urgent.
---
--- Sixty four a tick is a pass in moments on a small map and a minute and a half on a
--- megabase, which is the right pace for something nothing is waiting on.
local IDLE_BUDGET = 64

--- How many chunks across the square of ground read in one query is.
---
--- Asking the engine about a block of ground costs little more than asking it about one
--- chunk of that block, because most of what a query costs is the asking. Measured over
--- every chunk of a Space Age megabase, a quarter of a million of them, one query per chunk
--- came to 11.4us a chunk and four-by-four blocks to 5.5; the six microseconds between them
--- is the call itself. Eight-by-eight saves a little more and swallows four times as much
--- ground in one bite, which makes a worse mouthful for the budget.
---
--- All three return exactly the same inserters. Checked on the whole map: a strip against
--- the chunks in it disagreed on none of a quarter of a million chunks.
local BLOCK = 4

--- How much emptier than the ground in it a surface's rectangle may be before that surface
--- is read chunk by chunk instead.
---
--- Reading by blocks means reading the rectangle around a surface's generated chunks, gaps
--- and all, which is what makes the chunk list unnecessary. A gap is nearly free -- a query
--- over ground that was never generated costs 0.14us a chunk, against 5.5 for ground that
--- is really there -- so a rectangle has to be enormously emptier than the map before the
--- gaps eat the saving. The two come level at about a hundred and six times.
---
--- Thirty-two is well inside that and well outside anything an ordinary map does. On a
--- megabase spanning five planets and fifty-odd platforms the worst rectangle was 1.6 times
--- the ground in it. What it is really for is the shape a long journey leaves behind: a
--- line of chunks a thousand tiles long is a rectangle almost entirely made of gap.
local WASTE_LIMIT = 32

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

--- Where the crawl over a surface's chunk list has got to, which is deliberately not in
--- storage. The iterator is a game object and storage has to survive being written to a
--- file; keeping every chunk position instead was tens of thousands of numbers in every
--- save on a large map. What is stored is how many chunks in the crawl is, which is enough
--- to make the iterator again and wind it forward to the same place.
---
--- Wound forward rather than simply started again, because a save is loaded by a player
--- joining a game everybody else is still playing. Starting afresh would have that player
--- reading different chunks on different ticks from everyone else, and finding an inserter
--- a tick sooner or later than they do is enough to put the game out of step.
---
--- Only a surface being crawled needs any of this. A surface being read by blocks is at a
--- pair of chunk coordinates, which are numbers like any other, so they are simply stored
--- and there is nothing to wind.
local walk

---The surface to read after the one the state names.
---@param state table
---@return LuaSurface? surface
---@return boolean wrapped whether that was the last of them and this is the first again
local function next_surface(state)
  local found, first
  local past = false
  for _, candidate in pairs(game.surfaces) do
    if first == nil then first = candidate end
    if past and found == nil then found = candidate end
    if candidate.index == state.surface then past = true end
  end
  if found then return found, false end
  return first, true
end

---Look at every inserter in an area, however big it is.
---@param surface LuaSurface
---@param area BoundingBox
---@return integer how many were found
local function read_area(surface, area)
  local found = 0
  for _, inserter in pairs(surface.find_entities_filtered{ area = area, type = "inserter" }) do
    found = found + 1
    watch(inserter)
  end
  return found
end

---The ground a block of chunks covers.
---@param bx integer chunk x of its left edge
---@param by integer chunk y of its top edge
---@return BoundingBox
local function block_area(bx, by)
  return {{ bx * 32, by * 32 }, {(bx + BLOCK) * 32, (by + BLOCK) * 32 }}
end

---Whether a surface's rectangle is solid enough to be worth reading whole.
---@param rect { x0: integer, y0: integer, x1: integer, y1: integer, n: integer }
---@return boolean
local function worth_blocks(rect)
  local across = rect.x1 - rect.x0 + 1
  local down = rect.y1 - rect.y0 + 1
  return (across * down) <= (rect.n * WASTE_LIMIT)
end

---Note where a chunk lies, while crawling, so the surface's rectangle can be worked out.
---@param state table
---@param chunk ChunkPositionAndArea
local function survey(state, chunk)
  local seen = state.survey
  if seen == nil then
    seen = { x0 = chunk.x, x1 = chunk.x, y0 = chunk.y, y1 = chunk.y, n = 0 }
    state.survey = seen
  end
  if chunk.x < seen.x0 then seen.x0 = chunk.x end
  if chunk.x > seen.x1 then seen.x1 = chunk.x end
  if chunk.y < seen.y0 then seen.y0 = chunk.y end
  if chunk.y > seen.y1 then seen.y1 = chunk.y end
  seen.n = seen.n + 1
end

---Keep what a finished crawl learnt, so the surface can be read by blocks next time.
---@param state table
local function remember_rectangle(state)
  local seen = state.survey
  state.survey = nil
  -- a surface with no chunks at all has nothing to remember, and will be crawled again,
  -- which costs nothing because there is nothing to crawl
  if seen == nil then return end
  if worth_blocks(seen) then state.rect[state.surface] = seen end
end

---Take up reading a surface from its beginning.
---@param state table
---@param surface LuaSurface
local function begin_surface(state, surface)
  state.surface = surface.index
  state.at = 0
  state.survey = nil
  local rect = state.rect[surface.index]
  state.bx = rect and rect.x0 or nil
  state.by = rect and rect.y0 or nil
  walk = nil
end

---Read a slice of the map, a different slice each tick.
---
---Everything else this mod knows it was told: an inserter built, turned round, taken away.
---Not everything that changes the answer is announced. A script may build an inserter
---without raising anything, and an inserter let go of because it was aimed at rail comes
---back only because the rail going away happens to be an event. A picture assembled purely
---from events drifts, so this reads the map in the background for ever and puts it right.
---
---Two ways of reading it, and which one a surface gets depends on what the first reading of
---it found. The first time, the surface is crawled: its chunks are asked for one at a time,
---and where they lie is noted. After that the surface is read by blocks -- squares of
---ground taken straight from the rectangle those chunks turned out to fill, with no chunk
---list involved at all. Measured on a megabase, crawling a pass cost about 4.2 seconds of
---which the chunk list itself was nearly half; by blocks it is about 1.6.
---
---A surface whose rectangle is mostly gap is left crawling, which is what WASTE_LIMIT
---decides.
local function rescan_slice()
  local state = storage.rescan
  if state == nil then state = { at = 0, passes = 0 } storage.rescan = state end
  if state.rect == nil then state.rect = {} end
  -- quick until the map has been read once, a crawl for ever after
  local budget = (state.passes or 0) > 0 and IDLE_BUDGET or FIRST_PASS_BUDGET

  local surface = state.surface and game.surfaces[state.surface] or nil
  if surface == nil or not surface.valid then
    local next_one = next_surface(state)
    if next_one == nil then return end
    surface = next_one
    begin_surface(state, surface)
  end

  local left = budget
  local wraps = 0
  while left > 0 do
    local rect = state.rect[state.surface]
    local finished

    if rect then
      -- by blocks, straight off the rectangle
      if state.by == nil then state.bx, state.by = rect.x0, rect.y0 end
      finished = state.by > rect.y1
      if not finished then
        -- Charged by the ground covered rather than by the query, so that the budget goes
        -- on meaning chunks looked at whichever way they were looked at. The saving is
        -- taken as time rather than as a faster pass.
        left = left - (BLOCK * BLOCK) - read_area(surface, block_area(state.bx, state.by))
        state.bx = state.bx + BLOCK
        if state.bx > rect.x1 then
          state.bx = rect.x0
          state.by = state.by + BLOCK
        end
      end
    else
      -- crawling, which is also how a surface's rectangle is learnt
      --
      -- Made again whenever the iterator is not the one the state describes: after a load,
      -- or after the surface it was walking went away.
      if walk == nil or walk.surface ~= state.surface or walk.at ~= state.at then
        walk = { surface = state.surface, at = 0, iter = surface.get_chunks() }
        while walk.at < state.at and walk.iter() ~= nil do walk.at = walk.at + 1 end
        -- and if the surface has shrunk since, carry on from wherever that left off
        state.at = walk.at
      end
      local chunk = walk.iter()
      finished = chunk == nil
      if finished then
        remember_rectangle(state)
      else
        walk.at = walk.at + 1
        state.at = walk.at
        survey(state, chunk)
        left = left - 1 - read_area(surface, chunk.area)
      end
    end

    if finished then
      -- that surface is done; on to the next, and round to the first when they run out
      local next_one, wrapped = next_surface(state)
      if next_one == nil then break end
      if wrapped then
        state.passes = (state.passes or 0) + 1
        wraps = wraps + 1
        -- every surface there is holds no chunks at all, so there is nothing to read and
        -- going round again would only find that out twice
        if wraps > 1 then break end
      end
      surface = next_one
      begin_surface(state, surface)
    end
  end
end

---Stop reading a surface by blocks and crawl it again instead.
---@param state RescanState
---@param index uint
local function forget_rectangle(state, index)
  if state.rect == nil or state.rect[index] == nil then return end
  state.rect[index] = nil
  if state.surface == index then
    -- it is the surface being read, so where the blocks had got to means nothing now
    state.bx, state.by = nil, nil
    state.at = 0
    state.survey = nil
    walk = nil
  end
end

---Keep a surface's rectangle covering the ground that is really there.
---
---A rectangle is worked out once, by crawling the surface, and used for ever after, so
---ground generated later has to be taken into it or it would never be read again. Which is
---cheap: a chunk being generated is a rare thing beside a chunk being read, and all this
---does is stretch four numbers.
---@param event EventData.on_chunk_generated
local function onChunkGenerated(event)
  local state = storage.rescan
  if state == nil or state.rect == nil then return end
  local index = event.surface.index
  local rect = state.rect[index]
  if rect == nil then return end
  local at = event.position
  if at.x < rect.x0 then rect.x0 = at.x end
  if at.x > rect.x1 then rect.x1 = at.x end
  if at.y < rect.y0 then rect.y0 = at.y end
  if at.y > rect.y1 then rect.y1 = at.y end
  rect.n = rect.n + 1
  -- A rectangle stretched out of all proportion to the ground inside it is worse than
  -- reading chunk by chunk, and one chunk generated a long way off -- a journey, an
  -- outpost, a script having a look round -- can do that in a single event.
  if not worth_blocks(rect) then forget_rectangle(state, index) end
end

---@param event EventData.on_chunk_deleted
local function onChunkDeleted(event)
  -- Ground going away leaves a rectangle too big and its count of what is in it too high,
  -- and both of those argue for reading ground that is not there any more. Rare enough to
  -- answer by working the surface out again from the beginning.
  local state = storage.rescan
  if state then forget_rectangle(state, event.surface_index) end
end

---@param event EventData.on_surface_cleared|EventData.on_surface_deleted
local function onSurfaceGone(event)
  local state = storage.rescan
  if state then forget_rectangle(state, event.surface_index) end
end

---Forget every inserter and start the reading again from the top.
local function begin_reading()
  storage.droppers = {}
  storage.busy = {}
  storage.due = {}
  storage.pending = {}
  -- The rectangles go with it. They describe the map as it was when each surface was last
  -- crawled, and everything else here is being thrown away precisely because it may not
  -- describe the map any more.
  storage.rescan = { at = 0, passes = 0, rect = {} }
  walk = nil
end

---@param event EventData.on_tick
local function onTick(event)
  if not storage.active then return end
  local tick = event.tick

  -- a slice of the map, read again in the background for ever
  rescan_slice()

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
    -- begun rather than done: on a megabase reading the whole world in one tick is a five
    -- second freeze, and a research finishing is no moment to inflict one
    begin_reading()
  else
    storage.droppers = {}
    storage.busy = {}
    storage.due = {}
    storage.pending = {}
    storage.rescan = nil
    walk = nil
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

---Read the whole world again, now, however long it takes.
---
---What the mod's own remote interface offers, because somebody who asks for it wants it
---done rather than begun; everything the mod does of its own accord goes the slow way. On a
---factory of any size this is a long tick, which is the price of asking for it.
local function refreshData()
  rebuild()
  if not storage.active then return end
  -- Every chunk of every surface at once. On a factory of any size this is a long tick,
  -- which is the price of asking for it rather than letting the background reading come
  -- round; the background reading carries on from the top afterwards either way.
  for _, surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do read_area(surface, chunk.area) end
  end
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

-- What ground each surface covers, which is what lets the reading work in blocks rather
-- than off a chunk list. All three are rare next to a tick.
script.on_event(defines.events.on_chunk_generated, onChunkGenerated)
script.on_event(defines.events.on_chunk_deleted, onChunkDeleted)
script.on_event(defines.events.on_surface_cleared, onSurfaceGone)
script.on_event(defines.events.on_surface_deleted, onSurfaceGone)

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
---@return { active: boolean, passes: integer, watched: integer, busy: integer, pending: integer, blocked: integer, never_in_the_way: string[], never_let_go_of: string[] }
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
  return {
    active = storage.active or false,
    passes = storage.rescan and storage.rescan.passes or 0,
    watched = count(storage.droppers),
    busy = count(storage.busy),
    pending = count(storage.pending),
    -- how many surfaces have been crawled once and are now read by blocks
    blocked = count(storage.rescan and storage.rescan.rect),
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

-- igs-tests is never published, so this can never fire on a player's machine -- which
-- matters, because the fixtures build inserters and leave items lying on the ground.
if script.active_mods["factorio-test"] and script.active_mods["igs-tests"] then
  require("__factorio-test__/init")({
    "test.ft.stacking",
    "test.ft.research",
    "test.ft.limits",
    "test.ft.lifecycle",
    "test.ft.removals",
    "test.ft.rails",
    "test.ft.reading",
    "test.ft.ghosts",
    "test.ft.platforms",
    "test.ft.aquilo",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
