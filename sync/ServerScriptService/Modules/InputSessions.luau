local InputSessions = {}

local sessions = {}

function InputSessions.GetSession(player: Player)
	local session = sessions[player]
	if not session then
		session = { resolvers = {}, lastPress = {}, lastMove = 0 }
		sessions[player] = session
	end
	return session
end

function InputSessions.CancelActiveGestures(player: Player, isRemoving: boolean)
	local session = sessions[player]
	if not session then return end
	local now = os.clock()
	for _, resolver in pairs(session.resolvers) do
		resolver:Cancel(now, isRemoving)
	end
	if isRemoving then
		sessions[player] = nil
	end
end

return InputSessions
