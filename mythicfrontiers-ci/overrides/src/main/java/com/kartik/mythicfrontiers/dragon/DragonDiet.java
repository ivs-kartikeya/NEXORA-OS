package com.kartik.mythicfrontiers.dragon;

import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;

/** Natural prey is deliberately entity-based: dragons hunt livestock, not only steak items. */
public final class DragonDiet {
    private DragonDiet() {}
    public static boolean isNaturalPrey(Entity entity) {
        EntityType<?> type = entity.getType();
        return type == EntityType.SHEEP || type == EntityType.GOAT || type == EntityType.COW || type == EntityType.PIG;
    }
}
