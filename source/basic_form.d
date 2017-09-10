import simulation;
import dice;

import std.bitmanip;

struct BasicForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "attack_type",                 4,        // enum MultiAttackType
        ubyte, "attack_dice",                 4,
        ubyte, "attack_focus_token_count",    4,
        ubyte, "attack_target_lock_count",    4,

        ubyte, "defense_dice", 			      4,
        ubyte, "defense_focus_token_count",   4,
        ubyte, "defense_evade_token_count",   4,
        bool, "attack_rey_pilot",             1,
        bool, "attack_expertise",             1,
        bool, "attack_fearlessness",          1,
        bool, "attack_juke",                  1,

        bool, "attack_lone_wolf",             1,
        bool, "attack_marksmanship",          1,
        bool, "attack_predator_1",            1,
        bool, "attack_predator_2",            1,

        bool, "attack_rage",                  1,
        bool, "attack_wired",                 1,
        bool, "attack_bistan",                1,
        bool, "attack_dengar_1",              1,

        bool, "attack_dengar_2",              1,
        bool, "attack_ezra_crew",             1,
        bool, "attack_finn",                  1,
        bool, "attack_mercenary_copilot",     1,

        bool, "attack_adv_proton_torpedoes",  1,
        bool, "attack_concussion_missiles",   1,
        bool, "attack_heavy_laser_cannon",    1,
        bool, "attack_mangler_cannon",        1,

        bool, "attack_one_damage_on_hit",     1,
        bool, "attack_proton_torpedoes",      1,
        bool, "attack_accuracy_corrector",    1,
        bool, "attack_fire_control_system",   1,

        bool, "attack_guidance_chips_hit",    1,
        bool, "attack_guidance_chips_crit",   1,
        bool, "defense_concord_dawn",         1,
        bool, "defense_luke_pilot",           1,

        bool, "defense_rey_pilot",            1,
        bool, "defense_lone_wolf",            1,
        bool, "defense_wired",                1,
        bool, "defense_finn",                 1,

        bool, "defense_sensor_jammer",        1,
        bool, "defense_autothrusters",        1,
        bool, "attack_hotshot_copilot",       1,
        bool, "defense_hotshot_copilot",      1,
        ));

    // Can always add more on the end, so no need to reserve space explicitly

    static BasicForm defaults()
    {
        BasicForm defaults;

        // Anything not referenced defaults to 0/false
        defaults.attack_type = MultiAttackType.Single;
        defaults.attack_dice = 3;
        defaults.defense_dice = 3;

        return defaults;
    }
};

//pragma(msg, "sizeof(BasicForm) = " ~ to!string(BasicForm.sizeof));


static SimulationSetup to_simulation_setup(ref const(BasicForm) form)
{
    SimulationSetup setup;

    setup.type                       = cast(MultiAttackType)form.attack_type;

    setup.attack_dice				 = form.attack_dice;
    setup.attack_tokens.focus        = form.attack_focus_token_count;
    setup.attack_tokens.target_lock  = form.attack_target_lock_count;

    // Once per turn abilities are treated like "tokens" for simulation purposes
    setup.attack_tokens.amad_any_to_hit  = form.attack_guidance_chips_hit;
    setup.attack_tokens.amad_any_to_crit = form.attack_guidance_chips_crit;

    // Add results
    setup.AMAD.add_hit_count       += form.attack_fearlessness ? 1 : 0;
    setup.AMAD.add_blank_count     += form.attack_finn         ? 1 : 0;

    // Rerolls
    setup.AMAD.reroll_any_count    += form.attack_dengar_1      ? 1 : 0;
    setup.AMAD.reroll_any_count    += form.attack_dengar_2      ? 2 : 0;
    setup.AMAD.reroll_any_count    += form.attack_predator_1    ? 1 : 0;
    setup.AMAD.reroll_any_count    += form.attack_predator_2    ? 2 : 0;
    setup.AMAD.reroll_any_count    += form.attack_rage          ? 3 : 0;
    setup.AMAD.reroll_blank_count  += form.attack_lone_wolf     ? 1 : 0;
    setup.AMAD.reroll_blank_count  += form.attack_rey_pilot     ? 2 : 0;
    setup.AMAD.reroll_focus_count  += form.attack_wired         ? k_all_dice_count : 0;

    // Change results
    setup.AMAD.focus_to_crit_count  += form.attack_proton_torpedoes     ? 1 : 0;
    setup.AMAD.focus_to_crit_count  += form.attack_marksmanship         ? 1 : 0;
    setup.AMAD.focus_to_hit_count   += form.attack_marksmanship         ? k_all_dice_count : 0;
    setup.AMAD.focus_to_hit_count   += form.attack_expertise            ? k_all_dice_count : 0;
    setup.AMAD.blank_to_hit_count   += form.attack_concussion_missiles  ? 1 : 0;
    setup.AMAD.blank_to_focus_count += form.attack_adv_proton_torpedoes ? 3 : 0;
    setup.AMAD.hit_to_crit_count    += form.attack_bistan               ? 1 : 0;
    setup.AMAD.hit_to_crit_count    += form.attack_mercenary_copilot    ? 1 : 0;
    setup.AMAD.hit_to_crit_count    += form.attack_mangler_cannon       ? 1 : 0;
    setup.AMAD.accuracy_corrector    = form.attack_accuracy_corrector;

    // TODO: Needs "if stressed"
    //setup.AMAD.focus_to_crit_count  += form.attack_ezra_crew            ? 1 : 0;

    // Modify defense dice
    setup.AMDD.evade_to_focus_count += form.attack_juke                 ? 1 : 0;

    // Special effects...
    setup.attack_heavy_laser_cannon  = form.attack_heavy_laser_cannon;
    setup.attack_fire_control_system = form.attack_fire_control_system;
    setup.attack_one_damage_on_hit   = form.attack_one_damage_on_hit;

    setup.attack_must_spend_focus    = form.defense_hotshot_copilot;    // NOTE: Affects the *other* person
    setup.defense_must_spend_focus   = form.attack_hotshot_copilot;     // NOTE: Affects the *other* person

    setup.defense_dice            = form.defense_dice;
    setup.defense_tokens.focus    = form.defense_focus_token_count;
    setup.defense_tokens.evade    = form.defense_evade_token_count;

    // Add results
    setup.DMDD.add_evade_count      += form.defense_concord_dawn        ? 1 : 0;
    setup.DMDD.add_blank_count      += form.defense_finn                ? 1 : 0;

    // Rerolls
    setup.DMDD.reroll_blank_count   += form.defense_lone_wolf           ? 1 : 0;
    setup.DMDD.reroll_blank_count   += form.defense_rey_pilot           ? 2 : 0;
    setup.DMDD.reroll_focus_count   += form.defense_wired               ? k_all_dice_count : 0;

    // Change results
    setup.DMDD.focus_to_evade_count += form.defense_luke_pilot          ? 1 : 0;
    setup.DMDD.blank_to_evade_count += form.defense_autothrusters       ? 1 : 0;

    // Modify attack dice
    setup.DMAD.hit_to_focus_no_reroll_count += form.defense_sensor_jammer ? 1 : 0;

    return setup;
}
