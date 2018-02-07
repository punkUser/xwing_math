import simulation;
import dice;

import std.bitmanip;

enum AttackWeapon : ubyte
{
    Primary3Dice = 0,
    Primary4Dice,
    HarpoonMissile,
    ConcussionMissile,
}

align(1) struct AlphaForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "defense_dice", 			      4,
        ubyte, "defense_focus_token_count",   4,
        ubyte, "defense_evade_token_count",   4,
        ubyte, "defense_stress_count",        4,

        ubyte, "attack_weapon",               8, // AttackPilot enum

        bool, "attack_focus",                 1,
        bool, "attack_target_lock",           1,
        bool, "attack_guidance_chips_hit",    1,
        bool, "attack_guidance_chips_crit",   1,

        ubyte, "pad",                         4,
        ));

    // Can always add more on the end, so no need to reserve space explicitly

    static AlphaForm defaults()
    {
        AlphaForm defaults;

        // TODO

        return defaults;
    }
};

static SimulationSetup to_simulation_setup(ref const(AlphaForm) form)
{
    SimulationSetup setup;

    // TODO!

    return setup;
}
