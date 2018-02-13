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

// Wrapper to handle modifiers that vary based on token presence (not spending!)
// Example: many cards depend on whether yopu are stressed or unstressed
struct PassiveModifier
{
    int always = 0;         // Always active, regardless of tokens
    int unstressed = 0;     // Only active when unstressed
    int stressed = 0;       // Only active when stressed
    int focused = 0;        // Only active when focus token present

    int opCall(TokenState tokens) const
    {
        return always +
            (tokens.stress > 0 ? stressed : unstressed) +
            (tokens.focus > 0 ? focused : 0);
    }
};


struct SimulationSetup
{
    // Attack
    int attack_dice = 0;

    struct AttackerModifyAttackDice
    {
        // Add results
        int add_hit_count = 0;
        int add_crit_count = 0;
        int add_blank_count = 0;
        int add_focus_count = 0;

        // Rerolls
        PassiveModifier reroll_any_count;
        PassiveModifier reroll_blank_count;
        PassiveModifier reroll_focus_count;
        PassiveModifier reroll_any_gain_stress_count;

        // Change results
        PassiveModifier focus_to_crit_count;
        PassiveModifier focus_to_hit_count;
        int blank_to_crit_count = 0;
        int blank_to_hit_count = 0;
        int blank_to_focus_count = 0;
        int hit_to_crit_count = 0;

        // Spend tokens to change results
        int spend_focus_one_blank_to_hit = 0;

        // NOTE: Single use abilities are treated as "tokens" (see TokenState)

        // Can cancel all results and replace with 2 hits
        bool accuracy_corrector = false;
    };
    AttackerModifyAttackDice AMAD;

    struct AttackerModifyDefenseDice
    {
        // Rerolls
        PassiveModifier reroll_evade_gain_stress_count;     // Gain stress for each reroll

        // Change results
        int evade_to_focus_count = 0;
    };
    AttackerModifyDefenseDice AMDD;

    // Special effects
    bool attack_must_spend_focus = false;           // Attacker must spend focus (hotshot copilot on defender)
    bool attack_fire_control_system = false;        // Get a target lock after attack (only affects multi-attack)
    bool attack_heavy_laser_cannon = false;         // After initial roll, change all crits->hits
    bool attack_one_damage_on_hit = false;          // If attack hits, 1 damage (TLT, Ion, etc)
    bool attack_lose_stress_on_hit = false;         // If attack hits, lose one stress
    bool attack_crack_shot = false;                 // At the start of compare results, can spend to cancel an evade

    // Defense
    int defense_dice = 0;

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
        PassiveModifier reroll_blank_count;
        PassiveModifier reroll_focus_count;
        PassiveModifier reroll_any_count;

        // Change results
        int blank_to_evade_count = 0;
        PassiveModifier focus_to_evade_count;
        int spend_focus_one_blank_to_evade = 0;

        // Misc stuff
        bool spend_attacker_stress_add_evade = false;
    };
    DefenderModifyDefenseDice DMDD;

    // Special effects
    bool defense_must_spend_focus = false;          // Defender must spend focus (hotshot copilot on attacker)
    int defense_guess_evades = 0;                   // If initially roll this many evades, add another evade (C-3P0). Once per turn so see related token

    // TODO: Autoblaster (hit results cannot be canceled)
    // TODO: Lightweight frame

    // TODO: Crack shot? (gets a little bit complex as presence affects defender logic and as well)
    // TODO: 4-LOM Crew
    // TODO: Bossk Crew
    // TODO: Captain rex (only affects multi-attack)
    // TODO: Operations specialist? Again only multi-attack

    // Ones that require spending tokens (more complex generally)
    // TODO: Calculation (pay focus: one focus->crit)
    // TODO: Han Solo Crew (spend TL: all hits->crits)
    // TODO: R4 Agromech (after spending focus, gain TL that can be used in same attack)

    // TODO: Elusiveness
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
    double attack_delta_crack_shot   = 0;

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
    a.attack_delta_crack_shot    += b.attack_delta_crack_shot;

    a.defense_delta_focus_tokens += b.defense_delta_focus_tokens;
    a.defense_delta_evade_tokens += b.defense_delta_evade_tokens;
    a.defense_delta_stress       += b.defense_delta_stress;

    return a;
}

//-----------------------------------------------------------------------------------




class Simulation
{
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

    private static void assert_no_rerolled_or_final_dice(ref const(DiceState) dice)
    {
        debug
        {
            for (int i = 0; i < DieResult.Num; ++i)
            {
                assert(dice.rerolled_results[i] == 0);
                assert(dice.final_results[i] == 0);
            }
        }
    }

    // Offensive palpatine - change one die to a (final) crit
    private void do_attack_palpatine(ref DiceState dice, ref TokenState attack_tokens) const
    {
        // Palpatine happens right after rolling so there should not be any rerolled or final dice
        assert_no_rerolled_or_final_dice(dice);

        // As with other effects, this logic could get arbitrarily complicated based on simulating
        // the rest of the attack using the currently available mods. For practical purposes, we're
        // just going to consider passive ways to modify dice here and generally prefer changing
        // blanks, then focus, then hits, then crits unless we have passive ways to modify all
        // of the results that we rolled of a type.
        
        // TODO: Do we try and handle blank -> focus -> hit/crit chains?
        // TODO: Consider passive rerolls of certain types as well?
        int useful_blanks = m_setup.AMAD.blank_to_hit_count + m_setup.AMAD.blank_to_crit_count;
        int useful_focus =  m_setup.AMAD.focus_to_hit_count(attack_tokens) + m_setup.AMAD.focus_to_crit_count(attack_tokens);

        if (dice.results[DieResult.Blank] > useful_blanks)
            dice.change_dice_final(DieResult.Blank, DieResult.Crit, 1);
        else if (dice.results[DieResult.Focus] > useful_focus)
            dice.change_dice_final(DieResult.Focus, DieResult.Crit, 1);
        // Changing a crit->crit is still required if necessary, and prevents further modification
        else if (dice.change_dice_final(DieResult.Hit, DieResult.Crit, 1) == 0 &&
                 dice.change_dice_final(DieResult.Crit, DieResult.Crit, 1) == 0)
        {
            // No useless results. OMG WASTED PALP :P Palp something useful anyways as its required.
            if (dice.change_dice_final(DieResult.Focus, DieResult.Crit, 1) == 0)
                dice.change_dice_final(DieResult.Blank, DieResult.Crit, 1);
        }

        assert(dice.final_results[DieResult.Crit] == 1);
    }

    // Defensive palpatine - change one die to a (final) evade
    private void do_defense_palpatine(ref DiceState dice, ref TokenState defense_tokens) const
    {
        // Palpatine happens right after rolling so there should not be any rerolled or final dice
        assert_no_rerolled_or_final_dice(dice);

        // Logic is as above
        int useful_blanks = m_setup.DMDD.blank_to_evade_count;
        int useful_focus =  m_setup.DMDD.focus_to_evade_count(defense_tokens);

        if (dice.results[DieResult.Blank] > useful_blanks)
            dice.change_dice_final(DieResult.Blank, DieResult.Evade, 1);
        else if (dice.results[DieResult.Focus] > useful_focus)
            dice.change_dice_final(DieResult.Focus, DieResult.Evade, 1);
        else if (dice.change_dice_final(DieResult.Evade, DieResult.Evade, 1) == 0)
        {
            // No useless results. OMG WASTED PALP :P Palp something useful anyways as its required.
            if (dice.change_dice_final(DieResult.Focus, DieResult.Evade, 1) == 0)
                dice.change_dice_final(DieResult.Blank, DieResult.Evade, 1);
        }

        assert(dice.final_results[DieResult.Evade] == 1);
    }

    private int dmad_before_reroll(ref DiceState attack_dice, ref TokenState attack_tokens) const
    {
        // Nothing to do here yet
        return 0;
    }

    private void dmad_after_reroll(ref DiceState attack_dice, ref TokenState attack_tokens) const
    {
        attack_dice.change_dice_no_reroll(DieResult.Hit, DieResult.Focus, m_setup.DMAD.hit_to_focus_no_reroll_count);
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private int amad_before_reroll(ref DiceState attack_dice,
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
        int useful_focus_results = m_setup.AMAD.focus_to_hit_count(attack_tokens) + m_setup.AMAD.focus_to_crit_count(attack_tokens);
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
            m_setup.AMAD.reroll_blank_count(attack_tokens),
            m_setup.AMAD.reroll_focus_count(attack_tokens),
            m_setup.AMAD.reroll_any_count(attack_tokens),
            focus_to_reroll, blank_to_reroll);
        
        // Early out if we have nothing left to reroll
        if (focus_to_reroll == 0 && blank_to_reroll == 0)
            return dice_to_reroll;

        // Take into account our ability to freely change "any" results before spending tokens.
        // If we can change everything to hits/crits just with those abilities, don't spend anything.
        // Otherwise it's usually best to reroll everything since it could save us from using the once per round.
        int change_any_count =
            (attack_tokens.amad_any_to_crit ? 1 : 0) +
            (attack_tokens.amad_any_to_hit  ? 1 : 0);

        if ((focus_to_reroll + blank_to_reroll) <= change_any_count)
            return dice_to_reroll;

        // If we have a target lock, we can reroll the additional stuff
        if (attack_tokens.target_lock > 0)
        {
            int rerolled_count = attack_dice.remove_dice_for_reroll(DieResult.Blank, blank_to_reroll);
            rerolled_count    += attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_to_reroll);

            if (rerolled_count > 0)
            {
                --attack_tokens.target_lock;
                dice_to_reroll += rerolled_count;
            }
        }
        // Can we gain stress to reroll?
        else if (m_setup.AMAD.reroll_any_gain_stress_count(attack_tokens) > 0)
        {
            // Ok this gets a bit tricky as now we're intentionally gaining stress to do rerolls, which can
            // effect whether other passive modifiers are active or not. Examples: Expertise, Wired, etc.
            // There's not a perfect way to handle this in the arbitrary case.
            // Remember that we've computed the dice we want to reroll based on our analysis of the current
            // token set and active modifiers above.

            // Note that there are cases where gaining stress is desirable to turn on mods even if we don't
            // need to reroll anything (or have instead spent a TL to reroll), but that analysis also gets
            // a bit tricky in the arbitrary case, so we're sticking to the simpler logic that we will
            // prefer not gaining stress where possible.

            // For now, since there's currently no way to lost stress in the Modify Attack Dice phase (only
            // after an attack), it's safe to assume that any passive dice mods that depend on being unstressed
            // can (and should) be used now before gaining the additional stress. Otherwise we'd have to try
            // and track which effects we've used between the phases which implies we also need to split
            // out and separately track each card which turns into a UI nightmare.

            // NOTE: Use *only* the "unstressed" effects as we're going to be turning those off anyways
            attack_dice.change_dice(DieResult.Focus, DieResult.Crit,  m_setup.AMAD.focus_to_crit_count.unstressed);
            attack_dice.change_dice(DieResult.Focus, DieResult.Hit,   m_setup.AMAD.focus_to_hit_count.unstressed);

            int total_rerolls = m_setup.AMAD.reroll_any_gain_stress_count(attack_tokens);
            int rerolled_count  = attack_dice.remove_dice_for_reroll(DieResult.Blank, min(blank_to_reroll, total_rerolls));
            rerolled_count     += attack_dice.remove_dice_for_reroll(DieResult.Focus, min(focus_to_reroll, total_rerolls - rerolled_count));

            attack_tokens.stress += rerolled_count;
            dice_to_reroll += rerolled_count;
        }

        return dice_to_reroll;
    }

    // Removes rerolled dice from pool; returns number of dice to reroll
    private void amad_after_reroll(ref DiceState attack_dice,
                                   ref TokenState attack_tokens) const
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
        attack_dice.change_dice(DieResult.Focus, DieResult.Crit,  m_setup.AMAD.focus_to_crit_count(attack_tokens));
        attack_dice.change_dice(DieResult.Focus, DieResult.Hit,   m_setup.AMAD.focus_to_hit_count(attack_tokens));

        // TODO: We should technically take one damage on hit and a bunch of details about
        // the defender's maximum defense results into account here with respect to spending
        // tokens and once per round abilities. i.e. in certain situations there's no need to
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

        // Spend "once per round" abilities if present
        // TODO: In certain situations it could be better to use these instead of spending a focus or similar above,
        // but as these are more general modifications we tend to do them afterwards in case there's a second attack.
        if (attack_tokens.amad_any_to_crit)
        {
            attack_tokens.amad_any_to_crit = (attack_dice.change_blank_focus(DieResult.Crit, 1) == 0);
            
            // If this is the final attack, might as well change a hit to a crit also
            if (attack_tokens.amad_any_to_crit && m_attacker_final_attack)
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

    private int amdd_before_reroll(
        ref const(ubyte)[DieResult.Num] attack_results,
        ref TokenState attack_tokens,
        ref DiceState defense_dice,
        ref const(TokenState) defense_tokens) const
    {
        int dice_to_reroll = 0;

        int rerolled_evade_count = defense_dice.remove_dice_for_reroll(DieResult.Evade, m_setup.AMDD.reroll_evade_gain_stress_count(attack_tokens));
        attack_tokens.stress += rerolled_evade_count;
        dice_to_reroll += rerolled_evade_count;

        return dice_to_reroll;
    }

    private void amdd_after_reroll(
        ref const(ubyte)[DieResult.Num] attack_results,
        ref TokenState attack_tokens,
        ref DiceState defense_dice,
        ref const(TokenState) defense_tokens) const
    {
        // Change results
        defense_dice.change_dice(DieResult.Evade, DieResult.Focus, m_setup.AMDD.evade_to_focus_count);
    }

    private int dmdd_before_reroll(
        ref const(ubyte)[DieResult.Num] attack_results,
        ref DiceState defense_dice,
        ref TokenState defense_tokens) const
    {
        // If there aren't actually any hits from the attacker, early out
        if (attack_results[DieResult.Hit] == 0 && attack_results[DieResult.Crit] == 0)
            return 0;

        // Add free results
        defense_dice.results[DieResult.Blank] += m_setup.DMDD.add_blank_count;
        defense_dice.results[DieResult.Focus] += m_setup.DMDD.add_focus_count;
        defense_dice.results[DieResult.Evade] += m_setup.DMDD.add_evade_count;

        // "Useful" focus results are ones we can turn into evades
        int useful_focus_results = m_setup.DMDD.focus_to_evade_count(defense_tokens);
        if (defense_tokens.focus > 0)			// Simplification since this involves spending a token, but good enough
            useful_focus_results = k_all_dice_count;
        int useful_blank_results = m_setup.DMDD.blank_to_evade_count;

        int focus_to_reroll = 0;
        int blank_to_reroll = 0;
        int dice_to_reroll = do_free_rerolls(
            defense_dice, useful_focus_results, useful_blank_results,
            m_setup.DMDD.reroll_blank_count(defense_tokens),
            m_setup.DMDD.reroll_focus_count(defense_tokens),
            m_setup.DMDD.reroll_any_count(defense_tokens),
            focus_to_reroll, blank_to_reroll);

        // NOTE: We currently don't have any way to spend things to reroll defense dice, so we're done after the free rerolls
        return dice_to_reroll;
    }

    private void dmdd_after_reroll(
        ref const(ubyte)[DieResult.Num] attack_results,
        ref TokenState attack_tokens,       // Can take stress from attacker so can't be const()
        ref DiceState defense_dice,
        ref TokenState defense_tokens) const
    {
        // In case we need to undo our mods
        immutable(TokenState) initial_attack_tokens = attack_tokens;
        immutable(DiceState) initial_defense_dice = defense_dice;
        immutable(TokenState) initial_defense_tokens = defense_tokens;

        // Change results
        // NOTE: Order matters here - do the most useful changes first
        defense_dice.change_dice(DieResult.Blank, DieResult.Evade, m_setup.DMDD.blank_to_evade_count);
        defense_dice.change_dice(DieResult.Focus, DieResult.Evade, m_setup.DMDD.focus_to_evade_count(defense_tokens));

        // Figure out if we should spend focus or evade tokens (regular effect)
        int uncanceled_hits = attack_results[DieResult.Hit] + attack_results[DieResult.Crit];
        int mutable_focus_results = defense_dice.count_mutable(DieResult.Focus);        

        // If the attacker has crack shot, we attempt to mitigate it by having an extra evade
        int required_evades = uncanceled_hits - defense_dice.count(DieResult.Evade);
        if (uncanceled_hits > 0 && attack_tokens.crack_shot)
            ++required_evades;

        // FAQ update: can only spend a single focus or evade per attack!
        bool can_spend_focus = (defense_tokens.focus > 0 && mutable_focus_results > 0);
        bool can_spend_evade = (defense_tokens.evade > 0);

        bool spent_focus = false;
        bool spent_evade = false;

        // Spend regular focus or evade tokens?
        if (required_evades > 0 && (can_spend_focus || can_spend_evade))
        {
            // NOTE: Optimal strategy here depends on quite a lot of factors, but this is good enough in most cases
            // - If defender must spend focus (ex. hotshot copilot), prefer to spend focus.
            // - If attacker can modify evades into focus (ex. juke), prefer to spend evade.
            // - Generally prefer to spend focus if none of the above conditions apply                
            bool prefer_spend_focus = (m_setup.AMDD.evade_to_focus_count == 0) || (m_setup.defense_must_spend_focus);

            bool can_cancel_all_with_focus = can_spend_focus && (mutable_focus_results >= required_evades);
            bool can_cancel_all_with_evade = can_spend_evade && (1 >= required_evades);

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

        if (spent_focus)
        {
            required_evades -= mutable_focus_results;
            defense_dice.change_dice(DieResult.Focus, DieResult.Evade);
            --defense_tokens.focus;
        }

        // Evade tokens add defense dice to the pool
        if (spent_evade)
        {
            --required_evades;
            ++defense_dice.results[DieResult.Evade];
            --defense_tokens.evade;
        }
        
        // If we still have required_evades, consider spending other tokens if possible)

        // Spend a focus each to convert a blank into an evade
        if (required_evades > 0 && m_setup.DMDD.spend_focus_one_blank_to_evade > 0)
        {
            int blank_to_evade_count = min(m_setup.DMDD.spend_focus_one_blank_to_evade, defense_tokens.focus);
            int blanks_changed = defense_dice.change_dice(DieResult.Blank, DieResult.Evade, blank_to_evade_count);
            defense_tokens.focus -= blanks_changed;
            required_evades -= blanks_changed;            
        }

        // Spend attacker stress to add an evade?
        // NOTE: There are some edge cases where it's actually better to spend the attacker stress even
        // if we don't need the evade, as it may be enabling passive mods for a future attack.
        // These are pretty esoteric though, so we'll stick to the more intuitive logic for now.
        if (required_evades > 0 && m_setup.DMDD.spend_attacker_stress_add_evade && attack_tokens.stress > 0)
        {
            --attack_tokens.stress;
            ++defense_dice.results[DieResult.Evade];
            --required_evades;
        }        
        
        if (m_setup.attack_one_damage_on_hit)
        {
            // In the presence of "one damage on hit" effects from the attacker, if we can't cancel everything,
            // it's pointless to spend any tokens at all.
            // NOTE: We do *not* consider crack shot for this test as it's still valuable to force the opponent to
            // spend it to push the one damage through.

            int total_hits   = attack_results[DieResult.Hit] + attack_results[DieResult.Crit];
            int total_evades = defense_dice.count(DieResult.Evade);
            if (total_hits > total_evades)
            {
                // Retroactively undo all of our mods and token spending
                // Like accuracy corrector, since no dice have been rolled here it's safe to assume the player
                // can reason that there's no possible way to evade the attack before they spend anything.
                attack_tokens = initial_attack_tokens;
                defense_tokens = initial_defense_tokens;
                defense_dice = initial_defense_dice;
            }
        }
        else
        {
            // Sanity checks
            if (required_evades > 0)
            {
                assert(!can_spend_focus || spent_focus);
                assert(!can_spend_evade || spent_evade);
            }
        }

        // If required and we didn't already spend focus, spend it now
        // NOTE: This must stay after the logic that potentially undoes our token spend for one damage on hit cases, as it still
        // requires us to spend a focus regardless!
        if (m_setup.defense_must_spend_focus && defense_tokens.focus > 0 && defense_tokens.focus == initial_defense_tokens.focus)
        {
            defense_dice.change_dice(DieResult.Focus, DieResult.Evade);
            --defense_tokens.focus;
        }
        
        assert(defense_tokens.evade >= 0);
        assert(defense_tokens.focus >= 0);
    }

    // Returns true if attack hit, false otherwise
    private bool compare_results(
        ref TokenState attack_tokens,                              
        ubyte[DieResult.Num] attack_results,
        ref TokenState defense_tokens,
        ubyte[DieResult.Num] defense_results,
        ref ubyte[DieResult.Num] out_results) const
    {
        // Compare results

        int total_hits   = attack_results[DieResult.Hit] + attack_results[DieResult.Crit];
        int total_evades = defense_results[DieResult.Evade];

        // Attacker can use crack shot to cancel one evade if applicable
        if (attack_tokens.crack_shot && total_evades > 0)
        {
            // Push the extra hit through to trigger one damage on hit
            bool use_crack_shot = false;
            if (m_setup.attack_one_damage_on_hit)
                use_crack_shot = use_crack_shot || (total_hits == total_evades);
            else
                use_crack_shot = use_crack_shot || (total_hits >= total_evades);

            if (use_crack_shot)
            {
                --defense_results[DieResult.Evade];
                attack_tokens.crack_shot = false;
            }
        }

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

        out_results = attack_results;
        return attack_hit;
    }

    private void after_attack(ref TokenState attack_tokens, ref TokenState defense_tokens, bool attack_hit) const
    {
        // Update any abilities that trigger "after attacking" or "after defending"
        if (m_setup.attack_fire_control_system)
        {
            // TODO: Handle multi-target-lock stuff... really only an issue with Redline and so on
            if (attack_tokens.target_lock < 1)
                attack_tokens.target_lock = 1;
        }

        if (attack_hit && m_setup.attack_lose_stress_on_hit)
        {
            if (attack_tokens.stress > 0)
                --attack_tokens.stress;
        }
    }



    private SimulationState attack_dice_before_defender_reroll(SimulationState state) const
    {
        // "After rolling" events

        // Attacker palpatine ordering with respect to above affects is not specified in FAQ,
        // but only really affects some edge cases since the changed die cannot be modified again.
        // FAQ says palpatine still works even if locked by Omega Leader, while Omega Leader shuts
        // off the HLC effect though, so best current determination is that palpatine should happen first.
        if (state.attack_tokens.palpatine && m_setup.attack_dice > 0)
        {
            do_attack_palpatine(state.attack_dice, state.attack_tokens);
            state.attack_tokens.palpatine = false;
        }

        // NOTE: FAQ says sunny triggers before HLC (just because...)
        if (state.attack_tokens.sunny_bounder)
            state.attack_tokens.sunny_bounder = do_sunny_bounder(state.attack_dice);
        if (m_setup.attack_heavy_laser_cannon)
            state.attack_dice.change_dice(DieResult.Crit, DieResult.Hit);

        // Defender rerolls attack dice
        state.dice_to_reroll = cast(ubyte)dmad_before_reroll(state.attack_dice, state.attack_tokens);
        return state;
    }

    private SimulationState attack_dice_before_attacker_reroll(SimulationState state) const
    {
        dmad_after_reroll(state.attack_dice, state.attack_tokens);

        // Attacker rerolls attack dice
        state.dice_to_reroll = cast(ubyte)amad_before_reroll(state.attack_dice, state.attack_tokens);
        return state;
    }

    private SimulationState attack_dice_after_reroll(SimulationState state) const
    {
        // "After rerolling" events for attacker
        // TODO: Wackiness of spending target lock to reroll "0" dice? And sort out what that means for passive mods?
        if (state.dice_to_reroll > 0 && state.attack_tokens.sunny_bounder)
            state.attack_tokens.sunny_bounder = do_sunny_bounder(state.attack_dice);

        amad_after_reroll(state.attack_dice, state.attack_tokens);

        // Done modifying attack dice
        state.attack_dice.finalize();
        state.dice_to_reroll = 0;

        return state;
    }

    private SimulationState defense_dice_before_attacker_reroll(SimulationState state) const
    {
        // NOTE: Again, FAQ doesn't specify the ordering of some of these since they can never occur with current game rules,
        // so we're extrapolating a bit here...

        // Only palp on defense if there are hits to cancel and we're rolling at least one die
        int uncanceled_hits = state.attack_dice.final_results[DieResult.Hit] + state.attack_dice.final_results[DieResult.Crit];
        if (uncanceled_hits > 0 && state.defense_tokens.palpatine && m_setup.defense_dice > 0)
        {
            do_defense_palpatine(state.defense_dice, state.defense_tokens);
            state.defense_tokens.palpatine = false;
        }

        // "After rolling" events
        if (state.defense_tokens.sunny_bounder)
            state.defense_tokens.sunny_bounder = do_sunny_bounder(state.defense_dice);

        // Use our "guess evade results" (C-3P0) if available
        // NOTE: Only works if we are rolling at least one die
        if (state.defense_tokens.defense_guess_evades && m_setup.defense_dice > 0)
        {
            // Try out guess and mark it as used
            if (m_setup.defense_guess_evades == state.defense_dice.count(DieResult.Evade))
                ++state.defense_dice.results[DieResult.Evade];
            state.defense_tokens.defense_guess_evades = false;
        }

        // Attacker reroll defense dice
        state.dice_to_reroll = cast(ubyte)amdd_before_reroll(state.attack_dice.final_results, state.attack_tokens, state.defense_dice, state.defense_tokens);
        return state;
    }

    private SimulationState defense_dice_before_defender_reroll(SimulationState state) const
    {
        amdd_after_reroll(state.attack_dice.final_results, state.attack_tokens, state.defense_dice, state.defense_tokens);

        // Defender reroll defense dice
        state.dice_to_reroll = cast(ubyte)dmdd_before_reroll(state.attack_dice.final_results, state.defense_dice, state.defense_tokens);
        return state;
    }

    private SimulationState defense_dice_after_reroll(SimulationState state) const
    {
        // "After rerolling" events for defender
        if (state.dice_to_reroll > 0 && state.defense_tokens.sunny_bounder)
            state.defense_tokens.sunny_bounder = do_sunny_bounder(state.defense_dice);

        dmdd_after_reroll(state.attack_dice.final_results, state.attack_tokens, state.defense_dice, state.defense_tokens);

        // Done modifying defense dice
        state.defense_dice.finalize();
        state.dice_to_reroll = 0;

        // Compare results
        ubyte[DieResult.Num] attack_results;
        bool attack_hit = compare_results(
            state.attack_tokens, state.attack_dice.final_results, 
            state.defense_tokens, state.defense_dice.final_results,
            attack_results);

        state.final_hits  += attack_results[DieResult.Hit];
        state.final_crits += attack_results[DieResult.Crit];
        state.attack_hit   = state.attack_hit || attack_hit;        // Secondary perform twice attacks hit if *either* sub-attack hits

        // Simplify state in case of further iteration
        // Keep tokens and final results, discard the rest
        state.attack_dice.cancel_all();
        state.defense_dice.cancel_all();

        // TODO: Maybe assert only the relevant states are set on output here

        return state;
    }

    // Returns full set of states after result comparison (results put into state.final_hits, etc)
    // Does NOT trigger after attack events or directly accumulate as this may be part of a multi-attack sequence
    private SimulationStateMap simulate_single_attack(TokenState attack_tokens,
                                                      TokenState defense_tokens) const
    {
        SimulationState initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;

        SimulationStateMap states;
        states[initial_state] = 1.0f;

        // Roll and modify attack dice
        states = roll_attack_dice!(true)(states,  &attack_dice_before_defender_reroll, cast(ubyte)m_setup.attack_dice);
        states = roll_attack_dice!(false)(states, &attack_dice_before_attacker_reroll);
        states = roll_attack_dice!(false)(states, &attack_dice_after_reroll);

        // Roll and modify defense dice, and compare results
        states = roll_defense_dice!(true)(states,  &defense_dice_before_attacker_reroll, cast(ubyte)m_setup.defense_dice);
        states = roll_defense_dice!(false)(states, &defense_dice_before_defender_reroll);
        states = roll_defense_dice!(false)(states, &defense_dice_after_reroll);

        return states;
    }



    public this(TokenState attack_tokens, TokenState defense_tokens)
    {
        m_total_hits_pdf = new SimulationResult[1];
        foreach (ref i; m_total_hits_pdf)
            i = SimulationResult.init;

        m_initial_attack_tokens  = attack_tokens;
        m_initial_defense_tokens = defense_tokens;

        // Set up the initial state
        SimulationState initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;
        m_states[initial_state] = 1.0f;
    }


    // Main entry point for simulating a new attack following any previously simulated results
    //
    // If "final attack" is set for either attacker or defender, it may use tokens or abilities that it
    // would otherwise save. Usually this is only for minor things like changing hits to crits or similar since
    // the attacker will always try and get as many hits as possible and so on.
    //
    // If "trigger_after_attack" is true, this attack will considered to have hit if any attack since the
    // last "after attack" trigger hit. Example: secondary perform twice causes "after attack that hits" triggers
    // if *any* of the attacks hit. The attack hit flag is cleared after this attack completes if requested.
    //
    public void simulate_attack(
        ref const(SimulationSetup) setup,
        bool attacker_final_attack = false,
        bool defender_final_attack = false,
        bool trigger_after_attack = true,
        bool clear_attack_hit = true)
    {
        // Update internal state (just more convenient than passing it around every time)
        m_setup = setup;
        m_attacker_final_attack = attacker_final_attack;
        m_defender_final_attack = defender_final_attack;

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
        SimulationState[] initial_states_list = m_states.keys.dup;
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
                second_attack_states = simulate_single_attack(last_attack_tokens, last_defense_tokens);
                ++second_attack_evaluations;

                //writefln("Second attack in %s msec", sw.peek().msecs());
            }

            // Compose all of the results from the second attack set with this one
            auto initial_probability = m_states[initial_state];
            foreach (ref second_attack_state, second_probability; second_attack_states)
            {
                // NOTE: Important to keep the token state and such from after the second attack, not initial one
                // We basically just want to add each of the combinations of "final hits/crits" together for the
                // combined attack and potentially trigger "after attack" logic.
                SimulationState new_state = second_attack_state;
                new_state.final_hits  += initial_state.final_hits;
                new_state.final_crits += initial_state.final_crits;
                new_state.attack_hit   = new_state.attack_hit || initial_state.attack_hit;

                if (trigger_after_attack)
                {
                    after_attack(new_state.attack_tokens, new_state.defense_tokens, new_state.attack_hit);
                }

                if (clear_attack_hit)
                {
                    new_state.attack_hit = false;
                }

                append_state(new_states, new_state, initial_probability * second_probability);
            }
        }

        // Update our simulation with the new results
        m_states = new_states;
    }

    public void simulate_multi_attack(
        ref const(SimulationSetup) setup,
        MultiAttackType type)
    {
        if (type == MultiAttackType.Single)
        {
            simulate_attack(setup, true, true, true, true);
        }
        else if (type == MultiAttackType.SecondaryPerformTwice)
        {
            // NOTE: After attack triggers do not happen on the first of two "secondary perform twice" attacks
            // Secondary perform twice attacks are considered to have hit if either sub-attack hits.
            simulate_attack(setup, false, false, false, false);
            simulate_attack(setup, true, true, true, true);
        }
        else if (type == MultiAttackType.AfterAttack)
        {
            simulate_attack(setup, false, false, true, true);
            simulate_attack(setup, true, true, true, true);
        }
        else if (type == MultiAttackType.AfterAttackDoesNotHit)
        {
            // NOTE: Maintain the attack_hit flag so we can separate out the states
            simulate_attack(setup, false, false, true, false);

            // Only attack again for the states that didn't hit anything
            SimulationStateMap second_attack_states;
            SimulationStateMap no_second_attack_states;
            foreach (ref state, state_probability; m_states)
            {
                if (state.attack_hit)
                {
                    no_second_attack_states[state] = state_probability;
                }
                else
                {
                    second_attack_states[state] = state_probability;
                }
            }

            //writefln("Second attack for %s states.", second_attack_states.length);

            // Do the next attack for those states, then merge them into the other list
            if (second_attack_states.length > 0)
            {
                // This time clear the attack_hit flag as we no longer need it
                m_states = second_attack_states;
                simulate_attack(setup, true, true, true, true);

                // Now merge the ones that hit on the first attack back in
                foreach (ref state, state_probability; no_second_attack_states)
                {
                    append_state(m_states, state, state_probability);
                }
            }
            else
            {
                m_states = no_second_attack_states;
            }
        }
        else
        {
            // Unknown multi attack type!
            debug 
            {
                assert(false);
            }
        }

        // Record final results
        foreach (ref state, state_probability; m_states)
        {
            accumulate(state_probability, state.final_hits, state.final_crits, state.attack_tokens, state.defense_tokens);
        }
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
        SimulationResult result;
        result.probability = probability;

        result.hits  = probability * cast(double)hits;
        result.crits = probability * cast(double)crits;

        result.attack_delta_focus_tokens  = probability * cast(double)(attack_tokens.focus        - m_initial_attack_tokens.focus      );
        result.attack_delta_target_locks  = probability * cast(double)(attack_tokens.target_lock  - m_initial_attack_tokens.target_lock);
        result.attack_delta_stress        = probability * cast(double)(attack_tokens.stress       - m_initial_attack_tokens.stress     );
        result.attack_delta_crack_shot    = probability * cast(double)(attack_tokens.crack_shot  != m_initial_attack_tokens.crack_shot ? -1.0 : 0.0);

        result.defense_delta_focus_tokens = probability * cast(double)(defense_tokens.focus       - m_initial_defense_tokens.focus     );
        result.defense_delta_evade_tokens = probability * cast(double)(defense_tokens.evade       - m_initial_defense_tokens.evade     );
        result.defense_delta_stress       = probability * cast(double)(defense_tokens.stress      - m_initial_defense_tokens.stress    );
        
        m_total_sum = accumulate_result(m_total_sum, result);

        // Accumulate into the right bin of the total hits PDF
        int total_hits = hits + crits;
        if (total_hits >= m_total_hits_pdf.length)
            m_total_hits_pdf.length = total_hits + 1;
        m_total_hits_pdf[total_hits] = accumulate_result(m_total_hits_pdf[total_hits], result);

        // If there was at least one uncanceled crit, accumulate probability
        if (crits > 0)
            m_at_least_one_crit_probability += probability;
    }

    public SimulationResult[] total_hits_pdf() const
    {
        return m_total_hits_pdf.dup;
    }

    public SimulationResult total_sum() const
    {
        return m_total_sum;
    }

    public double at_least_one_crit_probability() const
    {
        return m_at_least_one_crit_probability;
    }


    // These are the core states that are updated as attacks chain
    private SimulationStateMap m_states;

    // Copies of the initial tokens; note: these are only particularly useful if they aren't replaced during an attack sequence
    private TokenState m_initial_attack_tokens;
    private TokenState m_initial_defense_tokens;

    // Store copies of the constant state for the current attack
    private SimulationSetup m_setup;
    private bool m_attacker_final_attack = true;
    private bool m_defender_final_attack = true;

    // Accumulated results
    private SimulationResult[] m_total_hits_pdf;
    private SimulationResult m_total_sum;
    private double m_at_least_one_crit_probability = 0.0;

    
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

    static void assert_hits_pdf(string name, ref const(SimulationSetup) setup, const(double)[] expected_p)
    {
        writefln("RUNNING TEST %s...", name);

        auto simulation = new Simulation(setup);
        simulation.simulate_attack();
        auto total_hits_pdf = simulation.total_hits_pdf();
        auto total_sum = simulation.total_sum();

        assert(total_hits_pdf.length >= expected_p.length);

        foreach (i; 0 .. expected_p.length)
        {
            bool matches = nearly_equal_p(total_hits_pdf[i].probability, expected_p[i]);
            if (!matches)
            {
                writefln("hits[%s]: %.15f %s %.15f", i, total_hits_pdf[i].probability, matches ? "==" : "!=", expected_p[i]);
                assert(false);
            }
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
        assert_hits_pdf("basic_3_3", setup, [0.53369140625, 0.289306640625, 0.146484375, 0.030517578125]);

        setup.attack_tokens.focus = 1;
        setup.attack_tokens.target_lock = 1;
        setup.defense_tokens.focus = 1;
        setup.defense_tokens.evade = 1;
        assert_hits_pdf("basic_3_3_tokens", setup, [0.730598926544189, 0.225949287414551, 0.043451786041259]);

        setup.type = MultiAttackType.SecondaryPerformTwice;
        assert_hits_pdf("basic_secondary_perform_twice",setup, [0.419614922167966, 0.295413697109325, 0.191800311527913, 0.076275200204690, 0.016023014264646, 0.000872854725457]);
        // Same as above as no "after attack" triggers are present
        setup.type = MultiAttackType.AfterAttack;
        assert_hits_pdf("basic_after_attack", setup, [0.419614922167966, 0.295413697109325, 0.191800311527913, 0.076275200204690, 0.016023014264646, 0.000872854725457]);
    }

    // Maul rerolling any = target lock
    {
        SimulationSetup setup;
        setup.attack_dice = 3;
        setup.defense_dice = 0;

        setup.attack_tokens.focus = 1;
        setup.attack_tokens.target_lock = 1;
        assert_hits_pdf("target_lock_reroll", setup, [0.000244140625000, 0.010986328125000, 0.164794921875000, 0.823974609375000]);

        setup.attack_tokens.focus = 1;
        setup.attack_tokens.target_lock = 0;
        setup.AMAD.reroll_any_gain_stress_count.unstressed = setup.attack_dice;
        assert_hits_pdf("maul_reroll", setup, [0.000244140625000, 0.010986328125000, 0.164794921875000, 0.823974609375000]);
    }
}
