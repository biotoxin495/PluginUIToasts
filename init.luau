--!strict

--  ____  _             _
-- |  _ \| |_   _  __ _(_)_ __
-- | |_) | | | | |/ _` | | '_ \
-- |  __/| | |_| | (_| | | | | |
-- |_|   |_|\__,_|\__, |_|_| |_|
--  _   _ ___ ____|___/           _
-- | | | |_ _|_   _|__   __ _ ___| |_ ___
-- | | | || |  | |/ _ \ / _` / __| __/ __|
-- | |_| || |  | | (_) | (_| \__ \ |_\__ \
--  \___/|___| |_|\___/ \__,_|___/\__|___/

-- made with ❤️ by biotoxin495

-- A small, self-contained toast notification utility for Roblox Studio plugins.
-- Each toast manager creates and owns a stack of notifications inside a given
-- GuiObject, and every notification returns a handle that can be dismissed or
-- queried independently of the manager.
--
-- Usage:
--   local PluginUIToasts = require(path.to.PluginUIToasts)
--   local toasts = PluginUIToasts.new(parentGuiObject, options)
--
--   toasts:show(message, kind, duration)   -- create a notification of the given kind
--   toasts:info(message, duration)         -- convenience: kind = "info"
--   toasts:success(message, duration)      -- convenience: kind = "success"
--   toasts:warning(message, duration)      -- convenience: kind = "warning"
--   toasts:danger(message, duration)       -- convenience: kind = "danger"
--
--   toast:dismiss()                        -- dismiss a single notification
--   toast:isActive()                       -- true until dismissed, evicted, or destroyed
--
--   toasts:dismiss(toast)                  -- dismiss a toast belonging to this manager
--   toasts:dismissAll()                    -- dismiss every active notification
--   toasts:destroy()                       -- destroy the manager and all its toasts
--
-- Kinds:
--   "info", "success", "warning", "danger"
--
-- Configuration (all optional, see the Options type for defaults):
--   Appearance: Colors, ToastWidth, ToastHeight, ZIndex
--   Layout:     Position, Padding
--   Timing:     DefaultDuration (duration = 0 creates a persistent toast)
--   Behavior:   MaxVisible, UseStudioTheme
--
-- Notifications can also be dismissed by clicking anywhere on the toast.

local TweenService = game:GetService("TweenService")

local StudioSettings = settings().Studio

local DEFAULT_COLORS = {
	Background = Color3.fromRGB(35, 37, 44),
	Border = Color3.fromRGB(56, 60, 70),
	Text = Color3.fromRGB(241, 245, 249),

	info = Color3.fromRGB(59, 130, 246),
	success = Color3.fromRGB(34, 197, 94),
	warning = Color3.fromRGB(245, 158, 11),
	danger = Color3.fromRGB(239, 68, 68),
}

local DEFAULT_DURATION = 2.6
local DEFAULT_MAX_VISIBLE = 3
local DEFAULT_TOAST_HEIGHT = 54
local DEFAULT_TOAST_WIDTH = 300
local DEFAULT_PADDING = 12
local DEFAULT_POSITION = "BottomRight"

local TOAST_SPACING = 8

local FADE_IN_TIME = 0.22
local FADE_OUT_TIME = 0.18

export type Kind = "info" | "success" | "warning" | "danger"

export type Position = "TopLeft" | "TopRight" | "BottomLeft" | "BottomRight"

export type Colors = {
	Background: Color3?,
	Border: Color3?,
	Text: Color3?,

	info: Color3?,
	success: Color3?,
	warning: Color3?,
	danger: Color3?,
}

export type Options = {
	Colors: Colors?,

	DefaultDuration: number?,
	MaxVisible: number?,

	ToastHeight: number?,
	ToastWidth: number?,

	ZIndex: number?,
	Padding: number?,

	UseStudioTheme: boolean?,
	Position: Position?,
}

export type Toast = {
	dismiss: (self: Toast) -> (),
	isActive: (self: Toast) -> boolean,
}

type ToastRecord = {
	root: CanvasGroup,
	message: TextLabel,
	accent: Frame,
	border: UIStroke,

	clickConnection: RBXScriptConnection,

	serial: number,
	kind: Kind,

	active: boolean,
	removed: boolean,

	handle: any?,

	lifetimeThread: thread?,

	dismissTween: Tween?,
	dismissConnection: RBXScriptConnection?,
}

local VALID_KINDS: { [string]: boolean } = {
	info = true,
	success = true,
	warning = true,
	danger = true,
}

local VALID_POSITIONS: { [string]: boolean } = {
	TopLeft = true,
	TopRight = true,
	BottomLeft = true,
	BottomRight = true,
}

local ToastHandle = {}
ToastHandle.__index = ToastHandle

function ToastHandle:dismiss()
	local owner = (self :: any)._owner

	if owner then
		owner:dismiss(self)
	end
end

function ToastHandle:isActive(): boolean
	local owner = (self :: any)._owner
	local record = (self :: any)._record

	return owner ~= nil and record ~= nil and record.active == true and record.removed == false
end

local PluginUIToasts = {}
PluginUIToasts.__index = PluginUIToasts

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function resolveColors(overrides: Colors?, useStudioTheme: boolean): { [string]: Color3 }
	local colors = table.clone(DEFAULT_COLORS)

	if useStudioTheme then
		local theme = StudioSettings.Theme

		colors.Background = theme:GetColor(Enum.StudioStyleGuideColor.Notification)

		colors.Border = theme:GetColor(Enum.StudioStyleGuideColor.Border)

		colors.Text = theme:GetColor(Enum.StudioStyleGuideColor.MainText)

		colors.info = theme:GetColor(Enum.StudioStyleGuideColor.InfoText)

		colors.warning = theme:GetColor(Enum.StudioStyleGuideColor.WarningText)

		colors.danger = theme:GetColor(Enum.StudioStyleGuideColor.ErrorText)
	end

	if overrides then
		for key, value in pairs(overrides) do
			if value then
				colors[key] = value
			end
		end
	end

	return colors
end

local function configurePlacement(container: Frame, layout: UIListLayout, position: Position, padding: number)
	container.Size = UDim2.new(1, -padding * 2, 1, -padding * 2)

	if position == "TopLeft" then
		container.AnchorPoint = Vector2.new(0, 0)
		container.Position = UDim2.new(0, padding, 0, padding)

		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
	elseif position == "TopRight" then
		container.AnchorPoint = Vector2.new(1, 0)
		container.Position = UDim2.new(1, -padding, 0, padding)

		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
	elseif position == "BottomLeft" then
		container.AnchorPoint = Vector2.new(0, 1)
		container.Position = UDim2.new(0, padding, 1, -padding)

		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	else
		container.AnchorPoint = Vector2.new(1, 1)
		container.Position = UDim2.new(1, -padding, 1, -padding)

		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
end

local function getLayoutOrder(position: Position, serial: number): number
	if position == "TopLeft" or position == "TopRight" then
		return -serial
	end

	return serial
end

function PluginUIToasts.new(parent: GuiObject, options: Options?)
	assert(parent and parent:IsA("GuiObject"), "PluginUIToasts.new expects a GuiObject parent")

	local resolvedOptions: Options = options or {}

	local useStudioTheme = resolvedOptions.UseStudioTheme

	if useStudioTheme == nil then
		useStudioTheme = true
	end

	local position = resolvedOptions.Position or DEFAULT_POSITION

	assert(VALID_POSITIONS[position], "PluginUIToasts.new received an invalid Position")

	local self = setmetatable({}, PluginUIToasts)

	self._colorOverrides = resolvedOptions.Colors
	self._useStudioTheme = useStudioTheme

	self._colors = resolveColors(self._colorOverrides, self._useStudioTheme)

	self._defaultDuration = math.max(0, resolvedOptions.DefaultDuration or DEFAULT_DURATION)

	self._maxVisible = math.max(1, math.floor(resolvedOptions.MaxVisible or DEFAULT_MAX_VISIBLE))

	self._toastHeight = math.max(1, resolvedOptions.ToastHeight or DEFAULT_TOAST_HEIGHT)

	self._toastWidth = math.max(1, resolvedOptions.ToastWidth or DEFAULT_TOAST_WIDTH)

	self._padding = math.max(0, resolvedOptions.Padding or DEFAULT_PADDING)

	self._zIndex = resolvedOptions.ZIndex or 200
	self._position = position :: Position

	self._serial = 0
	self._records = {} :: { ToastRecord }

	self._destroyed = false
	self._themeConnection = nil :: RBXScriptConnection?

	local container = Instance.new("Frame")

	container.Name = "PluginUIToasts"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ZIndex = self._zIndex
	container.Parent = parent

	self._container = container

	local layout = Instance.new("UIListLayout")

	layout.Name = "Layout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, TOAST_SPACING)
	layout.Parent = container

	self._layout = layout

	configurePlacement(container, layout, self._position, self._padding)

	if self._useStudioTheme then
		self._themeConnection = StudioSettings.ThemeChanged:Connect(function()
			if not self._destroyed then
				self:_refreshColors()
			end
		end)
	end

	return self
end

function PluginUIToasts:_applyColorsToRecord(record: ToastRecord)
	record.root.BackgroundColor3 = self._colors.Background
	record.border.Color = self._colors.Border
	record.message.TextColor3 = self._colors.Text

	record.accent.BackgroundColor3 = self._colors[record.kind] or self._colors.info
end

function PluginUIToasts:_refreshColors()
	self._colors = resolveColors(self._colorOverrides, self._useStudioTheme)

	for _, record in ipairs(self._records) do
		if not record.removed then
			self:_applyColorsToRecord(record)
		end
	end
end

function PluginUIToasts:_cancelLifetime(record: ToastRecord)
	local lifetimeThread = record.lifetimeThread

	if lifetimeThread then
		record.lifetimeThread = nil
		task.cancel(lifetimeThread)
	end
end

function PluginUIToasts:_removeRecord(record: ToastRecord)
	if record.removed then
		return
	end

	record.removed = true
	record.active = false

	self:_cancelLifetime(record)

	if record.dismissConnection then
		record.dismissConnection:Disconnect()
		record.dismissConnection = nil
	end

	if record.dismissTween then
		record.dismissTween:Cancel()
		record.dismissTween = nil
	end

	local index = table.find(self._records, record)

	if index then
		table.remove(self._records, index)
	end

	local handle = record.handle

	if handle then
		(handle :: any)._owner = nil
		(handle :: any)._record = nil

		record.handle = nil
	end

	if record.clickConnection.Connected then
		record.clickConnection:Disconnect()
	end

	record.root:Destroy()
end

function PluginUIToasts:_dismissRecord(record: ToastRecord, animate: boolean?)
	if record.removed then
		return
	end

	if not record.active then
		if animate == false then
			self:_removeRecord(record)
		end

		return
	end

	record.active = false

	self:_cancelLifetime(record)

	if animate == false then
		self:_removeRecord(record)
		return
	end

	local tween =
		TweenService:Create(record.root, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})

	record.dismissTween = tween

	record.dismissConnection = tween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		record.dismissTween = nil

		if record.dismissConnection then
			record.dismissConnection:Disconnect()
			record.dismissConnection = nil
		end

		if not record.removed then
			self:_removeRecord(record)
		end
	end)

	tween:Play()
end

function PluginUIToasts:_createRecord(message: string, kind: Kind): (ToastRecord, Toast)
	self._serial += 1

	local root = Instance.new("CanvasGroup")

	root.Name = "Toast"
	root.BackgroundColor3 = self._colors.Background
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.GroupTransparency = 1

	root.LayoutOrder = getLayoutOrder(self._position, self._serial)

	root.Size = UDim2.new(1, 0, 0, self._toastHeight)

	root.ZIndex = self._zIndex + 1

	addCorner(root, 6)

	local sizeConstraint = Instance.new("UISizeConstraint")

	sizeConstraint.MaxSize = Vector2.new(self._toastWidth, self._toastHeight)

	sizeConstraint.Parent = root

	local stroke = Instance.new("UIStroke")

	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = self._colors.Border
	stroke.Parent = root

	local accent = Instance.new("Frame")

	accent.Name = "Accent"
	accent.BackgroundColor3 = self._colors[kind] or self._colors.info

	accent.BorderSizePixel = 0

	accent.Size = UDim2.new(0, 6, 1, 0)

	accent.ZIndex = self._zIndex + 2
	accent.Parent = root

	local label = Instance.new("TextLabel")

	label.Name = "Message"

	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0

	label.Font = Enum.Font.Gotham

	label.Position = UDim2.new(0, 18, 0, 0)

	label.Size = UDim2.new(1, -30, 1, 0)

	label.Text = message
	label.TextColor3 = self._colors.Text
	label.TextSize = 12
	label.TextWrapped = true

	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	label.ZIndex = self._zIndex + 2
	label.Parent = root

	local clickTarget = Instance.new("TextButton")

	clickTarget.Name = "Dismiss"

	clickTarget.AutoButtonColor = false
	clickTarget.BackgroundTransparency = 1
	clickTarget.BorderSizePixel = 0

	clickTarget.Size = UDim2.fromScale(1, 1)

	clickTarget.Text = ""

	clickTarget.ZIndex = self._zIndex + 3
	clickTarget.Parent = root

	local record = {
		root = root,
		message = label,
		accent = accent,
		border = stroke,

		clickConnection = nil,

		serial = self._serial,
		kind = kind,

		active = true,
		removed = false,

		handle = nil,

		lifetimeThread = nil,

		dismissTween = nil,
		dismissConnection = nil,
	} :: any

	local handle = setmetatable({
		_owner = self,
		_record = record,
	}, ToastHandle)

	record.handle = handle

	record.clickConnection = clickTarget.Activated:Connect(function()
		self:_dismissRecord(record, true)
	end)

	root.Parent = self._container

	table.insert(self._records, record)

	return record, handle
end

function PluginUIToasts:_getActiveCount(): number
	local count = 0

	for _, record in ipairs(self._records) do
		if record.active and not record.removed then
			count += 1
		end
	end

	return count
end

function PluginUIToasts:_evictOldest()
	for _, record in ipairs(self._records) do
		if record.active and not record.removed then
			-- Capacity eviction is immediate so MaxVisible
			-- remains a strict visual limit.
			self:_dismissRecord(record, false)
			return
		end
	end
end

function PluginUIToasts:show(message: string, kind: Kind?, duration: number?): Toast
	assert(not self._destroyed, "Cannot show a toast after PluginUIToasts:destroy()")

	assert(type(message) == "string", "PluginUIToasts:show expects a string message")

	local rawKind = kind or "info"

	assert(VALID_KINDS[rawKind], "PluginUIToasts:show received an invalid toast kind")

	if duration ~= nil then
		assert(type(duration) == "number", "PluginUIToasts:show expects duration to be a number or nil")
	end

	while self:_getActiveCount() >= self._maxVisible do
		self:_evictOldest()
	end

	local resolvedKind = rawKind :: Kind

	local record, handle = self:_createRecord(message, resolvedKind)

	local fadeInTween = TweenService:Create(
		record.root,
		TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{
			GroupTransparency = 0,
		}
	)

	fadeInTween:Play()

	local lifetime = if duration == nil then self._defaultDuration else math.max(0, duration)

	-- Zero-duration toasts remain visible until manually dismissed.
	if lifetime > 0 then
		record.lifetimeThread = task.delay(lifetime, function()
			record.lifetimeThread = nil

			if self._destroyed then
				return
			end

			if record.active and not record.removed then
				self:_dismissRecord(record, true)
			end
		end)
	end

	return handle
end

function PluginUIToasts:info(message: string, duration: number?): Toast
	return self:show(message, "info", duration)
end

function PluginUIToasts:success(message: string, duration: number?): Toast
	return self:show(message, "success", duration)
end

function PluginUIToasts:warning(message: string, duration: number?): Toast
	return self:show(message, "warning", duration)
end

function PluginUIToasts:danger(message: string, duration: number?): Toast
	return self:show(message, "danger", duration)
end

function PluginUIToasts:dismiss(handle: Toast)
	if type(handle) ~= "table" then
		return
	end

	local rawHandle = handle :: any

	if rawHandle._owner ~= self then
		return
	end

	local record = rawHandle._record

	if record then
		self:_dismissRecord(record, true)
	end
end

function PluginUIToasts:dismissAll()
	local records = table.clone(self._records)

	for _, record in ipairs(records) do
		if record.active then
			self:_dismissRecord(record, true)
		end
	end
end

function PluginUIToasts:destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true

	if self._themeConnection then
		self._themeConnection:Disconnect()
		self._themeConnection = nil
	end

	local records = table.clone(self._records)

	for _, record in ipairs(records) do
		self:_dismissRecord(record, false)
	end

	self._container:Destroy()
end

return PluginUIToasts
