package com.kartik.mythicfrontiers.block.entity;
import com.kartik.mythicfrontiers.dragon.*;
import com.kartik.mythicfrontiers.entity.AbstractDragonEntity;
import com.kartik.mythicfrontiers.registry.ModBlockEntities;
import com.kartik.mythicfrontiers.registry.ModEntityTypes;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.ValueInput;
import net.minecraft.world.level.storage.ValueOutput;
import java.util.UUID;
public final class DragonEggBlockEntity extends BlockEntity {
    private DragonSpecies species=DragonSpecies.EMBER; private DragonGenome genome; private UUID bondedPlayer; private int incubation; private int hatchTarget=24000;
    public DragonEggBlockEntity(BlockPos pos,BlockState state){ super(ModBlockEntities.DRAGON_EGG,pos,state); }
    public void configure(DragonSpecies s,DragonGenome g,UUID player){species=s;genome=g;bondedPlayer=player;setChanged();}
    public static void tick(Level level,BlockPos pos,BlockState state,DragonEggBlockEntity egg){
        if(level.isClientSide()) return;
        if(egg.genome==null) egg.genome=DragonGenome.roll(level.getRandom(),egg.species);
        egg.incubation += egg.incubationRate(level,pos);
        if(egg.incubation>=egg.hatchTarget && level instanceof ServerLevel sl) egg.hatch(sl,pos);
        if((egg.incubation&255)==0) egg.setChanged();
    }
    private int incubationRate(Level level,BlockPos pos){
        int heat=0; for(BlockPos p:BlockPos.betweenClosed(pos.offset(-2,-1,-2),pos.offset(2,1,2))){ String n=level.getBlockState(p).getBlock().toString(); if(n.contains("lava")||n.contains("magma")||n.contains("fire")) heat++; }
        return switch(species){ case EMBER -> heat>0?3:1; case FROST -> level.canSeeSky(pos)?2:1; case STORM -> level.isRainingAt(pos.above())?3:1; case VERDANT -> level.getMaxLocalRawBrightness(pos)>9?2:1; };
    }
    private void hatch(ServerLevel level,BlockPos pos){
        AbstractDragonEntity d=switch(species){
            case EMBER -> ModEntityTypes.EMBER_DRAGON.create(level,EntitySpawnReason.TRIGGERED);
            case STORM -> ModEntityTypes.STORM_DRAGON.create(level,EntitySpawnReason.TRIGGERED);
            case FROST -> ModEntityTypes.FROST_DRAGON.create(level,EntitySpawnReason.TRIGGERED);
            case VERDANT -> ModEntityTypes.VERDANT_DRAGON.create(level,EntitySpawnReason.TRIGGERED);
        };
        if(d!=null){
            d.setPos(pos.getX()+.5,pos.getY()+.4,pos.getZ()+.5);
            d.setYRot(level.getRandom().nextFloat()*360f);
            d.setXRot(0f);
            d.installHatchedGenome(genome,bondedPlayer);
            level.addFreshEntity(d);
            level.removeBlock(pos,false);
        }
    }
    @Override protected void saveAdditional(ValueOutput out){
        super.saveAdditional(out);
        out.putString("Species",species.name());
        out.putInt("Incubation",incubation);
        out.putInt("HatchTarget",hatchTarget);
        if(bondedPlayer!=null) out.putString("BondedPlayer",bondedPlayer.toString());
        if(genome!=null){
            out.putDouble("AdultScale",genome.adultScale());
            out.putDouble("WingBias",genome.wingBias());
            out.putDouble("BulkBias",genome.bulkBias());
            out.putDouble("Temperament",genome.temperament());
            out.putLong("VisualSeed",genome.visualSeed());
        }
    }
    @Override protected void loadAdditional(ValueInput in){
        super.loadAdditional(in);
        try{species=DragonSpecies.valueOf(in.getStringOr("Species",DragonSpecies.EMBER.name()));}catch(Exception ignored){species=DragonSpecies.EMBER;}
        incubation=in.getIntOr("Incubation",0);
        hatchTarget=Math.max(1200,in.getIntOr("HatchTarget",24000));
        String bonded=in.getStringOr("BondedPlayer","");
        if(!bonded.isBlank()) try{bondedPlayer=UUID.fromString(bonded);}catch(IllegalArgumentException ignored){bondedPlayer=null;}
        double adultScale=in.getDoubleOr("AdultScale",Double.NaN);
        if(!Double.isNaN(adultScale)) genome=new DragonGenome(
                adultScale,
                in.getDoubleOr("WingBias",1.0),
                in.getDoubleOr("BulkBias",1.0),
                in.getDoubleOr("Temperament",0.5),
                in.getLongOr("VisualSeed",0L));
    }
}
