import simulation_state2;

import std.bitmanip;

align(1) struct DefenseForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "dice", 			                4,

        ubyte, "force_count",                   3,
        ubyte, "focus_count",                   3,
        ubyte, "calculate_count",               3,
        ubyte, "evade_count",                   3,
        ubyte, "reinforce_count",               3,        
        ubyte, "stress_count",                  3,
        ubyte, "jam_count",                     3,
        bool,  "c3p0",                          1,
        bool,  "lone_wolf",                     1,
        bool,  "stealth_device",                1,
        bool,  "biggs",                         1, 
        bool,  "_unused1",                      1,
        bool,  "iden",                          1,
        bool,  "selfless",                      1, 
        
        // 32
        ubyte, "pilot",                         6, // DefensePilot2 enum
        bool,  "l337",                          1,
        bool,  "elusive",                       1,
        
        // 40
        ubyte, "lock_count",                    3,
        bool,  "scum_lando_crew",               1,
        ubyte, "ship",                          6, // DefenseShip2 enum
        bool,  "serissu",                       1,
        bool,  "rebel_millennium_falcon",       1,
        bool,  "finn_gunner",                   1,
        bool,  "heroic",                        1,

        // Used by the shots to die form, but convenient to use the same defense form, albeit a subset
        uint,  "ship_hull",                     5, // 0..31
        uint,  "ship_shields",                  5, // 0..31
        ));

    mixin(bitfields!(
        bool,  "brilliant_evasion",             1,
        bool,  "hate_1_force",                  1,
        bool,  "hate_2_force",                  1,
        bool,  "hate_3_force",                  1,

        uint,  "",                              4,
        ));

    static DefenseForm defaults()
    {
        DefenseForm defaults;
        defaults.dice = 0;
        return defaults;
    }
};

public TokenState to_defense_tokens2(ref const(DefenseForm) form)
{
    TokenState defense_tokens;

    defense_tokens.lock                 = form.lock_count;
    defense_tokens.force                = form.force_count;
    defense_tokens.focus                = form.focus_count;
    defense_tokens.calculate            = form.calculate_count;
    defense_tokens.evade                = form.evade_count;
    defense_tokens.reinforce            = form.reinforce_count;
    defense_tokens.stress               = form.stress_count;

    defense_tokens.iden                 = form.iden;
    defense_tokens.lone_wolf            = form.lone_wolf;
    defense_tokens.stealth_device       = form.stealth_device;
    defense_tokens.l337                 = form.l337;
    defense_tokens.elusive              = form.elusive;

    return defense_tokens;
}
