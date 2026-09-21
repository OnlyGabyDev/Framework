--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Solver = { Solvers = {} }

function Solver:Cast(segment: Types.Segment, raycastParams: RaycastParams?): RaycastResult?
	local direction: Vector3 = Solver.Solvers[segment.Instance.ClassName]:ToDirection(segment)
	local lastCFrame: CFrame? = segment.CastData._LastCFrameBlockCast

	local result: RaycastResult = workspace:Blockcast(
		(lastCFrame or segment.Instance.WorldCFrame) * segment.CastData.CFrame,
		segment.CastData.Size,
		direction,
		raycastParams
	)

	-- Removed task.defer as it caused the LastCFrame to not persist properly, leading to tunneling
	segment.CastData._LastCFrameBlockCast = segment.Instance.WorldCFrame

	return result, direction
end

return Solver
