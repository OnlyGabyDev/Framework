local Skill = {
    data = { cooldown = 0.2, duration = 0, castTime = 0, name = "WeaponTransform" },
    callbacks = {
        onStart = function(self)
            local weaponComp = self.Entity:GetComponent(self.Entity.ComponentKey.Weapon)
            if not weaponComp then self:Stop(false); return end

            local currentMode = weaponComp:GetCurrentMode()
            local weaponData = weaponComp:GetWeaponData()
            if not weaponData or not weaponData.Modes then self:Stop(false); return end

            local nextMode = (currentMode == "Dual") and "Merged" or "Dual"
            local nextModeData = weaponData.Modes[nextMode]
            if not nextModeData then self:Stop(false); return end

            local statsTable = self.statusTable
            self.stateID = self.Entity.ApplyStatus(statsTable.States.NoControl, nextModeData.TransformTime, self.Runner)
            self.Entity.SetActionState(statsTable.ActionStates.Self.selfCast, self.Runner)

            -- Resolve a animação usando o AnimSet e TransformAnim da config, se existirem na charLib
            local animId = nil
            if self.charLib and nextModeData.AnimSet and self.charLib[nextModeData.AnimSet] then
                animId = self.charLib[nextModeData.AnimSet][nextModeData.TransformAnim]
            end

            if self.Entity.PlayAnimation and animId then
                self.track = self.Entity.PlayAnimation(animId)
            end

            self.pendingMode = nextMode

            self.cleanUp = function()
                if self.stateID then
                    self.Entity.RemoveStatusByID(self.stateID)
                    self.stateID = nil
                end
                self.Entity.RemoveActionState(self.Runner)
            end
        end,

        onEnd = function(self)
            if not self.pendingMode then return end
            local weaponComp = self.Entity:GetComponent(self.Entity.ComponentKey.Weapon)
            weaponComp:SetMode(self.pendingMode)

            local nextModeData = weaponComp:GetModeData()
            if nextModeData and nextModeData.Loadout then
                self.Entity.ApplyLoadout(nextModeData.Loadout)
            end

            if self.cleanUp then self.cleanUp() end
        end,

        onCancel = function(self)
            if self.cleanUp then self.cleanUp() end
        end,
    }
}

return Skill
