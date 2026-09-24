local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayVFX = ReplicatedStorage.RemoteEvents:WaitForChild("PlayVFX")

local VFXManager = {}

function VFXManager.PlayAll(effectName: string, data: {[string]: any})
	PlayVFX:FireAllClients(effectName, data)
end

function VFXManager.PlayNear(position: Vector3, radius: number, effectName: string, data: {[string]: any})
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and ((root :: BasePart).Position - position).Magnitude <= radius then
			PlayVFX:FireClient(player, effectName, data)
		end
	end
end

return VFXManager
