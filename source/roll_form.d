import form;
import dice;

import std.bitmanip;

align(1) struct RollForm
{
    mixin(bitfields!(
        ubyte, "attack_blank_count",       4,
        ubyte, "attack_focus_count",       4,
        ubyte, "attack_hit_count",         4,
        ubyte, "attack_crit_count",        4,

        ubyte, "defense_blank_count",      4,
        ubyte, "defense_focus_count",      4,
        ubyte, "defense_evade_count",      4,
        ubyte, "",                         4,
    ));

    static RollForm defaults()
    {
        RollForm defaults;
        return defaults;
    }
}

public DiceState to_attack_dice_state(ref const(RollForm) roll)
{
    DiceState dice;
    dice.results[DieResult.Blank] = roll.attack_blank_count;
    dice.results[DieResult.Focus] = roll.attack_focus_count;
    dice.results[DieResult.Hit]   = roll.attack_hit_count;
    dice.results[DieResult.Crit]  = roll.attack_crit_count;
    return dice;
}

public DiceState to_defense_dice_state(ref const(RollForm) roll)
{
    DiceState dice;
    dice.results[DieResult.Blank] = roll.defense_blank_count;
    dice.results[DieResult.Focus] = roll.defense_focus_count;
    dice.results[DieResult.Evade] = roll.defense_evade_count;
    return dice;
}
