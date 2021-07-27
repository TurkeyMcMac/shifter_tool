--[[
   Copyright (C) 2021  Jude Melton-Houghton

   This file contains the code for shifter_tool.

   shifter_tool is free software: you can redistribute it and/or modify
   it under the terms of the GNU Lesser General Public License as published
   by the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   shifter_tool is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with shifter_tool. If not, see <https://www.gnu.org/licenses/>.
]]

local S = minetest.get_translator("shifter_tool")

-- The wear added to the shifter per shift. When the wear gets past 65535, the
-- tool breaks.
local WEAR_PER_USE = 328 -- 200 uses.

-- Tries to tell whether an ObjectRef represents a real connected player.
local function object_is_player(object)
	if not object then return false end
	if not minetest.is_player(object) then return false end
	-- Pipeworks uses this:
	if object.is_fake_player then return false end
	-- Check if the positions match:
	local player = minetest.get_player_by_name(object:get_player_name())
	if not player then return false end
	local object_pos = object:get_pos()
	local player_pos = player:get_pos()
	if not object_pos or not player_pos then return false end
	return vector.equals(object_pos, player_pos)
end

-- Tries to shift the node at the position in the direction for the user. The
-- direction should be one unit long and parallel to an axis. The user will be
-- messaged if the shift didn't occur. The return value is whether it did.
local function shift_node(pos, move_dir, user)
	local name = user and user:get_player_name() or ""
	-- Whether or not the user is a real player:
	local is_player = object_is_player(user)
	if vector.length(move_dir) ~= 1 then
		-- A direction could not be determined due to where they are.
		if is_player then
			minetest.chat_send_player(name,
				S("You cannot shift the node due to your " ..
				"current position/orientation."))
		end
		return false
	end
	-- The name changed to conform to the conventions of mvps_push:
	local shifter_name = is_player and name or "$unknown"
	-- MineClone requires this position that is where the piston would be:
	local piston_pos = nil
	-- Detect Mineclone using the presence of mcl_get_neighbors:
	if mesecon.mcl_get_neighbors then
		piston_pos = vector.subtract(pos, move_dir)
	end
	-- Try to push the node:
	local shifted, stack, oldstack =
		mesecon.mvps_push(pos, move_dir, 1, shifter_name, piston_pos)
	-- Check that the shift actually happened:
	shifted = shifted and minetest.get_node(pos).name == "air"
	if shifted then
		mesecon.mvps_move_objects(pos, move_dir, oldstack)
	elseif is_player then
		-- On failure, stack here may represent the reason for failure:
		if stack == "protected" then
			minetest.chat_send_player(name,
				S("Nodes cannot be shifted to/from " ..
				"protected positions."))
		else
			minetest.chat_send_player(name,
				S("The node could not be shifted."))
		end
	end
	return shifted
end

-- Do the interaction. If reverse is true, the action pulling (otherwise it's
-- pushing.)
local function interact(tool, user, pointed_thing, reverse)
	if pointed_thing.type == "node" then
		local name = user and user:get_player_name() or ""
		local use_pos = pointed_thing.under
		local move_dir = vector.subtract(use_pos, pointed_thing.above)
		if reverse then move_dir = vector.multiply(move_dir, -1) end
		if shift_node(use_pos, move_dir, user) then
			local sound = reverse and "shifter_tool_pull" or
				"shifter_tool_push"
			minetest.sound_play(sound, {
				pos = use_pos,
				gain = 0.2,
			}, true)
			if not minetest.is_creative_enabled(name) then
				tool:add_wear(WEAR_PER_USE)
			end
		end
	end
	return tool
end

minetest.register_tool("shifter_tool:shifter", {
	description = S("Shifter"),
	inventory_image = "shifter_tool_shifter.png",
	_mcl_toollike_wield = true,
	node_dig_prediction = "",
	on_place = function(tool, user, pointed_thing)
		return interact(tool, user, pointed_thing, true)
	end,
	on_use = function(tool, user, pointed_thing)
		return interact(tool, user, pointed_thing, false)
	end,
	after_use = function() return nil end, -- Do nothing.
})

if minetest.registered_nodes["mesecons_pistons:piston_sticky_off"] then
	minetest.register_craft({
		output = "shifter_tool:shifter",
		recipe = {
			{"mesecons_pistons:piston_sticky_off", ""           },
			{"mesecons_pistons:piston_sticky_off", "group:stick"},
			{""                                  , "group:stick"},
		},
	})
end
