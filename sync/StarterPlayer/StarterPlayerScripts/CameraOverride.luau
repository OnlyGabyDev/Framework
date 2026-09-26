--[[
CameraOverride (CLIENTE)
========================
Over-the-shoulder com soft target-lock na entidade mais próxima num cone
frontal. Permite mover a câmera livremente com o mouse, mas gruda suavemente
no alvo se houver um no raio.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraOverride = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Você pode modificar à vontade os valores desta tabela para deixar a câmera 
-- perfeitamente ao seu gosto.
local Config = {
	ShoulderOffset = Vector3.new(4.2, 1.5, 0), -- Quão pra direita (X) e quão alto (Y) do seu pescoço
	Distance = 8.5,                            -- Distância que a câmera fica pra trás do ombro
	TargetLockRadius = 45,                     -- Distância máxima que o lock-on pega
	TargetLockConeAngleDeg = 310,               -- Ângulo de visão do lock-on
	TargetLockSoftness = 100,                   -- Força do lock-on (aumentado para "grudar" mais duro)
	TargetSearchInterval = 0.15,               -- A cada quantos segundos ele procura um alvo novo
}

local active = false
local currentTarget: Model? = nil
local connection: RBXScriptConnection? = nil
local toggleKey = Enum.KeyCode.C

local lastTargetSearch = 0
local yaw = 0
local pitch = 0

local function getCharacterParts()
	local character = CameraOverride.PossessedSubject or player.Character
	if not character then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function findSoftLockTarget(root: BasePart): Model?
	local bestTarget: Model? = nil
	local bestScore = -math.huge
	local camDirection = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector

	local countEntities = 0

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj ~= player.Character and obj:GetAttribute("EntityID") then
			local targetRoot = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
			
			if targetRoot then
				local toTarget = (targetRoot :: BasePart).Position - root.Position
				local distance = toTarget.Magnitude
				
				if distance > 0.1 then
					local dotProduct = math.clamp(camDirection:Dot(toTarget.Unit), -1, 1)
					local angle = math.deg(math.acos(dotProduct))
					
					if distance <= Config.TargetLockRadius then
						if angle <= Config.TargetLockConeAngleDeg then
							local score = -angle - (distance * 0.1)
							if score > bestScore then
								bestScore = score
								bestTarget = obj
							end
						end
					end
				end
			end
		end
	end



	return bestTarget
end

local function update(dt: number)
	local root, humanoid = getCharacterParts()
	if not root or not humanoid then return end

	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	local now = os.clock()
	if now - lastTargetSearch >= Config.TargetSearchInterval then
		lastTargetSearch = now
		currentTarget = findSoftLockTarget(root)
	end

	local focusPosition = root.Position + Vector3.new(0, 1.5, 0)

	if currentTarget then
		local targetRoot = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
			
		if targetRoot then
			local toTarget = ((targetRoot :: BasePart).Position - focusPosition).Unit
			local targetPitch = math.asin(toTarget.Y)
			local targetYaw = -math.atan2(toTarget.X, -toTarget.Z)
			
			local blend = 1 - math.exp(-Config.TargetLockSoftness * dt)
			
			local diffYaw = (targetYaw - yaw)
			diffYaw = (diffYaw + math.pi) % (2 * math.pi) - math.pi
			
			yaw = yaw + diffYaw * blend
			pitch = pitch + (targetPitch - pitch) * blend
		end
	end

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local desiredPosition = focusPosition
		+ rotation * Config.ShoulderOffset
		- rotation.LookVector * Config.Distance

	-- Raycast para não entrar em paredes
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local rayResult = workspace:Raycast(focusPosition, desiredPosition - focusPosition, raycastParams)
	
	if rayResult then
		desiredPosition = rayResult.Position + rotation.LookVector * 0.5
	end

	camera.CFrame = CFrame.new(desiredPosition) * rotation
end

function CameraOverride.Enable()
	if active then return end
	active = true
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	local rx, ry, rz = camera.CFrame:ToEulerAnglesYXZ()
	pitch = rx
	yaw = ry
	
	connection = RunService.RenderStepped:Connect(update)
end

function CameraOverride.Disable()
	if not active then return end
	active = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function CameraOverride.Toggle()
	if active then CameraOverride.Disable() else CameraOverride.Enable() end
end

function CameraOverride.IsActive(): boolean
	return active
end

function CameraOverride.GetCurrentTarget(): Model?
	return currentTarget
end

function CameraOverride.Init()
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			yaw -= input.Delta.X * 0.005
			pitch = math.clamp(pitch - input.Delta.Y * 0.005, -math.rad(80), math.rad(80))
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			Config.Distance = math.clamp(Config.Distance - input.Position.Z, 2, 12)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == toggleKey then
			CameraOverride.Toggle()
		end
	end)

	UserInputService.JumpRequest:Connect(function()
		if CameraOverride.PossessedSubject then
			local jumpEvent = ReplicatedStorage.RemoteEvents:FindFirstChild("RequestJump")
			if jumpEvent then jumpEvent:FireServer() end
		end
	end)

	local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	local Controls = PlayerModule:GetControls()
	local NATIVE_MOVE = Controls.moveFunction
	-- (Stub do humanoid foi removido em favor do _nativeJumpSuspended)

	local ControlStateChanged = ReplicatedStorage.RemoteEvents:WaitForChild("ControlStateChanged")
	local activeBeforeLock = false

	ControlStateChanged.OnClientEvent:Connect(function(isLocked: boolean, entityID: string?, suspendNative: boolean?)
		if entityID then
			for _, obj in ipairs(workspace:GetChildren()) do
				if obj:GetAttribute("EntityID") == entityID then
					CameraOverride.PossessedSubject = obj
					workspace.CurrentCamera.CameraSubject = obj:FindFirstChild("Humanoid") or obj.PrimaryPart
					break
				end
			end
			
			-- Se for o próprio player (exemplo: depois do Unlock, Volta pra id do player original)
			-- então clear o subject
			local selfId = player.Character and player.Character:GetAttribute("EntityID")
			if selfId == entityID then
				CameraOverride.PossessedSubject = nil
				if player.Character then
					workspace.CurrentCamera.CameraSubject = player.Character:FindFirstChild("Humanoid") or player.Character.PrimaryPart
				end
			end
		else
			CameraOverride.PossessedSubject = nil
			if player.Character then
				workspace.CurrentCamera.CameraSubject = player.Character:FindFirstChild("Humanoid") or player.Character.PrimaryPart
			end
		end

		if isLocked or suspendNative then
			Controls.moveFunction = function() end
			Controls._nativeJumpSuspended = true
		else
			Controls.moveFunction = NATIVE_MOVE
			Controls._nativeJumpSuspended = false
		end

		if isLocked then
			activeBeforeLock = active
			CameraOverride.Disable()
		elseif activeBeforeLock then
			CameraOverride.Enable()
		end
	end)
end

return CameraOverride
