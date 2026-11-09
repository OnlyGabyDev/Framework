--[[
	CollisionGroups — grupos de colisão do motor (F19). Quem é agarrado (FW_Grabbed) não colide com
	outro agarrado nem com quem agarrou (FW_Grabber); os dois continuam colidindo com o mundo.
	Assign devolve a função que restaura o grupo original de cada peça (chame no fim do grab).
]]

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {}
CollisionGroups.Grabbed = "FW_Grabbed"
CollisionGroups.Grabber = "FW_Grabber"

local registered = false
local function ensureRegistered()
	if registered then return end
	registered = true
	for _, group in { CollisionGroups.Grabbed, CollisionGroups.Grabber } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Grabbed, CollisionGroups.Grabbed, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Grabbed, CollisionGroups.Grabber, false)
end

--[[
Põe todas as BaseParts do model no grupo.
@return restore () -> () que devolve cada peça ao grupo que tinha
]]
function CollisionGroups.Assign(model: Instance?, group: string): () -> ()
	if not model then return function() end end
	ensureRegistered()
	local saved = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			saved[part] = part.CollisionGroup
			part.CollisionGroup = group
		end
	end
	return function()
		for part, previous in saved do
			if part.Parent then part.CollisionGroup = previous end
		end
		table.clear(saved)
	end
end

return CollisionGroups