--[[
DESC:
	A helper module for ClientData. Adds methods and their descriptions to proxies.
	Currently, you have to add the methods or functions here manually for them to appear in a proxy's autocomplete.
	If you find a better way to add descriptions to functions via types, tell me on discord PLEASE :sob:
- Nano_Boo
]]

--- / Other types /
local ItemTypes = require(game:GetService("ReplicatedStorage").Modules.Shared.Types.ItemTypes)
local DataTemplates: typeof(require(game:GetService("ServerStorage").Modules.Data.DataTemplates))

type Slot = typeof(DataTemplates.SLOT_TEMPLATE)
type Settings = typeof(DataTemplates.PROFILE_TEMPLATE.Settings)
type ClientData = {Slot: Slot, Settings: Settings}

--- / Method holders / (necessary to make types with methods via typeof())
local generic = {}
local pathed = {}

--[[
Returns a copy of the original data table of the current path.

Works in ANY path, even if this method doesn't show up and even if the --!strict type checker throws "Key 'GetRaw' not found in table ...".
Mainly meant for debugging.
]]
function generic:GetRaw():{any} end

--[[
Returns a BindableEvent that fires every time the current path's value is changed. Additionally, if this value is a table, this event will also fire when any nested value is changed.
The optional {LastKey} parameter is used to get the bindable for a final table key, as trying to do so without it will error because you tried indexing a non table.
The event returns the new value set to the currenet path (any value), and the full path of the changed value (string).
Events fired because a sub-event was fired do not return a new value.

Works in ANY path, even if this function doesn't show up and even if the --!strict type checker throws "Key 'Changed' not found in table ...".
]]
function generic.Changed(LastKey: string?):BindableEvent end

--[[
Yields the current thread until SlotData becomes available and returns said data.
]]
function pathed:WaitForSlot():Slot end


--- / Types /
export type Generic = typeof(generic)

type Pathed =
	{WaitForSlot: typeof(pathed.WaitForSlot)}


export type All = Generic & Pathed


--- / Module return /
return nil
