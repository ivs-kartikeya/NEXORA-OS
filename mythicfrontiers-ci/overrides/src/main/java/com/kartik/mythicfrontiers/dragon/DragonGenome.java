package com.kartik.mythicfrontiers.dragon;

import net.minecraft.util.RandomSource;

/** Persistent phenotype seed. Giant dragons are possible but intentionally rare. */
public record DragonGenome(double adultScale, double wingBias, double bulkBias, double temperament, long visualSeed) {
    public static DragonGenome roll(RandomSource random, DragonSpecies species) {
        double rarity = Math.pow(random.nextDouble(), 3.15);
        double size = species.minAdultScale + (species.maxAdultScale-species.minAdultScale)*rarity;
        double wing = clamp(0.92 + gaussianish(random)*0.15, 0.68, 1.30);
        double bulk = clamp(0.96 + gaussianish(random)*0.14, 0.72, 1.34);
        return new DragonGenome(size, wing, bulk, random.nextDouble(), random.nextLong());
    }
    public double visualScale(double maturity) {
        double t=clamp(maturity,0,1), smooth=t*t*(3-2*t);
        return 0.18 + (adultScale-0.18)*smooth;
    }
    private static double gaussianish(RandomSource r) { return (r.nextDouble()+r.nextDouble()+r.nextDouble()+r.nextDouble()-2.0)/2.0; }
    private static double clamp(double v,double lo,double hi){ return Math.max(lo,Math.min(hi,v)); }
}
