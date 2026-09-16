local  ModifierController = {}


local modData = {
	tags = "tags",
	func = "function",
	method = "method"
}


function ModifierController.new()
	local self = setmetatable({}, ModifierController)
	
	self.tags = {}
	self.queue = {{{}}} --0: Breakpoint, 1: Dicionario (pra privatização), 2: lista de ordem, 3: lista com os modificadores (ponto interno)
	self.passives = {}
	self.modifier = {}
	self.method = nil
	
	return self
end


function ModifierController:ApplyModifier (data) --Precisa buscar: função, tag, método (sequencial ou não)
	
	self.tag = data.tags or "*"
	
	if not table.find(data.tags) then --Se a tag já não estiver na tabela, então:
		table.insert(self.tags,self.tag)
	end
		
		
	if not self.method then --Se eu não tiver um método padrão declarado
		
		if data.method then --E se a skill também não tiver um override de método
			self.queue[data.breakpoint][self.tag][#self.queue] = data.func --insere no ultimo index da fila de modifiers a função
			return --finaliza a função
		end
		
		table.insert(self.queue[data.breakpoint][self.tag], data.func) --Cria uma nova camada de lista pra guardar os modifiers (sequential) caso não tenha um método
		
	end	
	
	
end

function ModifierController:HitBreakpoint(data)
end


function ModifierController:RunModifiers()
	
end


function ModifierController:RunPassives()

end



return ModifierController
