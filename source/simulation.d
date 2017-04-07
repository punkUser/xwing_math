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
    AfterAttackDoesNotHit,        // Ex. Gunner, Luke, IG88-B - TODO: Luke Gunner modeling somehow?
    AfterAttack,                  // Ex. Corran    
};

struct AttackSetup
{
    MultiAttackType type = MultiAttackType.Single;

    // Tokens
    int dice = 0;
    int initial_focus_token_count = 0;
    int initial_target_lock_count = 0;
    int initial_stress_token_count = 0;

    // Pilots

    // EPT
    bool juke = false;                  // Setting this to true implies evade token present as well
    bool marksmanship = false;          // One focus->crit, rest focus->hit
    int  predator_rerolls = 0;          // 0-2 rerolls
    bool rage = false;                  // 3 rerolls
    bool wired = false;                 // reroll any/all focus
    bool expertise = false;             // all focus -> hits    
    bool fearlessness = false;          // add 1 hit result
    // TODO: Lone wolf (1 blank reroll)
    // TODO: Crack shot? (gets a little bit complex as presence affects defender logic and as well)

    // Crew
    bool mercenary_copilot = false;     // One hit->crit
    bool finn = false;                  // Add one blank result to roll
    // TODO: Ezra Crew (one focus->crit)
    // TODO: Zuckuss Crew
    // TODO: 4-LOM Crew
    // TODO: Dengar Crew (overlaps w/ EPT rerolls...)
    // TODO: Bossk Crew (gets weird/hard...)
    // TODO: Hot shot copilot
    // TODO: Captain rex (only affects multi-attack)
    // TODO: Operations specialist? Again only multi-attack
    // TODO: Bistain (hit -> crit, like merc copilot)

    // System upgrades
    bool accuracy_corrector = false;    // Can cancel all results and replace with 2 hits    
    bool fire_control_system = false;   // Get a target lock after attack (only affects multi-attack)
    
    // Secondary weapons
    bool heavy_laser_cannon = false;    // After initial roll, change all crits->hits
    bool mangler_cannon = false;        // One hit->crit
    bool one_damage_on_hit = false;     // If attack hits, 1 damage (TLT, Ion, etc)    
    // TODO: Autoblaster (hit results cannot be canceled)
    
    // Ones that require spending tokens (more complex generally)
    // TODO: Calculation (pay focus: one focus->crit)
    // TODO: Han Solo Crew (spend TL: all hits->crits)
    // TODO: R4 Agromech (after spending focus, gain TL that can be used in same attack)
};

struct DefenseSetup
{
    // Tokens
    int dice = 0;
    int initial_focus_token_count = 0;
    int initial_evade_token_count = 0;
    int initial_stress_token_count = 0;

    // Pilots

    // EPTs
    bool wired = false;
    // TODO: Lone wolf (1 blank reroll)
    // TODO: Elusiveness

    // Crew
    bool finn = false;                  // Add one blank result to roll
    // TODO: C-3PO (always guess 0 probably the most relevant)
    // TODO: Latts? Gets a bit weird/complex

    // System upgrades
    bool sensor_jammer = false;         // Change one attacker hit to evade

    // Modifications
    bool autothrusters = false;
    // TODO: Lightweight frame
};

struct SimulationResult
{
    int trial_count = 0;

    int hits = 0;
    int crits = 0;

    // After - Before for all values here
    int attack_delta_focus_tokens = 0;
    int attack_delta_target_locks = 0;
    int attack_delta_stress       = 0;

    int defense_delta_focus_tokens = 0;
    int defense_delta_evade_tokens = 0;
    int defense_delta_stress       = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.trial_count += b.trial_count;

    a.hits += b.hits;
    a.crits += b.crits;

    a.attack_delta_focus_tokens  += b.attack_delta_focus_tokens;
    a.attack_delta_target_locks  += b.attack_delta_target_locks;
    a.attack_delta_stress        += b.attack_delta_stress;

    a.defense_delta_focus_tokens += b.defense_delta_focus_tokens;
    a.defense_delta_evade_tokens += b.defense_delta_evade_tokens;
    a.defense_delta_stress       += b.defense_delta_stress;

    return a;
}

//-----------------------------------------------------------------------------------

struct TokenState
{
    int focus = 0;
    int evade = 0;
    int target_lock = 0;
    int stress = 0;
}

// New setup where we only count totals and hash, etc.
struct DiceState
{
    // Count number of dice for each result
    // Count rerolled dice separately (can only reroll each die once)
    int[DieResult.Num] results;
    int[DieResult.Num] rerolled_results;

    // Cancel all dice/reinitialize
    void cancel_all()
    {
        results[] = 0;
        rerolled_results[] = 0;
    }

    // Utilities
    int count(DieResult type) const
    {
        return results[type] + rerolled_results[type];
    }
    int[DieResult.Num] count_all() const
    {
        int[DieResult.Num] total = results[];
        total[] += rerolled_results[];
        return total;
    }

    // Removes dice that we are able to reroll from results and returns the
    // number that were removed. Caller should add rerolled_results based on this.
    int remove_dice_for_reroll(DieResult from, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        int rerolled_count = min(results[from], max_count);
        results[from] -= rerolled_count;

        return rerolled_count;
    }

    // Prefers changing rerolled dice first where limited as they are more constrained
    int change_dice(DieResult from, DieResult to, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        // Change rerolled dice first
        int changed_count = 0;

        int delta = min(rerolled_results[from], max_count - changed_count);
        if (delta > 0)
        {
            rerolled_results[from] -= delta;
            rerolled_results[to]   += delta;
            changed_count          += delta;
        }
        // Then regular ones
        delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from] -= delta;
            results[to]   += delta;
            changed_count += delta;
        }

        return changed_count;
    }

    // Like above, but the changed dice cannot be rerolled
    // Because this is generally used when modifying *opponents* dice, we prefer
    // to change non-rerolled dice first to add additional constraints.
    // Ex. M9G8 forced reroll and sensor jammer can cause two separate dice
    // to be unable to be rerolled by the attacker.
    int change_dice_no_reroll(DieResult from, DieResult to, int max_count = -1)
    {
        if (max_count == 0)
            return 0;
        else if (max_count < 0)
            max_count = int.max;

        // Change regular dice first
        int changed_count = 0;

        int delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from]          -= delta;
            rerolled_results[to]   += delta; // Disallow reroll on the changed result(s)
            changed_count          += delta;
        }
        // Then rerolled ones
        delta = min(rerolled_results[from], max_count - changed_count);
        if (delta > 0)
        {
            rerolled_results[from] -= delta;
            rerolled_results[to]   += delta;
            changed_count          += delta;
        }

        return changed_count;
    }
}

//-----------------------------------------------------------------------------------




class Simulation
{
    public this(ref const(AttackSetup)  attack_setup,
                ref const(DefenseSetup) defense_setup)
    {
        m_attack_setup = attack_setup;
        m_defense_setup = defense_setup;
    }

    // TODO: Needs a way to force rerolls eventually as well
    private void defender_modify_attack_dice(ref DiceState attack_dice,
                                             ref TokenState attack_tokens)
    {
        if (m_defense_setup.sensor_jammer)
            attack_dice.change_dice_no_reroll(DieResult.Hit, DieResult.Focus, 1);
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private int attacker_modify_attack_dice_before_reroll(ref DiceState attack_dice,
                                                          ref TokenState attack_tokens)
    {
        int dice_to_reroll = 0;

        // Add any free results
        if (m_attack_setup.fearlessness)
            ++attack_dice.results[DieResult.Hit];
        if (m_attack_setup.finn)
            ++attack_dice.results[DieResult.Blank];

        // TODO: There are a few effects that should technically change our token spending behavior here...
        // Ex. One Damage on Hit (TLT, Ion) vs. enemies that can only ever get a maximum # of evade results
        // Doing more than that + 1 hits is just wasting tokens, and crits are useless (ex. Calculation)
        // It would be difficult to perfectly model this, and human behavior would not be perfect either.
        // That said, there is probably some low hanging fruit in a few situations that should get us
        // "close enough".

        // How many focus results can we turn into hits or crits?
        int useful_focus_results = 0;
        if (attack_dice.count(DieResult.Focus) > 0)   // Just an early out
        {
            // All of them
            if (attack_tokens.focus > 0 || m_attack_setup.marksmanship || m_attack_setup.expertise)
                useful_focus_results = int.max;

            // TODO: Other effects as we add them (Ezra, etc.)

            // If we are able to free reroll any focus results (wired, etc) that aren't useful, do so now
            if (m_attack_setup.wired)
            {
                int focus_to_reroll = max(0, attack_dice.count(DieResult.Focus) - useful_focus_results);
                dice_to_reroll += attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_to_reroll);
            }
        }

        // TODO: Any effects that modify blank dice into something useful here

        // How many free, unrestricted rerolls do we have?
        immutable int free_reroll_count =
            m_attack_setup.predator_rerolls +
            (m_attack_setup.rage ? 3 : 0);

        // If we have a target lock, we can reroll everything if we want to
        immutable int total_reroll_count = attack_tokens.target_lock > 0 ? int.max : free_reroll_count;
        int rerolled_dice_count = 0;

        // First, let's reroll any blanks we're allowed to - this is always useful
        rerolled_dice_count += attack_dice.remove_dice_for_reroll(DieResult.Blank, total_reroll_count);

        // Now reroll focus results that "aren't useful"
        {
            int focus_to_reroll = attack_dice.count(DieResult.Focus) - useful_focus_results;
            focus_to_reroll = clamp(focus_to_reroll, 0, total_reroll_count - rerolled_dice_count);

            rerolled_dice_count += attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_to_reroll);
        }

        // If we rerolled more than our total number of "free" rerolls, we have to spend a target lock
        if (rerolled_dice_count > free_reroll_count)
        {
            assert(attack_tokens.target_lock > 0);
            --attack_tokens.target_lock;
        }

        // This is a mess but pending reorg of "free" vs "paid" rerolling logic above
        return dice_to_reroll + rerolled_dice_count;
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private void attacker_modify_attack_dice_after_reroll(ref DiceState attack_dice,
                                                          ref TokenState attack_tokens)
    {
        // Rerolls are done - deal with focus results

        // TODO: Semi-complex logic in the case of abilities where you can spend something to change
        // a finite number of focus or blank results, etc. Gets a bit complicated in the presence of
        // other abilities like marksmanship and expertise and so on.

        // Marksmanship is always a better choice than regular focus token
        if (m_attack_setup.marksmanship)
        {
            attack_dice.change_dice(DieResult.Focus, DieResult.Crit, 1);
            attack_dice.change_dice(DieResult.Focus, DieResult.Hit);
        }
        // Expertise is the same as a regular focus token, but doesn't cost anything
        else if (m_attack_setup.expertise)
        {
            attack_dice.change_dice(DieResult.Focus, DieResult.Hit);
        }
        // Spend regular focus?
        else if (attack_tokens.focus > 0)
        {
            int changed_results = attack_dice.change_dice(DieResult.Focus, DieResult.Hit);
            if (changed_results > 0)
                --attack_tokens.focus;
        }

        // Mangler and merc copilot can make a hit into a crit
        // Do this last in case we focused into any hits, etc.
        {
            int hits_to_crits =
                (m_attack_setup.mercenary_copilot ? 1 : 0) +
                (m_attack_setup.mangler_cannon    ? 1 : 0);
            attack_dice.change_dice(DieResult.Hit, DieResult.Crit, hits_to_crits);
        }

        // TODO: Accuracy corrector should technically go here as it is part of the attacker modify dice section
    }

    int[DieResult.Num] roll_and_modify_attack_dice(ref TokenState attack_tokens)
    {
        TokenState initial_attack_tokens = attack_tokens;

        // Roll Attack Dice
        DiceState attack_dice;
        foreach (i; 0 .. m_attack_setup.dice)
        {
            auto new_result = k_attack_die_result[uniform(0, k_die_sides)];
            ++attack_dice.results[new_result];
        }

        // "Immediately after rolling" events
        if (m_attack_setup.heavy_laser_cannon)
            attack_dice.change_dice(DieResult.Crit, DieResult.Hit);

        defender_modify_attack_dice(attack_dice, attack_tokens);

        int dice_to_reroll = attacker_modify_attack_dice_before_reroll(attack_dice, attack_tokens);
        foreach (i; 0 .. dice_to_reroll)
        {
            auto new_result = k_attack_die_result[uniform(0, k_die_sides)];
            ++attack_dice.rerolled_results[new_result];
        }

        // Handle accuracy corrector... we cache the token state here before doing other modification -
        // namely focus spending - because we assume at this point that the player could determine if it's
        // better to spend tokens to modify, or just trigger accuracy corrector.
        // Note that human behavior here is not 100% optimal, but for our purposes it's fair to assume
        // that people will still attempt to modify dice as usual with rerolls until they determine they
        // can't beat AC.
        // TODO: As with some other things there are various edge cases that we could handle here... ex.
        // if there's no possible way to get more than two hits we could just trigger AC right off the bat
        // and ignore the rolled results entirely. More complex, in some cases with FCS + gunner it might be
        // better to cancel but not add the two hits back in to intentionally trigger FCS and gunner for a
        // second attack...
        TokenState attack_tokens_before_ac = attack_tokens;

        attacker_modify_attack_dice_after_reroll(attack_dice, attack_tokens);

        // Use accuracy corrector in the following cases:
        // a) We ended up with less than 2 hits/crits
        // b) We got exactly 2 hits/crits but we only care if we "hit the attack" (TLT, Ion, etc)
        // b) We got exactly 2 hits and no crits (still better to remove the extra die for LWF, and not spend tokens)
        if (m_attack_setup.accuracy_corrector)
        {
            int hits = attack_dice.count(DieResult.Hit);
            int crits = attack_dice.count(DieResult.Crit);
            if (((hits + crits) <  2) ||
                (hits == 2 && crits == 0) ||
                ((hits + crits) == 2 && m_attack_setup.one_damage_on_hit))
            {
                attack_tokens = attack_tokens_before_ac;  // Undo focus token spending (see above notes)

                attack_dice.cancel_all();
                attack_dice.results[DieResult.Hit] += 2;
            }
        }
        // No more modification after potential AC!

        // Done modifying attack dice - compute attack results
        auto attack_results = attack_dice.count_all();

        // Some final sanity checks in debug mode on the logic here as it is not always trivial...
        /*
        debug
        {
            // Did we have the ability to reroll more dice than we did?
            if (total_reroll_count > rerolled_dice_count)
            {
                // If so, every focus or blank result that is still around here should have been rerolled
                assert(attack_dice.results[DieResult.Blank] == 0);
                assert(attack_dice.results[DieResult.Focus] == 0);
            }
        }
        */

        return attack_results;
    }





    void attacker_modify_defense_dice(ref const(int)[DieResult.Num] attack_results,
                                      ref DiceState defense_dice,
                                      ref TokenState defense_tokens)
    {
        // Find one evade and turn it to a focus
        if (m_attack_setup.juke)
            defense_dice.change_dice(DieResult.Evade, DieResult.Focus, 1);
    }

    int defender_modify_defense_dice_before_reroll(ref const(int)[DieResult.Num] attack_results,
                                                   ref DiceState defense_dice,
                                                   ref TokenState defense_tokens)
    {
        int dice_to_reroll = 0;

        // Add free results
        if (m_attack_setup.finn)
            ++defense_dice.results[DieResult.Blank];

        // Find one blank and turn it to an evade
        if (m_defense_setup.autothrusters)
            defense_dice.change_dice(DieResult.Blank, DieResult.Evade, 1);

        // If we have any focus results and no focus token, reroll our focuses
        if (defense_tokens.focus == 0 && m_defense_setup.wired)
        {
            dice_to_reroll += defense_dice.remove_dice_for_reroll(DieResult.Focus);
        }

        return dice_to_reroll;
    }

    void defender_modify_defense_dice_after_reroll(ref const(int)[DieResult.Num] attack_results,
                                                    ref DiceState defense_dice,
                                                    ref TokenState defense_tokens)
    {
        int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit] - defense_dice.count(DieResult.Evade);
        bool can_spend_focus = defense_tokens.focus > 0 && defense_dice.count(DieResult.Focus) > 0;

        // Spend regular focus or evade tokens?
        if (can_spend_focus || defense_tokens.evade > 0)
        {
            int max_damage_canceled = (can_spend_focus ? defense_dice.count(DieResult.Focus) : 0) + defense_tokens.evade;
            bool can_cancel_all = (max_damage_canceled >= uncanceled_hits);

            // In the presence of "one damage on hit" effects from the attacker, if we can't cancel everything,
            // it's pointless to spend any tokens at all.
            if (can_cancel_all || !m_attack_setup.one_damage_on_hit)
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

                bool can_cancel_all_with_focus = can_spend_focus && (defense_dice.count(DieResult.Focus) >= uncanceled_hits);
                bool can_cancel_all_with_evade = defense_tokens.evade >= uncanceled_hits;

                bool spent_focus = false;
                int spent_evade_tokens = 0;

                // Do we need to spend both to cancel all hits?
                if (!can_cancel_all_with_focus && !can_cancel_all_with_evade)
                {
                    int uncancelled_hits_after_focus = uncanceled_hits;
                    if (can_spend_focus)
                    {
                        spent_focus = can_spend_focus;
                        uncancelled_hits_after_focus = max(0, uncanceled_hits - defense_dice.count(DieResult.Focus));
                    }
                    spent_evade_tokens = min(defense_tokens.evade, uncancelled_hits_after_focus);
                }
                else if (!m_attack_setup.juke)        // No juke - hold onto evade primarily
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
                    uncanceled_hits -= defense_dice.count(DieResult.Focus);
                    defense_dice.change_dice(DieResult.Focus, DieResult.Evade);
                    --defense_tokens.focus;
                }

                // Evade tokens add defense dice to the pool
                if (spent_evade_tokens > 0)
                {
                    uncanceled_hits -= spent_evade_tokens;
                    defense_dice.results[DieResult.Evade] += spent_evade_tokens;
                    defense_tokens.evade -= spent_evade_tokens;
                }

                assert(uncanceled_hits <= 0 || defense_tokens.evade == 0);
            }

            // Sanity
            assert(defense_tokens.evade >= 0);
            assert(defense_tokens.focus >= 0);
            assert(uncanceled_hits <= 0 || !can_cancel_all);
        }
    }

    private int[DieResult.Num] roll_and_modify_defense_dice(ref const(int)[DieResult.Num] attack_results,
                                                            ref TokenState defense_tokens)
    {
        // Roll Defense Dice
        DiceState defense_dice;
        foreach (i; 0 .. m_defense_setup.dice)
        {
            auto new_result = k_defense_die_result[uniform(0, k_die_sides)];
            ++defense_dice.results[new_result];
        }

        // Modify Defense Dice
        attacker_modify_defense_dice(attack_results, defense_dice, defense_tokens);

        int dice_to_reroll = defender_modify_defense_dice_before_reroll(attack_results, defense_dice, defense_tokens);
        foreach (i; 0 .. dice_to_reroll)
        {
            auto new_result = k_defense_die_result[uniform(0, k_die_sides)];
            ++defense_dice.rerolled_results[new_result];
        }
        defender_modify_defense_dice_after_reroll(attack_results, defense_dice, defense_tokens);

        // Done modifying defense dice - compute final defense results
        return defense_dice.count_all();
    }




    // Modifies input token spending
    private int[DieResult.Num] simulate_single_attack(ref TokenState attack_tokens,
                                                      ref TokenState defense_tokens,
                                                      bool trigger_after_attack = true)
    {
        auto attack_results  = roll_and_modify_attack_dice(attack_tokens);
        auto defense_results = roll_and_modify_defense_dice(attack_results, defense_tokens);

        // Sanity...
        assert(attack_results[DieResult.Evade] == 0);
        assert(defense_results[DieResult.Hit] == 0);
        assert(defense_results[DieResult.Crit] == 0);

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
        if (m_attack_setup.one_damage_on_hit && attack_hit)
        {
            attack_results[DieResult.Hit] = 1;
            attack_results[DieResult.Crit] = 0;
        }

        // Trigger any "after attacking" abilities if request
        if (trigger_after_attack)
        {
            // Update any abilities that trigger "after attacking" or "after defending"
            if (m_attack_setup.fire_control_system)
            {
                // TODO: Handle multi-target-lock stuff... really only an issue with Redline and so on
                attack_tokens.target_lock = max(attack_tokens.target_lock, 1);
            }
        }

        return attack_results;
    }

    public SimulationResult simulate_attack()
    {
        // TODO: Sanity checks on inputs?

        TokenState attack_tokens;
        attack_tokens.focus       = m_attack_setup.initial_focus_token_count;
        attack_tokens.target_lock = m_attack_setup.initial_target_lock_count;
        attack_tokens.stress      = m_attack_setup.initial_stress_token_count;

        TokenState defense_tokens;
        defense_tokens.focus  = m_defense_setup.initial_focus_token_count;
        defense_tokens.evade  = m_defense_setup.initial_evade_token_count;
        defense_tokens.stress = m_defense_setup.initial_stress_token_count;

        // Simulate first attack
        // TODO: We'll eventually need to pass some hints into this about the fact that there is a second attack
        // as it does change the optimal token spend strategies and so on somewhat.
        // Also upgrades matter here (FCS, etc).
        // NOTE: Attack/defense setup passed by reference as tokens are modified in place

        int[DieResult.Num] attack_results;
        bool first_attack_hit = (attack_results[DieResult.Hit] != 0 || attack_results[DieResult.Crit] != 0);

        if (m_attack_setup.type == MultiAttackType.Single)
        {
            attack_results = simulate_single_attack(attack_tokens, defense_tokens, true);
        }
        else if (m_attack_setup.type == MultiAttackType.SecondaryPerformTwice)
        {
            // We DO NOT trigger "after attack" type abilities between two "secondary perfom twice" attacks
            attack_results    = simulate_single_attack(attack_tokens, defense_tokens, false);
            attack_results[] += simulate_single_attack(attack_tokens, defense_tokens, true)[];
        }    
        else if (m_attack_setup.type == MultiAttackType.AfterAttack)
        {
            // After attack abilities trigger after both of these
            attack_results    = simulate_single_attack(attack_tokens, defense_tokens, true);
            attack_results[] += simulate_single_attack(attack_tokens, defense_tokens, true)[];
        }
        else if (m_attack_setup.type == MultiAttackType.AfterAttackDoesNotHit && !first_attack_hit)
        {
            // After attack abilities trigger after both of these
            attack_results    = simulate_single_attack(attack_tokens, defense_tokens, true);
            // Only do second attack if the first one missed
            if (attack_results[DieResult.Hit] == 0 && attack_results[DieResult.Crit] == 0)
                attack_results[] += simulate_single_attack(attack_tokens, defense_tokens, true)[];
        }
        else
        {
            assert(false);  // Unknown attack type
        }

        // Sanity checks on token spending
        assert(attack_tokens.focus >= 0);
        assert(attack_tokens.evade >= 0);
        assert(attack_tokens.target_lock >= 0);        // Possible to gain target locks due to FCS
        assert(attack_tokens.stress >= 0);

        assert(defense_tokens.focus >= 0);
        assert(defense_tokens.evade >= 0);
        assert(defense_tokens.target_lock >= 0);        // Possible to gain target locks due to FCS
        assert(defense_tokens.stress >= 0);

        // Compute final results of this simulation step
        SimulationResult result;
        result.trial_count = 1;

        result.hits  = attack_results[DieResult.Hit];
        result.crits = attack_results[DieResult.Crit];

        result.attack_delta_focus_tokens  = attack_tokens.focus        - m_attack_setup.initial_focus_token_count  ; 
        result.attack_delta_target_locks  = attack_tokens.target_lock  - m_attack_setup.initial_target_lock_count  ; 
        result.attack_delta_stress        = attack_tokens.stress       - m_attack_setup.initial_stress_token_count ;
        result.defense_delta_focus_tokens = defense_tokens.focus       - m_defense_setup.initial_focus_token_count ;
        result.defense_delta_evade_tokens = defense_tokens.evade       - m_defense_setup.initial_evade_token_count ;
        result.defense_delta_stress       = defense_tokens.stress      - m_defense_setup.initial_stress_token_count;

        return result;
    }


    private immutable AttackSetup m_attack_setup;
    private immutable DefenseSetup m_defense_setup;
};

