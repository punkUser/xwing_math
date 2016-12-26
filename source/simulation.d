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

struct AttackDie
{
    DieResult result = DieResult.Num;
    int roll_count = 0;

    void roll()
    {
        assert(can_reroll());
        result = k_attack_die_result[uniform(0, k_die_sides)];
        ++roll_count;
    }
    bool can_reroll() const { return roll_count < 2; }

    void focus_to_hit()
    {
        if (result == DieResult.Focus)
            result = DieResult.Hit;
    }

    // Convenience
    @property bool blank() const { return result == DieResult.Blank; }
    @property bool focus() const { return result == DieResult.Focus; }
};

struct DefenseDie
{
    DieResult result = DieResult.Num;
    int roll_count = 0;

    this(DieResult r)
    {
        result = r;
        roll_count = 1;
    }

    void roll()
    {
        assert(can_reroll());
        result = k_defense_die_result[uniform(0, k_die_sides)];
        ++roll_count;
    }
    bool can_reroll() const { return roll_count < 2; }

    void focus_to_evade()
    {
        if (result == DieResult.Focus)
            result = DieResult.Evade;
    }

    // Convenience
    @property bool blank() const { return result == DieResult.Blank; }
    @property bool focus() const { return result == DieResult.Focus; }
    @property bool evade() const { return result == DieResult.Evade; }
};

int[DieResult.Num] count_results(T)(const(T)[] dice)
{
    int[DieResult.Num] results;
    foreach (d; dice)
        ++results[d.result];
    return results;
}

int change_dice(T)(ref T[] dice, DieResult from, DieResult to, int max_count = 1)
{
    assert(max_count > 0);

    int changed_count = 0;
    foreach (ref d; dice)
    {
        if (d.result == from)
        {
            d.result = to;
            ++changed_count;
            if (changed_count >= max_count)
                break;
        }
    }
    return changed_count;
}


enum MultiAttackType : int
{
    Single = 0,                   // Regular single attack
    SecondaryPerformTwice,        // Ex. Twin Laser Turret, Cluster Missiles
    AfterAttackDoesNotHit,        // Ex. Gunner, Luke, IG88-B
    AfterAttack,                  // Ex. Corran    
};

struct AttackSetup
{
    MultiAttackType type = MultiAttackType.Single;

    int dice = 0;
    int focus_token_count = 0;
    int target_lock_count = 0;

    bool juke = false;                  // Setting this to true implies evade token present as well
    bool accuracy_corrector = false;
    bool one_damage_on_hit = false;     // If attack hits, 1 damage (TLT, Ion, etc)
    
    // Upgrades that only affect multi-attack situations
    bool fire_control_system = false;
};

struct DefenseSetup
{
    int dice = 0;
    int focus_token_count = 0;
    int evade_token_count = 0;

    bool autothrusters = false;
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

void defender_modify_attack_dice(ref AttackSetup  attack_setup,
                                 ref DefenseSetup defense_setup,
                                 ref AttackDie[] attack_dice)
{
}

void attacker_modify_attack_dice(ref AttackSetup  attack_setup,
                                 ref DefenseSetup defense_setup,
                                 ref AttackDie[] attack_dice)
{
    // First do any effects that are always obviously good... focus/blank->hit/crit or so on


    // Spend target lock?
    if (attack_setup.target_lock_count > 0)
    {
        auto attack_results = count_results(attack_dice);

        int number_of_dice_rerolled = 0;
        foreach (ref d; attack_dice)
        {
            // If we don't have a focus token, also reroll focus results
            if (d.can_reroll() &&
                (d.blank || (d.focus && attack_setup.focus_token_count == 0)))
            {
                d.roll();
                ++number_of_dice_rerolled;
            }
        }

        if (number_of_dice_rerolled > 0)
            --attack_setup.target_lock_count;
    }

    // Spend regular focus?
    if (attack_setup.focus_token_count > 0)
    {
        auto attack_results = count_results(attack_dice);

        if (attack_results[DieResult.Focus] > 0)
        {
            foreach (ref d; attack_dice)
                d.focus_to_hit();
            --attack_setup.focus_token_count;
        }
    }

    // TODO: Accuracy corrector should technically go here instead of below... minor extra cost of
    // recomputing results twice and so on.
}

int[DieResult.Num] roll_and_modify_attack_dice(ref AttackSetup  attack_setup,
                                               ref DefenseSetup defense_setup,)
{
    AttackSetup initial_attack_setup = attack_setup;

    // Roll Attack Dice
    auto attack_dice = new AttackDie[attack_setup.dice];
    foreach (ref d; attack_dice)
        d.roll();

    defender_modify_attack_dice(attack_setup, defense_setup, attack_dice);
    attacker_modify_attack_dice(attack_setup, defense_setup, attack_dice);

    // Done modifying attack dice - compute attack results
    auto attack_results = count_results(attack_dice);

    // Use accuracy corrector if we ended up with less than 2 hits/crits
    if (attack_setup.accuracy_corrector &&
        (attack_results[DieResult.Hit] + attack_results[DieResult.Crit] < 2))
    {
        attack_setup = initial_attack_setup;    // Undo any token spending
        foreach (ref r; attack_results) r = 0;  // Cancel all results
        attack_results[DieResult.Hit] = 2;      // Add two hits to the result
        // No more modifaction
    }

    return attack_results;
}





void attacker_modify_defense_dice(ref AttackSetup attack_setup,
                                  ref DefenseSetup defense_setup,
                                  int[DieResult.Num] attack_results,
                                  ref DefenseDie[] defense_dice)
{
    // Find one evade and turn it to a focus
    if (attack_setup.juke)            
        change_dice(defense_dice, DieResult.Evade, DieResult.Focus, 1);
}

void defender_modify_defense_dice(ref AttackSetup attack_setup,
                                  ref DefenseSetup defense_setup,
                                  int[DieResult.Num] attack_results,
                                  ref DefenseDie[] defense_dice)
{
    // Find one blank and turn it to an evade
    if (defense_setup.autothrusters)
        change_dice(defense_dice, DieResult.Blank, DieResult.Evade, 1);

    // Spend regular focus or evade tokens?
    if (defense_setup.focus_token_count > 0 || defense_setup.evade_token_count > 0)
    {
        auto defense_results = count_results(defense_dice);
        int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit] - defense_results[DieResult.Evade];

        bool can_spend_focus = defense_setup.focus_token_count > 0 && defense_results[DieResult.Focus] > 0;

        if (uncanceled_hits > 0 && (can_spend_focus || defense_setup.evade_token_count > 0))
        {
            // For now simple logic:
            // Cancel all hits with just a focus? Do it.
            // Cancel all hits with just evade tokens? Do that.
            // If attacker has juke, flip this order - it's usually better to hang on to focus tokens vs. juke
            //   NOTE: Optimal strategy here depends on quite a lot of factors, but this is good enough in most cases
            //   One improvement to the logic would be to only invoke this behavior if # remaining attacks > # focus tokens
            // Otherwise both.

            // TODO: Probably makes sense to always prefer spending fewer tokens. i.e. if we can spend one focus vs. two evades
            // even in the presence of Juke, etc. Certainly should make sense for smallish dice counts. TEST.
            // Obviously optimal would consider all the effects and how many attacks and what tokens each person has, but 
            // we should be able to get close enough for our purposes.

            bool can_cancel_all_with_focus = can_spend_focus && defense_results[DieResult.Focus] >= uncanceled_hits;
            bool can_cancel_all_with_evade = defense_setup.evade_token_count >= uncanceled_hits;

            bool spent_focus = false;
            int spent_evade_tokens = 0;

            // Do we need to spend both to cancel all hits?
            if (!can_cancel_all_with_focus && !can_cancel_all_with_evade)
            {
                int uncancelled_hits_after_focus = uncanceled_hits;
                if (can_spend_focus)
                {
                    spent_focus = can_spend_focus;
                    uncancelled_hits_after_focus = max(0, uncanceled_hits - defense_results[DieResult.Focus]);
                }
                spent_evade_tokens = min(defense_setup.evade_token_count, uncancelled_hits_after_focus);
            }
            else if (!attack_setup.juke)        // No juke - hold onto evade primarily
            {
                if (can_cancel_all_with_focus)
                    spent_focus = true;
                else
                    spent_evade_tokens = uncanceled_hits;
            }
            else                                // Juke - hold on to focus primarily
            {
                if (can_cancel_all_with_evade)
                    spent_evade_tokens = uncanceled_hits;
                else
                    spent_focus = true;
            }

            if (spent_focus)
            {
                foreach (ref d; defense_dice)
                    d.focus_to_evade();
                --defense_setup.focus_token_count;
                uncanceled_hits -= defense_results[DieResult.Focus];
            }

            // Evade tokens add defense dice to the pool
            foreach (i; 0 .. spent_evade_tokens)
                defense_dice ~= DefenseDie(DieResult.Evade);
            defense_setup.evade_token_count -= spent_evade_tokens;
            uncanceled_hits -= spent_evade_tokens;

            assert(defense_setup.evade_token_count >= 0);
            assert(defense_setup.focus_token_count >= 0);
            assert(uncanceled_hits <= 0 || defense_setup.evade_token_count == 0);
        }
    }
}

int[DieResult.Num] roll_and_modify_defense_dice(ref AttackSetup attack_setup,
                                                ref DefenseSetup defense_setup,
                                                int[DieResult.Num] attack_results)
{
    // Roll Defense Dice
    auto defense_dice = new DefenseDie[defense_setup.dice];
    foreach (ref d; defense_dice)
        d.roll();

    // Modify Defense Dice
    attacker_modify_defense_dice(attack_setup, defense_setup, attack_results, defense_dice);
    defender_modify_defense_dice(attack_setup, defense_setup, attack_results, defense_dice);

    // Done modifying defense dice - compute final defense results
    return count_results(defense_dice);
}





private SimulationResult simulate_single_attack(AttackSetup initial_attack_setup, DefenseSetup initial_defense_setup)
{
    auto attack_setup  = initial_attack_setup;
    auto defense_setup = initial_defense_setup;

    auto attack_results  = roll_and_modify_attack_dice(attack_setup, defense_setup);
    auto defense_results = roll_and_modify_defense_dice(attack_setup, defense_setup, attack_results);

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

    bool attack_hit = (attack_results[DieResult.Hit] + attack_results[DieResult.Crit]) > 0;

    // TLT/ion does one damage if it hits, regardless of the dice results
    if (attack_setup.one_damage_on_hit && attack_hit)
    {
        attack_results[DieResult.Hit] = 1;
        attack_results[DieResult.Crit] = 0;
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
