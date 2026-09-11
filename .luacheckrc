-- Factorio's runtime is a set of globals the game puts in place before a control script
-- runs, and its data stage another. Naming them here is what makes the one warning worth
-- having stand out: a local function used before it was defined reads as an undefined
-- global, which luac cannot see and which only fails when that line is finally reached.
std = "lua52"
-- game and settings are written to as well as read: a test changes a mod setting or a
-- force bonus, which is a write through a table the game hands out.
globals = { "storage", "data", "game", "settings" }
read_globals = {
  "script", "defines", "helpers", "remote", "prototypes", "rendering",
  "commands", "table_size", "serpent", "log", "localised_print",
  -- factorio-test puts these in place for a test file
  "describe", "it", "before_each", "after_each", "before_all", "after_all", "assert",
  "after_ticks", "async", "done", "on_tick", "test",
}
max_line_length = false
