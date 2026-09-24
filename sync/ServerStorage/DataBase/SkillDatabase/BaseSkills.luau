local baseSkills = {
	ComboWindow = require(script.ComboWindow),

	dash = function(dir,speed)
		if not dir or dir.Magnitude == 0 then
			return Vector3.zero
		end
		return dir.Unit * speed
	end,

	CreateProjectile = function()
	end,

	MeleeHit = function()
	end,
}

return baseSkills
