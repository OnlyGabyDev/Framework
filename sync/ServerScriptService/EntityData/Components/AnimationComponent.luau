--[[
	AnimationComponent - Sistema completo de animações para entidades
	- Suporta Humanoid (Animator) e modelos customizados (AnimationController)
	- Sistema de tracks com gerenciamento automático
	- Integração com AnimationLib
	- Sequências e markers
	- Cache de Animation instances para performance
]]

local ServerStorage = game:GetService("ServerStorage")

local AnimationComponent = {}
AnimationComponent.__index = AnimationComponent

--=============================================================================
--  TYPES
--=============================================================================

type SequenceStep = {
	id: number | string,
	key: string,
	fade: number?,
	weight: number?,
	speed: number?,
	marker: string?,
	delay: number?
}

type LoopInfo = {
	from: number,
	to: number,
	count: number,
	counter: number?
}

--=============================================================================
--  CONSTRUCTOR
--=============================================================================

--[[
Inicializa o componente de animação
@param entity - Entidade dona do componente EntityCore
@param config - Configurações iniciais TABLE (opcional)
@return nova instância do AnimationComponent AnimationComponent
]]
function AnimationComponent.new(entity, config)
	local self = setmetatable({}, AnimationComponent)
	
	self.Entity = entity
	
	-- Animator do Roblox
	self.Animator = nil
	
	-- Tipo de sistema de animação
	self.AnimationType = nil -- "Humanoid" ou "Custom"
	
	-- Tracks carregadas e ativas
	self.Tracks = {} -- [key] = AnimationTrack
	
	-- Cache de Animation instances
	self.AnimationCache = {} -- [animId] = Animation instance
	
	-- Biblioteca de animações do personagem
	self.AnimLib = nil
	
	-- Conexões ativas (para cleanup)
	self._connections = {}
	
	return self
end

--=============================================================================
--  INITIALIZATION
--=============================================================================

--[[
Inicializa o sistema de animação baseado no tipo de entidade
@return sucesso BOOLEAN
]]
function AnimationComponent:_Initialize() : boolean
	local charComp = self.Entity:GetComponent(self.Entity.ComponentKey.Character)
	if not charComp then
		warn("[AnimationComponent] Entidade sem CharacterComponent")
		return false
	end
	
	local wrapper = charComp:GetCharacterWrapper()
	if not wrapper then
		return false
	end
	
	
	-- Tenta obter Humanoid primeiro
	local humanoid = self.Entity:GetHumanoid()
	
	if humanoid then
		-- Sistema baseado em Humanoid
		self.Animator = humanoid:FindFirstChildOfClass("Animator")
		if not self.Animator then
			self.Animator = Instance.new("Animator")
			self.Animator.Parent = humanoid
		end
		self.AnimationType = "Humanoid"
		
	else
		-- Sistema customizado (AnimationController no model)
		local model = self.Entity.Instance
		local animController = model:FindFirstChildOfClass("AnimationController")
		
		if not animController then
			animController = Instance.new("AnimationController")
			animController.Parent = model
		end
		
		self.Animator = animController:FindFirstChildOfClass("Animator")
		if not self.Animator then
			self.Animator = Instance.new("Animator")
			self.Animator.Parent = animController
		end
		self.AnimationType = "Custom"
	end
	
	-- Carrega biblioteca de animações
	self:_LoadAnimLib()
	
	return true
end

--[[
Carrega a biblioteca de animações do personagem
]]
function AnimationComponent:_LoadAnimLib()
	local combatComp = self.Entity:GetComponent(self.Entity.ComponentKey.Combat)
	if not combatComp then return end
	
	local charName = combatComp.ChosenChar
	
	-- Tenta carregar AnimationLib
	local success, animLib = pcall(require, ServerStorage.Modules.Animation.AnimationLib)
	if success and animLib.character and animLib.character[charName] then
		self.AnimLib = animLib.character[charName]
	else
		warn("[AnimationComponent] AnimLib não encontrada para:", charName)
	end
end

--=============================================================================
--  CORE ANIMATION SYSTEM
--=============================================================================

--[[
Cria ou recupera uma Animation instance do cache
@param animId - ID da animação STRING|NUMBER
@return Animation instance
]]
function AnimationComponent:_GetAnimation(animId : string | number) : Animation
	local id = tostring(animId)
	
	if self.AnimationCache[id] then
		return self.AnimationCache[id]
	end
	
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. id
	
	self.AnimationCache[id] = anim
	return anim
end

--[[
Carrega e toca uma animação
@param animId - ID da animação STRING|NUMBER
@param key - Chave única para a track (opcional, padrão = animId) STRING
@param fadeTime - Tempo de fade in NUMBER (opcional, padrão 0.1)
@param weight - Peso da animação NUMBER (opcional)
@param speed - Velocidade de playback NUMBER (opcional, padrão 1)
@return AnimationTrack ou nil
]]
function AnimationComponent:PlayAnimation(animId : string | number, key : string?, fadeTime : number?, weight : number?, speed : number?) : AnimationTrack?
	if not self.Animator then
		warn("[AnimationComponent] Animator não inicializado")
		return nil
	end
	
	key = key or tostring(animId)
	fadeTime = fadeTime or 0.1
	speed = speed or 1
	
	-- Para animação anterior nessa key
	if self.Tracks[key] then
		self:StopAnimation(key, fadeTime)
	end
	
	-- Carrega animação
	local anim = self:_GetAnimation(animId)
	local track = self.Animator:LoadAnimation(anim)
	
	-- Aplica configurações
	if weight then
		track:AdjustWeight(weight, 0)
	end
	track:AdjustSpeed(speed)
	
	-- Toca
	track:Play(fadeTime)
	
	-- Armazena
	self.Tracks[key] = track
	
	-- Auto-cleanup quando terminar
	local connection = track.Stopped:Connect(function()
		self.Tracks[key] = nil
	end)
	table.insert(self._connections, connection)
	
	return track
end

--[[
Para uma animação específica
@param key - Chave da track STRING
@param fadeTime - Tempo de fade out NUMBER (opcional, padrão 0.1)
]]
function AnimationComponent:StopAnimation(key : string, fadeTime : number?)
	local track = self.Tracks[key]
	if not track then return end
	
	fadeTime = fadeTime or 0.1
	track:Stop(fadeTime)
	self.Tracks[key] = nil
end

--[[
Para todas as animações ativas
@param fadeTime - Tempo de fade out NUMBER (opcional, padrão 0.1)
]]
function AnimationComponent:StopAllAnimations(fadeTime : number?)
	fadeTime = fadeTime or 0.1
	
	for key, track in pairs(self.Tracks) do
		if track and track.IsPlaying then
			track:Stop(fadeTime)
		end
	end
	
	table.clear(self.Tracks)
end

--[[
Ajusta a velocidade de uma animação em execução
@param key - Chave da track STRING
@param speed - Nova velocidade NUMBER
]]
function AnimationComponent:AdjustSpeed(key : string, speed : number)
	local track = self.Tracks[key]
	if track then
		track:AdjustSpeed(speed)
	end
end

--[[
Ajusta o peso de uma animação em execução
@param key - Chave da track STRING
@param weight - Novo peso NUMBER
@param fadeTime - Tempo de transição NUMBER (opcional)
]]
function AnimationComponent:AdjustWeight(key : string, weight : number, fadeTime : number?)
	local track = self.Tracks[key]
	if track then
		track:AdjustWeight(weight, fadeTime or 0)
	end
end

--=============================================================================
--  ANIMATION SEQUENCES
--=============================================================================

--[[
Toca uma sequência de animações
@param sequence - Lista de steps da sequência TABLE
@param index - Índice interno NUMBER
@param loopInfo - Informações de loop TABLE (opcional)
]]
function AnimationComponent:PlaySequence(sequence: {SequenceStep}, index: number, loopInfo: LoopInfo?)
	index = index or 1
	local step = sequence[index]
	
	if not step then return end
	
	local track = self:PlayAnimation(
		step.id,
		step.key,
		step.fade,
		step.weight,
		step.speed
	)
	
	if not track then return end
	
	-- Função para avançar na sequência
	local function playNext()
		-- Lógica de loop
		if loopInfo and index >= loopInfo.from and index <= loopInfo.to then
			local counter = loopInfo.counter or 0
			counter = counter + 1
			loopInfo.counter = counter
			
			local totalSteps = loopInfo.to - loopInfo.from + 1
			local maxIterations = loopInfo.count * totalSteps
			
			if counter < maxIterations then
				local nextIndex = (index :: number) + 1
				if nextIndex > loopInfo.to then
					nextIndex = loopInfo.from
				end
				-- Chama recursivamente usando o componente
				task.defer(function()
					AnimationComponent.PlaySequence(self, sequence, nextIndex, loopInfo)
				end)
				return
			end
		end
		
		-- Próximo step normal
		task.defer(function()
			AnimationComponent.PlaySequence(self, sequence, (index :: number) + 1, loopInfo)
		end)
	end
	
	-- Determina quando ir pro próximo
	if step.marker then
		local signal = track:GetMarkerReachedSignal(step.marker)
		local connection = signal:Connect(playNext)
		table.insert(self._connections, connection)
		
	elseif step.delay then
		task.delay(step.delay, playNext)
		
	else
		local connection = track.Stopped:Connect(playNext)
		table.insert(self._connections, connection)
	end
end

--=============================================================================
--  MARKERS
--=============================================================================

--[[
Obtém o sinal de marker de uma animação
@param key - Chave da track STRING
@param markerName - Nome do marker STRING
@return RBXScriptSignal ou nil
]]
function AnimationComponent:GetMarkerSignal(key : string, markerName : string) : RBXScriptSignal?
	local track = self.Tracks[key]
	if not track then
		warn("[AnimationComponent] Track não encontrada:", key)
		return nil
	end
	
	return track:GetMarkerReachedSignal(markerName)
end

--[[
Espera por um marker ser atingido (bloqueante)
@param key - Chave da track STRING
@param markerName - Nome do marker STRING
@param timeout - Timeout em segundos NUMBER (opcional)
@return sucesso BOOLEAN
]]
function AnimationComponent:WaitForMarker(key : string, markerName : string, timeout : number?) : boolean
	local signal = self:GetMarkerSignal(key, markerName)
	if not signal then return false end
	
	if timeout then
		local fired = false
		local connection
		connection = signal:Connect(function()
			fired = true
			if connection then connection:Disconnect() end
		end)
		
		task.wait(timeout)
		if connection then connection:Disconnect() end
		return fired
	else
		signal:Wait()
		return true
	end
end

--[[
Conecta um callback a um marker
@param key - Chave da track STRING
@param markerName - Nome do marker STRING
@param callback - Função a ser executada FUNCTION
@return RBXScriptConnection ou nil
]]
function AnimationComponent:OnMarker(key : string, markerName : string, callback : () -> ()) : RBXScriptConnection?
	local signal = self:GetMarkerSignal(key, markerName)
	if not signal then return nil end
	
	local connection = signal:Connect(callback)
	table.insert(self._connections, connection)
	
	return connection
end

--=============================================================================
--  ANIMATION LIBRARY INTEGRATION
--=============================================================================

--[[
Toca animação da biblioteca
@param categoryName - Nome da categoria (ex: "M1", "S1") STRING
@param animName - Nome da animação dentro da categoria STRING
@param key - Chave única (opcional, auto-gerada) STRING
@param fadeTime - Tempo de fade NUMBER (opcional)
@return AnimationTrack ou nil

Exemplo:
PlayFromLib("M1", "M1Start", nil, 0.1)
]]
function AnimationComponent:PlayFromLib( categoryName : string, animName : string, key : string?, fadeTime : number?) : AnimationTrack?
	local animId = self:GetLibAnimId(categoryName, animName)
	if not animId then return nil end
	
	key = key or (categoryName .. "_" .. animName)
	
	return self:PlayAnimation(animId, key, fadeTime)
end

--[[
Obtém ID de animação da biblioteca
@param categoryName - Nome da categoria STRING
@param animName - Nome da animação STRING
@return ID da animação NUMBER|STRING ou nil
]]
function AnimationComponent:GetLibAnimId(categoryName : string, animName : string)
	if not self.AnimLib then
		warn("[AnimationComponent] AnimLib não carregada")
		return nil
	end
	
	local category = self.AnimLib[categoryName]
	if not category then
		warn("[AnimationComponent] Categoria não encontrada:", categoryName)
		return nil
	end
	
	local animId = category[animName]
	if not animId then
		warn("[AnimationComponent] Animação não encontrada:", animName, "em", categoryName)
		return nil
	end
	
	return animId
end

--[[
Obtém toda a categoria de animações
@param categoryName - Nome da categoria STRING
@return Tabela de animações TABLE ou nil
]]
function AnimationComponent:GetLibCategory(categoryName : string) : {}?
	if not self.AnimLib then return nil end
	return self.AnimLib[categoryName]
end

--=============================================================================
--  GETTERS
--=============================================================================

--[[
Retorna uma track específica
@param key - Chave da track STRING
@return AnimationTrack ou nil
]]
function AnimationComponent:GetTrack(key : string) : AnimationTrack?
	return self.Tracks[key]
end

--[[
Verifica se uma animação está tocando
@param key - Chave da track STRING
@return está tocando BOOLEAN
]]
function AnimationComponent:IsPlaying(key : string) : boolean
	local track = self.Tracks[key]
	return track ~= nil and track.IsPlaying
end

--[[
Retorna todas as tracks ativas
@return Tabela de tracks TABLE
]]
function AnimationComponent:GetAllTracks() : { [string]: AnimationTrack }
	return self.Tracks
end

--[[
Retorna o tipo de animação usado
@return tipo STRING ("Humanoid" ou "Custom")
]]
function AnimationComponent:GetAnimationType() : string
	return self.AnimationType or "Unknown"
end

--=============================================================================
--  LIFECYCLE
--=============================================================================

--[[
Função de inicialização do componente
]]
function AnimationComponent:OnAdded()
	self:_Initialize()
end

--[[
Destrói o componente, limpando todas as animações e conexões
]]
function AnimationComponent:Destroy()
	-- Para todas as animações
	self:StopAllAnimations(0)
	
	-- Desconecta todos os sinais
	for _, connection in ipairs(self._connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(self._connections)
	
	-- Limpa caches
	for _, anim in pairs(self.AnimationCache) do
		if anim then anim:Destroy() end
	end
	table.clear(self.AnimationCache)
	table.clear(self.Tracks)
	
	self.Entity = nil
	self.Animator = nil
	self.AnimLib = nil
end

--=============================================================================
--  API EXPOSE
--=============================================================================

local ExposeAPI = {
	-- Core
	PlayAnimation = function(component, ...) return component:PlayAnimation(...) end,
	StopAnimation = function(component, ...) return component:StopAnimation(...) end,
	StopAllAnimations = function(component, ...) return component:StopAllAnimations(...) end,
	AdjustSpeed = function(component, ...) return component:AdjustSpeed(...) end,
	AdjustWeight = function(component, ...) return component:AdjustWeight(...) end,
	
	-- Sequences
	PlaySequence = function(component, ...) return component:PlaySequence(...) end,
	
	-- Markers
	GetMarkerSignal = function(component, ...) return component:GetMarkerSignal(...) end,
	WaitForMarker = function(component, ...) return component:WaitForMarker(...) end,
	OnMarker = function(component, ...) return component:OnMarker(...) end,
	
	-- Library
	PlayFromLib = function(component, ...) return component:PlayFromLib(...) end,
	GetLibAnimId = function(component, ...) return component:GetLibAnimId(...) end,
	GetLibCategory = function(component, ...) return component:GetLibCategory(...) end,
	
	-- Getters
	GetTrack = function(component, ...) return component:GetTrack(...) end,
	IsPlaying = function(component, ...) return component:IsPlaying(...) end,
	GetAllTracks = function(component) return component:GetAllTracks() end,
	GetAnimationType = function(component) return component:GetAnimationType() end,
}

return {
	new = AnimationComponent.new,
	ExposeAPI = ExposeAPI,
}