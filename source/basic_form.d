import simulation;
import simulation_state;
import dice;
import form;

import std.bitmanip;

align(1) struct BasicForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "attack_type",                 4, // enum MultiAttackType
        ubyte, "attack_dice",                 4,
        ubyte, "attack_focus_token_count",    4,
        ubyte, "attack_target_lock_count",    4,

        ubyte, "defense_dice", 			      4,
        ubyte, "defense_focus_token_count",   4,
        ubyte, "defense_evade_token_count",   4,
        bool, "attack_linked_battery",        1,
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
        bool, "attack_wookie_commandos",      1,

        bool, "defense_latts_razzi",          1,
        bool, "defense_lone_wolf",            1,
        bool, "defense_wired",                1,
        bool, "defense_finn",                 1,

        bool, "defense_sensor_jammer",        1,
        bool, "defense_autothrusters",        1,
        bool, "attack_hotshot_copilot",       1,
        bool, "defense_hotshot_copilot",      1,
        ));

    mixin(bitfields!(
        ubyte, "attack_stress_count",         4,
        ubyte, "defense_stress_count",        4,

        ubyte, "attack_pilot",                8, // AttackPilot enum
        ubyte, "defense_pilot",               8, // DefensePilot enum

        bool, "attack_zuckuss_1_evade",       1,
        bool, "attack_zuckuss_all_evade",     1,
        bool, "attack_maul_1",                1,
        bool, "attack_maul_all",              1,

        bool, "attack_weapons_guidance",      1,
        bool, "defense_sensor_cluster",       1,
        bool, "defense_c3p0_0",               1,
        bool, "defense_c3p0_1",               1,

        bool, "attack_palpatine_crit",        1,
        bool, "defense_palpatine_evade",      1,
        bool, "attack_crack_shot",            1,
        bool, "attack_a_score_to_settle",     1,

        bool, "defense_glitterstim",          1,
        bool, "defense_m9g8_attack_die",      1,
        bool, "attack_is_duncan_howard",      1,
        bool, "defense_is_duncan_howard",     1,

        uint, "",                            24,
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

public TokenState to_attack_tokens(ref const(BasicForm) form)
{
    TokenState attack_tokens;

    attack_tokens.focus              = form.attack_focus_token_count;
    attack_tokens.target_lock        = form.attack_target_lock_count;
    attack_tokens.stress             = form.attack_stress_count;

    // Once per round abilities are treated like "tokens" for simulation purposes
    attack_tokens.amad_any_to_hit    = form.attack_guidance_chips_hit;
    attack_tokens.amad_any_to_crit   = form.attack_guidance_chips_crit;
    attack_tokens.sunny_bounder      = form.attack_pilot == AttackPilot.SunnyBounder;
    attack_tokens.palpatine          = form.attack_palpatine_crit;
    attack_tokens.crack_shot         = form.attack_crack_shot;

    return attack_tokens;
}

public TokenState to_defense_tokens(ref const(BasicForm) form)
{
    TokenState defense_tokens;

    defense_tokens.focus                  = form.defense_focus_token_count;
    defense_tokens.evade                  = form.defense_evade_token_count;
    defense_tokens.stress                 = form.defense_stress_count;

    // Once per round abilities are treated like "tokens" for simulation purposes
    defense_tokens.sunny_bounder          = form.defense_pilot == DefensePilot.SunnyBounder;
    defense_tokens.palpatine              = form.defense_palpatine_evade;

    defense_tokens.defense_guess_evades   = (form.defense_c3p0_0 || form.defense_c3p0_1);

    return defense_tokens;
}

public SimulationSetup to_simulation_setup(ref const(BasicForm) form)
{
    SimulationSetup setup;

    setup.type                                              = cast(MultiAttackType)form.attack_type;

    setup.attack_dice				                        = form.attack_dice;

    // Special effects...
    setup.attack_heavy_laser_cannon                         = form.attack_heavy_laser_cannon;
    setup.attack_fire_control_system                        = form.attack_fire_control_system;
    setup.attack_one_damage_on_hit                          = form.attack_one_damage_on_hit;
    setup.attack_must_spend_focus                           = form.defense_hotshot_copilot;    // NOTE: Affects the *other* person
    setup.attack_lose_stress_on_hit                         = (form.attack_maul_1 || form.attack_maul_all);
    setup.attack_is_duncan_howard                           = form.attack_is_duncan_howard;

    // Add results
    setup.AMAD.add_hit_count                                += form.attack_fearlessness                     ? 1 : 0;
    setup.AMAD.add_crit_count                               += form.attack_pilot == AttackPilot.Backdraft   ? 1 : 0;
    setup.AMAD.add_blank_count                              += form.attack_finn                             ? 1 : 0;

    // Rerolls
    setup.AMAD.reroll_any_count.always                      += form.attack_dengar_1                         ? 1 : 0;
    setup.AMAD.reroll_any_count.always                      += form.attack_dengar_2                         ? 2 : 0;
    setup.AMAD.reroll_any_count.always                      += form.attack_predator_1                       ? 1 : 0;
    setup.AMAD.reroll_any_count.always                      += form.attack_predator_2                       ? 2 : 0;
    setup.AMAD.reroll_any_count.always                      += form.attack_rage                             ? 3 : 0;
    setup.AMAD.reroll_any_count.always                      += form.attack_linked_battery                   ? 1 : 0;
    setup.AMAD.reroll_blank_count.always                    += form.attack_lone_wolf                        ? 1 : 0;
    setup.AMAD.reroll_blank_count.always                    += form.attack_pilot == AttackPilot.Rey         ? 2 : 0;
    setup.AMAD.reroll_blank_count.always                    += form.attack_pilot == AttackPilot.HortonSalm  ? k_all_dice_count : 0;
    setup.AMAD.reroll_focus_count.always                    += form.attack_wookie_commandos                 ? k_all_dice_count : 0;
    setup.AMAD.reroll_focus_count.stressed                  += form.attack_wired                            ? k_all_dice_count : 0;
    setup.AMAD.reroll_any_count.stressed                    += form.attack_pilot == AttackPilot.Ibtisam     ? 1 : 0;
    setup.AMAD.reroll_any_gain_stress_count.unstressed      += form.attack_maul_1                           ? 1 : 0;
    setup.AMAD.reroll_any_gain_stress_count.unstressed      += form.attack_maul_all                         ? k_all_dice_count : 0;

    // Change results
    setup.AMAD.focus_to_crit_count.always                   += form.attack_a_score_to_settle                ? 1 : 0;
    setup.AMAD.focus_to_crit_count.always                   += form.attack_proton_torpedoes                 ? 1 : 0;
    setup.AMAD.focus_to_crit_count.always                   += form.attack_pilot == AttackPilot.RearAdmiralChiraneau ? 1 : 0;
    setup.AMAD.focus_to_crit_count.stressed                 += form.attack_ezra_crew                        ? 1 : 0;
    setup.AMAD.focus_to_crit_count.always                   += form.attack_marksmanship                     ? 1 : 0;
    setup.AMAD.focus_to_hit_count.always                    += form.attack_marksmanship                     ? k_all_dice_count : 0;
    setup.AMAD.focus_to_hit_count.unstressed                += form.attack_expertise                        ? k_all_dice_count : 0;
    setup.AMAD.focus_to_hit_count.focused                   += form.attack_pilot == AttackPilot.PoeDameron  ? 1 : 0;
    setup.AMAD.blank_to_hit_count                           += form.attack_concussion_missiles              ? 1 : 0;
    setup.AMAD.blank_to_focus_count                         += form.attack_adv_proton_torpedoes             ? 3 : 0;
    setup.AMAD.hit_to_crit_count                            += form.attack_bistan                           ? 1 : 0;
    setup.AMAD.hit_to_crit_count                            += form.attack_mercenary_copilot                ? 1 : 0;
    setup.AMAD.hit_to_crit_count                            += form.attack_mangler_cannon                   ? 1 : 0;
    setup.AMAD.accuracy_corrector                            = form.attack_accuracy_corrector;

    setup.AMAD.spend_focus_one_blank_to_hit                 += form.attack_weapons_guidance                 ? 1 : 0;

    // Modify defense dice
    setup.AMDD.reroll_evade_gain_stress_count.unstressed    += form.attack_zuckuss_1_evade                  ? 1 : 0;
    setup.AMDD.reroll_evade_gain_stress_count.unstressed    += form.attack_zuckuss_all_evade                ? k_all_dice_count : 0;
    setup.AMDD.evade_to_focus_count                         += form.attack_juke                             ? 1 : 0;
    

    
    // ****************************************************************************************************************

    setup.defense_dice                          = form.defense_dice;
    
    // Special effects
    setup.defense_guess_evades                  = form.defense_c3p0_1 ? 1 : 0;
    setup.defense_must_spend_focus              = form.attack_hotshot_copilot;     // NOTE: Affects the *other* person
    setup.defense_is_duncan_howard              = form.defense_is_duncan_howard;

    // Add results
    setup.DMDD.add_evade_count                  += form.defense_concord_dawn                        ? 1 : 0;
    setup.DMDD.add_focus_count                  += form.defense_pilot == DefensePilot.SabineWrenLancer ? 1 : 0;
    setup.DMDD.add_blank_count                  += form.defense_finn                                ? 1 : 0;

    // Rerolls
    setup.DMDD.reroll_blank_count.always        += form.defense_lone_wolf                           ? 1 : 0;
    setup.DMDD.reroll_blank_count.always        += form.defense_pilot == DefensePilot.Rey           ? 2 : 0;
    setup.DMDD.reroll_focus_count.stressed      += form.defense_wired                               ? k_all_dice_count : 0;
    setup.DMDD.reroll_any_count.stressed        += form.defense_pilot == DefensePilot.Ibtisam       ? 1 : 0;

    // Change results
    setup.DMDD.focus_to_evade_count.always      += form.defense_glitterstim                         ? k_all_dice_count : 0;
    setup.DMDD.focus_to_evade_count.always      += form.defense_pilot == DefensePilot.LukeSkywalker ? 1 : 0;
    setup.DMDD.focus_to_evade_count.stressed    += form.defense_pilot == DefensePilot.EzraBridger   ? 2 : 0;
    setup.DMDD.focus_to_evade_count.focused     += form.defense_pilot == DefensePilot.PoeDameron    ? 1 : 0;
    setup.DMDD.blank_to_evade_count             += form.defense_autothrusters                       ? 1 : 0;

    setup.DMDD.spend_focus_one_blank_to_evade   += form.defense_sensor_cluster                      ? 1 : 0;

    setup.DMDD.spend_attacker_stress_add_evade   = form.defense_latts_razzi;

    // Modify attack dice
    setup.DMAD.hit_to_focus_no_reroll_count     += form.defense_sensor_jammer                       ? 1 : 0;
    setup.DMAD.reroll_any_count                 += form.defense_m9g8_attack_die                     ? 1 : 0;

    return setup;
}
