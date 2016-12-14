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
};

struct DefenseSetup
{
    int dice = 0;
    int focus_token_count = 0;
    int evade_token_count = 0;
};


struct SimulationResult
{
    int hits = 0;
    int crits = 0;
    int defense_evade_tokens_used = 0;
    int trial_count = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.hits += b.hits;
    a.crits += b.crits;
    a.defense_evade_tokens_used += b.defense_evade_tokens_used;
    a.trial_count += b.trial_count;
    return a;
}



SimulationResult simulate_attack(AttackSetup attack_setup, DefenseSetup defense_setup)
{
    assert(attack_setup.dice <= kMaxDice);
    assert(defense_setup.dice <= kMaxDice);

    // TODO: A lot of this could be optimized, but see how usable it is for now while keeping it readable

    // Roll Attack Dice
    DieResult[kMaxDice] max_attack_dice;
    DieResult[] attack_dice = max_attack_dice[0 .. attack_setup.dice];
    foreach (ref d; attack_dice)
        d = kAttackDieResult[uniform(0, kDieSides)];

    // Modify Attack Dice


    // Roll Defense Dice
    DieResult[kMaxDice] max_defense_dice;
    DieResult[] defense_dice = max_defense_dice[0 .. defense_setup.dice];
    foreach (ref d; defense_dice)
        d = kDefenseDieResult[uniform(0, kDieSides)];

    // Modify Defense Dice


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
    int defense_evade_tokens_used = 0;
    {
        // Cancel pairs of hits and evades
        int canceled_hits = min(attack_results[DieResult.Hit], defense_setup.evade_token_count);
        attack_results[DieResult.Hit]   -= canceled_hits;
        defense_setup.evade_token_count -= canceled_hits;
        defense_evade_tokens_used       += canceled_hits;


        // Cancel pairs of crits and evades
        int canceled_crits = min(attack_results[DieResult.Crit], defense_setup.evade_token_count);
        attack_results[DieResult.Hit]   -= canceled_crits;
        defense_setup.evade_token_count -= canceled_crits;
        defense_evade_tokens_used       += canceled_crits;
    }



    // Accumulate damage
    SimulationResult result;
    result.hits  = attack_results[DieResult.Hit];
    result.crits = attack_results[DieResult.Crit];
    result.defense_evade_tokens_used = defense_evade_tokens_used;
    result.trial_count = 1;

    return result;
}
