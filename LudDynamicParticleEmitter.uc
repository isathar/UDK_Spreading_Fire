class LudDynamicParticleEmitter extends Actor
	notplaceable;

var repnotify ParticleSystem				ParticleTemplate;
var repnotify float						ParticleScale;
var repnotify vector						ParticleWind;
var repnotify float						ParticleTime;

var float 								fTimeCreated, fShrinkTime;

var ParticleSystemComponent				Particles;
var CylinderComponent					CollisionCylinder;

var float 								fTouchDelay;
var float								fLastTouchTime;

var bool 								bHurtTouching, bCanGrow;
var class<DamageType>					HurtDamageType;

var float 								fCurrentParticleScale, fOldParticleScale;

var LudEmitter_Spreading					SpreadingParent;

var bool bIsTreeFire;


// MP Testing, not fully functional yet
replication
{
	if (bNetInitial || bNetDirty)
		ParticleTemplate, ParticleScale, ParticleWind, ParticleTime;
}

simulated event ReplicatedEvent(name VarName)
{
	if (VarName == 'ParticleTemplate') {
		SetParticleTemplate(ParticleTemplate);
		StartParticles();
		if (ParticleTemplate == None)
			Destroy();
	}
	else if (VarName == 'ParticleWind') {
		SetParticleWind(ParticleWind);
		StartParticles();
	}
	else
		Super.ReplicatedEvent(VarName);
}


simulated event PostBeginPlay()
{
	Super.PostBeginPlay();
	
	fLastTouchTime = WorldInfo.TimeSeconds;
}


simulated function SetParticleTemplate(ParticleSystem NewTemplate)
{
	Particles.SetTemplate(NewTemplate);
}

simulated function StartParticles()
{
	if (!Particles.bIsActive)
		Particles.ActivateSystem();
}

simulated function StopParticles()
{
	if (Particles.bIsActive)
		Particles.DeactivateSystem();
}

// Wind functions:
// sets new wind vector for particle system
simulated function SetParticleWind(vector newWind)
{
	Particles.SetVectorParameter('SmokeVelocity', newWind);
}

//returns current wind vector
simulated function vector GetParticleWind()
{
	local vector tempWind;
	
	if (Particles.GetVectorParameter('SmokeVelocity',tempWind))
		return tempWind;
	return vect(0,0,0);
}

//  called from the mian actor to update particle system's wind vector
simulated function UpdateWind(vector tempWind)
{
	if (ParticleWind != tempWind)
		ParticleWind = tempWind;
		
	SetParticleWind((tempWind));
}


// sets initial size of flame particles
simulated function UpdateParticleSizeScale(float newScale)
{
	local vector newSize;
	
	newSize = vect(500,500,500);
	
	if (bIsTreeFire) {
		newSize.Y = 4000;
		newSize = newSize * 2.0;
	}
	
	Particles.SetVectorParameter('ParticleSpawnSize',newSize * newScale);
}

// main init function called from main actor on creation
simulated function InitializeParticleSystem(LudEmitter_Spreading newSpreadEmitter, ParticleSystem NewTemplate, vector newWind, float newScale, float newTime, byte isTreeFire, optional float randomModifier = FRand())
{
	UpdateParticleSizeScale(0.05);
	fCurrentParticleScale = 0.01;
	fOldParticleScale = 0.01;
	ParticleScale = 0.01;
	
	if (isTreeFire > 0)
		bIsTreeFire = true;
	
	SpreadingParent = newSpreadEmitter;
	
	if (ParticleTemplate != NewTemplate) {
		ParticleTemplate = NewTemplate;
		SetParticleTemplate(NewTemplate);
	}
	
	if (ParticleWind != newWind) {
		ParticleWind = newWind;
		SetParticleWind(newWind);
	}
	
	if (ParticleScale != newScale) {
		ParticleScale = newScale;
	}
	
	if (ParticleTime != newTime) {
		ParticleTime = newTime;
		fShrinkTime = ParticleTime * 0.8;
	}
	
	StartParticles();
	UpdateWind(ParticleWind);
	fTimeCreated = WorldInfo.TimeSeconds;
	
	SetTimer(0.5,true,'UpdateParticleSize');
	SetTimer(1.0,true,'HurtTouching');
}

// damage touching actors
function HurtTouching()
{
	local Controller tempInstigator;
	local Actor actorToHurt;
	
	if (bHurtTouching) {
		ForEach TouchingActors(class'Actor', actorToHurt) {
			if (SpreadingParent.FireStarter != none)
				tempInstigator = SpreadingParent.FireStarter;
			actorToHurt.TakeDamage(10, tempInstigator, actorToHurt.Location, vect(0,0,8), HurtDamageType);
		}
	}
}

// timer/loop that continuosly updates the size of new flame particles
function UpdateParticleSize()
{
	if (bCanGrow) {	
		if (fCurrentParticleScale < ParticleScale) {
			fCurrentParticleScale = FInterpConstantTo(fCurrentParticleScale,ParticleScale,0.5,ParticleScale / (ParticleTime * 0.75));
			if (fCurrentParticleScale > (ParticleScale * 0.99)) {
				fCurrentParticleScale = ParticleScale;
				fOldParticleScale = fCurrentParticleScale;
				if (!bIsTreeFire)
					CreateEmitterDecal(fCurrentParticleScale);
				ParticleScale = 0.05;
			}
			UpdateParticleSizeScale(fCurrentParticleScale);
			
		} else if (fCurrentParticleScale > ParticleScale) {
			fCurrentParticleScale = FInterpConstantTo(fCurrentParticleScale,ParticleScale,0.5,fOldParticleScale / (ParticleTime * 0.25));
			UpdateParticleSizeScale(fCurrentParticleScale);
			
			if (fCurrentParticleScale < (ParticleScale * 1.01)) {
				fCurrentParticleScale = ParticleScale;
				ClearTimer('UpdateParticleSize');
				RemoveEmitter();
			}
		}
	}
}

// starts cleanup procedure
function RemoveEmitter()
{
	Particles.DeactivateSystem();
	SpreadingParent.RemoveEmitter(self);
	bHurtTouching = false;
	SetTimer(15.0,false,'RemoveEmitterTimer');
}

function RemoveEmitterTimer()
{
	ClearTimer('HurtTouching');
	Destroy();
}

// creates ground decal
function CreateEmitterDecal(float tempDecalScale)
{
	local vector tempLoc, tempNormal;
	local actor traceTarget;
	
	traceTarget = Trace(tempLoc, tempNormal, (Location + vect(0,0,32)) + vect(0,0,-96.f), Location + vect(0,0,32), false, vect(0,0,0), , TRACEFLAG_Bullet);
	if (traceTarget != none) {
		WorldInfo.MyDecalManager.SpawnDecal(
			DecalMaterial'LudWeapons_Ranged.Decals.scorchmark01',	
			tempLoc + vect(0,0,1),
			rotator(-tempNormal),
			512 * tempDecalScale, 512 * tempDecalScale,
			512 * tempDecalScale,
			false,
			FRand() * 360,
			,
			true,	false,
			,
			,
			,
			60.0,
		);
	}
}


DefaultProperties
{
	Begin Object Name=ParticleCompo Class=ParticleSystemComponent
		SecondsBeforeInactive=0
	End Object
	Particles=ParticleCompo
	Components.Add(ParticleCompo)
	
	Begin Object Name=CollisionCompo Class=CylinderComponent
		CollisionRadius=128.0
		CollisionHeight=128.0
		BlockActors=false
		BlockZeroExtent=false
		BlockNonZeroExtent=true
		BlockRigidBody=false
		AlwaysLoadOnClient=True
		AlwaysLoadOnServer=True
		bDisableAllRigidBody=true
		CollideActors=true
		AlwaysCheckCollision=true
	End Object
	CollisionCylinder=CollisionCompo
	CollisionComponent=CollisionCompo
	Components.Add(CollisionCompo)
	
	bCollideActors=True
	bNoEncroachCheck=true
	
	fTouchDelay=1.5
	bHurtTouching=true
	HurtDamageType=class'DamageType'
	
	ParticleScale=1.0
	ParticleTime=30.0
	fCurrentParticleScale=1.0
	
	bCanGrow=true
	
	RemoteRole=ROLE_SimulatedProxy
}