--!strict
-- module is called ClientData in-studio
-- module is a proxy based data receiver for clients

--[[
DESC:
	Simple proxy module for client data, used to access said data without having
to use remotes to fetch it. Gets updated every time changes are made to the server
sided data.
	Unlike the other server sided proxy modules (SlotManager / PlayerDataManager),
it automatically returns the proxy when the module is required, so you don't have
to use any .Get().
	Client data is defined as: the player's settings data, and their current slot data.
]]

--- / Services /
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService") --for type casting in studio

--- / Types / fun fact: anything inside a type cast wont run at runtime! these lines below wont error in the client.
local DataTemplates: typeof(require(ServerScriptService.PlayerDataTracking.ProfileDataLoader.DataTemplates))

type Slot = typeof(DataTemplates.SLOT_TEMPLATE)
type Settings = typeof(DataTemplates.PROFILE_TEMPLATE.Settings)
type ClientData = {Slot: Slot, Settings: Settings}

--compressed MethodDescriptions
local MethodHolder = {}
--[[Returns a copy of the original data table of the current path.

Works in ANY path, even if this method doesn't show up and even if the --!strict type checker throws "Key 'GetRaw' not found in table ...".
Mainly meant for debugging. ]]
function MethodHolder:GetRaw():{any} local a={}::{any} return a end
type GetRaw = {GetRaw: typeof(MethodHolder.GetRaw)}
--[[Returns a BindableEvent that fires every time the current path's value is changed. Additionally, if this value is a table, this event will also fire when any nested value is changed.
The optional {LastKey} parameter is used to get the bindable for a final table key, as trying to do so without it will error because you tried indexing a non table.
The event returns the new value set to the currenet path.
Events fired because a sub-event was fired do not return any value.

Works in ANY path except final keys, even if this function doesn't show up and even if the --!strict type checker throws "Key 'Changed' not found in table ...". ]]
function MethodHolder.ChangedEvent(LastKey: string?): BindableEvent return Instance.new("BindableEvent") end
type Changed = {Changed: typeof(MethodHolder.ChangedEvent)}
--Yields the current thread until the bindable fires and returns the Slot data.
function MethodHolder:WaitForSlot():Slot local a={}::Slot return a end
type WaitForSlot = {WaitForSlot: typeof(MethodHolder.WaitForSlot)}

type SlotProxy = Slot & Changed & GetRaw
type SettingsProxy = Settings & Changed & GetRaw
type ClientProxy = {Slot: SlotProxy, Settings: SettingsProxy} & Changed & WaitForSlot & GetRaw

type ProxyTable = {_path: {string}} --real proxy table type used in this module

MethodHolder = nil --delete after making types; dont use up memory

--- / Variable setup /
local Player = game.Players.LocalPlayer
assert(Player, "Script isn't running locally!")
local UpdateClientData = ReplicatedStorage.Remotes.UpdateClientData
local RequestClientData = ReplicatedStorage.Remotes.RequestClientData
local ClientData: ClientData --real stored data
local ClientProxy: ClientProxy --returned proxy
local ChangedEvents: {[string]: BindableEvent} = {}
local PooledSubproxies: {[string]: ProxyTable} = {} --for pooling Slot and Settings

--- / Settings /
local MAX_SUBPROXY_DEPTH = 3 --how deep a proxy can be nested in other proxies for it to still be pooled (too much pooling would fill up the memory, and too little could cause performance issues)


--- / Safe initialization / (lets module return without Slot data)
ClientData = RequestClientData:InvokeServer() :: ClientData

local IsSlotDataReady = false
task.spawn(function()
	while not ClientData.Slot do
		ClientData.Slot = (RequestClientData:InvokeServer()).Slot
		task.wait(1)
	end
	IsSlotDataReady = true
end)

--- / Local functions /
local function FireChangedSignals(path:{string}, value:any?): ()
	for i = #path, 0, -1 do
		local currentPath = table.concat(path, ".", 1, i)

		if ChangedEvents[currentPath] then
			ChangedEvents[currentPath]:Fire(value)
		end
	end
end

local function UpdateData(newData: {[string]: any}, path: {string}?)	
	path = path or {}
	local oldData = ClientData :: {[string]: any} --type checker suppression
	
	--go to the current paths
	local newDataField = newData
	local oldDataField = oldData
	for _,key in ipairs(path) do
		newDataField = newDataField[key]
		oldDataField = oldDataField[key]
	end
	
	--compare newData keys to oldData keys;
	--->add keys that werent there
	--->recurse if its a table (and if it did exist)
	--->update keys that are different
	for k,v in newDataField do
		if oldDataField[k] == nil then --key is missing; adding it
			local newPath = table.clone(path)
			table.insert(newPath, k)
			oldDataField[k] = v
			FireChangedSignals(newPath, v)

		elseif type(oldDataField[k]) == "table" and type(v) == "table" then --both tables; recurse
			local newPath = table.clone(path)
			table.insert(newPath, k)
			UpdateData(newData, newPath)
		
		elseif oldDataField[k] ~= v then --value is different; update
			oldDataField[k] = v
			local newPath = table.clone(path)
			table.insert(newPath, k)
			FireChangedSignals(newPath, v)

		end
	end
	
	--compare oldData keys to newData;
	--->delete oldData keys that arent in newData
	for k,v in oldDataField do
		if newDataField[k] == nil then
			oldDataField[k] = nil
			local newPath = table.clone(path)
			table.insert(newPath, k)
			FireChangedSignals(newPath, nil)
		end
	end
end

--- / Periodic sync /
task.spawn(function()
	while task.wait(60) do
		local newData = RequestClientData:InvokeServer() :: ClientData
		UpdateData(newData :: {[string]: any}) --type checker suppression
	end
end)


--- / Update listener /
UpdateClientData.OnClientEvent:Connect(function(path: string, value: any)
	local field = ClientData :: {[string]: {any}} --type checker silencer
	local pathTable = string.split(path,".")
	
	for i = 1, #pathTable - 1 do
		field = field[pathTable[i]]
		if not field then break end
	end
	
	if not field then warn("[ClientData] Received a client data update for an unknown path: "..path) return end
	
	--update that field
	field = value
	
	--fire any active .Changed() events 
	FireChangedSignals(string.split(path,"."), value)
end)


--- / Utility /
local function DeepCopy<T>(Table: T): T
	local Result = {}
	for Key, Value in Table :: {[any]: any} do Result[Key] = typeof(Value) == "table" and DeepCopy(Value) or Value end
	return Result
end

--Forward-declaring functions that will be referenced by metamethods
local CreateProxy

--- / Proxy Methods / (unfortunately all method desc. must be manually added through the SlotProxyMethodDescriptions module.)
local ProxyMethods = { --methods that can be used in any path
	GetRaw = function(self: ProxyTable): any
		local targetData = ClientData :: {[string]: {any}} --type checker silencer
		for _, key in ipairs(self._path) do
			targetData = targetData[key]
		end
		return DeepCopy(targetData)
	end,

	Changed = function(self: ProxyTable, LastKey: string?): BindableEvent
		local p = table.concat(self._path,".")
		if type(LastKey) == "string" then
			p ..= "."..LastKey
		end
		--make new table if it doesnt exist yet
		ChangedEvents[p] = ChangedEvents[p] or Instance.new("BindableEvent")
		return ChangedEvents[p]
	end,
}

--- / Shared metatable and metamethods /
local proxy_mt = {}

proxy_mt.__index = function(self:ProxyTable, key:string): any
	local path = self._path
	local data = ClientData
	
	--yield until slot data is ready
	if not IsSlotDataReady and key == "Slot" then
		error("[ClientData] Slot data not yet ready. :Wait() for it first:\n  local Slot = ClientData:WaitForSlot()")
		
	elseif key == "WaitForSlot" then
		return function()
			while not ClientData or not ClientData.Slot do
				task.wait()
			end
			IsSlotDataReady = true
			return ClientData.Slot
		end
	end

	--look up possible method in ProxyMethods.
	if ProxyMethods[key] then
		return (function(...) return ProxyMethods[key](self, ...) end) --returns a wrapped function because it uses local variables
	end

	--not a method. look for value in original data table.

	local newPath = table.clone(path) --path is used to know how deep into nested tables in "data" the current proxy is
	table.insert(newPath, key) --we're using newPath in recursive __index calls so those calls know in what nested table they currently are
	--btw newPath is where we are going to look next

	local value = data :: {[string]: any} --type checker silencer type cast
	for _,key in ipairs(newPath) do --go to the current recursive call's path in the real data table
		value = value[key] 
	end

	--if that recursive call's path result is still a table, look for an already existing pooled proxy OR call again to create a new proxy
	if typeof(value) == "table" then
		return PooledSubproxies[table.concat(newPath,".")] or CreateProxy(newPath)
	else
		return value
	end

end

proxy_mt.__newindex = function(self:ProxyTable, key:string, value:any): ()
	local path = self._path
	local data = ClientData
	
	--yield until slot data is ready
	if not IsSlotDataReady and key == "Slot" then
		error("[ClientData] Slot data not yet ready. :Wait() for it first:\n  local Slot = ClientData:WaitForSlot()")
	end
		
	local newPath = table.clone(rawget(self :: any, "_path")) :: {string}
	table.insert(newPath, key)

	local data_subfield = data :: {[string]: any} --type checker silencer type cast
	for i=1, #newPath - 1 do --navigate through original data table and stop right before the final key (so that we can still assign a value)
		data_subfield = data_subfield[newPath[i]]
	end

	local finalKey = newPath[#newPath]

	--return early if it causes no changes
	if data_subfield[finalKey] == value then return end

	--time to sanitize input

	local err: string?
	if data_subfield[finalKey] == nil then
		err = "Nonexistent key indexed; You cannot create new keys for slot data."
	elseif typeof(data_subfield[finalKey]) ~= typeof(value) then
		err = "Type mismatch when trying to assign a new value."
	elseif typeof(value) == "table" then
		err = "You cannot reassign entire tables."
	end

	--i wasnt sure if to warn, error or return the reason (edit these error / warning lines if necessary)
	if err then
		warn("[ClientData] "..err.."\nTried to assign value:", value, "\nTo path: "..table.concat(newPath,".")) --if value is a table, in error() it would print the string memory reference of the table instead of the table fields (ex: 0x123abc456) 
		error("[ClientData] Proxy caught an error, information in previous warning message.")
	end

	data_subfield[finalKey] = value

	--fire any active .Changed signals and parents
	FireChangedSignals(path)

	return
end

--intended for prints ( proxy:GetRaw() alternative ). also to prevent other scripts from seeing the real proxy data
--i dont know why a scripter might want to call tostring on a table if its not to print it...
proxy_mt.__tostring = function(self:ProxyTable): string
	local path = self._path
	local data = ClientData

	local value = data :: {[string]: any} --type checker silencer type cast
	for _,key in ipairs(path) do --go to the current recursive call's path in the real data table
		value = value[key] 
	end

	warn("[ClientData] 'tostring' called on ClientData proxy on path:",path)
	warn(value)
	return ""
end

proxy_mt.__len = function(self:ProxyTable): number
	local path = self._path
	local data = ClientData

	local value = data :: {[string]: any} --type checker silencer type cast
	for _,key in ipairs(path) do --go to the current recursive call's path in the real data table
		value = value[key] 
	end

	return #value
end

proxy_mt.__iter = function(self:ProxyTable): (typeof(next), {[string]: any}, nil)
	local path = self._path
	local data = ClientData

	local value = data :: {[string]: any} --type checker silencer type cast
	for _,key in ipairs(path) do --go to the current recursive call's path in the real data table
		value = value[key]
	end

	return next, (type(value) == "table" and DeepCopy(value)) or value :: any
end

table.freeze(proxy_mt) --prevent scripters from somehow editing this mt with getmetatable()

--- / Script functions / (they are missing the "local" because they were previously forward-declared)

function CreateProxy(path: {string}?): setmetatable<ProxyTable, typeof(proxy_mt)>
	local path = path or {} :: {string} --path variable redefinition with "local" is necessary rn so that the type checker behaves correctly

	local proxyTable:ProxyTable = {_path = path}

	--reuse metatable
	local proxy = setmetatable(proxyTable, proxy_mt)

	--prevent raw methods like table.insert() on the proxy table by freezing it
	table.freeze(proxyTable)

	--pool the (sub)proxy
	if #path <= MAX_SUBPROXY_DEPTH then
		PooledSubproxies[table.concat(path,".")] = proxy
	end
	
	return proxy
end


--create the proxy
ClientProxy = CreateProxy({}) :: ClientProxy


--- / Module return /  (return the proxy bc theres only 1 since its local)
return ClientProxy
