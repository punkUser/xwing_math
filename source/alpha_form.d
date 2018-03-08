import simulation;
import simulation_state;
import form;
import dice;

import std.bitmanip;

enum AlphaAttackWeapon : ubyte
{
    // NOTE: Do not change the order or it will invalidate links!
    _2d = 0,
    _2d_CrackShot,    
    _3d,
    _3d_CrackShot,
    _3d_IonCannon,
    _3d_LoneWolf,
    _3d_ManglerCannon,
    _3d_ManglerCannonLoneWolf,
    _3d_TwinLaserTurret,
    _3d_TwinLaserTurret_Maul1Ezra,
    _3d_ReyFinn,
    _4d,
    _4d_CrackShot,
    _4d_HeavyLaserCannon,
    _4d_HeavyLaserCannonLoneWolf,
    _4d_LoneWolf,
    _4d_Maul1Ezra,
    _4d_MaulAllEzra,
    _4d_ConcussionMissile,
    _4d_HarpoonMissile,
    _4d_ProtonTorpedo,
    _4d_ReyFinn,
    _5d,
    _5d_AdvancedProtonTorpedo,
    _5d_HarpoonMissile,
    _5d_Maul1Ezra,
    _5d_MaulAllEzra,
    _2d_Backdraft,
    _3d_Backdraft,
}

align(1) struct AlphaForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "defense_dice", 			        4,
        ubyte, "defense_focus_token_count",     4,
        ubyte, "defense_evade_token_count",     4,
        ubyte, "defense_stress_count",          4,

        ubyte, "defense_pilot",                 8, // DefensePilot enum

        bool, "defense_latts_razzi",            1,
        bool, "defense_lone_wolf",              1,
        bool, "defense_wired",                  1,
        bool, "defense_finn",                   1,
                                                
        bool, "defense_sensor_jammer",          1,
        bool, "defense_autothrusters",          1,
        bool, "defense_hotshot_copilot",        1,
        bool, "defense_concord_dawn",           1,
                                                
        bool, "defense_sensor_cluster",         1,
        bool, "defense_c3p0_0",                 1,
        bool, "defense_c3p0_1",                 1,
        bool, "defense_palpatine_evade",        1,

        bool, "defense_glitterstim",            1,
        bool, "defense_m9g8_attack_die",        1,

        ubyte, "",                              5,

        ubyte, "a1_weapon",                     8, // AlphaAttackWeapon enum
        ubyte, "a1_reroll_any_count",           4,
        bool,  "a1_enabled",                    1,
        bool,  "a1_focus",                      1,
        bool,  "a1_target_lock",                1,
        bool,  "a1_guidance_chips_hit",         1,
        bool,  "a1_guidance_chips_crit",        1,
        ubyte, "a1__unused",                    4,
    ));

    mixin(bitfields!(
        ubyte, "a2_weapon",                     8, // AlphaAttackWeapon enum
        ubyte, "a2_reroll_any_count",           4,
        bool,  "a2_enabled",                    1,
        bool,  "a2_focus",                      1,
        bool,  "a2_target_lock",                1,
        bool,  "a2_guidance_chips_hit",         1,
        bool,  "a2_guidance_chips_crit",        1,
        ubyte, "a2__unused",                    4,

        ubyte, "a3_weapon",                     8, // AlphaAttackWeapon enum
        ubyte, "a3_reroll_any_count",           4,
        bool,  "a3_enabled",                    1,
        bool,  "a3_focus",                      1,
        bool,  "a3_target_lock",                1,
        bool,  "a3_guidance_chips_hit",         1,
        bool,  "a3_guidance_chips_crit",        1,
        ubyte, "a3__unused",                    4,

        ubyte, "a4_weapon",                     8, // AlphaAttackWeapon enum
        ubyte, "a4_reroll_any_count",           4,
        bool,  "a4_enabled",                    1,
        bool,  "a4_focus",                      1,
        bool,  "a4_target_lock",                1,
        bool,  "a4_guidance_chips_hit",         1,
        bool,  "a4_guidance_chips_crit",        1,
        ubyte, "a4__unused",                    4,

        ubyte, "",                              1,
    ));

    mixin(bitfields!(
        ubyte, "a5_weapon",                     8, // AlphaAttackWeapon enum
        ubyte, "a5_reroll_any_count",           4,
        bool,  "a5_enabled",                    1,
        bool,  "a5_focus",                      1,
        bool,  "a5_target_lock",                1,
        bool,  "a5_guidance_chips_hit",         1,
        bool,  "a5_guidance_chips_crit",        1,
        ubyte, "a5__unused",                    4,

        ubyte, "",                             11,
    ));

    // Can always add more on the end, so no need to reserve space explicitly

    static AlphaForm defaults()
    {
        AlphaForm defaults;

        defaults.defense_dice       = 3;

        defaults.a1_weapon          = AlphaAttackWeapon._3d;
        defaults.a2_weapon          = AlphaAttackWeapon._3d;
        defaults.a3_weapon          = AlphaAttackWeapon._3d;
        defaults.a4_weapon          = AlphaAttackWeapon._3d;
        defaults.a5_weapon          = AlphaAttackWeapon._3d;

        defaults.a1_enabled         = true;

        return defaults;
    }
};

public TokenState to_attack_tokens(alias prefix)(ref const(AlphaForm) form)
{
    TokenState attack_tokens;

    mixin("attack_tokens.focus            = form." ~ prefix ~ "_focus ? 1 : 0;");
    mixin("attack_tokens.target_lock      = form." ~ prefix ~ "_target_lock ? 1 : 0;");
    mixin("attack_tokens.amad_any_to_hit  = form." ~ prefix ~ "_guidance_chips_hit;");
    mixin("attack_tokens.amad_any_to_crit = form." ~ prefix ~ "_guidance_chips_crit;");

    // "Tokens" based on the weapon
    mixin("const AlphaAttackWeapon weapon = cast(AlphaAttackWeapon)form." ~ prefix ~ "_weapon;");
    attack_tokens.crack_shot = 
        (weapon == AlphaAttackWeapon._2d_CrackShot ||
         weapon == AlphaAttackWeapon._3d_CrackShot ||
         weapon == AlphaAttackWeapon._4d_CrackShot);

    return attack_tokens;
}

public TokenState to_defense_tokens(ref const(AlphaForm) form)
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

static SimulationSetup to_simulation_setup(alias prefix)(ref const(AlphaForm) form)
{
    SimulationSetup setup;

    // Grab the relevant form values for this attacker
    mixin("const AlphaAttackWeapon weapon = cast(AlphaAttackWeapon)form." ~ prefix ~ "_weapon;");
    mixin("const int reroll_any_count     = form." ~ prefix ~ "_reroll_any_count;");

    // Hotshot on defender can be relevant for TLT attacks
    setup.AMAD.reroll_any_count.always   = reroll_any_count;
    setup.attack_must_spend_focus        = form.defense_hotshot_copilot;     // NOTE: Affects the *other* person

    switch (weapon)
    {
        case AlphaAttackWeapon._2d:
        case AlphaAttackWeapon._2d_CrackShot:                   // Crack shot handled in tokens
            setup.attack_dice                                   = 2;
            break;

        case AlphaAttackWeapon._2d_Backdraft:
            setup.attack_dice                                   = 2;
            setup.AMAD.add_crit_count                           = 1;       // Backdraft/ATC
            break;

        case AlphaAttackWeapon._3d:
        case AlphaAttackWeapon._3d_CrackShot:                   // Crack shot handled in tokens
            setup.attack_dice                                   = 3;
            break;

        case AlphaAttackWeapon._3d_Backdraft:
            setup.attack_dice                                   = 3;
            setup.AMAD.add_crit_count                           = 1;       // Backdraft/ATC
            break;

        case AlphaAttackWeapon._3d_IonCannon:
            setup.attack_dice                                   = 3;
            setup.attack_one_damage_on_hit                      = true;     // Ion Cannon
            break;

        case AlphaAttackWeapon._3d_LoneWolf:
            setup.attack_dice                                   = 3;
            setup.AMAD.reroll_blank_count.always                = 1;        // Lone Wolf
            break;

        case AlphaAttackWeapon._3d_ManglerCannon:
            setup.attack_dice                                   = 3;
            setup.AMAD.hit_to_crit_count                        = 1;        // Mangler Cannon
            break;

        case AlphaAttackWeapon._3d_ManglerCannonLoneWolf:
            setup.attack_dice                                   = 3;
            setup.AMAD.reroll_blank_count.always                = 1;        // Lone Wolf
            setup.AMAD.hit_to_crit_count                        = 1;        // Mangler Cannon
            break;

        case AlphaAttackWeapon._3d_TwinLaserTurret:
            setup.attack_dice                                   = 3;
            setup.type                                          = MultiAttackType.SecondaryPerformTwice;
            setup.attack_one_damage_on_hit                      = true;     // TLT
            break;

        case AlphaAttackWeapon._3d_TwinLaserTurret_Maul1Ezra:
            setup.attack_dice                                   = 3;
            setup.type                                          = MultiAttackType.SecondaryPerformTwice;
            setup.attack_one_damage_on_hit                      = true;     // TLT
            setup.attack_lose_stress_on_hit                     = true;     // Maul
            setup.AMAD.reroll_any_gain_stress_count.unstressed  = 1;        // Maul
            setup.AMAD.focus_to_crit_count.stressed             = 1;        // Ezra
            break;

        case AlphaAttackWeapon._3d_ReyFinn:
            setup.attack_dice                                   = 3;
            setup.AMAD.reroll_blank_count.always                = 2;        // Rey
            setup.AMAD.add_blank_count                          = 1;        // Finn
            break;

        case AlphaAttackWeapon._4d:
        case AlphaAttackWeapon._4d_CrackShot:                   // Crack shot handled in tokens
            setup.attack_dice                                   = 4;
            break;

        case AlphaAttackWeapon._4d_HeavyLaserCannon:
            setup.attack_dice                                   = 4;
            setup.attack_heavy_laser_cannon                     = true;     // HLC
            break;

        case AlphaAttackWeapon._4d_HeavyLaserCannonLoneWolf:
            setup.attack_dice                                   = 4;
            setup.attack_heavy_laser_cannon                     = true;     // HLC
            setup.AMAD.reroll_blank_count.always                = 1;        // Lone Wolf
            break;

        case AlphaAttackWeapon._4d_LoneWolf:
            setup.attack_dice                                   = 4;
            setup.AMAD.reroll_blank_count.always                = 1;        // Lone Wolf
            break;

        case AlphaAttackWeapon._4d_Maul1Ezra:
            setup.attack_dice                                   = 4;
            setup.attack_lose_stress_on_hit                     = true;     // Maul
            setup.AMAD.reroll_any_gain_stress_count.unstressed  = 1;        // Maul
            setup.AMAD.focus_to_crit_count.stressed             = 1;        // Ezra
            break;

        case AlphaAttackWeapon._4d_MaulAllEzra:
            setup.attack_dice                                   = 4;
            setup.attack_lose_stress_on_hit                     = true;             // Maul
            setup.AMAD.reroll_any_gain_stress_count.unstressed  = k_all_dice_count; // Maul
            setup.AMAD.focus_to_crit_count.stressed             = 1;                // Ezra
            break;

        case AlphaAttackWeapon._4d_ConcussionMissile:
            setup.attack_dice                                   = 4;
            setup.AMAD.blank_to_hit_count                       = 1;        // Concussion
            break;

        case AlphaAttackWeapon._4d_HarpoonMissile:
            setup.attack_dice                                   = 4;
            setup.attack_harpooned_on_hit                       = true;     // Harpoon
            break;

        case AlphaAttackWeapon._4d_ProtonTorpedo:
            setup.attack_dice                                   = 4;
            setup.AMAD.focus_to_crit_count.always               = 1;        // Proton
            break;

        case AlphaAttackWeapon._4d_ReyFinn:
            setup.attack_dice                                   = 4;
            setup.AMAD.reroll_blank_count.always                = 2;        // Rey
            setup.AMAD.add_blank_count                          = 1;        // Finn
            break;

        case AlphaAttackWeapon._5d:
            setup.attack_dice                                   = 5;
            break;

        case AlphaAttackWeapon._5d_AdvancedProtonTorpedo:
            setup.attack_dice                                   = 5;
            setup.AMAD.blank_to_focus_count                     = 3;        // APT
            break;

        case AlphaAttackWeapon._5d_HarpoonMissile:
            setup.attack_dice                                   = 5;
            setup.attack_harpooned_on_hit                       = true;     // Harpoon
            break;

        case AlphaAttackWeapon._5d_Maul1Ezra:
            setup.attack_dice                                   = 5;
            setup.attack_lose_stress_on_hit                     = true;     // Maul
            setup.AMAD.reroll_any_gain_stress_count.unstressed  = 1;        // Maul
            setup.AMAD.focus_to_crit_count.stressed             = 1;        // Ezra
            break;

        case AlphaAttackWeapon._5d_MaulAllEzra:
            setup.attack_dice                                   = 5;
            setup.attack_lose_stress_on_hit                     = true;             // Maul
            setup.AMAD.reroll_any_gain_stress_count.unstressed  = k_all_dice_count; // Maul
            setup.AMAD.focus_to_crit_count.stressed             = 1;                // Ezra
            break;

        default:
            assert(false);      // Unknown weapon!
    }
    
    




    // ****************************************************************************************************************

    setup.defense_dice                          = form.defense_dice;

    // Special effects
    setup.defense_guess_evades                  = form.defense_c3p0_1 ? 1 : 0;

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
