--[[

====================DOCUMENTAÇÃO==============================



---ESTRUTURA:---

-/Base/
 Pasta sem utilidade atual, comunica a forma do personagem, caso tenham futuras formas elas devem ser criadas na mesma camada que Base

-/DATA/
 Contém apenas os dados básicos do personagem e suas formas
 
 -/Script/
  Lógica e dados das skills
  
 -/Skills/
  Nome das skills, a váriavel encarregada de guardar esses valores deve ser nomeada com o nome da forma, como por exemplo Base
  
 -/BaseSkills/
 Informações/ações básicas que tendem a ser repetidas com frequência, como o comando básico de dash ou criação de hitboxes, a ideia é manter o mais básico com muitos parametros pra facil reutilização
 
 
 
 !IMPORTANTE!
 O NOME DAS SKILLS NOS SCRIPTS (DATA E LOGIC) DEVE SER O MESMO NOME APRESENTADO NOS DADOS PRESENTES EM SKILLS, O SISTEM BUSCA OS DADOS POR NOME.


--- CRIAÇÃO DE SKILLS ---

 - ESTRUTURA DE VÁRIAVEIS:
 
 data = {
 cooldown: número
 
 anim: string (nome da animação)
 }

- ESTRUTURA DE FUNÇÕES:

 callbacks = {
 
 onStart = function(self)
 onStep = function(self, dt)
 onEnd = function(self)
 
 }
 
 
  - TAGS:
  
  --Tags são utilizadas pra marcar o que a skill pode ignorar, como por exemplo iFrame, block, ragdoll e afins, essa tabela se encontra no StatusTable, onde também temos o que ignora qual efeito
  Devem ser aplicadas no Data da skill como uma tabela, ex: Tags = {Table.TrueHit, Table.BlockBreak}
  Table seria o caminho pra StateTable, onde as tags estão soltas fora da função pra facilitar acesso
  
  
  
  - Boas Práticas/Convenções:
  	Caso um pacote de funções precise ser chamado de forma recorrente durante os eventos da skill, recomenda-se criar funções locais no inicio da tabela de callbacks, com a devida documentação por exemplo:
  	
  	callbacks = {
  	
  	# LOCAL UTILS
  	
  	clearControl = function(animID,animFadeOut,statusID)
  		self.anim:Stop(param1,param2)
		self.cd:RemoveID(param3)
	end,
  	
  	#EVENTOS
  	
  	onStart = function(self)...
  	
  	}

	Dessa forma o código fica mais fácil de debugar, mais fácil de ler e mais fácil de manter.
	
  
  - APLICAÇÃO DE EFEITOS:
  
  --A criação de novos efeitos deve ser feita no StatusTable seguindo o padrão dos efeitos já existentes e da documentação presente no script, efeitos são lidos como skills pelo SkillRunner, então pode (e deve) utilizar eventos
  
  --Para aplicar efeitos, de dentro de uma skill: self:ApplyStatus(status, { Target = alvo, Duration = s, ID = id? })
  --(o runner vira o Source); fora de skill: entidade.ApplyStatus(status, { Duration = s, Source = runner?, ID = id? }).
  --Devolve o ID; remova com entidade.RemoveStatusByID(id).
  
  --É uma boa prática tratar efeitos com IDs e só fazer a remoção também por IDs, assim evita que skills cruzem o mesmo dado e tentem acessar o mesmo status
  --Isso também da o poder de controlar se uma skill pode apagar vários status/estados de uma vez, ou apenas alguns especificos, dando mais controle geral pra criação
  
  
  - INTERAÇÃO COM QUEM FOR ATINGIDO:
  
  --Para causar dano (geralmente no onHit da skill), use o runner como fonte:
  
	 local ok, dano = self:Damage(alvo, quantidade)
	 vai retornar ok = true se o hit conectou (passou por imunidade, bloqueio e proteções de stat). A partir daqui:
	 
	 if ok then
	 	self:ApplyStatus(Status, { Target = alvo, Duration = 2 })
	 end
	 
	 Efeitos que acompanham o hit vão em data.effects da skill (ver "Sistemas de 08/11" no fim deste DOC).
  
  
  

--- DADOS NECESSÁRIOS PARA O SKILLRUNNER MANEJAR A SKILL ---

 -É OBRIGATÓRIO TER, PODE TER VALOR 0 OU NIL-

 DURAÇÃO

 CAST TIME

 COOLDOWN


--- EVENTOS/FUNÇÕES (NÃO OBRIGATÓRIOS, PODEM NÃO SER DECLARADOS) ---

 onStart = É CHAMADO NA ATIVAÇÃO DA SKILL

 onStep = É CHAMADO A CADA DT (FRAME)

 onHit = É CHAMADO AO CONTATO COM ALGO

 onEnd = É CHAMADO QUANDO A SKILL ACABA

 onCancel = É CHAMADO QUANDO FOR CANCELADO

 onRecast = É CHAMADO QUANDO O BOTÃO FOR PRESSIONADO NOVAMENTE



--- CRIAÇÃO DE NOVOS EVENTOS ---

Adicionar a checagem para esse evento no SkillRunner conforme necessitado, podendo criar novas funções no mesmo desde que documentadas e realmente necessárias
Criar resposta a fallback no SkillFactory (ServerScriptService > Modules > SkillFactory)

utilizar: evento = function() end

evitando assim erros de nil e a necessidade de declarar todas as funções/eventos na hora de criar uma nova skill, pois o SkillHandler já trata esses casos chamando o factory antes do envio ao runner



--- ADIÇÃO DE NOVAS ARMAS ---

O método padrão de criação de armas:

Part principal (modelo da arma)

Handle (Part localizada onde o char deve segurar a arma, utilizar como marcador)

Handle > WeldConstraint (um pra cada parte principal do modelo), linkada ao modelo original

Motor6D (Linkar a Handle com a parte do char que irá segurar a arma) usado pra alterar os valores que vão ser utilizados na criação do Motor6D via script, ao finalizar de posicionar o modelo com o motor
guarde os valores no CFrameValue e o nome da parte em uma StringValue com o nome de AttachTo, o motor6D pode ser apagado após.

CFrameValue armazena as informações de localização do modelo (referente ao ponto de ancoragem) encontrado no Motor6D


hitOrigin é uma parte obrigatória pra todas as armas, ela informa o ponto de origem das hitboxes que vão se criadas futuramente a partir da arma


O nome do modelo da arma que o player ira utilizar deve estar referenciado como "weapon" (valor em string), no base dos personagens





- Prioridade de membro dominante para attach - 

O membro dominante para utilização da arma tem a seguinte prioridade de busca: arma > char > padrão (braço direito)
utilizamos essa estrutura pra permitir criação de armas com comportamento especificos, como troca de dual wield pra single hand, ou armas de fogo de dual wield, ou qualquer outro comportamento especifico

A declaração desses valores devem ser feitos da seguinte forma
Arma: StrinValue com o nome de AttachTo
Personagem: Váriavel no arquivo base com o nome de "AttachPriority" e o valor sendo uma string


Caso tenha alguma dúvida se refira a seção de refêrencias!



 --- CRIAÇÃO DE HITBOX ---
 
 Local de armazenamento:
 
ServerStorage > Assets > Hitboxes > Char > Nome da skill (se tiver variações pode criar subpastas com as variações, o processo de busca da hitbox não é automático e a mesma deve ser chamada internamente na skill)

Padrão de nomes: Raycast
				 Blockcast
				 Spherecast
				 
padrão de textura/cor: 
Bright Red
transparencia 0.75
				 
Esses nomes devem estar de acordo com o tipo de hitbox, facilitando assim a troca e teste de hitboxes sem precisar reescrever funções (o CD já é responsável de criar a hitbox do jeito certo baseado no nome)




--- ARQUITETURA ---

-Cliente-

InputHandler recebe o input do usuário e envia a informação ao server (passando qual o index/número da skill é referente ao botão pressionado)



-Server-

InputValidator recebe a intent (Intents.Id) e chama SkillHandler.HandleIntent, que pega a skill do slot no loadout
(CombatComponent: camadas Base + modo, montadas a partir do CharacterDatabase e do SkillDatabase)

Salva o Script da skill encontrado em:                                                      > Script > [Nome da skill]


Checa pelo nome da skill no EntityData, validando o request de cast (checando cooldowns e afins)

Se receber o OK pro cast, então envia pro SkillRunner e comunica o cooldown obtido em Data para o ED (Temp Player Data)

SkillRunner está responsável somente de ler e executar as informações da skill, mantendo alto nível de modularidade e separação de responsabilidade


RESUMO:

InputHandler recebe request do cliente

SkillHandler confere o que o cliente pediu, faz a validação, com OK envia o script pro SkillRunner

SkillRunner SÓ RODA A HABILIDADE, não sabe e nem deve saber de nehnuma informação externa, no máximo tentando confirmar se a skill tem scripts de eventos como onHit


# Referecias:

Criação de armas: https://www.youtube.com/watch?v=TB5maVsu5V0






EXEMPLIFICAÇÃO DE ARMA COM DIFERENTES MODOS DE USO!!


return {
	BaseName = "HunterBlades",
	DefaultMode = "Dual",

	Modes = {
		Dual = {
			AttachPoints = {
				primary = "Right Arm",
				secondary = "Left Arm"
			},
			AnimSet = "DualBlades",
			Skills = "DualSkills",  
			TransformTime = 0.5,
			TransformAnim = "MergeBlades"
		},

		Merged = {
			AttachPoints = {
				primary = "Right Arm"
			},
			AnimSet = "MergedBlade",
			Skills = "MergedSkills",
			TransformTime = 0.5,
			TransformAnim = "SplitBlades"
		}
	}
}









DADOS DE SKILLS:
data{

tags (table)
type (table)

}



Traits: comportamentos especiais e/ou indicativos pro sistema (como DOT, que não tem comportamento especial mas é importante pra permitir spellShields de DOT)

type: tipo da habilidade, conta como skill apenas? skill e efeito? pode ser ambos ou só um, caso não fornecido é injetado pelo runner.

tags: dados binarios que podem ter bypasses como CanMove, CanCast, Block, iFrame


=======================IMPORTANTE!========================

Cadeias (dano -> status -> dano, reflexo de parry, explosão em cadeia) têm limite no motor (F62),
declarado em StateTable.Enum.ChainLimits:
1 - Na mesma pilha, acima de MAX_RECURSION (50) níveis, a ação vai para uma fila e roda no próximo
frame (TakeDamage devolve false, "Deferred"; ApplyStatus devolve nil). A cadeia longa e finita
termina inteira (80 alvos em linha: 2 frames).
2 - Cada vez que uma ação adiada adia outra, conta uma geração. Acima de maxDeferrals (20) a ação é
recusada com aviso: o ping-pong infinito de dois reflexos para aí (~1000 reflexos, um lote por frame).
3 - Runner que cria runner (task.defer, status que aplica status): no máximo maxLiveRunnersPerRoot
(256) vivos ao mesmo tempo sob a mesma raiz da Lineage. Cadeia linear não tem limite (um status que
se renova é legítimo); a árvore que dobra a cada geração para na largura.
Para um reflexo que não deve adiar, quebre a cadeia você mesmo (delay, ou um status de imunidade).


SECONDARY TYPE são tabelas de tipos pra permitir modificações de tipo em runTime, NÃO CONFUNDIR COM TYPE, uma vez que type dita como o sistema lidara com aquela skill

qualquer modificação futura de tags que alterem comportamento, como uma nova trait de "instaCast" que ignora silence, devem ser checadas no CanContinue do CombatComponent

=======================SISTEMAS DE 08/11/2026========================
Cada sistema tem um dono único (regra 17): leia o cabeçalho do arquivo indicado antes de usar.

COOLDOWN (ServerScriptService.Modules.CooldownPolicy): a skill declara cooldown e, opcional,
cooldownPolicy = { start = Cast|End|Manual, recast = Blocked|Restart|Free|segundos, refund = {motivo = 0..1},
charges = n, ignoreReduction = bool, maxReduction = 0..1 }. Skill com onRecast precisa declarar recast.
Na skill: self:Fizzle() (desiste, devolve o cooldown), self:CommitCooldown() (start = Manual).
Redução: stat CooldownReduction. Herança (skill roubada): CooldownPolicy.Transfer(de, para, nome, "Copy"|"Move").

BLOQUEIO (StateTable.ResolveBlock): quem tem a tag block declara data.block = { mode = Full|Flat|Percent|Custom,
value = n }. Sem block e sem onTrigger não bloqueia (e avisa). Custom exige onTrigger.

EFEITOS ON-HIT (StateTable.ResolveEffect): data.effects = { status, { status = X, onBlocked = bool, onZeroDamage = bool } }.
Padrão em Enum.EffectDefaults (bloqueado não aplica; 0 de dano aplica); a skill sobrescreve em data.effectPolicy.

DANO (StateTable.MitigateDamage): DamageMult do atacante, depois as proteções do alvo em Enum.DamageMitigation
(Defense multiplicativa, Armor subtrativa). A trait TrueDamage fura.

LOADOUT (CombatComponent): camadas. ApplyLoadout(dados, camada?) troca só a camada (padrão Base);
Slots[slot] = false esvazia; RemoveLoadoutLayer(camada). O modo da arma usa a camada WeaponMode.

HITBOX DA ARMA: cada skill usa a sua: self:StartHitbox(duração) / self:StopHitbox(); o acerto vai só para ela.

SKILL PORTÁVEL (F55): data.kit = kit dono da skill (o CombatComponent carimba a pasta do SkillDatabase,
ex. "Schema"; skill feita em código pode declarar). self.charLib lê o conjunto de animações do kit dono
e, na falta, do kit de quem casta (AnimationLib.ForSkill): o M1 da Schema roubado toca as animações da
Schema em qualquer corpo. data.requires = { ComponentKey.Animation, ... } (ServerScriptService.EntityData.
ComponentsExport): sem esses componentes o runner é recusado antes de qualquer callback (aviso uma vez,
cooldown devolvido pelo motivo refused), em vez de errar no meio do onStart.

CRÉDITO DE MORTE (StateTable.EffectOwner): o OUT.OnDeath vai para o DONO do que matou. Um status (DOT,
reflexo) roda no portador, mas o dono é quem o aplicou (sobe runner.Source até a skill). A morte por
Bleed credita quem aplicou o Bleed, não a vítima.

OUT.OnDamage (D3, F101): emitido pelo HealthComponent no dono do dano (context.ownerEntity) em TODO dano,
direto (skill) e indireto (DOT, reflexo, área de status), com as traits do efeito no contexto. Quem não
quer DOT filtra: Listen({ Role = OUT, Breakpoint = OnDamage, Query = { None = { Traits.DOT } } }).
context.sourceEntity segue sendo onde o runner de origem roda (num DOT, a própria vítima).

EVENTOS DO HEALTH (F99): Events = { onDamage, onHeal, onDeath, onRevive } no config são do lado de quem
apanha; onDamage é o IN.PostDamage.

LIMITES DE STAT (F100): Enum.StatLimits (padrão Enum.StatLimitDefault: mínimo 0) vale para o valor final
do GetStat, com ou sem modificador. Defense pode ficar negativa (amplifica, D1).

AGARRÃO RÍGIDO (F103): entity.AttachTo(peçaDoLíder, offsetCFrame) devolve release(). O corpo vira parte do
assembly do líder (WeldConstraint) e anda com ele sem atraso, também quando o líder é um player; Forces e
caminhada do preso ficam suspensas, o Humanoid em PlatformStand e as peças sem massa. Detach()/GetAttachment().
FollowTarget (Force) persegue com elasticidade; AttachTo carrega. A Ultimate da Schema usa AttachTo.

CORPO DE CLIENTE (F104): o servidor vê o corpo do player ~0,35 s atrasado (Physics/NetworkView, Settings.
Client_View_Lag). Decisão de posição do servidor sobre corpo de cliente usa NetworkView.PredictedShift(root);
o AreaEffect já faz isso (a zona solta o vento quando o player sai de verdade).

ALVO E TIME (F105): componente Affiliation { Team = ... }. StateTable.Relation(a, b) = Self/Ally/Enemy/Neutral;
a hitbox da arma só entrega à skill os alvos que data.affects permite (padrão Enum.AffectsDefaults: inimigo e
neutro). Zona de skill: area:SetFilter(StateTable.AffectsFilter(runner)). Damage/ApplyStatus direto não filtram.

SEM PERSONAGEM (F106): Combat = { ChosenChar = false } cria a entidade sem personagem (sem loadout do banco e sem
aviso); o padrão do jogo é Enum.CombatDefaults.ChosenChar.

INSCRIÇÕES (Listen): Owner por entidade com StateTable.OwnerToken(entidade, "tag"), nunca string.

FORÇAS: Soft e caminhada do NPC proporcionais à massa (Physics/Settings: Force_Mass_Scaling); MassScaling = false
no config do Movement desliga por entidade. FollowTarget com feed-forward (MovementComponent, formato da Force).

LOG: require(ReplicatedStorage.Logger).Channel("Canal").Debug/Info/Warn/Error/WarnOnce; nível em
ReplicatedStorage.Config.LogConfig.

TESTES: Tests/IntegrationTests roda no Play (resultado em workspace:GetAttribute("FW_TestSummary"));
Tests/StaticChecks roda no modo Edit: require(Tests.StaticChecks)().
]]
