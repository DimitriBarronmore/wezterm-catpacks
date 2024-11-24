--[[
	Catpack parser for wezterm.
	Depends on: RXI's json.lua, being on a UNIX system.
	https://github.com/rxi/json.lua

	Supports Prismlauncher 9.0 catpack features.

	Usage:
	Require this file, and then register an event listener
	for wezterm's "window-resized" event. 
	If you're doing a lot of configuration editing, you could
	also do the same for the "window-config-reloaded" event.

	You can use catpacks.add_kitty(window, config, filepath, index)
	to add a cat image as layer [index] in config.background, or use
	catpacks.add_from_pack(window, config, catpack, index) to automatically
	get the appropriate cat image from the folder [catpack] for the current date.
	If [index] is not provided, the cat layer is placed on top.

	Note that you should have at least one layer already defined if you want
	a background which isn't mostly transparent.

	By binding a key to catpacks.toggle_cats, you can toggle the cats on/off
	and reroll random cat pictures from a catpack using randomized defaults.

	Example:

	wezterm.on('window-resized', function(window, pane)
        catpacks.add_from_pack(window, config, "maxwell_calendar")
	end)

	__________
	MIT License

	Copyright (c) 2024 Dimitri Barronmore

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
	__________
--]]
local catpacks = {}

-- These variables control how much of the window's size at most
-- can be taken up by a cat picture, and the opacity of the cat
-- layer. Reducing the maximum size helps prevent the image from
-- being cut off by the top tabbar, and reducing the opacity can
-- help increase text readability in front of the image.
catpacks.maximum_window_percentage = 0.8
catpacks.kitty_opacity = 0.6

-- Used for easily toggling cats on and off.
catpacks.draw_cat = true

local wezterm = require 'wezterm'
local json = require 'json'

--[[
	This function comes from a stackoverflow answer by islet8.
		Slightly modified to actually work.
	https://stackoverflow.com/a/16077650
	https://creativecommons.org/licenses/by-sa/3.0/
--]]
---@param o table
---@param seen table?
---@return table
local deepcopy
deepcopy = function(o, seen)
	seen = seen or {}
	if o == nil then return nil end
	if seen[o] then return seen[o] end

	local no
	if type(o) == 'table' then
	no = {}
	seen[o] = no

	for k, v in next, o, nil do
		no[deepcopy(k, seen)] = deepcopy(v, seen)
	end
	setmetatable(no, deepcopy(getmetatable(o), seen))
	else -- number, string, boolean, etc
	no = o
	end
	return no
end

local function get_image_dimensions(filepath)
    local f = io.popen("file '" .. filepath .."'")
    local txt = f:read("a")
    f:close()
    local _, _, w, h = txt:find("(%d+) ?x ?(%d+),")
    return tonumber(w), tonumber(h)
end

local function is_directory(path)
	local f = io.popen("file '" .. wezterm.config_dir .. "/" .. path .. "'")
	local txt = f:read("a")
	f:close()
	return (string.find(txt, ("directory"):format(path))) and true or false
end

catpacks.__daily_lock = false
local function handle_default(basedir, path)
	path = path:gsub("%./", "")
	local defaultpath = basedir .. path
	if not is_directory(defaultpath) then
		return defaultpath
	end
	local names = {}
	local f = io.popen("find '" .. wezterm.config_dir .. "/" .. defaultpath .."'")
	for line in f:lines() do
		if line ~= wezterm.config_dir .. "/" .. defaultpath then
			line = line:gsub(wezterm.config_dir .. "/", "")
			table.insert(names, line)
		end
	end
	f:close()
	table.sort(names, function(a, b) return a < b end)
	local t = os.date("*t")
	if string.lower(path) == "random" then
		local name
		if catpacks.__daily_lock then
			if catpacks.__daily_lock[1].yday == t.yday then
				name = catpacks.__daily_lock[2]
				return name
			end
		end
		name = names[math.random(#names)]
		catpacks.__daily_lock = {t, name}
		return name
	else
		return names[t.yday % #names]
	end
end

local function get_catpack(packname)
	local basedir = packname .. "/"
	local jfile, err = io.open(wezterm.config_dir .. "/" .. basedir .. "catpack.json")
	if not jfile then error(err) end
	local jstxt = jfile:read("a")
	jfile:close()
	local info = json.decode(jstxt)
	local ftime = os.date("*t")
	local time = {year = ftime.year, month = ftime.month, day = ftime.day}
	for _, image in ipairs(info.variants or {}) do
		local stime, endtime = image.startTime, image.endTime
		stime.year = time.year
		if endtime.month < stime.month then
			endtime.year = time.year + 1
		else
			endtime.year = time.year
		end
		local d, sd, ed = os.time(time), os.time(stime), os.time(endtime)
		if d >= sd and d <= ed then
			return basedir .. image.path
		end
	end
	return handle_default(basedir, info.default)
end


function catpacks.add_kitty(window, config, kittyname, index)
	local full_fname = wezterm.config_dir .. "/" .. kittyname
	local background = deepcopy(config.background) or {}
	local kitty_layer = {
		source = {File=full_fname},
		vertical_align = "Bottom",
		horizontal_align = "Right",
		repeat_x = "NoRepeat",
		repeat_y = "NoRepeat",
		opacity = catpacks.kitty_opacity,
		__IS_CATPACK = true,
	}
	if not catpacks.draw_cat then
		kitty_layer.opacity = 0
	end
	table.insert(background, index or #background + 1, kitty_layer)

	local sizes = window:get_dimensions()
	local kitty_w, kitty_h = get_image_dimensions(full_fname)
	kitty_layer.height = math.min(sizes.pixel_height * catpacks.maximum_window_percentage, kitty_h)
	local ratio = kitty_layer.height / kitty_h
	kitty_layer.width = kitty_w * ratio
	-- wezterm.log_info("adding kitty layer", kitty_layer)

	local overrides = window:get_config_overrides() or {}
	overrides.background = background
    window:set_config_overrides(overrides)
end

function catpacks.add_from_pack(window, config, packname, index)
	local catimage = get_catpack(packname)
	catpacks.add_kitty(window, config, catimage, index)
end

catpacks.toggle_cats = wezterm.action_callback(function(win, pane)
	wezterm.log_info "Toggling Catpacks"
	catpacks.draw_cat = not catpacks.draw_cat
	catpacks.__daily_lock = false
	local overrides = win:get_config_overrides()
	if overrides then
		for _, layer in ipairs(overrides.background) do
			if layer.__IS_CATPACK then
				layer.opacity = (catpacks.draw_cat and catpacks.kitty_opacity) or 0
			end
		end
		win:set_config_overrides(overrides)
	end
end)

return catpacks