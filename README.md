# PluginUIToasts — A small toast notification utility for Roblox Studio plugins

**PluginUIToasts** is a small, self-contained toast notification utility built specifically for Roblox Studio plugins.

It creates and manages its own UI inside any `GuiObject`, displays short-lived status messages for common plugin actions such as saving, publishing, validation, warnings, errors, imports, and exports, and supports Roblox Studio theme changes out of the box.

## Quick example

```lua
local PluginUIToasts = require(script.Parent.PluginUIToasts)
local toasts = PluginUIToasts.new(parentGuiObject)

toasts:info("Scanning assets...")
toasts:success("Saved successfully.")
toasts:warning("Some items were skipped.")
toasts:danger("Failed to save.")
```

Every call returns a toast handle. To dismiss a notification manually instead of waiting for its timer, call `toast:dismiss()`.

## 🚀 Features

* Fully standalone, dependency-free implementation
* Four built-in notification kinds: `info`, `success`, `warning`, `danger`
* Simple convenience method for each kind, plus a general-purpose `show`
* Automatic timed dismissal, with persistent toasts via `duration = 0`
* Click-to-dismiss on every notification
* Programmatic dismissal and status queries through toast handles
* Configurable maximum visible toast count with automatic oldest-toast eviction
* Roblox Studio Light/Dark theme support with automatic live updates
* Per-color theme overrides
* Configurable toast width, height, position, padding, and ZIndex
* Responsive width inside smaller plugin widgets
* Automatic cleanup of delayed tasks and event connections
* Strict Luau types

## 📖 Basic usage

Place the `PluginUIToasts` ModuleScript somewhere accessible to your plugin code, for example:

```text
Plugin
├── Modules
│   └── PluginUIToasts
└── Main
```

PluginUIToasts creates and animates Roblox UI, so it should be given a `GuiObject` that lives inside your plugin's interface.

### Creating a toast manager

Pass a `GuiObject` to `PluginUIToasts.new` along with an optional configuration table.

```lua
local toasts = PluginUIToasts.new(parentFrame, {
	DefaultDuration = 3,
	MaxVisible = 4,
	ToastWidth = 320,
	Position = "BottomRight",
})
```

By default, notifications remain visible for approximately `2.6` seconds and up to `3` can be visible at once.

### Convenience methods

Instead of calling `show()` directly, use the built-in convenience method for each kind:

```lua
toasts:info("Checking project...")       -- processing states, background status
toasts:success("Project saved.")         -- completed saves, exports, publishes
toasts:warning("Some assets skipped.")   -- partial failures, missing optional data
toasts:danger("Export failed.")          -- failed operations, invalid states
```

Each accepts an optional `duration` override:

```lua
toasts:success("Saved.", 1.5)
```

### Toast handles

Every notification returns a handle that can be queried or dismissed independently.

```lua
local toast = toasts:success("Finished.")

if toast:isActive() then
	print("The notification is still visible.")
end

toast:dismiss()
```

Calling `dismiss()` more than once, or on a toast that has already been removed, is safe.

### Persistent notifications

Passing `0` as the duration creates a notification without an automatic dismissal timer. This is useful for operations whose completion time isn't known ahead of time.

```lua
local toast = toasts:info("Exporting...", 0)

local success, result = pcall(performExport)

toast:dismiss()

if success then
	toasts:success("Export complete.")
else
	toasts:danger("Export failed.")
end
```

Persistent toasts remain visible until manually dismissed, evicted because of `MaxVisible`, or removed when the manager is destroyed.

### Click-to-dismiss

Every notification can also be dismissed by clicking anywhere on the toast. No additional configuration is required.

### Customization

Most visual and behavioral aspects of the toast stack can be configured through the options table passed to `PluginUIToasts.new`:

```lua
local toasts = PluginUIToasts.new(parentFrame, {
	Position = "TopRight",       -- "TopLeft" | "TopRight" | "BottomLeft" | "BottomRight"
	Padding = 20,                -- distance from the parent's edges
	MaxVisible = 5,              -- oldest toast is evicted once the limit is reached
	ToastWidth = 340,            -- acts as a maximum width; shrinks in narrow widgets
	ToastHeight = 60,
	ZIndex = 500,
	UseStudioTheme = true,       -- derive colors from the active Studio theme

	Colors = {
		success = Color3.fromRGB(80, 220, 120), -- only override what you need
	},
})
```

Custom `Colors` values always take priority over Studio theme colors, and remain applied even when the user switches Studio themes.

## ⚙️ API

### Manager

#### `PluginUIToasts.new(parent, options?)`

Creates a new toast manager. `parent` is a `GuiObject` that will contain the automatically created toast container; `options` is an optional configuration table (see the [configuration reference](#complete-configuration-reference) below).

```lua
local toasts = PluginUIToasts.new(widgetFrame)
```

#### `toasts:show(message, kind?, duration?)`

Displays a notification and returns a toast handle. `kind` defaults to `"info"`; `duration` defaults to `DefaultDuration`.

```lua
local toast = toasts:show("Plugin settings saved.", "success", 3)
```

#### `toasts:info(message, duration?)` / `toasts:success(message, duration?)` / `toasts:warning(message, duration?)` / `toasts:danger(message, duration?)`

Convenience wrappers around `show` for each built-in kind.

#### `toasts:dismiss(toast)`

Dismisses a toast belonging to this manager. Usually more convenient to call as `toast:dismiss()`.

#### `toasts:dismissAll()`

Dismisses every currently active notification.

#### `toasts:destroy()`

Destroys the toast manager and all associated resources: removes every notification, cancels pending lifetime tasks, disconnects click and Studio theme listeners, and destroys the toast container. New notifications cannot be created after this.

### Toast handle

#### `toast:dismiss()`

Dismisses the notification. Safe to call more than once.

#### `toast:isActive()`

Returns `true` while the toast is still visible, `false` once it has been dismissed, evicted, or destroyed.

## Complete configuration reference

```lua
local toasts = PluginUIToasts.new(parentFrame, {
	Colors = {
		Background = nil,
		Border = nil,
		Text = nil,

		info = nil,
		success = nil,
		warning = nil,
		danger = nil,
	},

	DefaultDuration = 2.6,
	MaxVisible = 3,

	ToastHeight = 54,
	ToastWidth = 300,

	ZIndex = 200,
	Padding = 12,

	UseStudioTheme = true,
	Position = "BottomRight",
})
```

| Option            | Type       | Default          | Description                                |
| ----------------- | ---------- | ---------------- | ------------------------------------------ |
| `Colors`          | `Colors?`  | Theme/default    | Overrides individual toast colors          |
| `DefaultDuration` | `number`   | `2.6`            | Default toast lifetime, in seconds         |
| `MaxVisible`      | `number`   | `3`              | Maximum active notifications               |
| `ToastHeight`     | `number`   | `54`             | Toast height in pixels                     |
| `ToastWidth`      | `number`   | `300`            | Maximum toast width in pixels              |
| `ZIndex`          | `number`   | `200`            | Base UI ZIndex                             |
| `Padding`         | `number`   | `12`             | Distance from the parent's edges           |
| `UseStudioTheme`  | `boolean`  | `true`           | Uses and monitors the current Studio theme |
| `Position`        | `Position` | `"BottomRight"`  | Corner used for the toast stack            |

## 📝 Notes

* PluginUIToasts is designed for short status messages, not complex interactive notifications — it intentionally has no titles, icons, action buttons, progress bars, notification history, or custom layouts.
* The complete toast surface acts as its own dismissal target.
* A zero-duration toast (`duration = 0`) never dismisses itself automatically.
* `MaxVisible` is a strict limit — the oldest active notification is removed before another is shown.
* Once a toast is gone, `toast:isActive()` returns `false` and further `toast:dismiss()` calls have no effect.
* When Studio theme integration is enabled, currently visible notifications update automatically when the active Studio theme changes.
* PluginUIToasts is intended for client-side plugin UI.

## 🛠️ Installation

Place `PluginUIToasts` (the ModuleScript folder) somewhere accessible to your plugin — for example:

```text
Plugin
├── Modules
│   └── PluginUIToasts
└── Main
```

Then require it from your plugin script:

```lua
local PluginUIToasts = require(script.Parent.Modules.PluginUIToasts)
```

The module does not require any other packages or modules.


made with ❤️ by biotoxin495
