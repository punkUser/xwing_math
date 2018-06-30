import simulation_state2;

import std.bitmanip;

align(1) struct DefenseForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "dice", 			        4,

        ubyte, "force_count",           3,
        ubyte, "focus_count",           3,
        ubyte, "calculate_count",       3,
        ubyte, "evade_count",           3,
        ubyte, "reinforce_count",       3,        
        ubyte, "stress_count",          3,
        ubyte, "jam_count",             3,
        bool,  "c3p0",                  1,
        bool,  "lone_wolf",             1,
        bool,  "stealth_device",        1,
        bool,  "biggs",                 1, 
        bool,  "_unused1",              1,
        bool,  "iden",                  1,
        bool,  "selfless",              1, 
        
        // 32
        ubyte, "pilot",                 6, // DefensePilot2 enum
        bool,  "l337",                  1,
        ubyte, "_unused2",              1, // USE ME
        
        // 40
        ubyte, "lock_count",            3,
        ubyte, "_unused3",              1, // USE ME
        ubyte, "ship",                  6, // DefenseShip2 enum

        uint, "",                      14,
        ));

    static DefenseForm defaults()
    {
        DefenseForm defaults;
        defaults.dice = 0;
        return defaults;
    }
};

public TokenState2 to_defense_tokens2(ref const(DefenseForm) form)
{
    TokenState2 defense_tokens;

    defense_tokens.lock               = form.lock_count;
    defense_tokens.force              = form.force_count;
    defense_tokens.focus              = form.focus_count;
    defense_tokens.calculate          = form.calculate_count;
    defense_tokens.evade              = form.evade_count;
    defense_tokens.reinforce          = form.reinforce_count;
    defense_tokens.stress             = form.stress_count;

    defense_tokens.iden               = form.iden;
    defense_tokens.lone_wolf          = form.lone_wolf;
    defense_tokens.stealth_device     = form.stealth_device;
    defense_tokens.l337               = form.l337;

    return defense_tokens;
}
