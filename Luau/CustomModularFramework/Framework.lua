--!strict
-- / Services /
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- / Variables /
local ModulesFolder = ReplicatedStorage.Modules

-- / Module /
local Framework = {
	Metadata = {
		IsStartedUp = false,
		IsLoaded = false,
		FinishedLoading = Instance.new("BindableEvent"),
		InitWaitTime = 0.1,
		LoadWaitTime = 0.1,
	},

	ModuleNames = {} :: {[number]: string}
}

-- / Types for strict type checker /
export type FrameworkType = typeof(Framework)
export type BaseModule = {
	_Init: 		() -> ()?,
	PreLoad: 	() -> ()?,
	Load: 		() -> ()?,
	PostLoad:	() -> ()?,
	[string]: 	(...any?) -> (...any?)?,
	Framework:	{}
}
--[[
all modules have a table "Framework" that is empty but has a metatable with
an __index metamethod pointing to Framework (module now has access to all other modules)
]]

-- / Utility finctions /
local function RoundToNonZeroDecimals(decimal:number, numOfNonzeroes: number?): number
	numOfNonzeroes = numOfNonzeroes or 0
	local currentMult = 1

	while decimal * currentMult < math.pow(10,numOfNonzeroes-1) do
		currentMult *= 10
	end
	
	return math.round(decimal * currentMult) / currentMult
end

local function WaitForThreads(Threads: {[string]: thread}, maxTime:number?)
	local startTime = tick()
	maxTime = maxTime or 10
	
	while next(Threads) ~= nil do --while there are still items in table
		
		for name,thread in pairs(Threads) do
			if coroutine.status(thread) == "dead" then
				Threads[name] = nil
			elseif coroutine.status(thread) == "suspended" then
				warn(`Thread {thread} is suspended! Remove any yielding functions from _Init()`)
			end
		end
		
		if tick() > startTime + maxTime and next(Threads) ~= nil then --they are taking too long
			warn("Some modules are taking too long to finish executing:")
			warn(Threads)
		end
		
	end
end

-- / Modules loading functions /
local function LoadModules()
	local Stages = {"PreLoad", "Load", "PostLoad"}

	for _,stage in ipairs(Stages) do
		
		local Threads: {[string]: thread} = {}
		
		for _,name:string in Framework.ModuleNames do
			if Framework[name] then

				--Call the stage if it exists
				if Framework[name][stage] then
					Threads[name] = task.spawn(function()
						Framework[name][stage]()
					end)
				else
					Framework.Logger.startupInfo(script.Name, `Module '{name}' has no stage '{stage}', skipping stage`)
				end

			else
				Framework.Logger.warn(script.Name, `CRITICAL: Module name {name} in ModuleNames list but not found in the framework`)
				continue
			end
		end
		
		local startTime = tick()
		WaitForThreads(Threads, Framework.Metadata.LoadWaitTime)
		local finalTime = RoundToNonZeroDecimals(tick() - startTime, 2)
		print(`[Framework]:'{stage}' stage done in {finalTime}s`)
	end
	
end

-- / Framework startup /
function Framework.Startup() --on startup, no method from any module should be called except _Init
	if Framework.Metadata.IsStartedUp then warn("[Framework]: Framework already started up") return end
	Framework.Metadata.IsStartedUp = true

	local descendants = ModulesFolder:GetDescendants()

	-- Init
	local InitThreads: {[string]: thread} = {}
	local Framework_mt = {__index = Framework}--predefined and reused to save up a tiny bit of memory 
	for _,child:Instance in descendants do
		if child:IsA("ModuleScript") then
			local module = require(child) :: BaseModule
			
			-- give module a table with an __index metamethod pointing to Framework
			module.Framework = {}
			setmetatable(module.Framework, Framework_mt)
			table.freeze(module.Framework)
			
			local name = child.Name

			if Framework[name] or Framework.ModuleNames[name] then
				warn(`[Framework]: Module with name {name} already exists in the framework!`)
				continue
			end

			Framework[name] = module
			table.insert(Framework.ModuleNames, name)

			--spawn tasks for all _Init()
			if type(module._Init) == "function" then
				InitThreads[name] = task.spawn(function() module._Init() end)
			else
				warn(`[Framework]: Module {name} has no _Init function`)
			end

		else
			--warn("[Framework]: Tried initializing a non module script:", child:GetFullName())
		end
	end

	-- wait for all _Init() to end. warn if any is taking too long
	local startTime = tick()
	WaitForThreads(InitThreads, Framework.Metadata.InitWaitTime)
	local finalTime = RoundToNonZeroDecimals(tick() - startTime, 2)
	assert(Framework.Logger, "Essential framework module 'Logger' is missing!")
	
	Framework.Logger.startupInfo(script.Name,`'Init' initial stage done in {finalTime}s, now loading modules`)
	LoadModules()
	
	local finalTime = RoundToNonZeroDecimals(tick() - startTime, 2)
	Framework.Logger.startupInfo(script.Name, `All modules loaded and ready to go in {finalTime}s`)
	
	Framework.Metadata.IsLoaded = true
	Framework.Metadata.FinishedLoading:Fire()
end



-- / Module Return /
return Framework
