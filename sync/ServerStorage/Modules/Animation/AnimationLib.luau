local lib = {

	character = {

		Ashley = {},

		GenerichChar = {},

		Schema = {

			M1 = {
			M1Start = "109260837176213",
			M1S2 = "101981431556110",
			},

			S1 = {
			SpinStart = "130893699034171",
			SpinLoop = "99420668636443",
			},

		},




	}

}

local views = {} -- [dono|quem casta] = vista
local NONE = "\0" -- chave de cache para kit ausente (nome de kit nunca tem \0)

--[[
Biblioteca que uma skill enxerga em self.charLib: o conjunto (M1, S1...) vem do kit DONO da skill
(data.kit, carimbado pelo CombatComponent a partir da pasta no SkillDatabase) e, na falta, do kit
de quem casta. Assim uma skill roubada por outro personagem segue com as animações dela. Uma vista
por par (dono, quem casta), cacheada: nenhum runner aloca.
@param skillKit - kit dono da skill (data.kit) STRING?
@param casterKit - personagem de quem casta (GetChosenChar) STRING?
@return vista só de leitura TABLE (pode não ter o conjunto pedido: a skill confere ou declara requires)
]]
function lib.ForSkill(skillKit: string?, casterKit: string?)
	local cacheKey = (skillKit or NONE) .. "|" .. (casterKit or NONE)
	local view = views[cacheKey]
	if view then return view end

	local own = skillKit and lib.character[skillKit]
	local caster = casterKit and lib.character[casterKit]
	view = setmetatable({}, {
		__index = function(_, setName)
			local set = own and own[setName]
			if set == nil and caster then set = caster[setName] end
			return set
		end,
		__newindex = function()
			error("[AnimationLib] a biblioteca da skill é só de leitura", 2)
		end,
	})
	views[cacheKey] = view
	return view
end

return lib
