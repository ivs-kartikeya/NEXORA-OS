package com.kartik.mythicfrontiers.entity;

import com.kartik.mythicfrontiers.dragon.*;
import com.kartik.mythicfrontiers.entity.ai.DragonFollowOwnerGoal;
import com.kartik.mythicfrontiers.entity.ai.DragonHuntPreyGoal;
import com.kartik.mythicfrontiers.entity.part.DragonHitRegionManager;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.RandomStrollGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.storage.ValueInput;
import net.minecraft.world.level.storage.ValueOutput;
import net.minecraft.world.phys.Vec3;
import com.geckolib.animatable.GeoEntity;
import com.geckolib.animatable.instance.AnimatableInstanceCache;
import com.geckolib.animatable.manager.AnimatableManager;
import com.geckolib.util.GeckoLibUtil;
import java.util.Optional;
import java.util.UUID;

/**
 * Dragon runtime. Anatomy is always wyvern-style: two hind legs; wings are the forelimbs.
 * Gameplay remains server authoritative. Client only sends rider intent.
 */
public abstract class AbstractDragonEntity extends PathfinderMob implements GeoEntity {
    private final AnimatableInstanceCache geoCache=GeckoLibUtil.createInstanceCache(this);
    private final DragonHitRegionManager hitRegions=new DragonHitRegionManager();
    private DragonGenome genome;
    private int lifeTicks;
    private int bond;
    private UUID ownerUuid;
    private DragonCommand command=DragonCommand.ROAM;
    private float flightStamina=100f;
    private boolean airborne;
    private DragonRideInput rideInput=DragonRideInput.idle();
    private int attackCooldown;

    protected AbstractDragonEntity(EntityType<? extends PathfinderMob> type, Level level){
        super(type,level); this.genome=DragonGenome.roll(this.getRandom(),species());
    }
    public abstract DragonSpecies species();

    public static AttributeSupplier.Builder baseDragonAttributes(){
        return PathfinderMob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 92).add(Attributes.MOVEMENT_SPEED,.27)
                .add(Attributes.FLYING_SPEED,.43).add(Attributes.ATTACK_DAMAGE,12)
                .add(Attributes.FOLLOW_RANGE,56).add(Attributes.KNOCKBACK_RESISTANCE,.45);
    }
    @Override protected void registerGoals(){
        goalSelector.addGoal(0,new FloatGoal(this));
        goalSelector.addGoal(2,new DragonFollowOwnerGoal(this,1.08,8,3));
        goalSelector.addGoal(3,new DragonHuntPreyGoal(this,1.05));
        goalSelector.addGoal(6,new RandomStrollGoal(this,.82));
        goalSelector.addGoal(8,new LookAtPlayerGoal(this,Player.class,24));
        goalSelector.addGoal(9,new RandomLookAroundGoal(this));
    }
    @Override public void tick(){
        super.tick();
        if(!level().isClientSide()){
            lifeTicks++;
            if(attackCooldown>0) attackCooldown--;
            tickFlight();
            flightStamina=Math.min(100f,flightStamina+(airborne?.022f:.11f));
            hitRegions.update(position(),getYRot(),Math.max(.2,visualScale()));
        }
    }
    private void tickFlight(){
        Player rider=controllingOwner();
        if(rider==null){ airborne=!onGround() && getDeltaMovement().y>-0.4; return; }
        DragonRideInput i=rideInput.sanitized();
        float yaw=i.yaw(); setYRot(yaw); setYHeadRot(yaw);
        double scale=visualScale();
        double max=DragonFlightModel.maxCruise(scale,species());
        double yawR=Math.toRadians(yaw); Vec3 forward=new Vec3(-Math.sin(yawR),0,Math.cos(yawR));
        Vec3 right=new Vec3(forward.z,0,-forward.x);
        double throttle=Math.max(0,i.forward());
        double speed=(.18+max*.23)*throttle*(i.sprint()?1.24:1.0);
        double lift=(i.climb()?0.22:0)-(i.descend()?0.19:0)-0.035;
        if(onGround() && i.climb() && flightStamina>3){ lift=.44; airborne=true; }
        Vec3 target=forward.scale(speed).add(right.scale(i.strafe()*.12)).add(0,lift-i.pitch()*.08,0);
        setDeltaMovement(getDeltaMovement().scale(.82).add(target.scale(.18)));
        if(airborne && (i.climb() || i.sprint())) flightStamina=Math.max(0,flightStamina-(float)DragonFlightModel.wingbeatCost(scale,genome.bulkBias())*.035f);
        if(flightStamina<=.1f) setDeltaMovement(getDeltaMovement().add(0,-.06,0));
        if(i.attack() && attackCooldown==0){ performBreathAttack(); attackCooldown=20; }
    }
    private void performBreathAttack(){
        Vec3 origin=getEyePosition(); Vec3 look=getLookAngle();
        float dmg=DragonCombat.scaledDamage(species(),DragonAttackType.BREATH,visualScale(),genome.bulkBias());
        for(LivingEntity target:level().getEntitiesOfClass(LivingEntity.class,DragonCombat.breathVolume(origin,look,visualScale()),e->e!=this && e!=getControllingPassenger())){
            if(DragonCombat.inForwardCone(origin,look,target,35)) target.hurt(damageSources().mobAttack(this),dmg);
        }
    }
    @Override protected InteractionResult mobInteract(Player p, InteractionHand hand){
        if(!level().isClientSide() && canBeRiddenBy(p) && p.getItemInHand(hand).isEmpty()){
            p.startRiding(this); return InteractionResult.SUCCESS;
        }
        return super.mobInteract(p,hand);
    }
    public void feedAndBond(Player p){ if(ownerUuid==null) ownerUuid=p.getUUID(); if(ownerUuid.equals(p.getUUID())) bond=DragonBond.clamp(bond+DragonBond.feedGain(lifeStage())); heal(5); }
    public void cycleCommand(Player p){ if(isOwner(p) && bond>=DragonBond.COMMAND) command=command.next(); }
    public void setRideInput(Player p, DragonRideInput input){ if(canBeRiddenBy(p) && getControllingPassenger()==p) rideInput=input.sanitized(); }
    public boolean isOwner(Player p){ return ownerUuid!=null && ownerUuid.equals(p.getUUID()); }
    public boolean canBeRiddenBy(Player p){ return isOwner(p) && bond>=DragonBond.RIDE && lifeStage().ordinal()>=DragonLifeStage.ADOLESCENT.ordinal(); }
    public Player controllingOwner(){ Entity e=getControllingPassenger(); return e instanceof Player p && isOwner(p)?p:null; }
    public Optional<UUID> ownerUuid(){ return Optional.ofNullable(ownerUuid); }
    public DragonCommand command(){ return command; }
    public int bond(){ return bond; }
    public double maturity(){ return Math.min(1,lifeTicks/252000.0); }
    public DragonLifeStage lifeStage(){ return DragonLifeStage.fromMaturity(maturity()); }
    public double visualScale(){ return genome.visualScale(maturity()); }
    public DragonGenome genome(){ return genome; }
    public float flightStamina(){ return flightStamina; }
    public DragonHitRegionManager hitRegions(){ return hitRegions; }
    public void installHatchedGenome(DragonGenome g, UUID owner){ genome=g; ownerUuid=owner; lifeTicks=1; bond=55; }

    @Override protected void addAdditionalSaveData(ValueOutput out){
        super.addAdditionalSaveData(out);
        out.putDouble("MFAdultScale",genome.adultScale());
        out.putDouble("MFWingBias",genome.wingBias());
        out.putDouble("MFBulkBias",genome.bulkBias());
        out.putDouble("MFTemperament",genome.temperament());
        out.putLong("MFVisualSeed",genome.visualSeed());
        out.putInt("MFLifeTicks",lifeTicks);
        out.putInt("MFBond",bond);
        out.putString("MFCommand",command.name());
        out.putFloat("MFFlightStamina",flightStamina);
        if(ownerUuid!=null) out.putString("MFOwner",ownerUuid.toString());
    }
    @Override protected void readAdditionalSaveData(ValueInput in){
        super.readAdditionalSaveData(in);
        genome=new DragonGenome(
                in.getDoubleOr("MFAdultScale", genome.adultScale()),
                in.getDoubleOr("MFWingBias", genome.wingBias()),
                in.getDoubleOr("MFBulkBias", genome.bulkBias()),
                in.getDoubleOr("MFTemperament", genome.temperament()),
                in.getLongOr("MFVisualSeed", genome.visualSeed()));
        lifeTicks=in.getIntOr("MFLifeTicks",0);
        bond=DragonBond.clamp(in.getIntOr("MFBond",0));
        flightStamina=in.getFloatOr("MFFlightStamina",100f);
        String owner=in.getStringOr("MFOwner","");
        if(!owner.isBlank()) try{ ownerUuid=UUID.fromString(owner); }catch(IllegalArgumentException ignored){ ownerUuid=null; }
        try{ command=DragonCommand.valueOf(in.getStringOr("MFCommand",DragonCommand.ROAM.name())); }catch(Exception ignored){ command=DragonCommand.ROAM; }
    }
    @Override public void registerControllers(AnimatableManager.ControllerRegistrar controllers){ }
    @Override public AnimatableInstanceCache getAnimatableInstanceCache(){ return geoCache; }
}
