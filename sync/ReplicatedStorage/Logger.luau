--[[
	Logger — saída padronizada do framework (F64, regra 18). Cada módulo pede um canal e escreve
	por nível; o que aparece é decidido em ReplicatedStorage.Config.LogConfig (dado do jogo).

		local Log = require(ReplicatedStorage.Logger).Channel("DataManager")
		Log.Debug("entidade criada:", id)      -- some no nível padrão
		Log.Warn("ID inválido:", id)           -- aviso estrutural
		Log.WarnOnce(chave, "...")             -- 1ª vez em Warn, as seguintes só em Debug

	Formato: "[Canal] mensagem". Debug/Info saem como print, Warn/Error como warn.
]]

local Config = require(script.Parent.Config.LogConfig)

local Logger = {}

Logger.Levels = table.freeze({ Debug = 1, Info = 2, Warn = 3, Error = 4, Off = 5 })

local function levelOf(name)
	local level = Logger.Levels[name]
	if not level then
		warn("[Logger] nível desconhecido em LogConfig:", tostring(name), "- usando Warn")
		return Logger.Levels.Warn
	end
	return level
end

local globalLevel = levelOf(Config.Level or "Info")
local channelLevels = {}
for channel, level in Config.Channels or {} do
	channelLevels[channel] = levelOf(level)
end

--[[ Muda o nível em runtime (todos os canais, ou só `channel`) ]]
function Logger.SetLevel(level: string, channel: string?)
	if channel then
		channelLevels[channel] = levelOf(level)
	else
		globalLevel = levelOf(level)
	end
end

local channels = {}

function Logger.Channel(name: string)
	local existing = channels[name]
	if existing then return existing end

	local prefix = "[" .. name .. "]"
	local function enabled(level)
		return level >= (channelLevels[name] or globalLevel)
	end
	local warnedKeys = {}

	local channel = {}
	function channel.Debug(...)
		if enabled(1) then print(prefix, ...) end
	end
	function channel.Info(...)
		if enabled(2) then print(prefix, ...) end
	end
	function channel.Warn(...)
		if enabled(3) then warn(prefix, ...) end
	end
	function channel.Error(...)
		if enabled(4) then warn(prefix, "ERRO:", ...) end
	end
	function channel.WarnOnce(key: any, ...)
		if warnedKeys[key] then
			channel.Debug(...)
			return
		end
		warnedKeys[key] = true
		channel.Warn(...)
	end

	channels[name] = channel
	return channel
end

return Logger