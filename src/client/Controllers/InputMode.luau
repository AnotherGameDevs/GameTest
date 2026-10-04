-- Single owner of "who has the cursor". Every menu goes through here; nothing else sets cursor state, so menus
-- cannot fight each other.
--   Mining mode      : cursor locked, mouse-look and mining active.
--   Free-cursor mode : toggled with Alt. Cursor free, no mouse-look, no mining. Shortcuts still work.
--   Menu open        : the shop or the pause/settings menu (or Roblox's own Escape menu). Cursor free, no mouse-look,
--                      no mining, and gameplay shortcuts are disabled.
-- Closing a menu returns to whichever of mining / free-cursor was active before it, because free-cursor is tracked
-- separately from menus. Listeners (the dig controller) use OnChanged to drop held input; mining only resumes
-- on a fresh press.
local GuiService = game:GetService("GuiService")

local InputMode = {}

local menus: { [string]: boolean } = {}
local freeCursor = false
local listeners: { () -> () } = {}

local function notify()
	for _, cb in ipairs(listeners) do
		task.spawn(cb)
	end
end

function InputMode.OnChanged(cb: () -> ())
	table.insert(listeners, cb)
end

function InputMode.OpenMenu(name: string)
	if not menus[name] then
		menus[name] = true
		notify()
	end
end

function InputMode.CloseMenu(name: string)
	if menus[name] then
		menus[name] = nil
		notify()
	end
end

function InputMode.IsMenuOpen(): boolean
	if GuiService.MenuIsOpen then
		return true -- Roblox's own Escape menu is never overridden
	end
	return next(menus) ~= nil
end

function InputMode.IsFreeCursor(): boolean
	return freeCursor
end

function InputMode.SetFreeCursor(free: boolean)
	if freeCursor ~= free then
		freeCursor = free
		notify()
	end
end

-- True whenever the cursor must be free and the world must not react (menu OR toggled free-cursor).
function InputMode.IsCursorFree(): boolean
	return freeCursor or InputMode.IsMenuOpen()
end

function InputMode.Init()
	GuiService.MenuOpened:Connect(notify)
	GuiService.MenuClosed:Connect(notify)
end

return InputMode
