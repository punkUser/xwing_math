import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;

private int dmad(const(SimulationSetup2) setup, ref SimulationState2 state)
{
    // Base case
    if (state.attack_temp.finished_dmad)
        return 0;

    SearchDelegate[2] search_options;
    size_t search_options_count = 0;
    search_options[search_options_count++] = do_defense_finish_dmad();

    // Decide whether to use l337 or not via search
    // NOTE: This may be better than what a human can do by a decent margin, but go with it...
    if (state.defense_tokens.l337)
        search_options[search_options_count++] = do_defense_l337();

    // NOTE: We want to *minimize* the attack hits since we're the defender :)
    int dice_to_reroll = search_attack(setup, state, search_options[0..search_options_count], true);
    if (dice_to_reroll > 0)
        return dice_to_reroll;
    else
        return dmad(setup, state);      // Continue defender modifying
}


// Returns number of dice to reroll, or 0 when done modding
// Modifies state in place
public int modify_attack_dice(const(SimulationSetup2) setup, ref SimulationState2 state)
{
    /* Currently unused
    // First have to do any "after rolling" abilities
    if (!state.attack_temp.finished_after_rolling)
    {
        // Placeholder for any after rolling stuff
        state.attack_temp.finished_after_rolling = true;
    }
    */

    // Next the defender modifies the dice
    if (!state.attack_temp.finished_dmad)
    {
        int reroll_count = dmad(setup, state);
        if (reroll_count > 0)
            return reroll_count;
        assert(state.attack_temp.finished_dmad);
    }

    // Before we might spend tokens, see if we can do any of our passive effects
    // NOTE: These could be tied to the forward search options themselves, but in many cases it's harmless to
    // attempt to apply them eagerly.

    // Advanced Targeting Computer
    if (state.attack_tokens.lock > 0 && setup.attack.advanced_targeting_computer && !state.attack_temp.used_advanced_targeting_computer)
        state.attack_temp.used_advanced_targeting_computer = (state.attack_dice.change_dice(DieResult.Hit, DieResult.Crit, 1) > 0);

    // Base case
    if (state.attack_temp.finished_amad)
        return 0;

    // Search from all our potential token spending and rerolling options to find the optimal one
    SearchDelegate[32] search_options;
    size_t search_options_count = 0;

    // First option to try is just finishing up our attack mods (spending focus and things like that) and terminating
    search_options[search_options_count++] = do_attack_finish_amad();

    // Any token spending options we might want to do before reroll, such as those that add results
    if (setup.attack.shara_bey_pilot && state.attack_tokens.lock > 0 && !state.attack_temp.cannot_spend_lock && !state.attack_temp.used_shara_bey_pilot)
        search_options[search_options_count++] = do_attack_shara_bey();

    // The top level decision here is which dice to reroll. As noted above, it's always desirable to reroll blanks first and thus
    // the decision is effectively just how many dice to reroll from 1..(all rerollable blanks + all rerollable focus).
    // We'll put rerolling *more* dice earlier in the list of search results so that we favor stuff like spending a lock to
    // reroll all dice at once vs. using a sequence of single die rerolls, *unless* the latter produces a better expected damage.
    // Since each of these reroll loops generally consumes a single token this has the effect of roughly trying to minimize token
    // use for the same result, although keep in mind that if doing rerolls one by one improves the expected damage, we do actually
    // want to do that (and the forward search will figure that out for us).

    // This code could be restructured a bit for performance, but given relatively small dice counts and subtlety of this logic,
    // its desirable to keep it more easily readable/editable for now.

    int rerollable_focus_results = state.attack_dice.results[DieResult.Focus];
    int rerollable_blank_results = state.attack_dice.results[DieResult.Blank];

    const int max_dice_to_reroll = rerollable_blank_results + rerollable_focus_results;
    foreach_reverse (const dice_to_reroll; 1 .. (max_dice_to_reroll+1))
    {
        const int blanks_to_reroll = min(rerollable_blank_results, dice_to_reroll);
        const int focus_to_reroll = dice_to_reroll - blanks_to_reroll;
        
        // Now append to the search any effects that can reroll this set of dice
        // Again note that *for this set of dice to reroll*, put the more desirable (less general) tokens/effects to use first

        // Always prefer free rerolls - don't even add paid ones if free ones are available
        // NOTE: Can use "reroll up to 2/3" abilities to reroll just one if needed as well, but less desirable

        // TODO: Various ways to clean up this logic but this keeps it logically clear at least
        if (dice_to_reroll == 3)
        {
            if (setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count)
                search_options[search_options_count++] = do_attack_reroll_3(dice_to_reroll);
        }
        else if (dice_to_reroll == 2)
        {
            if (setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count)
                search_options[search_options_count++] = do_attack_reroll_2(dice_to_reroll);
            else if (setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count)
                search_options[search_options_count++] = do_attack_reroll_3(dice_to_reroll);
        }
        else if (dice_to_reroll == 1)
        {
            
            if (setup.attack.reroll_1_count > state.attack_temp.used_reroll_1_count)
                search_options[search_options_count++] = do_attack_reroll_1();
            else if (setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count)
                search_options[search_options_count++] = do_attack_reroll_2(dice_to_reroll);
            else if (setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count)
                search_options[search_options_count++] = do_attack_reroll_3(dice_to_reroll);
            else 
            {
                if (state.attack_tokens.lone_wolf)
                    search_options[search_options_count++] = do_attack_lone_wolf();
            }
        }
        
        // Lock can always reroll arbitrary sets of dice
        if (state.attack_tokens.lock > 0 && !state.attack_temp.cannot_spend_lock)
            search_options[search_options_count++] = do_attack_lock(blanks_to_reroll, focus_to_reroll);
    }

    // Search modifies the state to execute the best of the provided options
    int dice_to_reroll = search_attack(setup, state, search_options[0..search_options_count]);
    if (dice_to_reroll > 0)
        return dice_to_reroll;
    else
    {
        // Continue modifying
        // TODO: Could easily do this with a loop rather than tail recursion, just will cover a good
        // chunk of this function so experiment with which is cleaner.
        return modify_attack_dice(setup, state);
    }
}

// Logic is:
// - If there's >1 focus results, spend focus if able
// - Otherwise spend calculate, then force (by default, see parameter to swap)
private SimulationState2 spend_focus_calculate_force(
    ref SimulationState2 state, bool prefer_spend_calculate = true)
{
    int initial_calculate_tokens = state.attack_tokens.calculate;

    int focus_results_to_change = state.attack_dice.count_mutable(DieResult.Focus);
    if (focus_results_to_change > 0)
    {
        int single_focus_token_mods = state.attack_tokens.calculate + state.attack_tokens.force;
        if (state.attack_tokens.focus > 0 && (focus_results_to_change > 1 || single_focus_token_mods == 0))
        {
            int changed = state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit);
            assert(changed > 0);
            state.attack_tokens.focus = state.attack_tokens.focus - 1;
        }
        else
        {
            int change_with_calculate = state.attack_tokens.calculate;
            int change_with_force     = state.attack_tokens.force;
            if (prefer_spend_calculate)
            {
                change_with_calculate  = min(change_with_calculate, focus_results_to_change);
                change_with_force      = min(change_with_force,     focus_results_to_change - change_with_calculate);
            }
            else
            {
                change_with_force      = min(change_with_force,     focus_results_to_change);
                change_with_calculate  = min(change_with_calculate, focus_results_to_change - change_with_force);
            }
            state.attack_tokens.calculate = state.attack_tokens.calculate - state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, change_with_calculate);
            state.attack_tokens.force     = state.attack_tokens.force     - state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, change_with_force);
        }
    }

    // Flag if calculate was spent here (for leebo, etc)
    if (state.attack_tokens.calculate != initial_calculate_tokens)
        state.attack_tokens.spent_calculate = true;

    return state;
}





alias int delegate(const(SimulationSetup2) setup, ref SimulationState2) SearchDelegate;

private SearchDelegate do_attack_finish_amad()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(!state.attack_temp.finished_amad);

        if (setup.attack.any_to_hit_count > state.attack_temp.used_any_to_hit_count)
        {
            int count = setup.attack.any_to_hit_count - state.attack_temp.used_any_to_hit_count;
            state.attack_temp.used_any_to_hit_count = state.attack_temp.used_any_to_hit_count +
                state.attack_dice.change_blank_focus(DieResult.Hit, count);
        }

        state = spend_focus_calculate_force(state);

        if (setup.attack.hit_to_crit_count > state.attack_temp.used_hit_to_crit_count)
        {
            int count = setup.attack.hit_to_crit_count - state.attack_temp.used_hit_to_crit_count;
            state.attack_temp.used_hit_to_crit_count = state.attack_temp.used_hit_to_crit_count + 
                state.attack_dice.change_dice(DieResult.Hit, DieResult.Crit, count);
        }

        state.attack_temp.finished_amad = true;
        return 0;
    };
}

private SearchDelegate do_attack_lock(int blank_rerolls, int focus_rerolls)
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(state.attack_tokens.lock > 0);
        assert(!state.attack_temp.cannot_spend_lock);

        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll(DieResult.Blank, blank_rerolls);
        dice_to_reroll    += state.attack_dice.remove_dice_for_reroll(DieResult.Focus, focus_rerolls);

        assert(dice_to_reroll > 0);

        // If we have fire control system and are only rerolling one die we don't need to spend the lock,
        // but then we are not allowed to spend it during this attack.
        // TODO: Not sure how this is supposed to work for multiple locks; for now it will lock out all
        // lock usage which could be suboptimal if new effects are added later that spend locks.
        if (setup.attack.fire_control_system && dice_to_reroll == 1)
            state.attack_temp.cannot_spend_lock = true;
        else
            state.attack_tokens.lock = state.attack_tokens.lock - 1;

        return dice_to_reroll;
    };
}

// Rerolls a blank if present, otherwise focus
private SearchDelegate do_attack_reroll_1()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(setup.attack.reroll_1_count > state.attack_temp.used_reroll_1_count);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(1);
        state.attack_temp.used_reroll_1_count = state.attack_temp.used_reroll_1_count + 1;
        assert(dice_to_reroll == 1);
        return dice_to_reroll;
    };
}
private SearchDelegate do_attack_reroll_2(int count = 2)
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(count > 0 && count <= 2);
        assert(setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(count);
        state.attack_temp.used_reroll_2_count = state.attack_temp.used_reroll_2_count + 1;
        assert(dice_to_reroll == count);
        return dice_to_reroll;
    };
}
private SearchDelegate do_attack_reroll_3(int count = 3)
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(count > 0 && count <= 3);
        assert(setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(count);
        state.attack_temp.used_reroll_3_count = state.attack_temp.used_reroll_3_count + 1;
        assert(dice_to_reroll == count);
        return dice_to_reroll;
    };
}

// Rerolls a blank if present or a focus otherwise
private SearchDelegate do_attack_lone_wolf()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(state.attack_tokens.lone_wolf);

        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll(DieResult.Blank, 1);
        if (dice_to_reroll == 0)
            dice_to_reroll = state.attack_dice.remove_dice_for_reroll(DieResult.Focus, 1);
        assert(dice_to_reroll == 1);

        state.attack_tokens.lone_wolf = false;
        return dice_to_reroll;
    };
}

// Spend lock to add a focus result
private SearchDelegate do_attack_shara_bey()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(setup.attack.shara_bey_pilot);
        assert(!state.attack_temp.used_shara_bey_pilot);
        assert(state.attack_tokens.lock > 0);
        assert(!state.attack_temp.cannot_spend_lock);

        ++state.attack_dice.results[DieResult.Focus];

        state.attack_temp.used_shara_bey_pilot = true;
        state.attack_tokens.lock = state.attack_tokens.lock - 1;
        return 0;
    };
}


// Defender modifies attack dice (DMAD)
private SearchDelegate do_defense_finish_dmad()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(!state.attack_temp.finished_dmad);
        // Nothing to do here currently...
        state.attack_temp.finished_dmad = true;
        return 0;
    };
}

private SearchDelegate do_defense_l337()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(!state.attack_temp.finished_dmad);
        assert(state.defense_tokens.l337);
        
        // Must reroll all dice that we can (i.e. all that haven't yet been rerolled)
        int reroll_count = 
            state.attack_dice.remove_dice_for_reroll(DieResult.Crit) +
            state.attack_dice.remove_dice_for_reroll(DieResult.Hit) +
            state.attack_dice.remove_dice_for_reroll(DieResult.Focus) +
            state.attack_dice.remove_dice_for_reroll(DieResult.Blank);

        state.defense_tokens.l337 = false;
        return reroll_count;
    };
}




private double search_expected_damage(const(SimulationSetup2) setup, SimulationState2 state, int reroll_count)
{
    if (reroll_count == 0)
    {
        reroll_count = modify_attack_dice(setup, state);
        if (reroll_count == 0)
        {
            // Base case; done modifying dice
            return state.attack_dice.count(DieResult.Hit) + state.attack_dice.count(DieResult.Crit);
        }
    }

    // Reroll and recurse
    double expected_damage = 0.0f;
    assert(reroll_count > 0);
    roll_attack_dice(reroll_count, (int blank, int focus, int hit, int crit, double probability) {
        auto new_state = state;
        new_state.attack_dice.rerolled_results[DieResult.Crit]  += crit;
        new_state.attack_dice.rerolled_results[DieResult.Hit]   += hit;
        new_state.attack_dice.rerolled_results[DieResult.Focus] += focus;
        new_state.attack_dice.rerolled_results[DieResult.Blank] += blank;
        new_state.probability *= probability;
        // NOTE: Rather than have the leaf nodes weight by their state probability, we just accumulate it
        // as we fork here instead. This is just to normalize the expected damage with respect to the state
        // that we started the search from rather than the global state space.
        expected_damage += probability * search_expected_damage(setup, new_state, 0);
    });

    return expected_damage;
}

// NOTE: Will prefer options earlier in the list if equivalent, so put stuff that spends more
// or more valuable tokens later in the options list.
// NOTE: Search delegates *must* evolve the state in a way that will eventually terminate,
// i.e. spending a finite token, rerolling dice and so on.
// NOTE: If minimize_damage is set to true, will instead search for the minimal damage option
// This is useful for opoonent searches (i.e. DMAD).
private int search_attack(
    const(SimulationSetup2) setup,
    ref SimulationState2 output_state,
    SearchDelegate[] options,
    bool minimize_damage = false)
{
    assert(options.length > 0);

    // Early out if there's only one option; no need for search
    if (options.length == 1)
        return options[0](setup, output_state);

    // Try each option and track which ends up with the best expected damage
    const(SimulationState2) initial_state = output_state;
    SimulationState2 best_state = initial_state;
    double best_expected_damage = minimize_damage ? 100000.0f : -1.0f;
    int best_state_rerolls = 0;

    //debug log_message("Forward search on %s (%s options):",
    //                  output_state.attack_dice, options.length, max_state_rerolls);

    foreach (option; options)
    {
        // Do any requested rerolls; note that instead of appending states we simple do a depth
        // first search of each result one by one. This keeps forward searches somewhat more efficient
        SimulationState2 state = initial_state;
        int reroll_count = option(setup, state);

        // Assert that delegate actually changed the state in some way; otherwise potential infinite loop!
        assert(reroll_count > 0 || state != initial_state);

        // TODO: Experiment with epsilon; this is to prefer earlier options when equivalent
        immutable double epsilon = 1e-9;

        bool new_best = false;
        double expected_damage = search_expected_damage(setup, state, reroll_count);
        if ((!minimize_damage && expected_damage > (best_expected_damage + epsilon)) ||
            ( minimize_damage && expected_damage < (best_expected_damage - epsilon)))
        {
            new_best = true;
            best_expected_damage = expected_damage;
            best_state = state;
            best_state_rerolls = reroll_count;
        }

        //debug log_message("Option %s (reroll %s) expected damage: %s %s",
        //                  i, reroll_count, expected_damage, new_best ? "(new best)" : "");
    }

    output_state = best_state;
    return best_state_rerolls;
}



