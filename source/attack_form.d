import simulation_state2;

import std.bitmanip;

align(1) struct AttackForm
{
    mixin(bitfields!(
        bool,  "enabled",                        1,
        ubyte, "lock_count",                     3,
        ubyte, "dice",                           4,

        // 8        
        ubyte, "force_count",                    3,
        ubyte, "focus_count",                    3,
        ubyte, "calculate_count",                3,
        ubyte, "evade_count",                    3,
        ubyte, "reinforce_count",                3,
        ubyte, "stress_count",                   3,
        ubyte, "jam_count",                      3,
        bool,  "fire_control_system",            1,
        bool,  "heavy_laser_cannon",             1,
        bool,  "proton_torpedoes",               1,

        // 32
        ubyte, "pilot",                          6, // AttackPilot2 enum
        bool,  "predator",                       1,
        bool,  "ion_weapon",                     1,
        
        // 40
        bool,  "juke",                           1,
        bool,  "roll_all_hits",                  1,
        bool,  "howlrunner",                     1,
        bool,  "lone_wolf",                      1,
        bool,  "marksmanship",                   1,
        byte,  "defense_dice_diff",              4,

        // 32
        bool,  "fearless",                       1,
        ubyte, "ship",                           6, // AttackShip2 enum

        bool,  "saw_gerrera_pilot",              1,
        bool,  "scum_lando_crew",                1,
        bool,  "agent_kallus",                   1,
        bool,  "finn_gunner",                    1,
        bool,  "fanatical",                      1,
        bool,  "heroic",                         1,

        uint, "",                                2,
        ));

    static AttackForm defaults(int attack_index)
    {
        AttackForm defaults;
        defaults.dice       = 3;
        defaults.enabled    = (attack_index == 0);
        return defaults;
    }
}

public TokenState to_attack_tokens2(ref const(AttackForm) form)
{
    TokenState attack_tokens;

    attack_tokens.lock                = form.lock_count;
    attack_tokens.force               = form.force_count;
    attack_tokens.focus               = form.focus_count;
    attack_tokens.calculate           = form.calculate_count;
    attack_tokens.evade               = form.evade_count;
    attack_tokens.reinforce           = form.reinforce_count;
    attack_tokens.stress              = form.stress_count;
    attack_tokens.lone_wolf           = form.lone_wolf;

    return attack_tokens;
}
