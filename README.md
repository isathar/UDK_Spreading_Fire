UDK_Spreading_Fire
==================

Unrealscript classes for an actor that creates a spreading fire by maintaining a pool of custom particle emitters



NOTES:

LightFunction_Fire.uc and LudPhysicalMaterialProperty.uc are examples for your own Lightfunctions and PhysicalMaterialProperties.
If you already have a PhysicalMaterialProperties class, just copy over the fFlammability and fFireSizeScale variables.

No assets are included, so search for and replace the following with your own:

LightFunction_Fire.uc:
	Material'LudGame_Materials.lightfunctions.Fire01_LF'
	- This should be a simple flickering effect as described on the UDN page for LightFunctions.
	
LudDynamicParticleEmitter.uc:
	HurtDamageType=class'LudDamageType_Burning_DOT'
	- Replace this with your own DamageType class.

LudEmitter_Spreading.uc:
	SoundCue'LudGame_Sounds.Fire01Loop'
	- This should be a looping soundcue with a long fade distance.
	
	ParticleSystem'LudGameParticles.ParticleSystems.NewTestFire_smokeTest'
	- My particle system is divided into four emitters, but only two are required
		- A smoke column emitter with smoke particles that slowly move upwards,
		- a flame emitter with fire particles that grow + shrink (size over life) and last for about 1-2 seconds each
		(optional - embers and second smoke layer for the ground)
		
	- Parameters:
		(Flame emitter)
		"ParticleSpawnSize"
		- This should be set for "Initial Size" on the flame emitter
		
		(Smoke Column Emitter)
		"SmokeVelocity"
		- This should be set for "Initial Velocity" on the Smoke Column emitter



spawn with something like this:

function StartBurningEffect()
{
	local LudEmitter_Spreading spreadingFire;
	
	spreadingFire = Spawn(class'LudEmitter_Spreading');
	spreadingFire.InitSpreadingEmitters(Instigator.Controller);
}