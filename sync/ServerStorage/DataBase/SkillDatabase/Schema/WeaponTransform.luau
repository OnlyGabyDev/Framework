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
            -- A troca acontece no fim da transformação, não no 1º frame: com duration = 0 a janela
            -- de cancelamento era de 1 frame, embora o NoControl durasse TransformTime (F81)
            self.runtimeDuration = nextModeData.TransformTime or 0
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
        end,

        -- onEnd roda em qualquer fim (F54): limpa sempre, mas só troca de modo se a
        -- transformação não foi cancelada (antes um Stun no meio trocava o modo mesmo assim).
        onEnd = function(self, ctx)
            if self.stateID then
                self.Entity.RemoveStatusByID(self.stateID)
                self.stateID = nil
            end
            self.Entity.RemoveActionState(self.Runner)

            -- Só troca de modo se a transformação chegou ao fim (cancelamento, erro e desistência não trocam)
            if not self.pendingMode or ctx.reason ~= self.statusTable.Enum.EndReasons.Duration then return end
            local weaponComp = self.Entity:GetComponent(self.Entity.ComponentKey.Weapon)
            weaponComp:SetMode(self.pendingMode)

            local nextModeData = weaponComp:GetModeData()
            if nextModeData and nextModeData.Loadout then
                self.Entity.ApplyLoadout(nextModeData.Loadout)
            end
        end,
    }
}

return Skill
