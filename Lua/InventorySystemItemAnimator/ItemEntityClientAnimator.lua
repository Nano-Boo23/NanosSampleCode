--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemsFolder = ReplicatedStorage.Items

--- / Module /
local ItemEntityAnimator = {
	PICKUP_ANIMATION_TIME = 0.2
}

--lerps part towards a goal part for a smoother client sided look
local function PickupAnimation(part: BasePart, goalPart: BasePart?) 
	if not part or not part:IsA("BasePart") then return end
	if not goalPart or not goalPart:IsA("BasePart") then
		part:Destroy()
		return
	end

	part.Anchored = true

	local startTime = os.clock()
	local startPosition = part.Position

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not part or not part.Parent or not goalPart or not goalPart.Parent then
			if connection then connection:Disconnect() end
			return
		end

		local elapsed = os.clock() - startTime
		local alpha = math.clamp(elapsed / ItemEntityAnimator.PICKUP_ANIMATION_TIME, 0, 1)

		-- Move proportionally toward CURRENT goal position
		part.Position = startPosition:Lerp(goalPart.Position, alpha)

		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end



--btw this never welds anything to the server sided part to not disturb its position
function ItemEntityAnimator.RenderEntity(EntityPart: Part)
	if not EntityPart:IsA("Part") then warn("Non part recieved! Canceling client render") return end
	
	local ItemId = EntityPart:GetAttribute("ItemId")
	local UUID = EntityPart:GetAttribute("UUID")
	
	if EntityPart:GetAttribute("IsRendered") then
		warn("Item Entity "..EntityPart:GetFullName().." with ItemId "..ItemId.." and UUID "..UUID.." was already rendered")
		return
	end
	
	local ModelTemplate = ItemsFolder:FindFirstChild(ItemId) :: Tool?
	if not ModelTemplate then
		warn("Invalid ItemId. Not rendering but marking as rendered.")
		EntityPart:SetAttribute("IsRendered", true)
		EntityPart:SetAttribute("ErrorRendering", "Nonexisting Id") --maybe for later error tracking
		return
	end
	
	--item model found, attaching a visual
	
	local Model = ModelTemplate:Clone()
	Model.Parent = workspace

	-- Create centered pivot in item model
	local bboxCFrame = Model:GetBoundingBox()
	local pivot = Instance.new("Part")
	pivot.Size = Vector3.new(0.2,0.2,0.2)
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CFrame = bboxCFrame
	pivot.Parent = Model
	
	--weld everything just in case
	for _, part in ipairs(Model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= pivot then
			part.Anchored = false
			part.CanCollide = false

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = pivot
			weld.Part1 = part
			weld.Parent = pivot
		end
	end
	
	--make EntityPart invisible to client (the red box part)
	EntityPart.Transparency = 1

	local rotation = 0
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		if not EntityPart.Parent then
			Model:Destroy()
			return
		end

		rotation += math.rad(90) * dt
		t += dt

		-- Follow position only (ignore itemPart rotation)
		local position = EntityPart.Position
		pivot.CFrame = CFrame.new(position) * CFrame.Angles(0, rotation, 0) --spin
		pivot.CFrame += Vector3.new(0, math.sin(t)/2+0.5, 0) --bob
	end)
	
	
	--local pickup animation
	local ServerTouchPart = EntityPart:FindFirstChild("TouchInterestSensor") :: Part
	if not ServerTouchPart then
		warn("No TouchInterestSensor child found for item entity:",EntityPart.Name)
		return
	end
	
	local touchConn: RBXScriptConnection
	touchConn = ServerTouchPart.Touched:Connect(function(hit: BasePart)
		if not EntityPart:GetAttribute("CanPickup") then return end
		if not hit or not hit:IsA("BasePart") then return end
		local character = hit.Parent :: Model?
		local touchingPlayer = character and game.Players:GetPlayerFromCharacter(character)
		if not touchingPlayer or touchingPlayer ~= game.Players.LocalPlayer then return end
		assert(character)
		
		--print("picking item up locally")
		touchConn:Disconnect()
		local HRP = character:FindFirstChild("HumanoidRootPart") :: BasePart

		--update entity part even if it overrides the server position for a brief moment and causes a desync
		PickupAnimation(EntityPart, HRP)
	end)
end

--- / Module return /
return ItemEntityAnimator
