local machine = {}

machine.new = function(options)
	local StateMachine = {}
	options = options or {}

	StateMachine.WaitTime = options.WaitTime or 0.2
	StateMachine.InitialDelay = options.InitialDelay or 0
	StateMachine.CurrentState = nil
	StateMachine.HasStarted = false

	StateMachine.SwitchState = function(newState)
		if StateMachine.CurrentState then
			StateMachine.CurrentState.Stop()
		end

		StateMachine.CurrentState = newState

		if newState then
			newState.Start()
		end
	end

	StateMachine.NewState = function()
		local state = {}
		state.Name = ""
		state.Conditions = {}
		state.isRunning = false
		state.Action = function() end
		state.Init = function() end

		state.Run = function()
			state.isRunning = true
			-- Stagger only the first update for this brain. Later state changes
			-- remain immediate instead of adding delay to each transition.
			if not StateMachine.HasStarted then
				StateMachine.HasStarted = true
				task.wait(StateMachine.InitialDelay)
				if not state.isRunning then return end
			end

			while state.isRunning do
				for _, condition in pairs(state.Conditions) do
					if condition.Evaluate() then
						StateMachine.SwitchState(condition.TransitionState)
						return
					end
				end

				state.Action()
				task.wait(StateMachine.WaitTime)
			end
		end

		state.Start = function()
			state.Init()
			task.spawn(state.Run)
		end

		state.Stop = function()
			state.isRunning = false
		end

		return state
	end

	StateMachine.NewCondition = function()
		local condition = {}
		condition.Name = ""
		condition.Evaluate = function()
			return false
		end
		condition.TransitionState = {}
		return condition
	end

	return StateMachine
end

return machine
