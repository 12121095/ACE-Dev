-- init.lua

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include("shared.lua")

local EngineTable = ACF.Weapons.Engines

do

	local EngineWireDescs = {
		--Inputs
		["Throttle"]		= "Controls the amount of fuel which will be displaced to the engine.\n Increasing it will also increase RPM, Power and fuel consumption. Values go from 0-100.",

		--Outputs
		["RPM"]			= "Returns the current RPM.",
		["Torque"]		= "Returns the current Torque.",
		["Power"]		= "Returns the current power of this engine.",
		["Fuel Use"]		= "Gives the actual fuel consumption of the engine.",
		["EngineHeat"]	= "Returns the engine's temperature."
	}

	function ENT:Initialize()

		self.Throttle	= 0
		self.Active		= false
		self.IsMaster	= true
		self.GearLink	= {} -- a "Link" has these components: Ent, Rope, RopeLen, ReqTq
		self.FuelLink	= {}

		self.NextUpdate	= 0
		self.LastThink	= 0
		self.MassRatio	= 1
		self.FuelTank	= 0
		self.Heat		= ACE.AmbientTemp
		self.TotalFuel	= 0
		self.Efficiency	= 1-(ACF.Efficiency[self.EngineType] or ACF.Efficiency["GenericPetrol"]) -- Energy not transformed into kinetic energy and instead into thermal
		self.Legal		= true
		self.CanUpdate	= true
		self.RequiresFuel	= false
		self.NextLegalCheck = ACF.CurTime + math.random(ACF.Legal.Min, ACF.Legal.Max) -- give any spawning issues time to iron themselves out
		self.Legal		= true
		self.LegalIssues	= ""
		self.LockOnActive	= false --used to turn on the engine in case of being lockdown by not legal
		self.CrewLink	= {}
		self.HasDriver	= 0

		self.LastDamageTime = CurTime()

		self.Inputs = Wire_CreateInputs( self, { "Active", "Throttle (" .. EngineWireDescs["Throttle"] .. ")" } ) --use fuel input?
		self.Outputs = WireLib.CreateSpecialOutputs( self,  { "RPM (" .. EngineWireDescs["RPM"] .. ")", "Torque (" .. EngineWireDescs["Torque"] .. ")", "Power (" .. EngineWireDescs["Power"] .. ")", "Fuel Use (" .. EngineWireDescs["Fuel Use"] .. ")", "Total Fuel" , "Entity", "Mass", "Physical Mass" , "EngineHeat (" .. EngineWireDescs["EngineHeat"] .. ")"},
														{ "NORMAL","NORMAL","NORMAL", "NORMAL", "NORMAL", "ENTITY", "NORMAL", "NORMAL", "NORMAL" } )

		Wire_TriggerOutput( self, "Entity", self )
		Wire_TriggerOutput(self, "EngineHeat", self.Heat)

		self.WireDebugName = "ACF Engine"

	end

end

do

	local BackComp = {
		["Induction motor, Tiny"]                 = "Electric-Tiny-NoBatt",
		["Induction motor, Small, Standalone"]    = "Electric-Small-NoBatt",
		["Induction motor, Medium, Standalone"]   = "Electric-Medium-NoBatt",
		["Induction motor, Large, Standalone"]    = "Electric-Large-NoBatt",

		["AVDS-1790-9A"]                          = "24.8-V12",
		["AVDS-1790-1500"]                        = "27.0-V12"
	}

	function MakeACF_Engine(Owner, Pos, Angle, Id)

		if not Owner:CheckLimit("_acf_misc") then return false end

		local Engine = ents.Create( "acf_engine" )
		if not IsValid( Engine ) then return false end

		if not ACE_CheckEngine( Id ) then
			Id = BackComp[Id] or "5.7-V8"
		end

		local Lookup = EngineTable[Id]

		Engine:SetAngles(Angle)
		Engine:SetPos(Pos)
		Engine:Spawn()
		Engine:CPPISetOwner(Owner)
		Engine.Id = Id

		Engine.Model            = Lookup.model
		Engine.Weight           = Lookup.weight
		Engine.PeakTorque       = Lookup.torque
		Engine.peakkw           = Lookup.peakpower
		Engine.PeakKwRPM        = Lookup.peakpowerrpm
		Engine.PeakTorqueHeld   = Lookup.torque
		Engine.IdleRPM          = Lookup.idlerpm
		Engine.PeakMinRPM       = Lookup.peakminrpm
		Engine.PeakMaxRPM       = Lookup.peakmaxrpm
		Engine.LimitRPM         = Lookup.limitrpm
		Engine.Inertia          = Lookup.flywheelmass * 3.1416 ^ 2
		Engine.iselec           = Lookup.iselec
		Engine.FlywheelOverride = Lookup.flywheeloverride
		Engine.IsTrans          = Lookup.istrans -- driveshaft outputs to the side
		Engine.FuelType         = Lookup.fuel or "Petrol"
		Engine.EngineType       = Lookup.enginetype or "GenericPetrol"
		Engine.TorqueCurve      = Lookup.torquecurve or ACF.GenericTorqueCurves[Engine.EngineType]
		Engine.RequiresFuel     = Lookup.requiresfuel
		Engine.SoundPath        = Lookup.sound
		Engine.DefaultSound     = Engine.SoundPath
		Engine.SoundPitch       = Lookup.pitch or 100
		Engine.SpecialHealth    = true
		Engine.SpecialDamage    = true
		Engine.TorqueMult       = 1
		Engine.FuelTank         = 0
		Engine.Heat             = ACE.AmbientTemp

		Engine.TorqueScale	= ACF.TorqueScale[Engine.EngineType]

		--calculate base fuel usage
		if Engine.EngineType == "Electric" then
			Engine.FuelUse = ACF.ElecRate / (ACF.Efficiency[Engine.EngineType] * 60 * 60) --elecs use current power output, not max
		else
			Engine.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[Engine.EngineType] * Engine.peakkw / (60 * 60)
		end

		Engine.FlyRPM = 0
		Engine:SetModel( Engine.Model )
		Engine.Sound = nil
		Engine.RPM = {}

		Engine:PhysicsInit( SOLID_VPHYSICS )
		Engine:SetMoveType( MOVETYPE_VPHYSICS )
		Engine:SetSolid( SOLID_VPHYSICS )

		Engine.Out = Engine:WorldToLocal(Engine:GetAttachment(Engine:LookupAttachment( "driveshaft" )).Pos)

		local phys = Engine:GetPhysicsObject()
		if IsValid( phys ) then
			phys:SetMass( Engine.Weight )
			Engine.ModelInertia = 0.99 * phys:GetInertia() / phys:GetMass() -- giving a little wiggle room
		end

		Engine:SetNWString( "WireName", Lookup.name )
		Engine:UpdateOverlayText()

		Owner:AddCount("_acf_misc", Engine)
		Owner:AddCleanup( "acfmenu", Engine )

		ACF_Activate( Engine, 0 )

		return Engine
	end
	list.Set( "ACFCvars", "acf_engine", {"id"} )
	duplicator.RegisterEntityClass("acf_engine", MakeACF_Engine, "Pos", "Angle", "Id")

end

function ENT:Update( ArgsTable )
	-- That table is the player data, as sorted in the ACFCvars above, with player who shot,
	-- and pos and angle of the tool trace inserted at the start

	if self.Active then
		return false, "Turn off the engine before updating it!"
	end

	local Id = ArgsTable[4] -- Argtable[4] is the engine ID
	local Lookup = EngineTable[Id]

	if Lookup.model ~= self.Model then
		return false, "The new engine must have the same model!"
	end

	local Feedback = ""
	if Lookup.fuel ~= self.FuelType then
		Feedback = " Fuel type changed, fuel tanks unlinked."
		for Key in pairs(self.FuelLink) do
			table.remove(self.FuelLink,Key)
			self:UpdateOverlayText()
			--need to remove from tank master?
		end
	end

	self.Id                = Id
	self.Weight            = Lookup.weight
	self.PeakTorque        = Lookup.torque
	self.peakkw            = Lookup.peakpower
	self.PeakKwRPM         = Lookup.peakpowerrpm
	self.PeakTorqueHeld    = Lookup.torque
	self.IdleRPM           = Lookup.idlerpm
	self.PeakMinRPM        = Lookup.peakminrpm
	self.PeakMaxRPM        = Lookup.peakmaxrpm
	self.LimitRPM          = Lookup.limitrpm
	self.Inertia           = Lookup.flywheelmass * 3.1416 ^ 2
	self.iselec            = Lookup.iselec -- is the engine electric?
	self.FlywheelOverride  = Lookup.flywheeloverride -- modifies rpm drag on iselec==true
	self.IsTrans           = Lookup.istrans
	self.FuelType          = Lookup.fuel
	self.EngineType        = Lookup.enginetype
	self.RequiresFuel      = Lookup.requiresfuel
	self.SoundPath         = Lookup.sound
	self.DefaultSound      = self.SoundPath
	self.SoundPitch        = Lookup.pitch or 100
	self.SpecialHealth     = true
	self.SpecialDamage     = true
	self.TorqueMult        = self.TorqueMult or 1
	self.FuelTank          = 0

	self.TorqueScale		= ACF.TorqueScale[self.EngineType]

	--calculate base fuel usage
	if self.EngineType == "Electric" then
		self.FuelUse = ACF.ElecRate / (ACF.Efficiency[self.EngineType] * 60 * 60) --elecs use current power output, not max
	else
		self.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[self.EngineType] * self.peakkw / (60 * 60)
	end

	self:SetModel( self.Model )
	self:SetSolid( SOLID_VPHYSICS )
	self.Out = self:WorldToLocal(self:GetAttachment(self:LookupAttachment( "driveshaft" )).Pos)

	local phys = self:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetMass( self.Weight )
	end

	self:SetNWString( "WireName", Lookup.name )
	self:UpdateOverlayText()

	ACF_Activate( self, 1 )

	return true, "Engine updated successfully!" .. Feedback
end

function ENT:UpdateOverlayText()

	local pbmin = self.PeakMinRPM
	local pbmax = self.PeakMaxRPM

	local SpecialBoost = self.RequiresFuel and ACF.TorqueBoost or 1
	local text = "Power: " .. math.Round( self.peakkw * SpecialBoost ) .. " kW / " .. math.Round( self.peakkw * SpecialBoost * 1.34 ) .. " hp\n"
	text = text .. "Torque: " .. math.Round( self.PeakTorque * SpecialBoost ) .. " Nm / " .. math.Round( self.PeakTorque * SpecialBoost * 0.73 ) .. " ft-lb\n"
	text = text .. "Powerband: " .. (math.Round(pbmin / 10) * 10) .. " - " .. (math.Round(pbmax / 10) * 10) .. " RPM\n"
	text = text .. "Redline: " .. self.LimitRPM .. " RPM\n\n"
	text = text .. "Temp: " .. math.Round(self.Heat) .. " °C / " .. math.Round((self.Heat * (9 / 5)) + 32) .. " °F\n"

	if self.FuelLink and #self.FuelLink > 0 then
		text = text .. "\nSupplied with " .. (self.EngineType == "Electric" and "Batteries" or "fuel")
	end

	if self.HasDriver > 0 then
		text = text .. "\nDriver Provided"  --fuck yeah
	end

	if not self.Legal then
		text = text .. "\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACF.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )

end

function ENT:TriggerInput( iname, value )

	if (iname == "Throttle") then
		self.Throttle = math.Clamp(value,0,100) / 100
	elseif (iname == "Active") then
		if (value > 0 and not self.Active and self.Legal) then
			--make sure we have fuel
			local HasFuel
			if not self.RequiresFuel then
				HasFuel = true
			else
				for _,fueltank in pairs(self.FuelLink) do
					if fueltank.Fuel > 0 and fueltank.Active and fueltank.Legal then HasFuel = true break end
				end
			end

			if HasFuel then
				self.Active = true
				if self.SoundPath ~= "" then

					--stupid workaround for the engine sound. THANK YOU garry
					filter = RecipientFilter(true)
					filter:AddAllPlayers()

					self.Sound = CreateSound(self, self.SoundPath , filter)
					self.Sound:PlayEx(0.5,100)

				end
				self:ACFInit()
			end
		elseif (value <= 0 and self.Active) then
			self.Active = false
			self.FlyRPM = 0
			self.RPM = {}
			self.RPM[1] = self.IdleRPM
			if self.Sound then
				self.Sound:Stop()
			end
			self.Sound = nil
			Wire_TriggerOutput( self, "RPM", 0 )
			Wire_TriggerOutput( self, "Torque", 0 )
			Wire_TriggerOutput( self, "Power", 0 )
			Wire_TriggerOutput( self, "Fuel Use", 0 )
		end
	end
end

function ENT:ACF_Activate()
	--Density of steel = 7.8g cm3 so 7.8kg for a 1mx1m plate 1m thick
	local Entity = self
	Entity.ACF = Entity.ACF or {}

	local Count
	local PhysObj = Entity:GetPhysicsObject()
	if PhysObj:GetMesh() then Count = #PhysObj:GetMesh() end
	if PhysObj:IsValid() and Count and Count > 100 then

		if not Entity.ACF.Area then
			Entity.ACF.Area = (PhysObj:GetSurfaceArea() * 6.45) * 0.52505066107
		end

	else
		local Size = Entity.OBBMaxs(Entity) - Entity.OBBMins(Entity)
		if not Entity.ACF.Area then
			Entity.ACF.Area = ((Size.x * Size.y) + (Size.x * Size.z) + (Size.y * Size.z)) * 6.45
		end

	end

	Entity.ACF.Ductility = Entity.ACF.Ductility or 0

	local Area = Entity.ACF.Area
	local Armour = (Entity:GetPhysicsObject():GetMass() * 1000 / Area / 0.78)
	local Health = Area / ACF.Threshold

	local Percent = 1

	if Recalc and Entity.ACF.Health and Entity.ACF.MaxHealth then
		Percent = Entity.ACF.Health / Entity.ACF.MaxHealth
	end

	Entity.ACF.Health = Health * Percent * ACF.EngineHPMult[self.EngineType]
	Entity.ACF.MaxHealth = Health * ACF.EngineHPMult[self.EngineType]
	Entity.ACF.Armour = Armour * (0.5 + Percent / 2)
	Entity.ACF.MaxArmour = Armour * ACF.ArmorMod
	Entity.ACF.Type = nil
	Entity.ACF.Mass = PhysObj:GetMass()
	--Entity.ACF.Density = (PhysObj:GetMass() * 1000)/Entity.ACF.Volume

	Entity.ACF.Type = "Prop"
	--print(Entity.ACF.Health)

	Entity.ACF.Material	= not isstring(Entity.ACF.Material) and ACE.BackCompMat[Entity.ACF.Material] or Entity.ACF.Material or "RHA"

end

function ENT:ACF_OnDamage( Entity, Energy, FrArea, Angle, Inflictor, _, Type )	--This function needs to return HitRes

	local Mul = (((Type == "HEAT" or Type == "THEAT" or Type == "HEATFS" or Type == "THEATFS") and ACF.HEATMulEngine) or 1) --Heat penetrators deal bonus damage to engines
	local HitRes = ACF_PropDamage( Entity, Energy, FrArea * Mul, Angle, Inflictor ) --Calling the standard damage prop function

	return HitRes --This function needs to return HitRes
end

function ENT:IllegalCrewSeatRemove(crewEntities)
	for _, crewEnt in ipairs(crewEntities) do
		if not crewEnt.Legal then
			self:Unlink(crewEnt)
		end
	end
end

function ENT:Think()

	if ACF.CurTime > self.NextLegalCheck then
		self.Legal, self.LegalIssues = ACF_CheckLegal(self, self.Model, math.Round(self.Weight,2), self.ModelInertia, true, true)
		self.NextLegalCheck = ACF.Legal.NextCheck(self.legal)
		self:CheckRopes()
		self:CheckFuel()
		self:CalcMassRatio()

		self:UpdateOverlayText()
		self.NextUpdate = ACF.CurTime + 1

		self:IllegalCrewSeatRemove(self.CrewLink)

		if not self.Legal and self.Active then
			self:TriggerInput("Active",0) -- disable if not legal and active
			self.LockOnActive = true
		else
			--turn on the engine back as it was before the lockdown. IK that then engine could turn on when the user turned off by himself after of flagged illegal, i prefer that it turns on though
			if self.LockOnActive then
				self.LockOnActive = false
				self:TriggerInput("Active",1)
			end
		end
	end

	-- when not legal, update overlay displaying lockout and issues
	if not self.Legal and ACF.CurTime > self.NextUpdate then
		self:UpdateOverlayText()
		self.NextUpdate = ACF.CurTime + 1
	end

	self.Heat = ACE_HeatFromEngine( self )
	Wire_TriggerOutput(self, "EngineHeat", self.Heat)

	if ACF.CurTime > self.NextUpdate then

		self.TotalFuel = self:GetMaxFuel()
		Wire_TriggerOutput(self, "Total Fuel", self.TotalFuel)

		self:UpdateOverlayText()
		self.NextUpdate = ACF.CurTime + 0.5

	end

	if self.Active then
		self:CalcRPM()
	end

	self.LastThink = ACF.CurTime
	self:NextThink( ACF.CurTime )
	return true

end

-- specialized calcmassratio for engines
function ENT:CalcMassRatio()

	local Mass = 0
	local PhysMass = 0
	local Check = nil

	-- get the shit that is physically attached to the vehicle
	local PhysEnts = ACF_GetAllPhysicalConstraints( self )

	-- get the wheels directly connected to the drivetrain
	local Wheels = ACF_GetLinkedWheels(self)

	-- check if any wheels aren't in the physicalconstraint tree
	for _,Ent in pairs( Wheels ) do
		if not PhysEnts[Ent] then -- WE GOT EM BOIS
			Check = Ent
			Wheels[Ent] = nil -- manual removal, idk how table.remove would handle indexing by ent. probably not well. indexing by entity sucks, please use ent id.
			break
		end
	end

	-- if there's a wheel that's not in the engine constraint tree, use it as a start for getting physical constraints
	if IsValid(Check) then -- sneaky bastards trying to get away with remote engines...  NOT ANYMORE
		table.Merge(PhysEnts, Wheels) -- I mean, they'll still be remote... but they wont get free extra power from calcmass not seeing the contraption it's powering
		ACF_GetAllPhysicalConstraints( Check, PhysEnts ) -- no need for assignment here
	end

	-- add any parented but not constrained props you sneaky bastards
	local AllEnts = table.Copy( PhysEnts )
	for _, v in pairs( PhysEnts ) do
		table.Merge( AllEnts, ACF_GetAllChildren( v ) )
	end

	for _, v in pairs( AllEnts ) do

		if not IsValid( v ) then continue end

		local phys = v:GetPhysicsObject()
		if not IsValid( phys ) then continue end

		Mass = Mass + phys:GetMass()

		if PhysEnts[ v ] then
			PhysMass = PhysMass + phys:GetMass()
		end

	end

	--phys / parented
	--total: 6000 kgs
	--5000/1000 = 5 ratio
	--1000/5000 = 0.2 ratio
	--local Tmass = PhysMass + Mass

	self.MassRatio = PhysMass / Mass
	--self.MassRatio = 1 / (Tmass/10000)
	--self.MassRatio = (PhysMass ^ 0.9225) / Mass

	Wire_TriggerOutput( self, "Mass", math.Round( Mass, 2 ) )
	Wire_TriggerOutput( self, "Physical Mass", math.Round( PhysMass, 2 ) )

end

function ENT:ACFInit()

	self:CalcMassRatio()

	self.LastThink = CurTime()
	self.Torque = self.PeakTorque
	self.FlyRPM = self.IdleRPM * 1.5

end

function ENT:GetMaxFuel()

	local TFuel = 0

	for _, Tank in pairs(self.FuelLink) do
		if not IsValid(Tank) then continue end
		if not Tank.Active then continue end

		TFuel = TFuel + Tank.Fuel

	end

	return TFuel
end

function ENT:CalcRPM()

	local PhysObj = self:GetPhysicsObject()
	local DeltaTime = CurTime() - self.LastThink
	-- local AutoClutch = math.min(math.max(self.FlyRPM-self.IdleRPM,0)/(self.IdleRPM + self.LimitRPM/10),1)
	--local ClutchRatio = math.min(Clutch/math.max(TorqueDiff,0.05),1)

	--find next active tank with fuel
	local Tank = nil
	local boost = 1
	local MaxTanks = #self.FuelLink

	for i = 1, MaxTanks do
		Tank = self.FuelLink[self.FuelTank + 1]
		self.FuelTank = (self.FuelTank + 1) % MaxTanks
		if IsValid(Tank) and Tank.Fuel > 0 and Tank.Active and Tank.Legal then
			break --return Tank
		end
		Tank = nil
		i = i + 1
	end

	--calculate fuel usage
	if Tank then
		local Consumption
		if self.FuelType == "Electric" then
			Consumption = (self.Torque * self.FlyRPM / 9548.8) * self.FuelUse * DeltaTime
		else
			local Load = 0.3 + self.Throttle * 0.7
			Consumption = Load * self.FuelUse * (self.FlyRPM / self.PeakKwRPM) * DeltaTime / ACF.FuelDensity[Tank.FuelType]
		end
		Tank.Fuel = math.max(Tank.Fuel - Consumption,0)
		boost = ACF.TorqueBoost
		Wire_TriggerOutput(self, "Fuel Use", math.Round(60 * Consumption / DeltaTime,3))
	elseif self.RequiresFuel then
		self:TriggerInput( "Active", 0 ) --shut off if no fuel and requires it
		return 0
	else
		Wire_TriggerOutput(self, "Fuel Use", 0)
	end

	--adjusting performance based on damage
	self.TorqueMult = math.Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, self.TorqueScale, 1)
	self.PeakTorque = self.PeakTorqueHeld * self.TorqueMult * (1 + self.HasDriver * ACF.DriverTorqueBoost)

	-- Calculate the current torque from flywheel RPM
	local perc = math.Remap(self.FlyRPM, self.IdleRPM, self.LimitRPM, 0, 1)
	self.Torque = boost * self.Throttle * ACF_CalcCurve(self.TorqueCurve, perc) * self.PeakTorque * (self.FlyRPM < self.LimitRPM and 1 or 0)

	local Drag
	if self.iselec == true then
		Drag = self.PeakTorque * (math.max( self.FlyRPM - self.IdleRPM, 0) / self.FlywheelOverride) * (1 - self.Throttle) / self.Inertia
	else
		Drag = self.PeakTorque * (math.max( self.FlyRPM - self.IdleRPM, 0) / self.PeakMaxRPM) * ( 1 - self.Throttle) / self.Inertia
	end

	-- Let's accelerate the flywheel based on that torque
	self.FlyRPM = math.Clamp( self.FlyRPM + self.Torque / self.Inertia - Drag, 0 , self.LimitRPM )

	-- The gearboxes don't think on their own, it's the engine that calls them, to ensure consistent execution order
	local Boxes = table.Count( self.GearLink )

	local TotalReqTq = 0

	-- Get the requirements for torque for the gearboxes (Max clutch rating minus any wheels currently spinning faster than the Flywheel)
	for _, Link in pairs( self.GearLink ) do

		if not Link.Ent.Legal then continue end

		Link.ReqTq = Link.Ent:Calc( self.FlyRPM, self.Inertia )
		TotalReqTq = TotalReqTq + Link.ReqTq

	end

	-- This is the presently available torque from the engine
	local TorqueDiff = math.max( self.FlyRPM - self.IdleRPM, 0 ) * self.Inertia

	-- Calculate the ratio of total requested torque versus what's avaliable
	local AvailRatio = math.min( TorqueDiff / TotalReqTq / Boxes, 1 )

	-- Split the torque fairly between the gearboxes who need it
	for _, Link in pairs( self.GearLink ) do

		if not Link.Ent.Legal then continue end

		Link.Ent:Act( Link.ReqTq * AvailRatio * self.MassRatio, DeltaTime, self.MassRatio )

	end

	self.FlyRPM = self.FlyRPM - math.min( TorqueDiff, TotalReqTq ) / self.Inertia

	local Mass = PhysObj:GetMass()

	--print(self.Heat)

	self.Heat = ACE_HeatFromEngine( self )

	local HealthRatio = self.ACF.Health / self.ACF.MaxHealth

	if HealthRatio < 0.95 then
		if HealthRatio > 0.025 then
			HitRes = ACF_Damage(self, {
				Kinetic = (1 + math.max(Mass / 2, 20) / 2.5) / self.Throttle * 100,
				Momentum = 0,
				Penetration = (1 + math.max(Mass / 2, 20) / 2.5) / self.Throttle * 100
			}, 2, 0, self:CPPIGetOwner())
		else
			--Turns Off due to massive damage
			self:TriggerInput("Active", 0)
		end
	end

--  743.2 Estimate for engine material, 35% weight steel, 65% weight aluminum

	-- Then we calc a smoothed RPM value for the sound effects
	table.remove( self.RPM, 10 )
	table.insert( self.RPM, 1, self.FlyRPM )
	local SmoothRPM = 0
	for _, RPM in pairs( self.RPM ) do
		SmoothRPM = SmoothRPM + (RPM or 0)
	end
	SmoothRPM = SmoothRPM / 10

	local Power = self.Torque * SmoothRPM / 9548.8
	Wire_TriggerOutput(self, "Torque", math.Round(self.Torque))
	Wire_TriggerOutput(self, "Power", math.Round(Power))
	Wire_TriggerOutput(self, "RPM", math.Round(self.FlyRPM))
	--Wire_TriggerOutput(self, "EngineHeat", self.Heat) --Definately an RPM calculation

	if self.Sound then
		self.Sound:ChangePitch( math.min( 20 + (SmoothRPM * (self.SoundPitch / 100)) / 50, 255 ), 0 )
		self.Sound:ChangeVolume( 0.25 + (0.1 + 0.9 * ((SmoothRPM / self.LimitRPM) ^ 1.5)) * self.Throttle / 1.5, 0 )
	end

	return RPM
end

function ENT:CheckRopes()

	for _, Link in pairs( self.GearLink ) do

		local Ent = Link.Ent

		local OutPos = self:LocalToWorld( self.Out )
		local InPos = Ent:LocalToWorld( Ent.In )

		-- make sure it is not stretched too far
		if OutPos:Distance( InPos ) > Link.RopeLen * 1.5 then
			self:Unlink( Ent )
		end

		-- make sure the angle is not excessive
		if not self:Checkdriveshaft( Ent ) then
			self:Unlink( Ent )
			local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
			self:EmitSound(soundstr,500,100)
		end
	end
end

--unlink fuel tanks out of range
function ENT:CheckFuel()
	for _,tank in pairs(self.FuelLink) do
		if self:GetPos():Distance(tank:GetPos()) > 512 then
			self:Unlink( tank )
			local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
			self:EmitSound(soundstr,500,100)
			self:UpdateOverlayText()
		end
	end
end

do
	--[[
	--HARDCODED. USE MODELDEFINITION INSTEAD
	local TransAxialGearboxes = {
		["models/engines/transaxial_l.mdl"] = true,
		["models/engines/transaxial_m.mdl"] = true,
		["models/engines/transaxial_s.mdl"] = true,
		["models/engines/transaxial_t.mdl"] = true --mhm acf extras invading...
	}
	]]

	-- make sure the angle is not excessive
	function ENT:Checkdriveshaft( NextEnt )
		local InPos = NextEnt:LocalToWorld( NextEnt.In ) 	--gearbox to connect to engine
		local OutPos = self:LocalToWorld( self.Out ) 		--the engine output

		local MaxAngle = 0.7 --magic number to define the max tolerance of link between gearboxes
		local Direction = self.IsTrans and -self:GetRight() or self:GetForward() --transaxial like turbines. Forward is for conventional engines like a V8
		local DrvAngle 	= ( OutPos - InPos ):GetNormalized():Dot( Direction )

		--Check if the link is right from engine's perspective
		if DrvAngle < MaxAngle then
			return false
		--else
			--[[ --Disabled since this could break several builds. When we have more junctions, this could be enforced.
			--Now, do the same, but from gearbox's perspective this time.
			Direction 	= TransAxialGearboxes[ NextEnt:GetModel() ] and -NextEnt:GetForward() or -NextEnt:GetRight()
			DrvAngle 	= ( InPos - OutPos ):GetNormalized():Dot( Direction )

			if DrvAngle < MaxAngle then
				return false
			end
			]]
		end

		return true
	end

end

function ENT:Link( Target )

	if not IsValid( Target ) or (Target:GetClass() ~= "acf_gearbox" and Target:GetClass() ~= "acf_fueltank" and Target:GetClass() ~= "ace_crewseat_driver") then
		return false, "Can only link to gearboxes, fuel tanks, or driver crew seats!"
	end

	if Target:GetClass() == "acf_fueltank" then
		return self:LinkFuel( Target )
	end

	if Target:GetClass() == "ace_crewseat_driver" then

		if not Target.Legal then
			return false, "The driver seat is illegal!"
		end

		if self.HasDriver == 1 then
			return false, "The engine already has a driver!"
		end

		table.insert( self.CrewLink, Target )
		table.insert( Target.Master, self )

		Target.LinkedEngine = self
		self.HasDriver = 1
		self:UpdateOverlayText()

		return true, "Link successful!"
	end

	-- Check if target is already linked
	for _, Link in pairs( self.GearLink ) do
		if Link.Ent == Target then
			return false, "That is already linked to this engine!"
		end
	end

	-- make sure the angle is not excessive
	if not self:Checkdriveshaft( Target ) then
		return false, "Cannot link due to excessive driveshaft angle!"
	end

	local InPos = Target:LocalToWorld( Target.In ) 	--gearbox to connect to engine
	local OutPos = self:LocalToWorld( self.Out ) 	--the engine output

	local Rope = nil
	if self:CPPIGetOwner():GetInfoNum( "ACF_MobilityRopeLinks", 1) == 1 then
		Rope = ACE_CreateLinkRope( OutPos, self, self.Out, Target, Target.In )
	end

	local Link = {
		Ent 	= Target,
		Rope 	= Rope,
		RopeLen = ( OutPos - InPos ):Length(),
		ReqTq 	= 0
	}

	table.insert( self.GearLink, Link )
	table.insert( Target.Master, self )

	return true, "Link successful!"
end


function ENT:Unlink( Target )

	if Target:GetClass() == "acf_fueltank" then
		return self:UnlinkFuel( Target )
	end


	if Target:GetClass() == "ace_crewseat_driver" then

		self.HasDriver = 0
		self:UpdateOverlayText()


		for Key,Value in pairs(self.CrewLink) do
		if Value == Target then
			table.remove(self.CrewLink,Key)
			Success = true
			self.HasDriver = 0
			Target.LinkedEngine = nil
			return true, "Unlink successful!"
		end
	end

	end

	for Key, Link in pairs( self.GearLink ) do

		if Link.Ent == Target then

			-- Remove any old physical ropes leftover from dupes
			for _, Rope in pairs( constraint.FindConstraints( Link.Ent, "Rope" ) ) do
				if Rope.Ent1 == self or Rope.Ent2 == self then
					Rope.Constraint:Remove()
				end
			end

			if IsValid( Link.Rope ) then
				Link.Rope:Remove()
			end

			table.remove( self.GearLink,Key )

			return true, "Unlink successful!"

		end

	end

	return false, "That gearbox is not linked to this engine!"

end

function ENT:LinkFuel( Target )

	if not (self.FuelType == "Multifuel" and Target.FuelType ~= "Electric") and self.FuelType ~= Target.FuelType then
		return false, "Cannot link because fuel type is incompatible."
	end

	if Target.NoLinks then
		return false, "This fuel tank doesn\'t allow linking."
	end

	for _, Value in pairs(self.FuelLink) do
		if Value == Target then
			return false, "That fuel tank is already linked to this engine!"
		end
	end

	if self:GetPos():Distance( Target:GetPos() ) > 512 then
		return false, "Fuel tank is too far away."
	end

	table.insert( self.FuelLink, Target )
	table.insert( Target.Master, self )

	return true, "Link successful!"

end

function ENT:UnlinkFuel( Target )

	for Key, Value in pairs( self.FuelLink ) do
		if Value == Target then
			table.remove( self.FuelLink, Key )
			return true, "Unlink successful!"
		end
	end

	return false, "That fuel tank is not linked to this engine!"

end

function ENT:PreEntityCopy()

	--Link Saving
	local info = {}
	local entids = {}
	for Key, Link in pairs( self.GearLink ) do				--First clean the table of any invalid entities
		if not IsValid( Link.Ent ) then
			table.remove( self.GearLink, Key )
		end
	end
	for _, Link in pairs( self.GearLink ) do				--Then save it
		table.insert( entids, Link.Ent:EntIndex() )
	end

	info.entities = entids
	if info.entities then
		duplicator.StoreEntityModifier( self, "GearLink", info )
	end

	--fuel tank link saving
	local fuel_info = {}
	local fuel_entids = {}
	for _, Value in pairs(self.FuelLink) do				--First clean the table of any invalid entities
		if not Value:IsValid() then
			table.remove(self.FuelLink, Value)
		end
	end
	for _, Value in pairs(self.FuelLink) do				--Then save it
		table.insert(fuel_entids, Value:EntIndex())
	end

	fuel_info.entities = fuel_entids
	if fuel_info.entities then
		duplicator.StoreEntityModifier( self, "FuelLink", fuel_info )
	end

	--driver seat link saving
	for _, Value in pairs(self.CrewLink) do				--First clean the table of any invalid entities
		if not Value:IsValid() then
			table.remove(self.CrewLink, Value)
		end
	end
	for _, Value in pairs(self.CrewLink) do				--Then save it
		table.insert(entids, Value:EntIndex())
	end

	info.entities = entids
	if info.entities then
		duplicator.StoreEntityModifier( self, "CrewLink", info )
	end


	--Wire dupe info
	self.BaseClass.PreEntityCopy( self )

end

function ENT:PostEntityPaste( Player, Ent, CreatedEntities )

	--Link Pasting
	if Ent.EntityMods and Ent.EntityMods.GearLink and Ent.EntityMods.GearLink.entities then
		local GearLink = Ent.EntityMods.GearLink
		if GearLink.entities and next(GearLink.entities) then
			timer.Simple( 0, function() -- this timer is a workaround for an ad2/makespherical issue https://github.com/nrlulz/ACF/issues/14#issuecomment-22844064
				for _,ID in pairs(GearLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end )
		end
		Ent.EntityMods.GearLink = nil
	end

--self.HasDriver
	--fuel tank link Pasting
	if Ent.EntityMods and Ent.EntityMods.FuelLink and Ent.EntityMods.FuelLink.entities then
		local FuelLink = Ent.EntityMods.FuelLink
		if FuelLink.entities and next(FuelLink.entities) then
			for _,ID in pairs(FuelLink.entities) do
				local Linked = CreatedEntities[ ID ]
				if IsValid( Linked ) then
					self:Link( Linked )
				end
			end
		end
		Ent.EntityMods.FuelLink = nil
	end
--ace_crewseat_gunner
	if Ent.EntityMods and Ent.EntityMods.CrewLink and Ent.EntityMods.CrewLink.entities then
		local CrewLink = Ent.EntityMods.CrewLink
		if CrewLink.entities and next(CrewLink.entities) then
			for _,ID in pairs(CrewLink.entities) do
				local Linked = CreatedEntities[ ID ]
				if IsValid( Linked ) then
					self:Link( Linked )
				end
			end
		end
		Ent.EntityMods.CrewLink = nil
	end





	--Wire dupe info
	self.BaseClass.PostEntityPaste( self, Player, Ent, CreatedEntities )

end

function ENT:OnRemove()
	if self.Sound then
		self.Sound:Stop()
	end
end


