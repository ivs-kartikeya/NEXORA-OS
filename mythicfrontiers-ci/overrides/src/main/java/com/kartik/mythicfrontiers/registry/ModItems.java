package com.kartik.mythicfrontiers.registry;
import com.kartik.mythicfrontiers.MythicFrontiers;
import com.kartik.mythicfrontiers.item.*;
import net.fabricmc.fabric.api.creativetab.v1.CreativeModeTabEvents;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.Identifier;
import net.minecraft.world.item.*;
import java.util.function.Function;
public final class ModItems {
    private static ResourceKey<Item> key(String s){return ResourceKey.create(Registries.ITEM,Identifier.fromNamespaceAndPath(MythicFrontiers.MOD_ID,s));}
    private static Item reg(String id,Function<Item.Properties,Item> f,Item.Properties p){ ResourceKey<Item> k=key(id); Item i=f.apply(p.setId(k)); return Registry.register(BuiltInRegistries.ITEM,k,i); }
    public static final Item DRAGON_WHISTLE=reg("dragon_whistle",DragonWhistleItem::new,new Item.Properties().stacksTo(1));
    public static final Item DRAGON_HARNESS=reg("dragon_harness",DragonHarnessItem::new,new Item.Properties().stacksTo(1));
    public static final Item DRAGON_EGG=reg("dragon_egg",p->new BlockItem(ModBlocks.DRAGON_EGG,p),new Item.Properties().stacksTo(1).useBlockDescriptionPrefix());
    private ModItems(){}
    public static void bootstrap(){
        CreativeModeTabEvents.modifyOutputEvent(CreativeModeTabs.TOOLS_AND_UTILITIES).register(e->{e.accept(DRAGON_WHISTLE);e.accept(DRAGON_HARNESS);e.accept(DRAGON_EGG);});
    }
}
