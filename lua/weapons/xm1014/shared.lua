AddCSLuaFile("shared.lua")
SWEP.Base = "ace_basewep"

if (CLIENT) then
SWEP.PrintName		= "XM1014"
SWEP.Slot		    = 2
SWEP.SlotPos		= 1			
end

SWEP.Spawnable		= true	

--Visual
SWEP.ViewModelFlip 	= true
SWEP.ViewModel		= "models/weapons/v_shot_xm1014.mdl"	
SWEP.WorldModel		= "models/weapons/w_shot_xm1014.mdl"	
SWEP.ReloadSound	= "weapons/m3/m3_insertshell.wav"	
SWEP.HoldType		= "shotgun"		
SWEP.CSMuzzleFlashes	= true


-- Other settings
SWEP.Weight			= 10						
 
-- Weapon info		
SWEP.Purpose		= "SO MUCH RECOIL"	
SWEP.Instructions	= "Left mouse to shoot"		

-- Primary fire settings
SWEP.Primary.Sound			= "weapons/m3/m3-1.wav"	
SWEP.Primary.NumShots		= 1	
SWEP.Primary.Recoil			= 5	
SWEP.Primary.RecoilAngleVer	= 0.15	
SWEP.Primary.RecoilAngleHor	= 0.1		
SWEP.Primary.Cone			= 0.1		
SWEP.Primary.Delay			= 0.3
SWEP.Primary.ClipSize		= 8		
SWEP.Primary.DefaultClip	= 7			
SWEP.Primary.Force			= 1	
SWEP.Primary.Automatic		= false	
SWEP.Primary.Ammo		= "buckshot"	

SWEP.Secondary.Ammo		= "none"	
SWEP.Secondary.ClipSize		= -1		
SWEP.Secondary.DefaultClip	= -1

SWEP.ReloadSoundEnabled = 1

SWEP.Category 			= "ACE Sweps - SG"

SWEP.AimOffset = Vector(0,0,0)
SWEP.InaccuracyAccumulation = 0
SWEP.lastFire=CurTime()

SWEP.MaxInaccuracyMult = 3
SWEP.InaccuracyAccumulationRate = 0.2
SWEP.InaccuracyDecayRate = 1
SWEP.CarrySpeedMul = 1.5 --WalkSpeedMult when carrying the weapon

SWEP.Reloading = 0
SWEP.NextReload = 0
--

function SWEP:InitBulletData()
	
	self.BulletData = {}

		self.BulletData.Id = "7.62mmMG"
		self.BulletData.Type = "AP"
		self.BulletData.Id = 1
		self.BulletData.Caliber = 1.2
		self.BulletData.PropLength = 1.2 --Volume of the case as a cylinder * Powder density converted from g to kg		
		self.BulletData.ProjLength = 5 --Volume of the projectile as a cylinder * streamline factor (Data5) * density of steel
		self.BulletData.Data5 = 0  --He Filler or Flechette count
		self.BulletData.Data6 = 0 --HEAT ConeAng or Flechette Spread
		self.BulletData.Data7 = 0
		self.BulletData.Data8 = 0
		self.BulletData.Data9 = 0
		self.BulletData.Data10 = 1 -- Tracer
		self.BulletData.Colour = Color(255, 0, 0)
		--
		self.BulletData.Data13 = 0 --THEAT ConeAng2
		self.BulletData.Data14 = 0 --THEAT HE Allocation
		self.BulletData.Data15 = 0
	
		self.BulletData.AmmoType  = self.BulletData.Type
		self.BulletData.FrAera    = 3.1416 * (self.BulletData.Caliber/2)^2
		self.BulletData.ProjMass  = self.BulletData.FrAera * (self.BulletData.ProjLength*7.9/1000)
		self.BulletData.PropMass  = self.BulletData.FrAera * (self.BulletData.PropLength*ACF.PDensity/1000) --Volume of the case as a cylinder * Powder density converted from g to kg
--		self.BulletData.DragCoef  = 0 --Alternatively manually set it
		self.BulletData.DragCoef  = ((self.BulletData.FrAera/10000)/self.BulletData.ProjMass)	

		--Don't touch below here
		self.BulletData.MuzzleVel = ACF_MuzzleVelocity( self.BulletData.PropMass, self.BulletData.ProjMass, self.BulletData.Caliber )		
		self.BulletData.ShovePower = 0.2
		self.BulletData.KETransfert = 0.3
		self.BulletData.PenAera = self.BulletData.FrAera^ACF.PenAreaMod
		self.BulletData.Pos = Vector(0 , 0 , 0)
		self.BulletData.LimitVel = 800	
		self.BulletData.Ricochet = 60
		self.BulletData.Flight = Vector(0 , 0 , 0)
		self.BulletData.BoomPower = self.BulletData.PropMass
		
		--For Fake Crate
		self.Type = self.BulletData.Type
		self.BulletData.Tracer = self.BulletData.Data10
		self.Tracer = self.BulletData.Tracer
		self.Caliber = self.BulletData.Caliber
		self.ProjMass = self.BulletData.ProjMass
		self.FillerMass = self.BulletData.Data5
		self.DragCoef = self.BulletData.DragCoef
		self.Colour = self.BulletData.Colour
		
end	
		
function SWEP:PrimaryAttack()		
	self.Reloading = 0
	if ( !self:CanPrimaryAttack() ) then return end		

	self:SetNextPrimaryFire( CurTime() + self.Primary.Delay )	
	self.Weapon:EmitSound(Sound(self.Primary.Sound), 100, 100, 1, CHAN_WEAPON )	
	if CLIENT then 
	return 
	end
	
	self.BulletData.Owner = self.Owner
	self.BulletData.Gun = self	
	self:ACEFireBullet()
	self:ACEFireBullet()
	self:ACEFireBullet()
	self:ACEFireBullet()
	self:ACEFireBullet()
	self.InaccuracyAccumulation = math.Clamp(self.InaccuracyAccumulation + self.InaccuracyAccumulationRate - self.InaccuracyDecayRate*(CurTime()-self.lastFire),1,self.MaxInaccuracyMult)
	
	self.lastFire=CurTime()
--	print("Inaccuracy: "..self.InaccuracyAccumulation)
	
	
	self.Weapon:SendWeaponAnim( ACT_VM_PRIMARYATTACK )							
	self.Owner:SetAnimation( PLAYER_ATTACK1 )			
	self.Owner:ViewPunch(Angle( -self.Primary.Recoil, 0, 0 ))
	if (self.Primary.TakeAmmoPerBullet) then			
		self:TakePrimaryAmmo(self.Primary.NumShots)
	else
		self:TakePrimaryAmmo(1)
	end

	self:SetNextPrimaryFire( CurTime() + self.Primary.Delay )	
end

function SWEP:Think()	

	if CurTime() > self.NextReload and self.Reloading == 1 then

	if self:Clip1() < self.Primary.ClipSize and self:Ammo1() > 0 then
	
	self.Weapon:EmitSound(Sound(self.ReloadSound))

	self:SendWeaponAnim(ACT_VM_RELOAD)	
	self.Weapon:SetClip1( self.Weapon:Clip1() + 1 )
	
	self.NextReload = CurTime()+0.5

	elseif self:Clip1() == self.Primary.ClipSize and 	self.Reloading == 1 then
	
	self:SendWeaponAnim(ACT_SHOTGUN_RELOAD_FINISH)	
	self.Reloading = 0
	end
	
	end
		
end

function SWEP:Reload()	

	if CurTime() > self.NextReload then
	
	if 	self.Reloading == 0 and self:Clip1() < self.Primary.ClipSize and self:Ammo1() > 0 then 

	self:SendWeaponAnim(ACT_SHOTGUN_RELOAD_START)
	self.Reloading = 1
	self.NextReload = CurTime()+0.5
	end
	
	end


	self:Think()
	return true
end


