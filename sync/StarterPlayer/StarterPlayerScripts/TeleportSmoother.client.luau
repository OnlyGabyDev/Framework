--[[
	TeleportSmoother (cliente)
	==========================
	Suaviza a CÂMERA (não o personagem) quando a posição do personagem local
	dá um salto abrupto — ex: saída de um SetFrozen/Anchored, respawn,
	correção de rede. NÃO mexe no rig físico: hitboxes, animações e o que
	outros jogadores veem não são afetados, só a experiência de câmera do
	dono do personagem.

]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SNAP_THRESHOLD = 6       
local RECOVER_SECONDS = 0.25   

local player = Players.LocalPlayer

local lastPosition: Vector3? = nil
local offset = Vector3.zero

local function trackCharacter(character)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	lastPosition = root and root.Position
	offset = Vector3.zero
end

player.CharacterAdded:Connect(trackCharacter)
if player.Character then
	trackCharacter(player.Character)
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	local currentPosition = root.Position
	if lastPosition then
		local jump = currentPosition - lastPosition
		if jump.Magnitude > SNAP_THRESHOLD then
			-- "Esconde" o salto: a câmera passa a impressão de ainda estar
			-- perto da posição antiga, e o offset decai suavemente depois.
			offset -= jump
		end
	end
	lastPosition = currentPosition

	local decay = 1 - math.exp(-dt / RECOVER_SECONDS)
	offset = offset:Lerp(Vector3.zero, decay)

	humanoid.CameraOffset = offset
end)
