package com.kartik.mythicfrontiers.dragon;

import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.world.entity.Entity;

/** Natural prey is deliberately entity-based: dragons hunt livestock, not only steak items. */
public final class DragonDiet {
    private DragonDiet() {}
    public static boolean isNaturalPrey(Entity entity) {
        Identifier id = BuiltInRegistries.ENTITY_TYPE.getKey(entity.getType());
        if (id == null) return false;
        return switch (id.toString()) {
            case "minecraft:sheep", "minecraft:goat", "minecraft:cow", "minecraft:pig" -> true;
            default -> false;
        };
    }
}
