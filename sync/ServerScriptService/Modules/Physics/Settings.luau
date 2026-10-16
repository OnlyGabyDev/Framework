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


	--========= Validação de movimento do player (GlobalAntiCheat, F05) =========--
	-- O corpo do player é simulado pelo cliente; o servidor confere a distância andada
	-- contra a velocidade permitida (WalkSpeed do servidor + Forces + chão) e devolve o
	-- corpo à última posição válida quando ela estoura. Com Workspace.AuthorityMode =
	-- Server (alvo da reescrita do movimento) a validação fica redundante: desligue aqui.
	Movement_Validation_Enabled = true,

	-- Multiplicador sobre o WalkSpeed do servidor.
	Movement_Speed_Tolerance = 1.25,

	-- Folga somada à velocidade permitida (studs/s), na horizontal e na subida.
	Movement_Speed_Slack = 2,

	-- Crédito máximo, em segundos de velocidade permitida. Absorve a rajada de
	-- replicação (vários frames de movimento chegando juntos depois de um atraso de
	-- rede). É também o maior "salto" que um cheater ganha de uma vez.
	Movement_Burst_Seconds = 0.25,

	-- Excesso tolerado além do crédito (studs) antes de corrigir.
	Movement_Excess_Limit = 4,

	-- Por quanto tempo (s) uma velocidade permitida maior continua valendo depois de
	-- cair: a Force que acabou no servidor ainda está sendo aplicada no cliente. É a
	-- base: o atraso de rede do player (Movement_Ping_Factor) soma em cima.
	Movement_Latency_Window = 0.35,

	-- Janela de confiança (s) depois de o servidor mover o corpo (teleporte, PivotTo,
	-- volta da possessão): pacote antigo do cliente ainda em trânsito não vira correção.
	-- Também é a base, com o atraso de rede somado.
	Movement_Trust_Seconds = 0.5,

	-- Quantas vezes o GetNetworkPing do player entra nas duas janelas acima. Sem isso,
	-- com 200 ms de atraso Dash, voo e Stun/Lock viravam correção; 2 cobre o ping ser
	-- ida-e-volta ou um sentido (a doc não diz).
	Movement_Ping_Factor = 2,

	-- Alcance (studs) do raycast do chão além da HipHeight, para somar plataforma móvel.
	-- Cobre as pernas do R6 (HipHeight 0, 2 studs de perna) com folga.
	Movement_Ground_Probe = 3.5,

	-- Intervalo mínimo (s) entre dois warns de correção do mesmo player.
	Movement_Warn_Interval = 1,
}
