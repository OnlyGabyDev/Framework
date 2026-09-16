local AnimationController = {}
AnimationController.__index = AnimationController

function AnimationController.new(animator)
	assert(animator and animator:IsA("Animator"), "Animator inválido")

	local self = setmetatable({}, AnimationController)
	self.Animator = animator
	self.Tracks = {} -- [string] = AnimationTrack
	return self
end

function AnimationController:Play(rawid, key, fadeTime, weight)
	local id = tostring(rawid)

	if self.Tracks[key] then
		self.Tracks[key]:Stop(fadeTime or 0.1)
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. id

	local track = self.Animator:LoadAnimation(anim)
	track:Play(fadeTime or 0.1)
	if weight then
		track:AdjustWeight(weight, fadeTime or 0.1)
	end

	self.Tracks[key or rawid] = track

	return track
end

function AnimationController:GetAnimMark(key, markerName)

	local track = self.Tracks[key]
	if track then
		return track:GetMarkerReachedSignal(markerName)
	end
end

function AnimationController:Stop(key, fadeTime)
	if self.Tracks[key] then
		self.Tracks[key]:Stop(fadeTime or 0.1)
		
		self.Tracks[key] = nil
	end
end

function AnimationController:StopAll(fadeTime)
	for key, track in pairs(self.Tracks) do
		if track then
			track:Stop(fadeTime or 0.1)
		end
	end
	self.Tracks = {}
end

function AnimationController:PlaySequence(sequence, index, loopInfo)
	index = index or 1
	local step = sequence[index]
	if not step then return end

	local track = self:Play(step.id, step.key, step.fade or 0.1, step.weight)

	local next = function()
		-- Se tiver info de loop e o index atual está dentro do range
		if loopInfo and index >= loopInfo.from and index <= loopInfo.to then
			loopInfo.counter += 1
			if loopInfo.counter < loopInfo.count * (loopInfo.to - loopInfo.from + 1) then
				local nextIndex = index + 1
				if nextIndex > loopInfo.to then
					nextIndex = loopInfo.from
				end
				self:PlaySequence(sequence, nextIndex, loopInfo)
				return
			end
		end
		self:PlaySequence(sequence, index + 1)
	end

	if step.marker then
		local signal = track:GetMarkerReachedSignal(step.marker)
		signal:Connect(next)
	elseif step.delay then
		task.delay(step.delay, next)
	else
		track.Stopped:Connect(next)
	end
end



return AnimationController
