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

	-- Forças proporcionais à massa (D7; F31, F32, F33). Com isto ligado, o orçamento padrão
	-- de uma Force Soft e a força de caminhada do NPC sem Humanoid saem de aceleração × massa
	-- do corpo (AssemblyMass): todo corpo responde igual, do dummy ao chefe. Antes eram
	-- números fixos (2500 e 2000): o chefe não andava e o vento não o movia. Os valores
	-- abaixo dão os números antigos num corpo de massa 10. Por entidade: MassScaling = false
	-- no config do Movement volta aos números fixos (chefe "pesado" de propósito). Um
	-- MaxForce declarado na Force continua absoluto; Hard continua Hard_Force_Strength.
	Force_Mass_Scaling = true,
	Soft_Force_Acceleration = 250, -- studs/s²
	-- Corpo com Humanoid (player e NPC do D8): o controlador do Humanoid segura a velocidade na da
	-- caminhada, e 250 não o vence (F32: 0,8 de ~20 studs). Varredura de 11/11 num corpo de massa
	-- 13,6: até 500 o vento não move; de 1000 em diante chega à velocidade pedida e andar contra o
	-- vento soma certo (30 - 16 = 14). 2500 dá folga de 5× e o menor tremor (desvio 0,1 studs/s);
	-- é ~34000 nesse corpo, perto do MaxForce 35000 que o ventilador já usava. O alvo continua
	-- sendo caminhada + Soft (D6): a força alta não tira o controle de quem anda no vento.
	Humanoid_Soft_Force_Acceleration = 2500, -- studs/s²
	NPC_Walk_Acceleration = 200,   -- studs/s²
	NPC_Walk_Force = 2000,         -- força fixa de caminhada quando MassScaling = false


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

	-- Atraso (s) com que o servidor vê um corpo simulado pelo cliente, sem contar o ping (medido
	-- em 11/11 no Studio: ~0,35 s). Base do NetworkView, que prevê onde o corpo está de verdade.
	-- As janelas do AntiCheat acima são tolerâncias, com outro papel: não derive uma da outra.
	Client_View_Lag = 0.35,
	-- Quanto do GetNetworkPing (ida e volta) entra no atraso de visão: 0,5 = um sentido.
	Client_View_Ping_Factor = 0.5,
	-- Margem (studs) da busca de candidatos de uma zona para corpos de cliente: cobre o quanto
	-- um corpo anda durante o atraso (100 studs/s × 0,4 s)
	Zone_Prediction_Margin = 40,
}
