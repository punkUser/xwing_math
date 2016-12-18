module simulation;

import std.algorithm;
import std.random;
import std.stdio;

public immutable k_die_sides = 8;


enum DieResult : int
{
    Blank = 0,
    Hit,
    Crit,
    Focus,
    Evade,
    Num
};
immutable DieResult[k_die_sides] k_attack_die_result = [
    DieResult.Blank, DieResult.Blank,
    DieResult.Focus, DieResult.Focus,
    DieResult.Hit, DieResult.Hit, DieResult.Hit,
    DieResult.Crit
];
immutable DieResult[k_die_sides] k_defense_die_result = [
    DieResult.Blank, DieResult.Blank, DieResult.Blank,
    DieResult.Focus, DieResult.Focus,
    DieResult.Evade, DieResult.Evade, DieResult.Evade
];

enum MultiAttackType : int
{
    Single = 0,                   // Regular single attack
    SecondaryPerformTwice,        // Ex. Twin Laser Turret, Cluster Missiles
    AfterAttackDoesNotHit,        // Ex. Gunner, Luke, IG88-B
    AfterAttack,                  // Ex. Corran    
};

struct AttackSetup
{
    int dice = 0;
    int focus_token_count = 0;
    int target_lock_count = 0;

    bool juke = false;                  // Setting this to true implies evade token present as well
    bool accuracy_corrector = false;

    MultiAttackType type = MultiAttackType.Single;
    // Upgrades that only affect multi-attack situations
    bool fire_control_system = false;
};

struct DefenseSetup
{
    int dice = 0;
    int focus_token_count = 0;
    int evade_token_count = 0;
};



struct MultiAttackSetup
{
    
};


struct SimulationResult
{
    int trial_count = 0;

    int hits = 0;
    int crits = 0;

    int attack_target_locks_used = 0;
    int attack_focus_tokens_used = 0;

    int defense_focus_tokens_used = 0;
    int defense_evade_tokens_used = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b, bool separate_trials = true)
{
    if (separate_trials)
        a.trial_count += b.trial_count;
    else
        assert(a.trial_count == 1); // Multi-attack use case

    a.hits += b.hits;
    a.crits += b.crits;

    a.attack_target_locks_used += b.attack_target_locks_used;
    a.attack_focus_tokens_used += b.attack_focus_tokens_used;
    a.defense_evade_tokens_used += b.defense_evade_tokens_used;
    a.defense_evade_tokens_used += b.defense_evade_tokens_used;

    return a;
}




private SimulationResult simulate_single_attack(AttackSetup initial_attack_setup, DefenseSetup initial_defense_setup)
{
    auto attack_setup  = initial_attack_setup;
    auto defense_setup = initial_defense_setup;

    // TODO: A lot of this could be optimized, but see how usable it is for now while keeping it readable

    // Roll Attack Dice
    DieResult[] attack_dice = new DieResult[attack_setup.dice];
    foreach (ref d; attack_dice)
        d = k_attack_die_result[uniform(0, k_die_sides)];

    // Track any that we re-roll... can only do this once per die
    bool[] attack_dice_rerolled = new bool[attack_setup.dice];
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
            foreach (i; 0 .. attack_dice.length)
            {
                // If we don't have a focus token, also reroll focus results
                if (!attack_dice_rerolled[i] &&
                    (attack_dice[i] == DieResult.Blank ||
                    (attack_setup.focus_token_count == 0 && attack_dice[i] == DieResult.Focus)))
                {
                    attack_dice_rerolled[i] = true;
                    ++number_of_dice_rerolled;
                    attack_dice[i] = k_attack_die_result[uniform(0, k_die_sides)];
                }
            }

            if (number_of_dice_rerolled > 0)
                --attack_setup.target_lock_count;
        }

        // Spend regular focus?
        if (attack_setup.focus_token_count > 0)
        {
            int[DieResult.Num] attack_results;
            foreach (d; attack_dice)
                ++attack_results[d];

            if (attack_results[DieResult.Focus] > 0)
            {
                foreach (ref d; attack_dice)
                    if (d == DieResult.Focus)
                        d = DieResult.Hit;
                --attack_setup.focus_token_count;
            }
        }
    }

    // Done modifying attack dice - compute final attack results
    int[DieResult.Num] attack_results;  // Init to 0 by default
    foreach (d; attack_dice)
        ++attack_results[d];

    // Use accuracy corrector if we ended up with less than 2 hits/crits
    if (attack_setup.accuracy_corrector &&
        (attack_results[DieResult.Hit] + attack_results[DieResult.Crit] < 2))
    {
        attack_setup = initial_attack_setup;    // Undo any token spending
        foreach (ref r; attack_results) r = 0;  // Cancel all results
        attack_results[DieResult.Hit] = 2;      // Add two hits to the result
        // No more modifaction
    }

    // ----------------------------------------------------------------------------------------

    // Roll Defense Dice
    DieResult[] defense_dice = new DieResult[defense_setup.dice];
    foreach (ref d; defense_dice)
        d = k_defense_die_result[uniform(0, k_die_sides)];

    // Modify Defense Dice
    int attack_target_lock_tokens_used = 0;
    {
        // Attacker modify defense dice
        if (attack_setup.juke)
        {
            // Find one evade and turn it to a focus
            foreach (ref d; defense_dice)
            {
                if (d == DieResult.Evade)
                {
                    d = DieResult.Focus;
                    break;
                }
            }
        }

        // Defender modify defense dice
        // Spend regular focus or evade tokens?
        if (defense_setup.focus_token_count > 0 || defense_setup.evade_token_count > 0)
        {
            int[DieResult.Num] defense_results;
            foreach (d; defense_dice)
                ++defense_results[d];
            int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit] - defense_results[DieResult.Evade];

            if (uncanceled_hits > 0)
            {
                // For now simple logic:
                // Cancel all hits with just a focus? Do it.
                // Cancel all hits with just evade tokens? Do that.
                // Otherwise both.
                bool spent_focus = false;
                int spent_evade_tokens = 0;
                if (defense_setup.focus_token_count > 0 && defense_results[DieResult.Focus] >= uncanceled_hits)
                {
                    spent_focus = true;
                    uncanceled_hits = max(0, uncanceled_hits - defense_results[DieResult.Focus]);
                }
                else if (defense_setup.evade_token_count >= uncanceled_hits)
                {
                    spent_evade_tokens = uncanceled_hits;
                    uncanceled_hits = 0;
                }
                else
                {
                    if (defense_setup.focus_token_count > 0)
                    {
                        spent_focus = true;
                        uncanceled_hits = max(0, uncanceled_hits - defense_results[DieResult.Focus]);
                    }

                    spent_evade_tokens = min(defense_setup.evade_token_count, uncanceled_hits);
                    uncanceled_hits -= spent_evade_tokens;
                }

                if (spent_focus)
                {
                    foreach (ref d; defense_dice)
                        if (d == DieResult.Focus)
                            d = DieResult.Evade;
                    --defense_setup.focus_token_count;
                }

                // Evade tokens add defense dice to the pool
                foreach (i; 0 .. spent_evade_tokens)
                    defense_dice ~= DieResult.Evade;
                defense_setup.evade_token_count -= spent_evade_tokens;

                assert(uncanceled_hits == 0 || defense_setup.evade_token_count == 0);
            }
        }
    }

    // Done modifying defense dice - compute final defense results
    int[DieResult.Num] defense_results; // Init to 0 by default    
    foreach (d; defense_dice)
        ++defense_results[d];

    // ----------------------------------------------------------------------------------------

    // Compare results

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

    // Compute final results of this simulation step
    SimulationResult result;
    result.trial_count = 1;

    result.hits  = attack_results[DieResult.Hit];
    result.crits = attack_results[DieResult.Crit];

    result.attack_target_locks_used  = initial_attack_setup.target_lock_count  - attack_setup.target_lock_count;
    result.attack_focus_tokens_used  = initial_attack_setup.focus_token_count  - attack_setup.focus_token_count;
    result.defense_focus_tokens_used = initial_defense_setup.focus_token_count - defense_setup.focus_token_count;
    result.defense_evade_tokens_used = initial_defense_setup.evade_token_count - defense_setup.evade_token_count;

    return result;
}


SimulationResult simulate_attack(AttackSetup attack_setup, DefenseSetup defense_setup)
{
    // Simulate first attack
    // TODO: We'll eventually need to pass some hints into this about the fact that there is a second attack
    // as it does change the optimal token spend strategies and so on somewhat.
    // Also upgrades matter here (FCS, etc).
    auto result_1 = simulate_single_attack(attack_setup, defense_setup);
    
    // Update token spend
    attack_setup.focus_token_count  -= result_1.attack_focus_tokens_used;
    attack_setup.target_lock_count  -= result_1.attack_target_locks_used;
    defense_setup.focus_token_count -= result_1.defense_focus_tokens_used;
    defense_setup.evade_token_count -= result_1.defense_evade_tokens_used;

    if (attack_setup.type == MultiAttackType.Single)
    {
        return result_1;
    }
    else if (attack_setup.type == MultiAttackType.SecondaryPerformTwice)
    {
        // Second attack, do not consider a separate "trial" in the PDF
        auto result_2 = simulate_single_attack(attack_setup, defense_setup);
        return accumulate_result(result_1, result_2, false);
    }
    else if (attack_setup.type == MultiAttackType.AfterAttack ||
             attack_setup.type == MultiAttackType.AfterAttackDoesNotHit)
    {
        // Update any abilities that trigger "after attacking" or "after defending"
        if (attack_setup.fire_control_system)
        {
            // TODO: Handle multi-target-lock stuff... really only an issue with Redline and so on
            attack_setup.target_lock_count = max(attack_setup.target_lock_count, 1);
        }

        if (attack_setup.type == MultiAttackType.AfterAttack || (result_1.hits == 0 && result_1.crits == 0))
        {
            // Second attack, do not consider a separate "trial" in the PDF
            auto result_2 = simulate_single_attack(attack_setup, defense_setup);
            return accumulate_result(result_1, result_2, false);
        }
        else
        {
            // First attack hit, no second attack
            return result_1;
        }
    }

    // Should have returned from somewhere above
    assert(false);
}
