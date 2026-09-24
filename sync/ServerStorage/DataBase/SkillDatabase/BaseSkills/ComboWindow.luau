--!strict
--[[
ComboWindow: marca/consome uma janela de combo curta e genérica. Skill A
declara "acabei de fazer algo", skill B lê e consome, sem acoplamento direto
entre A e B. Implementado em cima do Status genérico já existente — não
inventa sistema de tags paralelo.
]]

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local Enum = StateTable.Enum

local ComboWindow = {}

local function BuildMarkerStatus(markerName: string)
	return {
		data = {
			name = markerName,
			category = Enum.Categories.Internal,
			duration = 0,
		},
		callbacks = {},
	}
end

function ComboWindow.Mark(entity: any, markerName: string, window: number, payload: {[string]: any}?, source: any?): string?
	local statusData = BuildMarkerStatus(markerName)
	local id = entity.ApplyStatus(statusData, { Duration = window, Source = source, ID = markerName .. "_ComboWindow" })

	if id and payload then
		local entries = entity.GetStatus(markerName)
		local entry = entries and entries[1]
		if entry and entry.runner then
			entry.runner.skill.ComboPayload = payload
		end
	end

	return id
end

function ComboWindow.Consume(entity: any, markerName: string): {[string]: any}?
	local entries = entity.GetStatus(markerName)
	local entry = entries and entries[1]
	if not entry then
		return nil
	end

	local payload = (entry.runner and entry.runner.skill.ComboPayload) or {}
	entity.RemoveStatus(markerName)
	return payload
end

function ComboWindow.Peek(entity: any, markerName: string): boolean
	return entity.GetStatus(markerName) ~= nil
end

return ComboWindow
