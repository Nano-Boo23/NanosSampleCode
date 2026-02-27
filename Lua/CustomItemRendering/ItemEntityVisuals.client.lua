local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemEntityAnimator = require(ReplicatedStorage.Modules.ItemEntityClientAnimator)

local ItemEntitiesFoler = workspace.ItemEntities

for _,entity: Part in ItemEntitiesFoler:GetChildren() do
	ItemEntityAnimator.RenderEntity(entity)
end
ItemEntitiesFoler.ChildAdded:Connect(function(child: Instance)
	if not child:IsA("Part") then warn("Found a non-part in", ItemEntitiesFoler:GetFullName()) return end
	
	ItemEntityAnimator.RenderEntity(child)
end)
