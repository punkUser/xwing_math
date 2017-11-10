import simulation_state;
import dice;

import std.algorithm;
import std.stdio;
import std.datetime;

import vibe.core.core;

// NOTE: This is one enum that we directly use in the forms, so rearrange or delete values!
enum MultiAttackType : int
{
    Single = 0,                   // Regular single attack
    SecondaryPerformTwice,        // Ex. Twin Laser Turret, Cluster Missiles
    AfterAttackDoesNotHit,        // Ex. Gunner, Luke, IG88-B - TODO: Luke Gunner modeling somehow?
    AfterAttack,                  // Ex. Corran
    Max,
};

struct SimulationSetup
{
    MultiAttackType type = MultiAttackType.Single;

    // Tokens
    int attack_dice = 0;
    TokenState attack_tokens;

    // TODO: Perhaps clean up parameters that depend on tokens somewhat?
    // Probably just with a simple structure with 3 params and utility function to query based on tokens
    struct AttackerModifyAttackDice
    {
        // Add results
        int add_hit_count = 0;
        int add_crit_count = 0;
        int add_blank_count = 0;
        int add_focus_count = 0;

        // Rerolls
        int reroll_any_count = 0;
        int reroll_blank_count = 0;
        int reroll_focus_count = 0;

        // Rerolls depending on whether stress is present
        int stressed_reroll_focus_count = 0;
        int stressed_reroll_any_count = 0;
        int unstressed_reroll_focus_count = 0;
        int unstressed_reroll_any_count = 0;

        // Change results
        int focus_to_crit_count = 0;
        int focus_to_hit_count = 0;
        int blank_to_crit_count = 0;
        int blank_to_hit_count = 0;
        int blank_to_focus_count = 0;
        int hit_to_crit_count = 0;

        // Free change results depending on whether stress is present
        int stressed_focus_to_hit_count = 0;
        int stressed_focus_to_crit_count = 0;
        int unstressed_focus_to_hit_count = 0;
        int unstressed_focus_to_crit_count = 0;

        // Spend tokens to change results
        int spend_focus_one_blank_to_hit = 0;

        // NOTE: Single use abilities are treated as "tokens" (see TokenState)

        // Can cancel all results and replace with 2 hits
        bool accuracy_corrector = false;
    };
    AttackerModifyAttackDice AMAD;

    struct AttackerModifyDefenseDice
    {
        // Change results
        int evade_to_focus_count = 0;
    };
    AttackerModifyDefenseDice AMDD;

    // Special effects    
    bool attack_must_spend_focus = false;           // Attacker must spend focus (hotshot copilot on defender)
    bool attack_fire_control_system = false;        // Get a target lock after attack (only affects multi-attack)
    bool attack_heavy_laser_cannon = false;         // After initial roll, change all crits->hits
    bool attack_one_damage_on_hit = false;          // If attack hits, 1 damage (TLT, Ion, etc)

    // Defense tokens
    int defense_dice = 0;
    TokenState defense_tokens;

    struct DefenderModifyAttackDice
    {
        int hit_to_focus_no_reroll_count = 0;
    };
    DefenderModifyAttackDice DMAD;

    struct DefenderModifyDefenseDice
    {
        // Add results
        int add_blank_count = 0;
        int add_focus_count = 0;
        int add_evade_count = 0;

        // Rerolls
        int reroll_blank_count = 0;
        int reroll_focus_count = 0;
        int reroll_any_count = 0;

        // Rerolls depending on whether stress is present
        int stressed_reroll_focus_count = 0;
        int stressed_reroll_any_count = 0;
        int unstressed_reroll_focus_count = 0;
        int unstressed_reroll_any_count = 0;

        // Change results
        int blank_to_evade_count = 0;
        int focus_to_evade_count = 0;
        int spend_focus_one_blank_to_evade = 0;

        // Free change results depending on whether stress is present
        int stressed_focus_to_evade_count = 0;
        int unstressed_focus_to_evade_count = 0;

        // Misc stuff
        bool spend_attacker_stress_add_evade = false;
    };
    DefenderModifyDefenseDice DMDD;

    // Special effects
    bool defense_must_spend_focus = false;          // Defender must spend focus (hotshot copilot on attacker)

    // TODO: Autoblaster (hit results cannot be canceled)

    // TODO: Crack shot? (gets a little bit complex as presence affects defender logic and as well)
    // TODO: Zuckuss Crew
    // TODO: 4-LOM Crew
    // TODO: Bossk Crew
    // TODO: Captain rex (only affects multi-attack)
    // TODO: Operations specialist? Again only multi-attack

    // Ones that require spending tokens (more complex generally)
    // TODO: Calculation (pay focus: one focus->crit)
    // TODO: Han Solo Crew (spend TL: all hits->crits)
    // TODO: R4 Agromech (after spending focus, gain TL that can be used in same attack)

    // TODO: Elusiveness
    // TODO: C-3PO (always guess 0 probably the most relevant)
    // TODO: Lightweight frame
};


struct SimulationResult
{
    // Performance/debug metadata
    int evaluation_count = 1;

    double probability = 0.0f;

    double hits = 0;
    double crits = 0;

    // After - Before for all values here
    double attack_delta_focus_tokens = 0;
    double attack_delta_target_locks = 0;
    double attack_delta_stress       = 0;

    double defense_delta_focus_tokens = 0;
    double defense_delta_evade_tokens = 0;
    double defense_delta_stress       = 0;
};

SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.evaluation_count += b.evaluation_count;
    a.probability += b.probability;

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




class Simulation
{
    public this(ref const(SimulationSetup) setup)
    {
        m_setup  = setup;

        // We always show at least 0..6 labels on the graph as this looks nice
        m_total_hits_pdf = new SimulationResult[7];
        foreach (ref i; m_total_hits_pdf)
            i = SimulationResult.init;
    }


    // Utility function to compute the ideal number of dice to reroll based on abilities and do any "free" rerolls.
    // This logic is the same on attack/defense when modifying own dice.
    // Returns count of dice to reroll. Also returns additional information about focus and blanks that should
    // still be rerolled (presumably at a cost) if possible.
    static private int do_free_rerolls(
        ref DiceState dice,
        int useful_focus_results, int useful_blank_results,
        int free_reroll_blank_count, int free_reroll_focus_count, int free_reroll_any_count,
        out int out_focus_to_reroll, out int out_blank_to_reroll)
    {
        // Initialize outputs
        out_focus_to_reroll = 0;
        out_blank_to_reroll = 0;

        // If all results are "useful", no need to reroll anything
        int useless_focus_count = dice.count(DieResult.Focus) - useful_focus_results;
        int useless_blank_count = dice.count(DieResult.Blank) - useful_blank_results;
        if (useless_focus_count <= 0 && useless_blank_count <= 0)
        {
            return 0;
        }

        // Logic here is if we have spare effects that can turn "anything but what it is now" into a useful result, it's "safe"
        // to reroll as we can't make it any "worse" and we may make it "better" by rerolling right into something useful.
        //
        // Technically there are cases in which even rerolling a useful result can be slightly better on average:
        // i.e. if there are enough dice being rerolled that we're likely to roll into another useful one.
        //
        // However taking the conservative approach tends to do better with the more common dice counts (and multi-attack
        // since it tends to spend fewer tokens) and is more typical of human reasoning, so we'll stick to that approach here.

        int focus_to_reroll = useless_focus_count;
        int blank_to_reroll = useless_blank_count;
        assert(useless_focus_count > 0 || useless_blank_count > 0);
        if (focus_to_reroll < 0)
        {
            // Extra effects for focus available, so safe to reroll extra blanks (if free)
            assert(blank_to_reroll > 0);
            blank_to_reroll += -useless_focus_count;
        }
        else if (useless_blank_count < 0)
        {
            // Extra effects for blanks available, so safe to reroll extra focus (if free)
            assert(focus_to_reroll > 0);
            focus_to_reroll += -blank_to_reroll;
        }
        focus_to_reroll = max(0, focus_to_reroll);
        blank_to_reroll = max(0, blank_to_reroll);

        // Early out if we don't need to reroll anything
        if (focus_to_reroll == 0 && blank_to_reroll == 0)
            return 0;

        // Free rerolls of specific results first
        int rerolled_blank_count = dice.remove_dice_for_reroll(DieResult.Blank, min(free_reroll_blank_count, blank_to_reroll));
        int rerolled_focus_count = dice.remove_dice_for_reroll(DieResult.Focus, min(free_reroll_focus_count, focus_to_reroll));

        // Free general rerolls
        {
            int any_rerolls_used_for_blanks = dice.remove_dice_for_reroll(DieResult.Blank,
                min(free_reroll_any_count, blank_to_reroll - rerolled_blank_count));
            rerolled_blank_count  += any_rerolls_used_for_blanks;
            free_reroll_any_count -= any_rerolls_used_for_blanks;
        }
        {
            int any_rerolls_used_for_focus = dice.remove_dice_for_reroll(DieResult.Focus,
                min(free_reroll_any_count, focus_to_reroll - rerolled_focus_count));
            rerolled_focus_count  += any_rerolls_used_for_focus;
            free_reroll_any_count -= any_rerolls_used_for_focus;
        }

        // Indicate to the caller any additional dice that should be rerolled if possible (at cost)
        out_focus_to_reroll = focus_to_reroll - rerolled_focus_count;
        out_blank_to_reroll = blank_to_reroll - rerolled_blank_count;

        // Sanity
        assert(out_focus_to_reroll >= 0);
        assert(out_blank_to_reroll >= 0);

        return rerolled_focus_count + rerolled_blank_count;
    }




    // Utilities...
    private pure int amad_focus_to_hit_count(ref TokenState attack_tokens) const
    {
        return m_setup.AMAD.focus_to_hit_count + 
            (attack_tokens.stress > 0 ? m_setup.AMAD.stressed_focus_to_hit_count : m_setup.AMAD.unstressed_focus_to_hit_count);
    }
    private pure int amad_focus_to_crit_count(ref TokenState attack_tokens) const
    {
        return m_setup.AMAD.focus_to_crit_count + 
            (attack_tokens.stress > 0 ? m_setup.AMAD.stressed_focus_to_crit_count : m_setup.AMAD.unstressed_focus_to_crit_count);
    }
    private pure int dmdd_focus_to_evade_count(ref TokenState defense_tokens) const
    {
        return m_setup.DMDD.focus_to_evade_count + 
            (defense_tokens.stress > 0 ? m_setup.DMDD.stressed_focus_to_evade_count : m_setup.DMDD.unstressed_focus_to_evade_count);
    }

    private pure int amad_reroll_focus_count(ref TokenState attack_tokens) const
    {
        return m_setup.AMAD.reroll_focus_count +
            (attack_tokens.stress > 0 ? m_setup.AMAD.stressed_reroll_focus_count : m_setup.AMAD.unstressed_reroll_focus_count);
    }
    private pure int dmdd_reroll_focus_count(ref TokenState defense_tokens) const
    {
        return m_setup.DMDD.reroll_focus_count +
            (defense_tokens.stress > 0 ? m_setup.DMDD.stressed_reroll_focus_count : m_setup.DMDD.unstressed_reroll_focus_count);
    }
    private pure int amad_reroll_any_count(ref TokenState attack_tokens) const
    {
        return m_setup.AMAD.reroll_any_count +
            (attack_tokens.stress > 0 ? m_setup.AMAD.stressed_reroll_any_count : m_setup.AMAD.unstressed_reroll_any_count);
    }
    private pure int dmdd_reroll_any_count(ref TokenState defense_tokens) const
    {
        return m_setup.DMDD.reroll_any_count +
            (defense_tokens.stress > 0 ? m_setup.DMDD.stressed_reroll_any_count : m_setup.DMDD.unstressed_reroll_any_count);
    }

    // If all dice match, add another one
    // Returns true if the ability is still available, i.e. if it was *not* used
    private static bool do_sunny_bounder(ref DiceState dice)
    {
        // This algorithm allows common cases to early out which is desirable
        int seen_result = DieResult.Num;
        foreach (int result; 0 .. DieResult.Num)
        {
            if (dice.count(cast(DieResult)result) > 0)
            {
                if (seen_result == DieResult.Num)
                    seen_result = result;
                else
                    return true;     // Seen two different results
            }
        }

        // If we only saw one unique result, add another of that type!
        if (seen_result != DieResult.Num)
        {
            ++dice.results[seen_result];
            return false;
        }

        return true;
    }

    // TODO: Needs a way to force rerolls eventually as well
    private void defender_modify_attack_dice(ref DiceState attack_dice,
                                             ref TokenState attack_tokens) const
    {
        attack_dice.change_dice_no_reroll(DieResult.Hit, DieResult.Focus, m_setup.DMAD.hit_to_focus_no_reroll_count);
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private int attacker_modify_attack_dice_before_reroll(ref DiceState attack_dice,
                                                          ref TokenState attack_tokens) const
    {
        // Add free results
        attack_dice.results[DieResult.Hit]   += m_setup.AMAD.add_hit_count;
        attack_dice.results[DieResult.Crit]  += m_setup.AMAD.add_crit_count;
        attack_dice.results[DieResult.Blank] += m_setup.AMAD.add_blank_count;
        attack_dice.results[DieResult.Focus] += m_setup.AMAD.add_focus_count;

        // In most cases rerolling logic is fairly simple: reroll anything that isn't modifyable into a hit/crit ("useful")
        //
        // In the general case it can actually get quite complicated though, and involve probability math related to
        // the potential utility of tokens in various contexts, etc. Humans do not reason about these cases perfectly though,
        // so there's questionable value in achieving the "theoretically optimal" solution anyways.
        // 
        // One intentional simplification we've made here - both to logic and for the exhaustive search efficiency -
        // is that we choose all the dice we want to reroll *once*, then reroll all of them rather than rerolling sets
        // of dice and using their results to decide whether to reroll others. The latter can theoretically be slightly more
        // optimal in some cases, but it also makes the UI unusably complex, as now it needs a notion of which rerolls
        // must be done "together" and which can be done separately and so on.
        
        // "Useful" focus results are ones we can turn into hits or crits
        int useful_focus_results = (amad_focus_to_hit_count(attack_tokens) + m_setup.AMAD.focus_to_crit_count);
        if (attack_tokens.focus > 0)			// Simplification since this involves spending a token, but good enough
            useful_focus_results = k_all_dice_count;

        int useful_blank_results = (m_setup.AMAD.blank_to_hit_count + m_setup.AMAD.blank_to_crit_count);
        
        // Blank to focus we have to treat a bit carefully... again things can technically get fairly complicated in
        // the "optimal" case here, but for the most part we can get away with considering these blanks "useful" iff
        // we have excess "useful" focus tokens in the same amount. That's a good enough solution for the common cases.
        // This logic definitely isn't perfect since if we don't trigger this condition we're basically not considering
        // the blank to focus availability at all (which might affect things like whether it's "safe" to reroll focus
        // results since we can always immediately convert them back to focus even if we roll into a blank), but
        // it's sufficient for the time being without introducing too much additional complexity.
        {
            int excess_useless_blanks = min(m_setup.AMAD.blank_to_focus_count, attack_dice.count(DieResult.Blank) - useful_blank_results);
            int excess_useful_focus   = useful_focus_results - attack_dice.count(DieResult.Focus);
            if (excess_useless_blanks > 0 && excess_useful_focus >= excess_useless_blanks)
            {
                useful_blank_results += excess_useless_blanks;
                useful_focus_results -= excess_useless_blanks;
                assert(useful_focus_results >= 0);
                assert(useful_blank_results >= 0);
            }
        }

        int focus_to_reroll = 0;
        int blank_to_reroll = 0;
        int dice_to_reroll = do_free_rerolls(
            attack_dice, useful_focus_results, useful_blank_results,
            m_setup.AMAD.reroll_blank_count, amad_reroll_focus_count(attack_tokens), amad_reroll_any_count(attack_tokens),
            focus_to_reroll, blank_to_reroll);
        
        // Early out if we have nothing left to reroll
        if (focus_to_reroll == 0 && blank_to_reroll == 0)
            return dice_to_reroll;

        // If we have a target lock, we can reroll the additional stuff
        if (attack_tokens.target_lock > 0)
        {
            // Take into account our ability to freely change "any" results before spending target lock.
            // If we can change everything to hits/crits just with those abilities, don't spend the lock.
            // Otherwise it's usually best to reroll everything since it could save us from using the once per turn.
            int change_any_count =
                (attack_tokens.amad_any_to_crit ? 1 : 0) +
                (attack_tokens.amad_any_to_hit  ? 1 : 0);
            
            if ((focus_to_reroll + blank_to_reroll) > change_any_count)
            {
                int rerolled_count = attack_dice.remove_dice_for_reroll(DieResult.Blank, blank_to_reroll);
                rerolled_count    += attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_to_reroll);

                if (rerolled_count > 0)
                {
                    --attack_tokens.target_lock;
                    dice_to_reroll += rerolled_count;
                }
            }
        }

        return dice_to_reroll;
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private void attacker_modify_attack_dice_after_reroll(ref DiceState attack_dice,
                                                          ref TokenState attack_tokens,
                                                          bool final_attack) const
    {
        // Handle accuracy corrector... we cache the token state here before doing other modification -
        // namely focus spending - because we assume at this point that the player could determine if it's
        // better to spend tokens to modify, or just trigger accuracy corrector.
        // Note that human behavior here is not 100% optimal, but for our purposes it's fair to assume
        // that people will still attempt to modify dice as usual with rerolls until they determine they
        // can't beat AC.
        // TODO: As usual, there are various edge cases that we could handle here... ex.
        // if there's no possible way to get more than two hits we could just trigger AC right off the bat
        // and ignore the rolled results entirely. More complex, in some cases with FCS + gunner it might be
        // better to cancel but not add the two hits back in to intentionally trigger FCS and gunner for a
        // second attack...
        TokenState attack_tokens_before_ac = attack_tokens;

        // Rerolls are done - change results

        // NOTE: Order matters here - do the most useful changes first
        attack_dice.change_dice(DieResult.Blank, DieResult.Crit,  m_setup.AMAD.blank_to_crit_count);
        attack_dice.change_dice(DieResult.Blank, DieResult.Hit,   m_setup.AMAD.blank_to_hit_count);
        attack_dice.change_dice(DieResult.Blank, DieResult.Focus, m_setup.AMAD.blank_to_focus_count);
        attack_dice.change_dice(DieResult.Focus, DieResult.Crit,  amad_focus_to_crit_count(attack_tokens));
        attack_dice.change_dice(DieResult.Focus, DieResult.Hit,   amad_focus_to_hit_count(attack_tokens));

        // TODO: We should technically take one damage on hit and a bunch of details about
        // the defender's maximum defense results into account here with respect to spending
        // tokens and once per turn abilities. i.e. in certain situations there's no need to
        // over-spend if there's no possible way the defender can dodge the shot already.
        //
        // That said, this logic can actually get pretty non-trivial in the general case.
        // In the short/mid term probably the most reasonable thing is to just look at how
        // many dice + evade token + add results abilities they have as a rough proxy for
        // the maximum number of evades they could get.

        // Spend regular focus?
        // Generally we prefer spending focus to any more general modifications that work other dice results
        if (attack_tokens.focus > 0)
        {
            int initial_focus_count = attack_tokens.focus;

            // Regular focus effect
            if (attack_dice.change_dice(DieResult.Focus, DieResult.Hit) > 0)
                --attack_tokens.focus;
            
            // Spend a focus each to convert a blank into a hit
            int blank_to_hit_count = min(m_setup.AMAD.spend_focus_one_blank_to_hit, attack_tokens.focus);
            attack_tokens.focus -= attack_dice.change_dice(DieResult.Blank, DieResult.Hit, blank_to_hit_count);

            // NOTE: This still works correctly with accuracy corrector, as the FAQ states that if you
            // invoke AC and thus cannot modify dice, you are no longer able/required to spend focus.
            if (m_setup.attack_must_spend_focus && initial_focus_count == attack_tokens.focus)
            {
                --attack_tokens.focus;
                // NOTE: Would need to modify this logic if we add additional complexity around "one damage on hit"
                assert(attack_dice.count_mutable(DieResult.Focus) == 0);
            }
        }

        // Spend "once per turn" abilities if present
        if (attack_tokens.amad_any_to_crit)
        {
            attack_tokens.amad_any_to_crit = (attack_dice.change_blank_focus(DieResult.Crit, 1) == 0);
            
            // If this is the final attack, might as well change a hit to a crit also
            if (attack_tokens.amad_any_to_crit && final_attack)
            {
                attack_tokens.amad_any_to_crit = (attack_dice.change_dice(DieResult.Hit, DieResult.Crit, 1) == 0);
            }
        }
        if (attack_tokens.amad_any_to_hit)
            attack_tokens.amad_any_to_hit  = (attack_dice.change_blank_focus(DieResult.Hit,  1) == 0);

        // Modify any hit results (including those generated above) as appropriate
        attack_dice.change_dice(DieResult.Hit, DieResult.Crit, m_setup.AMAD.hit_to_crit_count);

        // Use accuracy corrector in the following cases:
        // a) We ended up with less than 2 hits/crits
        // b) We got exactly 2 hits/crits but we only care if we "hit the attack" (TLT, Ion, etc)
        // b) We got exactly 2 hits and no crits (still better to remove the extra die for LWF, and not spend tokens)
        if (m_setup.AMAD.accuracy_corrector)
        {
            int hits = attack_dice.count(DieResult.Hit);
            int crits = attack_dice.count(DieResult.Crit);
            if (((hits + crits) <  2) ||
                (hits == 2 && crits == 0) ||
                ((hits + crits) == 2 && m_setup.attack_one_damage_on_hit))
            {
                attack_tokens = attack_tokens_before_ac;  // Undo focus token spending (see above notes)

                attack_dice.cancel_all();
                attack_dice.results[DieResult.Hit] += 2;
            }
        }
        // No more modification after AC!
    }

    void attacker_modify_defense_dice(
        ubyte[DieResult.Num] attack_results,
        ref DiceState defense_dice,
        ref TokenState defense_tokens) const
    {
        // Change results
        defense_dice.change_dice(DieResult.Evade, DieResult.Focus, m_setup.AMDD.evade_to_focus_count);
    }

    int defender_modify_defense_dice_before_reroll(
        const(ubyte)[DieResult.Num] attack_results,
        ref DiceState defense_dice,
        ref TokenState defense_tokens) const
    {
        // Add free results
        defense_dice.results[DieResult.Blank] += m_setup.DMDD.add_blank_count;
        defense_dice.results[DieResult.Focus] += m_setup.DMDD.add_focus_count;
        defense_dice.results[DieResult.Evade] += m_setup.DMDD.add_evade_count;

        // "Useful" focus results are ones we can turn into evades
        int useful_focus_results = dmdd_focus_to_evade_count(defense_tokens);
        if (defense_tokens.focus > 0)			// Simplification since this involves spending a token, but good enough
            useful_focus_results = k_all_dice_count;
        int useful_blank_results = m_setup.DMDD.blank_to_evade_count;

        int focus_to_reroll = 0;
        int blank_to_reroll = 0;
        int dice_to_reroll = do_free_rerolls(
            defense_dice, useful_focus_results, useful_blank_results,
            m_setup.DMDD.reroll_blank_count, dmdd_reroll_focus_count(defense_tokens), dmdd_reroll_any_count(defense_tokens),
            focus_to_reroll, blank_to_reroll);

        // NOTE: We currently don't have any way to spend things to reroll defense dice, so we're done after the free rerolls
        return dice_to_reroll;
    }

    void defender_modify_defense_dice_after_reroll(
        const(ubyte)[DieResult.Num] attack_results,
        ref TokenState attack_tokens,
        ref DiceState defense_dice,
        ref TokenState defense_tokens) const
    {
        int initial_focus_count = defense_tokens.focus;

        // Change results
        // NOTE: Order matters here - do the most useful changes first
        defense_dice.change_dice(DieResult.Blank, DieResult.Evade, m_setup.DMDD.blank_to_evade_count);
        defense_dice.change_dice(DieResult.Focus, DieResult.Evade, dmdd_focus_to_evade_count(defense_tokens));

        // Figure out if we should spend focus or evade tokens (regular effect)
        int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit] - defense_dice.count(DieResult.Evade);
        int mutable_focus_results = defense_dice.count_mutable(DieResult.Focus);

        // FAQ update: can only spend a single focus or evade per attack!
        bool can_spend_focus = (defense_tokens.focus > 0 && mutable_focus_results > 0);
        bool can_spend_evade = (defense_tokens.evade > 0);

        bool spent_focus = false;
        bool spent_evade = false;

        // Spend regular focus or evade tokens?
        if (uncanceled_hits > 0 && (can_spend_focus || can_spend_evade))
        {
            int max_damage_canceled = (can_spend_focus ? mutable_focus_results : 0) + (can_spend_evade ? 1 : 0);
            bool can_cancel_all = (max_damage_canceled >= uncanceled_hits);

            // In the presence of "one damage on hit" effects from the attacker, if we can't cancel everything,
            // it's pointless to spend any tokens at all.
            if (can_cancel_all || !m_setup.attack_one_damage_on_hit)
            {
                // NOTE: Optimal strategy here depends on quite a lot of factors, but this is good enough in most cases
                // - If defender must spend focus (ex. hotshot copilot), prefer to spend focus.
                // - If attacker can modify evades into focus (ex. juke), prefer to spend evade.
                // - Generally prefer to spend focus if none of the above conditions apply                
                bool prefer_spend_focus = (m_setup.AMDD.evade_to_focus_count == 0) || (m_setup.defense_must_spend_focus);

                bool can_cancel_all_with_focus = can_spend_focus && (mutable_focus_results >= uncanceled_hits);
                bool can_cancel_all_with_evade = can_spend_evade && (1 >= uncanceled_hits);

                // Do we need to spend both to cancel all hits?
                if (!can_cancel_all_with_focus && !can_cancel_all_with_evade)
                {
                    spent_focus = can_spend_focus;
                    spent_evade = can_spend_evade;
                }
                else if (prefer_spend_focus)      // Hold onto evade primarily
                {
                    if (can_cancel_all_with_focus)
                    {
                        assert(can_spend_focus);
                        spent_focus = true;
                    }
                    else
                    {
                        assert(can_cancel_all_with_evade);
                        spent_evade = can_spend_evade;
                    }
                }
                else                              // Hold on to focus primarily
                {
                    if (can_cancel_all_with_evade)
                    {
                        assert(can_spend_evade);
                        spent_evade = true;
                    }
                    else
                    {
                        assert(can_cancel_all_with_focus);
                        spent_focus = can_spend_focus;
                    }
                }
            }
        }

        if (spent_focus)
        {
            uncanceled_hits -= mutable_focus_results;
            defense_dice.change_dice(DieResult.Focus, DieResult.Evade);
            --defense_tokens.focus;
        }

        // Evade tokens add defense dice to the pool
        if (spent_evade)
        {
            --uncanceled_hits;
            ++defense_dice.results[DieResult.Evade];
            --defense_tokens.evade;
        }
        
        // If we still have uncanceled hits, consider spending other tokens if possible)

        // Spend a focus each to convert a blank into an evade
        if (uncanceled_hits > 0 && m_setup.DMDD.spend_focus_one_blank_to_evade > 0)
        {
            int blank_to_evade_count = min(m_setup.DMDD.spend_focus_one_blank_to_evade, defense_tokens.focus);
            int blanks_changed = defense_dice.change_dice(DieResult.Blank, DieResult.Evade, blank_to_evade_count);
            defense_tokens.focus -= blanks_changed;
            uncanceled_hits -= blanks_changed;            
        }

        // Spend attacker stress to add an evade?
        // NOTE: There are some edge cases where it's actually better to spend the attacker stress even
        // if we don't need the evade, as it may be enabling passive mods for a future attack.
        // These are pretty esoteric though, so we'll stick to the more intuitive logic for now.
        if (uncanceled_hits > 0 && m_setup.DMDD.spend_attacker_stress_add_evade && attack_tokens.stress > 0)
        {
            --attack_tokens.stress;
            ++defense_dice.results[DieResult.Evade];
            --uncanceled_hits;
        }        

        // If required and we didn't already spend focus, spend it now
        if (m_setup.defense_must_spend_focus && initial_focus_count > 0 && initial_focus_count == defense_tokens.focus)
        {
            --defense_tokens.focus;
            assert(uncanceled_hits == 0 || defense_dice.count_mutable(DieResult.Focus) == 0);
        }

        // Sanity
        assert(uncanceled_hits <= 0 || ((!can_spend_focus || spent_focus) && (!can_spend_evade || spent_evade)));
        assert(defense_tokens.evade >= 0);
        assert(defense_tokens.focus >= 0);
    }

    private ubyte[DieResult.Num] compare_results(
        ubyte[DieResult.Num] attack_results,
        ubyte[DieResult.Num] defense_results) const
    {
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
        if (m_setup.attack_one_damage_on_hit && attack_hit)
        {
            attack_results[DieResult.Hit] = 1;
            attack_results[DieResult.Crit] = 0;
        }
        return attack_results;
    }

    private void after_attack(ref TokenState attack_tokens, ref TokenState defense_tokens) const
    {
        // Update any abilities that trigger "after attacking" or "after defending"
        if (m_setup.attack_fire_control_system)
        {
            // TODO: Handle multi-target-lock stuff... really only an issue with Redline and so on
            if (attack_tokens.target_lock < 1) attack_tokens.target_lock = 1;
        }
    }



    // Returns full set of states after result comparison (results put into state.final_hits, etc)
    // Does not directly accumulate as this may be part of a multi-attack sequence.
    public SimulationStateMap simulate_single_attack(TokenState attack_tokens,
                                                     TokenState defense_tokens,
                                                     int completed_attack_count = 0)
    {
        SimulationState initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;
        initial_state.completed_attack_count = completed_attack_count;

        SimulationStateMap states;
        states[initial_state] = 1.0f;

        // Roll and modify attack dice
        states = roll_attack_dice!(true)(states, &attack_modify_before_reroll, m_setup.attack_dice);
        states = roll_attack_dice!(false)(states, &attack_modify_after_reroll);

        // Roll and modify defense dice, and compare results
        states = roll_defense_dice!(true)(states, &defense_modify_before_reroll, m_setup.defense_dice);
        states = roll_defense_dice!(false)(states, &defense_modify_after_reroll);

        return states;
    }


    // Returns full set of states after result comparison (results put into state.final_hits, etc)
    // Does not directly accumulate as this may be part of a multi-attack sequence.
    public SimulationStateMap simulate_single_attack(SimulationStateMap initial_states)
    {
        // NOTE: It would be "correct" here to just immediately fork all of our states set into another attack,
        // but that is relatively inefficient. Since the core thing that affects how the next attack plays out is
        // our *tokens*, we want to only simulate additional attacks with unique token sets, then apply
        // the results to any input states with that token set.

        // For now we'll do that in the simplest way possible: simply iterate the states and perform second
        // attack simulations for any unique token sets that we run into. Then we'll apply the results with all
        // input states to use that token set.
        //
        // NOTE: This is all assuming that an "attack" logic only depends on the "setup" and "tokens", and never
        // on anything like the number of hits that happened in the previous attack. This is a safe assumption for
        // now. We could technically split our state set into two parts to represent this more formally, but that
        // would make it a lot more wordy - and potentially less efficient - to pass it around everywhere.

        SimulationStateMap new_states;
        int second_attack_evaluations = 0;

        // Sort our states by tokens so that any matching sets are back to back in the list
        SimulationState[] initial_states_list = initial_states.keys.dup;
        multiSort!("a.attack_tokens < b.attack_tokens", "a.defense_tokens < b.defense_tokens")(initial_states_list);
        
        TokenState last_attack_tokens;
        TokenState last_defense_tokens;
        // Hacky just to ensure these don't match the first element
        last_attack_tokens.focus = initial_states_list[0].attack_tokens.focus;
        ++last_attack_tokens.focus;

        SimulationStateMap second_attack_states;
       
        foreach (ref initial_state; initial_states_list)
        {
            // If our tokens are the same as the previous simulation (we sorted), we don't have to simulate again
            if (initial_state.attack_tokens != last_attack_tokens ||
                initial_state.defense_tokens != last_defense_tokens)
            {
                // This can be expensive for lots of states so worth allowing other things to run occasionally
                vibe.core.core.yield();

                //auto sw = StopWatch(AutoStart.yes);

                // New token state set, so run a new simulation
                last_attack_tokens = initial_state.attack_tokens;
                last_defense_tokens = initial_state.defense_tokens;

                // TODO: Consider the use of completed attack count here...
                // It should be fine since any calls to second attacks, etc. are done in lock step with the relevant
                // states being carried forward, but there may be some simple ways to make this somewhat more robust
                // to theoretical cases of mixed state sets.
                second_attack_states = simulate_single_attack(last_attack_tokens,
                                                              last_defense_tokens,
                                                              initial_state.completed_attack_count);
                ++second_attack_evaluations;

                //writefln("Second attack in %s msec", sw.peek().msecs());
            }

            // Compose all of the results from the second attack set with this one
            auto initial_probability = initial_states[initial_state];
            foreach (ref second_attack_state, second_probability; second_attack_states)
            {
                // NOTE: Important to keep the token state and such from after the second attack, not initial one
                // We basically just want to add each of the combinations of "final hits/crits" together for the
                // combined attack.
                SimulationState new_state = second_attack_state;
                new_state.final_hits			 += initial_state.final_hits;
                new_state.final_crits		     += initial_state.final_crits;
                new_state.completed_attack_count += initial_state.completed_attack_count;
                append_state(new_states, new_state, initial_probability * second_probability);
            }
        }

        return new_states;
    }

    public void simulate_attack()
    {
        // First attack
        auto states = simulate_single_attack(m_setup.attack_tokens, m_setup.defense_tokens);

        //writefln("Attack complete with %s states.", states.length);

        if (m_setup.type == MultiAttackType.SecondaryPerformTwice ||
            m_setup.type == MultiAttackType.AfterAttack)
        {
            // Unconditional second attacks
            states = simulate_single_attack(states);
        }
        else if (m_setup.type == MultiAttackType.AfterAttackDoesNotHit)
        {
            // Only attack again for the states that didn't hit anything
            SimulationStateMap second_attack_states;
            SimulationStateMap no_second_attack_states;
            foreach (ref state, state_probability; states)
            {
                if (state.final_hits == 0 && state.final_crits == 0)
                {
                    second_attack_states[state] = state_probability;
                }
                else
                {
                    no_second_attack_states[state] = state_probability;
                }
            }

            //writefln("Second attack for %s states.", second_attack_states.length);

            // Do the next attack for those states, then merge them into the other list
            if (second_attack_states.length > 0)
            {
                second_attack_states = simulate_single_attack(second_attack_states);

                states = no_second_attack_states;
                foreach (ref state, state_probability; second_attack_states)
                {
                    assert(!(state in states));		// Should not be possible since attack index will be incremented
                    states[state] = state_probability;
                }
            }
        }

        // Record final results
        foreach (ref state, state_probability; states)
        {
            accumulate(state_probability, state.final_hits, state.final_crits, state.attack_tokens, state.defense_tokens);
        }
    }

    private SimulationState attack_modify_before_reroll(SimulationState state)
    {
        // "After rolling" events
        // NOTE: FAQ says sunny triggers before HLC (just because...)
        if (state.attack_tokens.sunny_bounder)
            state.attack_tokens.sunny_bounder = do_sunny_bounder(state.attack_dice);
        if (m_setup.attack_heavy_laser_cannon)
            state.attack_dice.change_dice(DieResult.Crit, DieResult.Hit);

        defender_modify_attack_dice(state.attack_dice, state.attack_tokens);
        state.dice_to_reroll = attacker_modify_attack_dice_before_reroll(state.attack_dice, state.attack_tokens);
        return state;
    }

    private SimulationState attack_modify_after_reroll(SimulationState state)
    {
        // "After rerolling" events
        // TODO: Wackiness of spending target lock to reroll "0" dice? And sort out what that means for passive mods?
        if (state.dice_to_reroll > 0 && state.attack_tokens.sunny_bounder)
            state.attack_tokens.sunny_bounder = do_sunny_bounder(state.attack_dice);

        bool final_attack = (m_setup.type == MultiAttackType.Single || state.completed_attack_count == 1);
        attacker_modify_attack_dice_after_reroll(state.attack_dice, state.attack_tokens, final_attack);

        // Done modifying attack dice
        state.attack_dice.finalize();
        state.dice_to_reroll = 0;

        return state;
    }

    private SimulationState defense_modify_before_reroll(SimulationState state)
    {
        // "After rolling" events
        if (state.defense_tokens.sunny_bounder)
            state.defense_tokens.sunny_bounder = do_sunny_bounder(state.defense_dice);

        attacker_modify_defense_dice(state.attack_dice.final_results, state.defense_dice, state.defense_tokens);
        state.dice_to_reroll = defender_modify_defense_dice_before_reroll(state.attack_dice.final_results, state.defense_dice, state.defense_tokens);
        return state;
    }

    private SimulationState defense_modify_after_reroll(SimulationState state)
    {
        // "After rerolling" events
        if (state.dice_to_reroll > 0 && state.defense_tokens.sunny_bounder)
            state.defense_tokens.sunny_bounder = do_sunny_bounder(state.defense_dice);

        defender_modify_defense_dice_after_reroll(state.attack_dice.final_results, state.attack_tokens, state.defense_dice, state.defense_tokens);

        // Done modifying defense dice
        state.defense_dice.finalize();
        state.dice_to_reroll = 0;

        // Compare results
        auto attack_results = compare_results(state.attack_dice.final_results, state.defense_dice.final_results);

        // "After attack" abilities do not trigger on the first of a "secondary perform twice" attack
        if (state.completed_attack_count > 0 || m_setup.type != MultiAttackType.SecondaryPerformTwice)
        {
            after_attack(state.attack_tokens, state.defense_tokens);
        }

        state.final_hits  += attack_results[DieResult.Hit];
        state.final_crits += attack_results[DieResult.Crit];
        ++state.completed_attack_count;

        // Simplify state in case of further iteration
        // Keep tokens and final results, discard the rest
        state.attack_dice.cancel_all();
        state.defense_dice.cancel_all();

        // TODO: Maybe assert only the relevant states are set on output here

        return state;
    }

    






    private void accumulate(double probability, int hits, int crits, TokenState attack_tokens, TokenState defense_tokens)
    {
        // Sanity checks on token spending
        assert(attack_tokens.focus >= 0);
        assert(attack_tokens.evade >= 0);
        assert(attack_tokens.target_lock >= 0);
        assert(attack_tokens.stress >= 0);

        assert(defense_tokens.focus >= 0);
        assert(defense_tokens.evade >= 0);
        assert(defense_tokens.target_lock >= 0);
        assert(defense_tokens.stress >= 0);

        // Compute final results of this simulation step
        // TODO: Can clean this up
        SimulationResult result;
        result.probability = probability;

        result.hits  = probability * cast(double)hits;
        result.crits = probability * cast(double)crits;

        result.attack_delta_focus_tokens  = probability * cast(double)(attack_tokens.focus        - m_setup.attack_tokens.focus      );
        result.attack_delta_target_locks  = probability * cast(double)(attack_tokens.target_lock  - m_setup.attack_tokens.target_lock);
        result.attack_delta_stress        = probability * cast(double)(attack_tokens.stress       - m_setup.attack_tokens.stress     );
        result.defense_delta_focus_tokens = probability * cast(double)(defense_tokens.focus       - m_setup.defense_tokens.focus     );
        result.defense_delta_evade_tokens = probability * cast(double)(defense_tokens.evade       - m_setup.defense_tokens.evade     );
        result.defense_delta_stress       = probability * cast(double)(defense_tokens.stress      - m_setup.defense_tokens.stress    );

        m_total_sum = accumulate_result(m_total_sum, result);

        // Accumulate into the right bin of the total hits PDF
        int total_hits = hits + crits;
        if (total_hits >= m_total_hits_pdf.length)
            m_total_hits_pdf.length = total_hits + 1;
        m_total_hits_pdf[total_hits] = accumulate_result(m_total_hits_pdf[total_hits], result);
    }

    public SimulationResult[] total_hits_pdf() const
    {
        return m_total_hits_pdf.dup;
    }

    public SimulationResult total_sum() const
    {
        return m_total_sum;
    }

    // Accumulated results
    private SimulationResult[] m_total_hits_pdf;
    private SimulationResult m_total_sum;

    private immutable SimulationSetup m_setup;
};




unittest
{
    import std.math;

    static bool nearly_equal_p(double v, double expected)
    {
        assert(v >= 0.0 && v <= 1.0 && expected >= 0.0 && expected <= 1.0);

        // If we expect exactly 0 probability, we require it exactly (i.e. not a single trial went that route)        
        if (expected == 0.0)
            return v == 0.0;
        else
            return ((abs(v - expected) / expected) < 1e-7);    // Relative error
    }

    static void assert_hits_pdf(ref const(SimulationSetup) setup, const(float)[] expected_p)
    {
        auto simulation = new Simulation(setup);
        simulation.simulate_attack();
        auto total_hits_pdf = simulation.total_hits_pdf();
        auto total_sum = simulation.total_sum();

        assert(total_hits_pdf.length >= expected_p.length);

        foreach (i; 0 .. expected_p.length)
        {
            bool matches = nearly_equal_p(total_hits_pdf[i].probability, expected_p[i]);
            //writefln("hits[%s]: %.15f %s %.15f", i, matches ? "==" : "!=", total_hits_pdf[i].probability, expected_p[i]);
            assert(nearly_equal_p(total_hits_pdf[i].probability, expected_p[i]));
        }

        foreach (i; expected_p.length .. total_hits_pdf.length)
        {
            assert(total_hits_pdf[i].probability == 0.0);
        }
    }

    // Basic sanity checks
    {
        SimulationSetup setup;
        setup.attack_dice = 3;
        setup.defense_dice = 3;
        assert_hits_pdf(setup, [0.53369140625, 0.289306640625, 0.146484375, 0.030517578125]);

        setup.attack_tokens.focus = 1;
        setup.attack_tokens.target_lock = 1;
        setup.defense_tokens.focus = 1;
        setup.defense_tokens.evade = 1;
        assert_hits_pdf(setup, [0.730598926544189, 0.225949287414551, 0.043451786041259, 0.0]);

        setup.type = MultiAttackType.SecondaryPerformTwice;
        assert_hits_pdf(setup, [0.419614922167966, 0.295413697109325, 0.191800311527913, 0.076275200204690, 0.016023014264646, 0.000872854725457]);
        // Same as above as no "after attack" triggers are present
        setup.type = MultiAttackType.AfterAttack;
        assert_hits_pdf(setup, [0.419614922167966, 0.295413697109325, 0.191800311527913, 0.076275200204690, 0.016023014264646, 0.000872854725457]);
    }
}
