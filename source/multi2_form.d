import simulation;
import simulation_state;
import dice;
import form;

import std.bitmanip;

align(1) struct Multi2Form
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(
        ubyte, "defense_dice",                4,
        uint,  "",                           28,
        ));

    // TODO: Multiple copies obviously
    mixin(bitfields!(
        ubyte, "attack_dice",                 4,
        uint,  "",                           28,
        ));

    // Can always add more on the end, so no need to reserve space explicitly

    static Multi2Form defaults()
    {
        Multi2Form defaults;

        // Anything not referenced defaults to 0/false
        defaults.attack_dice = 3;
        defaults.defense_dice = 3;

        return defaults;
    }
};

//pragma(msg, "sizeof(Multi2Form) = " ~ to!string(Multi2Form.sizeof));

public TokenState to_attack_tokens(ref const(Multi2Form) form)
{
    TokenState attack_tokens;

    return attack_tokens;
}

public TokenState to_defense_tokens(ref const(Multi2Form) form)
{
    TokenState defense_tokens;

    return defense_tokens;
}
