UDK_Spreading_Fire
==================

Unrealscript classes for an actor that creates a spreading fire by maintaining a pool of custom particle emitters



NOTES:

Change HurtDamageType in LudDynamicParticleEmitter.uc to your damage type.

I forgot to include the decal material in the assets package, so you will need to change line 225 in LudDynamicParticleEmitter.uc to a valid DecalMaterial.


LightFunction_Fire.uc and LudPhysicalMaterialProperty.uc are examples for your own Lightfunctions and PhysicalMaterialProperties.
If you already have a PhysicalMaterialProperties class, just copy over the fFlammability and fFireSizeScale variables.

Assets are available at

http://www.gamefront.com/files/24655740/FireActor_ExampleFiles.zip


spawn with something like this:

function StartBurningEffect()
{
	local LudEmitter_Spreading spreadingFire;
	
	spreadingFire = Spawn(class'LudEmitter_Spreading');
	spreadingFire.InitSpreadingEmitters(Instigator.Controller);
}