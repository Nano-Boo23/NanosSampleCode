--!strict

-- can be easily edited to allow for more "types" of prints, like
-- the one I recently added called "startupInfo"

-- / Module /
local Logger = {
	IsDebugActive = false,
	IsInfoActive = true,
	IsStartupInfoActive = true,
}

-- / Utility /
function CheckPrefix(prefix)
	return Logger.Framework[prefix] and prefix
		or prefix == "Framework" and "Framework"
		or prefix == "Client" and "Client"
		or `UNKNOWN ({prefix})`
end


-- / Logger prints /
function Logger.print(...)
	Logger.warn(script.Name, "Use .info instead of .print")
	Logger.info(...)
end
function Logger.debug(prefix, ...)
	if not Logger.IsDebugActive then return end
	
	print(`[{CheckPrefix(prefix)}]:`, ...)
end

function Logger.info(prefix, ...)
	if not Logger.IsInfoActive then return end
	
	print(`[{CheckPrefix(prefix)}]:`, ...)
end

function Logger.startupInfo(prefix, ...)
	if not Logger.IsStartupInfoActive then return end

	print(`[{CheckPrefix(prefix)}]:`, ...)
end


-- / Logger warns /
function Logger.warn(prefix, ...)
	warn(`[{CheckPrefix(prefix)}]:`, ...)
end

-- / Logger errors /
function Logger.error(prefix, ...)
	error({`[{CheckPrefix(prefix)}]:`, ...},2) --level 2 blame
end





function Logger._Init()
	if Logger.IsDebugActive then
		Logger.warn(script.Name, "Logger active for debug prints")
	end
	if Logger.IsInfoActive then
		Logger.warn(script.Name, "Logger active for info prints")
	end
end

return Logger
