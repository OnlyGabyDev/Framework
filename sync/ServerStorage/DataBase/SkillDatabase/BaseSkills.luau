local baseSkills = {
	
	
	--Base de dash, apenas retorna vetor
dash = function(dir,speed)
	
	if not dir or dir.Magnitude == 0 then
		return Vector3.zero
	end
	
	return dir.Unit * speed --Retorna só o calculo do vetor, quem está chamando que é responsável de dizer quem é o root e em qual vetor isso vai ser aplicado
	
end,



CreateProjectile = function()

end,

MeleeHit = function()
	
end,
	
}

return baseSkills
