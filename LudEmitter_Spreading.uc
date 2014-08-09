/***********************************************************************************
	An actor that serves as a base for spreading particle effects
	made for spreading fire, gas, fog
	includes damage handling
***********************************************************************************/
class LudEmitter_Spreading extends Actor;

var array<LudDynamicParticleEmitter> 	EmitterPool;

var ParticleSystem					ParticleSystemName;

var int							iMaxNumEmitters;			// max number of emitters handled by this actor
var float 							fTimePerInstance;			//max time per emitter
var float							fTotalTime;				// total time for actor to keep spawning emitters
var float							fSpreadingRate;				// interval at which spreading function is called 
var float							fMinDistBetweenEmitters;
var float							fTraceDist;				// min distance for emitter spawn checks

//  directions for traces
var vector					vTraceDirections[8];
var vector					vDownTrace, vUpTrace;

var PointLightComponent 			AreaLight;
var LightFunction_Fire 				AreaLightFunction;

var AudioComponent					AreaAudioComponent;
var SoundCue						AreaSoundCue;				// burning sound loop

var bool 							bReachedEnd;				// if true, spawn no new emitters
var Controller						FireStarter;				// TBD: burning damage instigator

var WindDirectionalSource			WindSource;

var bool							bShowDebug;				// show debug lines + log output

var float 							fMaxwindStrength;			// maximum wind strength for calculating spark flight



simulated event PostBeginPlay()
{
	super.PostBeginPlay();
	//fix for underground/no fires
	SetLocation(Location + vect(0,0,32));
}


function InitSpreadingEmitters(Controller tempFireStarter)
{
	local Rotator tempRot;
	local WindDirectionalSource tempWind;
	
	FireStarter = tempFireStarter;

	tempRot.pitch = 0;
	tempRot.yaw = 0;
	tempRot.roll = 0;
	
	SetRotation(tempRot);

	AreaLightFunction = new class'LightFunction_Fire';
	
	if (tempWind == none) {
		ForEach AllActors(class'WindDirectionalSource',tempWind)
		{
			Windsource = tempWind;
			break;
		}
	}
	
	AreaLight.SetLightProperties(, , AreaLightFunction);
	AreaAudioComponent.Stop();
	AreaLight.SetEnabled(false);
	
	SetTimer(fSpreadingRate, true, 'ContinueSpreading');
	SetTimer(fTotalTime, false, 'RemoveFireTimer');
	SetTimer(5.0, true, 'UpdateWindTimer');
}

// calculates center point of the emitter cluster
function vector GetNewCenterPoint(vector oldLoc = Location)
{
	local vector tempLoc;
	local int i;
	
	tempLoc = vect(0,0,0);
	
	if (EmitterPool.length > 0) {
		if (EmitterPool.length > 1) {
			for (i=0;i<EmitterPool.length;i++)
				tempLoc = tempLoc + (EmitterPool[i].Location - oldLoc);
			
			tempLoc = tempLoc / EmitterPool.length;
		} else
			tempLoc = EmitterPool[0].Location - oldLoc;
	} else
		tempLoc = vect(0,0,32);
	
	if (bShowDebug && !IsZero(tempLoc))
		DrawDebugLine(oldLoc + tempLoc + vect(0,0,32), oldLoc + vect(0,0,32), 255, 0, 0, true);
	
	return tempLoc + oldLoc;
}

// performs traces and probability checks to pick new spot to spread to
function vector GetNewSpreadLoc(out int isTreeFire, out float tempScale)
{
	local Actor traceTarget;
	local vector HitLoc, HitLoc2, HitNorm, tempLoc, tempWindDir;
	local int i, tempIndex;
	local PhysicalMaterial tempPhysMat;
	local TraceHitInfo HitInfo, defaultHitInfo;
	local float tempTraceDist, tempDotProduct, tempProb;
	local rotator tempWindrot;
	local array<vector> possLocs;
	local array<float> locProbs, locScales;
	local array<int> locTreeFire;
	
	// wind rotation
	tempWindrot = WindSource.Rotation;
	
	// random direction if wind strength is too low
	if (WindSource.Component.Strength < 0.1)
		tempWindRot = RotRand(false);
	tempWindDir = Vector(tempWindRot);
	
	// pick particle system closest to wind direction
	tempIndex = GetNextSpreadStart(tempWindRot);
	if (tempIndex > -1)
		tempLoc = EmitterPool[tempIndex].Location;
	else
		tempLoc = Location;
	
	//random chance to jump + random start location jitter to simulate sparks
	if (WindSource.Component.Strength >= (fMaxwindStrength * 0.75)) {
		tempTraceDist = fTraceDist * 2.0;
		tempLoc.X += RandRange(-2.0,2.0);
		tempLoc.Y += RandRange(-2.0,2.0);
	} else if (WindSource.Component.Strength >= (fMaxwindStrength * 0.5)) {
		tempTraceDist = fTraceDist * 1.5;
		tempLoc.X += RandRange(-4.0,4.0);
		tempLoc.Y += RandRange(-4.0,4.0);
	} else if (WindSource.Component.Strength >= (fMaxwindStrength * 0.25)) {
		tempTraceDist = fTraceDist;
		tempLoc.X += RandRange(-8.0,8.0);
		tempLoc.Y += RandRange(-8.0,8.0);
	} else {
		tempTraceDist = fTraceDist * 0.5;
		tempLoc.X += RandRange(-16.0,16.0);
		tempLoc.Y += RandRange(-16.0,16.0);
	}
	
	//trace in each direction, compare to wind direction
	for (i=0; i<8; i++) {
		tempDotProduct = NoZDot(tempWindDir, vTraceDirections[i]);
		
		// check if trace direction and wind direction are within 90 degree wedge
		if (tempDotProduct >= 0.0) {
			traceTarget = none;
			HitLoc = vect(0,0,0);
			tempPhysMat = none;
			//reset hitinfo for edge cases
			HitInfo = defaultHitInfo;
			
			// trace in x,y direction at an upwards pointing angle
			traceTarget = Trace(HitLoc, HitNorm, tempLoc + ((vTraceDirections[i] * tempTraceDist)) + vect(0,0,96), tempLoc, false, vect(0,0,0), HitInfo, TRACEFLAG_Bullet);
			
			//down trace if hit nothing
			if (traceTarget == none) {
				if (IsZero(HitLoc))
					HitLoc = tempLoc + ((vTraceDirections[i] * tempTraceDist)) + vect(0,0,96);

				traceTarget = Trace(HitLoc2, HitNorm, HitLoc + (vDownTrace * (fTraceDist * 3.0)), HitLoc, false, vect(0,0,0), HitInfo, TRACEFLAG_Bullet);
				HitLoc = HitLoc2;
			}
			
			// gather spot's variables, only add to list if something was hit
			if (traceTarget != none) {
				tempPhysMat = HitInfo.PhysMaterial;
				if (tempPhysMat != none && tempPhysMat.PhysicalMaterialProperty != none) {
					if (LudPhysicalMaterialProperty(tempPhysMat.PhysicalMaterialProperty).fFlammability > 0.0) {
						tempProb = FRand();
						if (tempProb < (tempDotProduct + LudPhysicalMaterialProperty(tempPhysMat.PhysicalMaterialProperty).fFlammability) * 0.5) {
							if (!CheckDist(HitLoc)) {
								//return HitLoc;
								if (traceTarget.class == class'SpeedTreeActor')
									possLocs.AddItem(traceTarget.Location);
								else
									possLocs.AddItem(HitLoc);
								
								locProbs.AddItem(tempProb);
								
								if (traceTarget.class == class'SpeedTreeActor')
									locTreeFire.AddItem(1);
								else
									locTreeFire.AddItem(0);
								
								if (traceTarget.class == class'StaticMeshActor')
									locScales.AddItem(LudPhysicalMaterialProperty(tempPhysMat.PhysicalMaterialProperty).fFireSizeScale + 0.2);
								else if (traceTarget.class == class'SpeedTreeActor')
									locScales.AddItem(2.0);
								else
									locScales.AddItem(LudPhysicalMaterialProperty(tempPhysMat.PhysicalMaterialProperty).fFireSizeScale);
							}
						}
					}
				}
			}
		}
	}
	
	// find best spot from list
	if (locProbs.length > 0) {
		tempIndex = 0;
		if (locProbs.length > 1) {
			for (i=1; i<locProbs.length; i++) {
				if (locProbs[i] > locProbs[tempIndex])
					tempIndex = i;
			}
		}
		HitLoc = possLocs[tempIndex];
		isTreeFire = locTreeFire[tempIndex];
		tempScale = locScales[tempIndex];
	} else {
		tempScale = 0;
		HitLoc = vect(0,0,0);
		isTreeFire = 0;
	}
	
	return HitLoc;
}

// returns true if emitters are within tempdist of spot
// using VSizeSq for a minimal performance gain
function bool CheckDist(vector tempLoc, optional float tempDist = fMinDistBetweenEmitters)
{
	local int i;
	
	if (EmitterPool.length > 0) {
		for (i=0; i<EmitterPool.length; i++) {
			if (VSizeSq(tempLoc - EmitterPool[i].Location) < tempDist)
				return true;
		}
	}
	return false;
}

// returns the index of the emitter with direction from cluster's center closest to the wind's direction or -1 if no emitters are in the list
function int GetNextSpreadStart(rotator windRot)
{
	local int i, tempIndex;
	local vector windVector;
	local float checkDot, tempDot;
	
	tempIndex = -1;
	
	if (EmitterPool.length > 0) {
		windVector = Vector(windRot);
		checkDot = NoZDot(windVector, Vector(Rotator(EmitterPool[0].Location - Location)));
		tempIndex = 0;
		
		if (EmitterPool.length > 1) {
			for (i=1; i<EmitterPool.length; i++) {
				tempDot = NoZDot(windVector, Vector(Rotator(EmitterPool[i].Location - Location)));
				if (checkDot < tempDot) {
					tempIndex = i;
					checkDot = tempDot;
				}
			}
		}
	}
	return tempIndex;
}

// main loop that handles fire spreading + actor location
function ContinueSpreading()
{
	local vector tempLoc;
	local int iIsTreeFire;
	local float tempScale;
	
	if (!bReachedEnd) {
		if (EmitterPool.length < iMaxNumEmitters) {
			tempLoc = GetNewSpreadLoc(iIsTreeFire, tempScale);
			if (!IsZero(tempLoc)) {
				CreateEmitter(tempLoc, tempScale, iIsTreeFire);
				SetLocation(GetNewCenterPoint());
			}
		}
	}
}

function CheckEmitterPoolBeforeDestroy()
{
	if (EmitterPool.length < 1) {
		ClearTimer('CheckEmitterPoolBeforeDestroy');
		if (AreaLight.bEnabled)
			AreaLight.SetEnabled(false);
		if (AreaAudioComponent.IsPlaying())
			AreaAudioComponent.Stop();
		
		Destroy();
	}
}

// creates a new emitter at emitterLoc with semi-random properties determined by flammability
function CreateEmitter(vector emitterLoc, float tempFlammability, optional byte isTreeFire)
{
	local LudDynamicParticleEmitter newEmitter;
	local vector tempDir;
	local float volumeLevel;
	local float tempScale, tempTime;
	
	tempDir = normal(vector(WindSource.Rotation)) * WindSource.Component.Strength  * 20.0;
	tempDir.z = 150;
	
	newEmitter = Spawn(class'LudDynamicParticleEmitter');
		
	EmitterPool.AddItem(newEmitter);
	volumeLevel = FMax((EmitterPool.length / iMaxNumEmitters), 0.05);

	if (isTreeFire > 0)
		tempScale = RandRange(tempFlammability, (tempFlammability * 4.0) + volumeLevel);
	else
		tempScale = RandRange(tempFlammability * 0.2, tempFlammability + volumeLevel);
		
	tempTime = fTimePerInstance * tempScale;
	newEmitter.SetLocation(emitterLoc);
	
	if (!AreaLight.bEnabled)
		AreaLight.SetEnabled(true);
	AreaLight.SetLightProperties(0.2 + 3.0 * volumeLevel);
	
	if (!AreaAudioComponent.IsPlaying())
		AreaAudioComponent.Play();
	AreaAudioComponent.VolumeMultiplier = AreaAudioComponent.VolumeMultiplier + volumeLevel;
	
	newEmitter.InitializeParticleSystem(self, ParticleSystemName, tempDir, tempScale, tempTime, isTreeFire);
	
	if (bShowDebug)
		`log("SpreadingFire created a new emitter, current count = " $ EmitterPool.length);
}

// wind direction check loop
function UpdateWindTimer()
{
	UpdateEmitterWind(WindSource.Rotation, WindSource.Component.Strength);
}

// updates wind direction for each emitter
function UpdateEmitterWind(rotator WindDir, float WindStr)
{
	local int i;
	local vector tempDir;
	
	if (EmitterPool.length > 0) {
		tempDir = normal(vector(WindDir)) * (WindStr * 60.0);
		tempDir.z = 250;
		for (i=0;i<EmitterPool.length;i++)
			EmitterPool[i].UpdateWind(tempDir);
		
		if (bShowDebug)
			`log("SpreadingFire updated wind for " $ EmitterPool.length $ " emitters to new value " $ tempDir);
	}
}

// prepares emitter for deletion + updates main actor
function RemoveEmitter(LudDynamicParticleEmitter emitterToDestroy)
{
	local float volumeLevel;
	
	EmitterPool.RemoveItem(emitterToDestroy);
	
	if (EmitterPool.length < 1) {
		if (AreaLight.bEnabled)
			AreaLight.SetEnabled(false);
		if (AreaAudioComponent.IsPlaying())
			AreaAudioComponent.Stop();
	} else {
		volumeLevel = FMax((EmitterPool.length / iMaxNumEmitters), 0.06);
		
		AreaLight.SetLightProperties(0.2 + 3.0 * volumeLevel);
		AreaAudioComponent.VolumeMultiplier = AreaAudioComponent.VolumeMultiplier + volumeLevel;
	}
	SetLocation(GetNewCenterPoint());
	
	if (bShowDebug)
		`log("SpreadingFire deleted an emitter, current count = " $ EmitterPool.length);
}

// final deletion timer start
function RemoveFireTimer()
{
	bReachedEnd = true;
	if (!IsTimerActive('CheckEmitterPoolBeforeDestroy'))
		SetTimer(2.0,true,'CheckEmitterPoolBeforeDestroy');
}


DefaultProperties
{
	RemoteRole=ROLE_SimulatedProxy
	
	ParticleSystemName=ParticleSystem'Test_FireParticles.ParticleSystems.SpreadingFire_PS'

	iMaxNumEmitters=24				// 16-24 for good quality vs performance ratio
	fTimePerInstance=60.0			// should always be higher than fSpreadingRate, is influenced by the fire's calculated scale
	fTotalTime=300.f				// this is approximate as cleanup doesn't happen until all emitters are finished
	fSpreadingRate=5.0
	fTraceDist=96.0
	fMinDistBetweenEmitters=512.0 	// ~22^2, orig. 32^2=1024.0
	
	//clockwise
	vTraceDirections(0)=(x=1,y=0,z=0) 	//F
	vTraceDirections(1)=(x=1,y=1,z=0)	//FL
	vTraceDirections(2)=(x=0,y=1,z=0)	//L
	vTraceDirections(3)=(x=-1,y=1,z=0)	//BL
	vTraceDirections(4)=(x=-1,y=0,z=0)	//B
	vTraceDirections(5)=(x=-1,y=-1,z=0)	//BR
	vTraceDirections(6)=(x=0,y=-1,z=0)	//R
	vTraceDirections(7)=(x=1,y=-1,z=0)	//FR

	vDownTrace=(x=0,y=0,z=-1)
	vUpTrace=(x=0,y=0,z=1)
	
	Begin Object class=AudioComponent Name=AreaSoundCompo
		SoundCue=SoundCue'Test_FireParticles.Sounds.Fire_Looping_Cue'
	End Object
	AreaAudioComponent=AreaSoundCompo
	Components.Add(AreaSoundCompo);
	
	Begin Object class=PointLightComponent Name=AreaLightCompo1
		LightColor=(R=255,G=128,B=0)
		Radius=768
		Brightness=2.0
		bForceDynamicLight=true
		bRenderLightShafts=true
		OcclusionDepthRange=1000
		BloomScale=1.0
		BloomThreshold=0.2
		BloomScreenBlendThreshold=0.8
		BloomTint=(R=255,G=128,B=0)
		RadialBlurPercent=75
		OcclusionMaskDarkness=0.8
		LightingChannels=(BSP=TRUE,Static=TRUE,Dynamic=TRUE,bInitialized=TRUE)
		Translation=(X=0.0,Y=0.0,Z=32.0)
	End Object
	AreaLight=AreaLightCompo1
	Components.Add(AreaLightCompo1)
	
	bShowDebug=true
	
	fMaxwindStrength=4.0
}