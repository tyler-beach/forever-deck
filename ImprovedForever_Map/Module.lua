-- Improved Forever: Map. The peek map: the game's map shown while a press
-- is held (PeekMap.lua), placed and sized in its tab (PeekMapEditor.lua).
-- RestedXP path lines: RXPPath.lua (soft-dep RXPGuides).
local IF = ImprovedForever

IF.AddModule({ key = "map", label = "Map", icon = IF.TEX .. "ic_mod_map", addon = ... })

-- /if peek: the peek map's hotkey binding; prints each press
IF.AddCommand("peek", function() IF.PeekMap.Probe() end, ": the peek map's binding, each press")

-- /if path: RestedXP world-map path lines
IF.AddCommand("path", function(args)
	IF.RXPPath.Command(args[1], args[2])
end, "[on|off|debug|force|status]: RestedXP gold path on the world map")

