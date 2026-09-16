package com.kartik.mythicfrontiers.entity.ai;
import com.kartik.mythicfrontiers.dragon.*;
import com.kartik.mythicfrontiers.entity.AbstractDragonEntity;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import java.util.Comparator;
import java.util.EnumSet;
public final class DragonHuntPreyGoal extends Goal {
    private final AbstractDragonEntity dragon; private final double speed; private LivingEntity prey;
    public DragonHuntPreyGoal(AbstractDragonEntity d,double speed){dragon=d;this.speed=speed;setFlags(EnumSet.of(Flag.MOVE,Flag.LOOK));}
    @Override public boolean canUse(){
        if(dragon.command()==DragonCommand.STAY || dragon.lifeStage()==DragonLifeStage.HATCHLING) return false;
        if(dragon.command()!=DragonCommand.HUNT && dragon.getRandom().nextInt(120)!=0) return false;
        prey=dragon.level().getEntitiesOfClass(LivingEntity.class,dragon.getBoundingBox().inflate(28),DragonDiet::isNaturalPrey).stream().min(Comparator.comparingDouble(dragon::distanceToSqr)).orElse(null);
        return prey!=null;
    }
    @Override public boolean canContinueToUse(){ return prey!=null && prey.isAlive() && dragon.distanceTo(prey)<40 && dragon.command()!=DragonCommand.STAY; }
    @Override public void tick(){
        dragon.getLookControl().setLookAt(prey,25,20); dragon.getNavigation().moveTo(prey,speed);
        if(dragon.distanceTo(prey)<3.2*dragon.visualScale() && dragon.getSensing().hasLineOfSight(prey) && dragon.level() instanceof ServerLevel sl) dragon.doHurtTarget(sl,prey);
    }
}
