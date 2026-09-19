--[[
	Settings centralizadas do sistema de movimento/Forces.

	Se um dia precisar ajustar "quão difícil é resistir a um dash" ou "quão
	rápido a câmera se recupera de um teleport" alterar aqui
]]

return {
	-- Força máxima (em massa*studs/s²) que o LinearVelocity pode usar por eixo
	-- reivindicado por uma Force "Hard" (dash, ultimate, etc). Bem acima de
	-- qualquer coisa que a física natural (gravidade, fricção do Humanoid,
	-- colisões comuns) consiga opor — na prática, "inquebrável".
	Hard_Force_Strength = 1e6,

	-- Força máxima por eixo pra uma Force "Soft" (knockback leve, vento,
	-- correnteza). Forte o bastante pra mover o personagem de forma
	-- perceptível, mas fraca o bastante pra ceder contra colisões e pra não
	-- parecer um teleporte.
	Soft_Force_Strength = 2500,


	-- Quão rápido (unidades arbitrárias de "rigidez") a AlignOrientation gira
	-- o personagem pra encarar a direção de uma Force com FaceDirection = true.
	Face_Direction_Responsiveness = 25,
	

	-- Tempo (segundos) que o TeleportSmoother do cliente leva pra "engolir"
	-- um salto abrupto de posição (ver StarterPlayerScripts/TeleportSmoother).
	Teleport_Smoothing_Recovery_Seconds = 0.25,
	

	-- Distância (studs) acima da qual um salto de posição é tratado como
	-- teleporte/correção (e portanto suavizado na câmera) ao invés de
	-- movimento normal.
	Teleport_Smoothing_Snap_Threshold = 6,
}
