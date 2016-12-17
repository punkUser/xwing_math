module simulation;

import std.algorithm;
import std.random;
import std.stdio;

public immutable kMaxDice = 10;
public immutable kDieSides = 8;


enum DieResult : int
{
    Blank = 0,
    Hit,
    Crit,
    Focus,
    Evade,
    Num
};
immutable DieResult[kDieSides] kAttackDieResult = [
    DieResult.Blank, DieResult.Blank,
    DieResult.Focus, DieResult.Focus,
    DieResult.Hit, DieResult.Hit, DieResult.Hit,
    DieResult.Crit
];
immutable DieResult[kDieSides] kDefenseDieResult = [
    DieResult.Blank, DieResult.Blank, DieResult.Blank,
    DieResult.Focus, DieResult.Focus,
    DieResult.Evade, DieResult.Evade, DieResult.Evade
];


struct AttackSetup
{
    int dice = 0;
    int focus_token_count = 0;
    int target_lock_count = 0;

    bool juke = false;                  // Setting this to true implies evade token present as well
    bool accuracy_corrector = false;
};

struct DefenseSetup
{
    int dice = 0;
    int focus_token_count = 0;
    int evade_token_count = 0;
};


struct SimulationResult
{
    int trial_count = 0;
    int hits = 0;
    int crits = 0;
    int attack_target_locks_used = 0;
    int defense_evade_tokens_used = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.trial_count += b.trial_count;
    a.hits += b.hits;
    a.crits += b.crits;
    a.attack_target_locks_used += b.attack_target_locks_used;
    a.defense_evade_tokens_used += b.defense_evade_tokens_used;
    return a;
}



SimulationResult simulate_attack(AttackSetup initial_attack_setup, DefenseSetup initial_defense_setup)
{
    assert(initial_attack_setup.dice  <= kMaxDice);
    assert(initial_defense_setup.dice <= kMaxDice);

    auto attack_setup  = initial_attack_setup;
    auto defense_setup = initial_defense_setup;

    // TODO: A lot of this could be optimized, but see how usable it is for now while keeping it readable

    // Roll Attack Dice
    DieResult[kMaxDice] max_attack_dice;
    DieResult[] attack_dice = max_attack_dice[0 .. attack_setup.dice];
    foreach (ref d; attack_dice)
        d = kAttackDieResult[uniform(0, kDieSides)];

    // Track any that we re-roll... can only do this once total
    bool[kMaxDice] attack_dice_rerolled;
    foreach (ref d; attack_dice_rerolled)
        d = false;

    // Modify Attack Dice
    {
        // Spend target lock?
        if (attack_setup.target_lock_count > 0)
        {
            int[DieResult.Num] attack_results;
            foreach (d; attack_dice)
                ++attack_results[d];

            int number_of_dice_rerolled = 0;
            foreach (int i; 0 .. attack_dice.length)
            {
                // If we don't have a focus token, also reroll focus results
                if (!attack_dice_rerolled[i] &&
                    (attack_dice[i] == DieResult.Blank ||
                    (attack_setup.focus_token_count == 0 && attack_dice[i] == DieResult.Focus)))
                {
                    attack_dice_rerolled[i] = true;
                    ++number_of_dice_rerolled;
                    attack_dice[i] = kAttackDieResult[uniform(0, kDieSides)];
                }
            }

            if (number_of_dice_rerolled > 0)
                --attack_setup.target_lock_count;
        }

        // Regular focus?
        if (attack_setup.focus_token_count > 0)
        {
            int[DieResult.Num] attack_results;
            foreach (d; attack_dice)
                ++attack_results[d];

            int number_of_dice_focused = 0;
            foreach (ref d; attack_dice)
            {
                // If we don't have a focus token, also reroll focus results
                if (d == DieResult.Focus)
                {
                    ++number_of_dice_focused;
                    d = DieResult.Hit;
                }
            }

            if (number_of_dice_focused > 0)
                --attack_setup.focus_token_count;
        }
    }


    // Roll Defense Dice
    DieResult[kMaxDice] max_defense_dice;
    DieResult[] defense_dice = max_defense_dice[0 .. defense_setup.dice];
    foreach (ref d; defense_dice)
        d = kDefenseDieResult[uniform(0, kDieSides)];

    // Modify Defense Dice
    int attack_target_lock_tokens_used = 0;
    {
        // Attacker modify defense dice
        if (attack_setup.juke)
        {
            // Find one evade and turn it to eye
            foreach (ref d; defense_dice)
            {
                if (d == DieResult.Evade)
                {
                    d = DieResult.Focus;
                    break;
                }
            }
        }
    }


    // Compare Results
    int[DieResult.Num] attack_results;  // Init to 0 by default
    int[DieResult.Num] defense_results; // Init to 0 by default

    foreach (d; attack_dice)
        ++attack_results[d];
    foreach (d; defense_dice)
        ++defense_results[d];

    // Cancel pairs of hits and evades
    {
        int canceled_hits = min(attack_results[DieResult.Hit], defense_results[DieResult.Evade]);
        attack_results[DieResult.Hit]    -= canceled_hits;
        defense_results[DieResult.Evade] -= canceled_hits;

        // Cancel pairs of crits and evades
        int canceled_crits = min(attack_results[DieResult.Crit], defense_results[DieResult.Evade]);
        attack_results[DieResult.Crit]   -= canceled_crits;
        defense_results[DieResult.Evade] -= canceled_crits;
    }

    // TODO: Parameterize this logic
    // TODO: Use focus tokens preferentially on defense if any eye results...?

    // Still uncanceled hits? Use evade tokens if present
    {
        // Cancel pairs of hits and evades
        int canceled_hits = min(attack_results[DieResult.Hit], defense_setup.evade_token_count);
        attack_results[DieResult.Hit]   -= canceled_hits;
        defense_setup.evade_token_count -= canceled_hits;

        // Cancel pairs of crits and evades
        int canceled_crits = min(attack_results[DieResult.Crit], defense_setup.evade_token_count);
        attack_results[DieResult.Hit]   -= canceled_crits;
        defense_setup.evade_token_count -= canceled_crits;
    }

    // Accumulate damage
    SimulationResult result;
    result.hits  = attack_results[DieResult.Hit];
    result.crits = attack_results[DieResult.Crit];
    result.attack_target_locks_used  = initial_attack_setup.target_lock_count  - attack_setup.target_lock_count;
    result.defense_evade_tokens_used = initial_defense_setup.evade_token_count - defense_setup.evade_token_count;
    result.trial_count = 1;

    return result;
}
