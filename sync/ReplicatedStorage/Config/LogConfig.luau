--[[
	LogConfig — quanto do framework aparece no Output (F64, regra 18). Configuração do JOGO: troque
	aqui. Vale para servidor e cliente.

	Níveis, do mais verboso ao mais quieto: Debug < Info < Warn < Error < Off
	- Debug: rotina do motor (entidade criada, componente registrado, efeito tocado)
	- Info: eventos que valem ver em teste (AntiCheat iniciado, movimento corrigido)
	- Warn: algo configurado errado ou que falhou e foi contornado
	- Error: falha que interrompeu uma ação

	Channels sobrescreve o nível por canal (o nome entre colchetes na mensagem), ex.:
		Channels = { DataManager = "Debug", VFXPlayer = "Off" }
	Em runtime: require(ReplicatedStorage.Logger).SetLevel("Debug" [, "Canal"]).
]]

return {
	Level = "Info",
	Channels = {},
}