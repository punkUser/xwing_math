import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;


private StateFork after_rolling(const(SimulationSetup) setup, ref SimulationState state)
{
    // Base case
    if (state.attack_temp.finished_after_rolling)
        return StateForkNone();

    SearchDelegate[16] search_options;
    size_t search_options_count = 0;
    
    search_options[search_options_count++] = do_attack_finish_after_rolling();

    if (setup.attack.rebel_han_pilot && !state.attack_temp.used_rebel_han_pilot)
    {
        // Only consider if we have blanks or focus to reroll
        if ((state.attack_dice.count_mutable(DieResult.Blank) + state.attack_dice.count_mutable(DieResult.Focus)) > 0)
            search_options[search_options_count++] = do_attack_rebel_han_pilot();
    }

    int rerollable_results = state.attack_dice.results[DieResult.Blank] + state.attack_dice.results[DieResult.Focus];
    if (rerollable_results > 0)
    {
        // Lando pilot rerolls (all blanks)
        if (setup.attack.scum_lando_pilot && !state.attack_temp.used_scum_lando_pilot &&
            state.attack_tokens.stress == 0 && state.attack_dice.results[DieResult.Blank] > 0) {
            search_options[search_options_count++] = do_attack_scum_lando_pilot();
        }

        // Lando crew rerolls
        if (setup.attack.scum_lando_crew && !state.attack_temp.used_scum_lando_crew) {
            // Try rerolling 1 or 2 results with each green token we have (in order of general preference)
            // NOTE: Always reroll blanks, so only try 1 if it's a focus
            bool at_least_two_blanks = state.attack_dice.results[DieResult.Blank] > 1;
            foreach (immutable token; [GreenToken.Reinforce, GreenToken.Evade, GreenToken.Calculate, GreenToken.Focus]) {
                if (state.attack_tokens.count(token) == 0) continue;
                if (rerollable_results > 1)
                    search_options[search_options_count++] = do_attack_scum_lando_crew(2, token);
                if (!at_least_two_blanks)
                    search_options[search_options_count++] = do_attack_scum_lando_crew(1, token);
            }
        }
    }

    StateFork fork = search_attack(setup, state, search_options[0..search_options_count]);
    if (fork.required())
        return fork;
    else
        return after_rolling(setup, state);      // Continue after rolling
}


private StateFork dmad(const(SimulationSetup) setup, ref SimulationState state)
{
    // Base case
    if (state.attack_temp.finished_dmad)
        return StateForkNone();

    SearchDelegate[2] search_options;
    size_t search_options_count = 0;
    search_options[search_options_count++] = do_defense_finish_dmad();

    // Decide whether to use l337 or not via search
    // NOTE: This may be better than what a human can do by a decent margin, but go with it...
    if (state.defense_tokens.l337)
        search_options[search_options_count++] = do_defense_l337();

    // NOTE: We want to *minimize* the attack hits since we're the defender :)
    StateFork fork = search_attack(setup, state, search_options[0..search_options_count], true);
    if (fork.required())
        return fork;
    else
        return dmad(setup, state);      // Continue defender modifying
}


// Returns number of dice to reroll, or 0 when done modding
// Modifies state in place
public StateFork modify_attack_dice(const(SimulationSetup) setup, ref SimulationState state)
{
    // First have to do any "after rolling" abilities
    if (!state.attack_temp.finished_after_rolling)
    {
        StateFork fork = after_rolling(setup, state);
        if (fork.required())
            return fork;
        assert(state.attack_temp.finished_after_rolling);
    }

    // Next the defender modifies the dice
    if (!state.attack_temp.finished_dmad)
    {
        StateFork fork = dmad(setup, state);
        if (fork.required())
            return fork;
        assert(state.attack_temp.finished_dmad);
    }

    // Attacker modifies

    // Add results
    if (!state.attack_temp.used_add_results)
    {
        state.attack_dice.results[DieResult.Blank] += setup.attack.add_blank_count;
        state.attack_dice.results[DieResult.Focus] += setup.attack.add_focus_count;
        state.attack_temp.used_add_results = true;
    }

    // Before we might spend tokens, see if we can do any of our passive effects
    // NOTE: These could be tied to the forward search options themselves, but in many cases it's harmless to
    // attempt to apply them eagerly. We put this before the "base case" return so that we don't have to duplicate them in two
    // places (i.e. here and inside the finish_amad delegate).

    // Advanced Targeting Computer
    if (state.attack_tokens.lock > 0 && setup.attack.advanced_targeting_computer && !state.attack_temp.used_advanced_targeting_computer)
        state.attack_temp.used_advanced_targeting_computer = (state.attack_dice.change_dice(DieResult.Hit, DieResult.Crit, 1) > 0);

    // Base case
    if (state.attack_temp.finished_amad)
        return StateForkNone();

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

    // If we can use heroic that's the only option we need for rerolls; optimal effect to reroll all dice if all are blank
    if (setup.attack.heroic && state.attack_dice.are_all_blank() &&
        state.attack_dice.count(DieResult.Blank) > 1 && rerollable_blank_results > 0)
    {
        search_options[search_options_count++] = do_attack_heroic();
    }
    else
    {
        const int max_dice_to_reroll = rerollable_blank_results + rerollable_focus_results;
        foreach_reverse (const dice_to_reroll; 1 .. (max_dice_to_reroll+1))
        {
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
                search_options[search_options_count++] = do_attack_lock(dice_to_reroll);
        }
    }

    // Search modifies the state to execute the best of the provided options
    StateFork fork = search_attack(setup, state, search_options[0..search_options_count]);
    if (fork.required())
        return fork;
    else
    {
        // Continue modifying
        // TODO: Could easily do this with a loop rather than tail recursion, just will cover a good
        // chunk of this function so experiment with which is cleaner.
        return modify_attack_dice(setup, state);
    }
}

// Logic is:
// - If there's >1 focus results, spend focus if able (outside of special cases like Ezra pilot)
// - Otherwise spend calculate, then force (by default, see parameter to swap)
private SimulationState spend_focus_calculate_force(
    const(SimulationSetup) setup, SimulationState state, bool prefer_spend_calculate = true)
{
    int initial_calculate_tokens = state.attack_tokens.calculate;

    int focus_results_to_change = state.attack_dice.count_mutable(DieResult.Focus);
    if (focus_results_to_change > 0)
    {
        bool ezra_available = setup.attack.ezra_pilot && state.attack_tokens.stress > 0 && state.attack_tokens.force > 0;
        bool force_calculate_available = (state.attack_tokens.calculate + state.attack_tokens.force) > 0;
        int change_with_one_token_count = ezra_available ? 2 : (force_calculate_available > 0 ? 1 : 0);
        
        if (state.attack_tokens.focus > 0 && (focus_results_to_change > change_with_one_token_count))
        {
            int changed = state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit);
            assert(changed > 0);
            state.attack_tokens.focus = state.attack_tokens.focus - 1;
        }
        else
        {
            // Ezra is more efficient at changing results, so use him if available regardless of preference
            if (ezra_available && focus_results_to_change > 1)
            {
                state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, 2);
                state.attack_tokens.force = state.attack_tokens.force - 1;
                focus_results_to_change -= 2;
            }

            // Regular single focus token mod spending for usual effect
            if (prefer_spend_calculate)
            {
                state.attack_tokens.calculate = state.attack_tokens.calculate - state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, state.attack_tokens.calculate);
                state.attack_tokens.force     = state.attack_tokens.force     - state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, state.attack_tokens.force);
            }
            else
            {
                state.attack_tokens.force     = state.attack_tokens.force     - state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, state.attack_tokens.force);
                state.attack_tokens.calculate = state.attack_tokens.calculate - state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, state.attack_tokens.calculate);
            }
        }
    }

    // Flag if calculate was spent here (for leebo, etc)
    if (state.attack_tokens.calculate != initial_calculate_tokens)
        state.attack_tokens.spent_calculate = true;

    return state;
}





alias StateFork delegate(const(SimulationSetup) setup, ref SimulationState) SearchDelegate;

// After rolling (before defender modifies)
private SearchDelegate do_attack_finish_after_rolling()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.attack_temp.finished_after_rolling);
        // Nothing to do here currently...
        state.attack_temp.finished_after_rolling = true;
        return StateForkNone();
    };
}

// Spend green token to reroll up to 2 results.
private SearchDelegate do_attack_scum_lando_crew(int count, GreenToken token)
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.attack_temp.used_scum_lando_crew);
        assert(count > 0 && count <= 2);        
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(count);
        assert(dice_to_reroll > 0);

        switch (token) {
            case GreenToken.Focus:      state.attack_tokens.focus       = state.attack_tokens.focus - 1;      break;            
            case GreenToken.Evade:      state.attack_tokens.evade       = state.attack_tokens.evade - 1;      break;
            case GreenToken.Reinforce:  state.attack_tokens.reinforce   = state.attack_tokens.reinforce - 1;  break;
            case GreenToken.Calculate:
                state.attack_tokens.calculate = state.attack_tokens.calculate - 1;
                state.attack_tokens.spent_calculate = true;
                break;
            default: assert(false);
        }

        state.attack_temp.used_scum_lando_crew = true;
        return StateForkReroll(dice_to_reroll);
    };
}

// Reroll all blanks, gain stress
private SearchDelegate do_attack_scum_lando_pilot()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.attack_temp.used_scum_lando_pilot);
        assert(state.attack_tokens.stress == 0);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll(DieResult.Blank);
        assert(dice_to_reroll > 0);
        state.attack_tokens.stress = state.attack_tokens.stress + 1;
        state.attack_temp.used_scum_lando_pilot = true;
        return StateForkReroll(dice_to_reroll);
    };
}

// Reroll all dice; doesn't count as reroll!
private SearchDelegate do_attack_rebel_han_pilot()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.attack_temp.used_rebel_han_pilot);

        // Roll all mutable dice again
        // NOTE: We don't have clarification on whether or not any potentially "unmodifyable"/final dice would be affected
        // We also don't know if we should be trying to track which dice have already been rerolled "through" this reroll
        // Thus we'll do the simplest thing for now since these interactions are not currently possible yet anyways.
        int dice_to_roll =
            state.attack_dice.count_mutable(DieResult.Blank) + 
            state.attack_dice.count_mutable(DieResult.Focus) +
            state.attack_dice.count_mutable(DieResult.Hit) +
            state.attack_dice.count_mutable(DieResult.Crit);
        assert(dice_to_roll > 0);

        state.attack_dice.cancel_mutable();        
        state.attack_temp.used_rebel_han_pilot = true;

        // NOTE: "Roll" not "Reroll" here as it doesn't count as rerolling
        return StateForkRoll(dice_to_roll);
    };
}



private SearchDelegate do_attack_finish_amad()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.attack_temp.finished_amad);

        // Free changes
        state.attack_dice.change_dice(DieResult.Focus, DieResult.Crit, setup.attack.focus_to_crit_count);
        state.attack_dice.change_dice(DieResult.Focus, DieResult.Hit, setup.attack.focus_to_hit_count);

        if (setup.attack.major_vermeil_pilot && state.defense_tokens.green_token_count() == 0)
            state.attack_dice.change_blank_focus(DieResult.Hit, 1);

        state.attack_dice.change_blank_focus(DieResult.Hit, setup.attack.any_to_hit_count);

        // If we have other uses for a given token, it's sometimes better to prefer to spend the other here
        bool prefer_spend_calculate = true;
        state = spend_focus_calculate_force(setup, state, prefer_spend_calculate);

        if (setup.attack.rey_pilot && state.attack_tokens.force > 0)
        {
            if (state.attack_dice.change_dice(DieResult.Blank, DieResult.Hit, 1) > 0)
                state.attack_tokens.force = state.attack_tokens.force - 1;
        }

        if (setup.attack.advanced_optics && state.attack_tokens.focus > 0)
        {
            if (state.attack_dice.change_dice(DieResult.Blank, DieResult.Hit, 1) > 0)
                state.attack_tokens.focus = state.attack_tokens.focus - 1;
        }

        state.attack_dice.change_dice(DieResult.Hit, DieResult.Crit, setup.attack.hit_to_crit_count);

        state.attack_temp.finished_amad = true;
        return StateForkNone();
    };
}

private SearchDelegate do_attack_lock(int count)
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(state.attack_tokens.lock > 0);
        assert(!state.attack_temp.cannot_spend_lock);

        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(count);
        assert(dice_to_reroll > 0);

        // If we have fire control system and are only rerolling one die we don't need to spend the lock,
        // but then we are not allowed to spend it during this attack.
        // TODO: Not sure how this is supposed to work for multiple locks; for now it will lock out all
        // lock usage which could be suboptimal if new effects are added later that spend locks.
        if (setup.attack.fire_control_system && dice_to_reroll == 1)
            state.attack_temp.cannot_spend_lock = true;
        else
            state.attack_tokens.lock = state.attack_tokens.lock - 1;

        return StateForkReroll(dice_to_reroll);
    };
}

// Rerolls a blank if present, otherwise focus
private SearchDelegate do_attack_reroll_1()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(setup.attack.reroll_1_count > state.attack_temp.used_reroll_1_count);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(1);
        state.attack_temp.used_reroll_1_count = state.attack_temp.used_reroll_1_count + 1;
        assert(dice_to_reroll == 1);
        return StateForkReroll(dice_to_reroll);
    };
}
private SearchDelegate do_attack_reroll_2(int count = 2)
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(count > 0 && count <= 2);
        assert(setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(count);
        state.attack_temp.used_reroll_2_count = state.attack_temp.used_reroll_2_count + 1;
        assert(dice_to_reroll == count);
        return StateForkReroll(dice_to_reroll);
    };
}
private SearchDelegate do_attack_reroll_3(int count = 3)
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(count > 0 && count <= 3);
        assert(setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(count);
        state.attack_temp.used_reroll_3_count = state.attack_temp.used_reroll_3_count + 1;
        assert(dice_to_reroll == count);
        return StateForkReroll(dice_to_reroll);
    };
}

private SearchDelegate do_attack_heroic()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(setup.attack.heroic);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll(DieResult.Blank);
        assert(dice_to_reroll > 0);     // One or more of the 2+ blanks may not be rerollable in theory
        return StateForkReroll(dice_to_reroll);
    };
}

// Rerolls a blank if present or a focus otherwise
private SearchDelegate do_attack_lone_wolf()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(state.attack_tokens.lone_wolf);
        int dice_to_reroll = state.attack_dice.remove_dice_for_reroll_blank_focus(1);
        assert(dice_to_reroll == 1);
        state.attack_tokens.lone_wolf = false;
        return StateForkReroll(dice_to_reroll);
    };
}

// Spend lock to add a focus result
private SearchDelegate do_attack_shara_bey()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(setup.attack.shara_bey_pilot);
        assert(!state.attack_temp.used_shara_bey_pilot);
        assert(state.attack_tokens.lock > 0);
        assert(!state.attack_temp.cannot_spend_lock);

        ++state.attack_dice.results[DieResult.Focus];

        state.attack_temp.used_shara_bey_pilot = true;
        state.attack_tokens.lock = state.attack_tokens.lock - 1;
        return StateForkNone();
    };
}


// Defender modifies attack dice (DMAD)
private SearchDelegate do_defense_finish_dmad()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.attack_temp.finished_dmad);
        // Nothing to do here currently...
        state.attack_temp.finished_dmad = true;
        return StateForkNone();
    };
}

private SearchDelegate do_defense_l337()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
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
        return StateForkReroll(reroll_count);
    };
}




private double search_expected_damage(const(SimulationSetup) setup, SimulationState state, StateFork fork)
{
    if (!fork.required())
    {
        fork = modify_attack_dice(setup, state);
        if (!fork.required())
        {
            // Base case; done modifying dice
            return state.attack_dice.count(DieResult.Hit) + state.attack_dice.count(DieResult.Crit);
        }
    }

    double expected_damage = 0.0f;
    fork_attack_state(state, fork, (SimulationState new_state, double probability) {
        // NOTE: Rather than have the leaf nodes weight by their state probability, we just accumulate it
        // as we fork here instead. This is just to normalize the expected damage with respect to the state
        // that we started the search from rather than the global state space.
        expected_damage += probability * search_expected_damage(setup, new_state, StateForkNone());
    });

    return expected_damage;
}

// NOTE: Will prefer options earlier in the list if equivalent, so put stuff that spends more
// or more valuable tokens later in the options list.
// NOTE: Search delegates *must* evolve the state in a way that will eventually terminate,
// i.e. spending a finite token, rerolling dice and so on.
// NOTE: If minimize_damage is set to true, will instead search for the minimal damage option
// This is useful for opoonent searches (i.e. DMAD).
private StateFork search_attack(
    const(SimulationSetup) setup,
    ref SimulationState output_state,
    SearchDelegate[] options,
    bool minimize_damage = false)
{
    assert(options.length > 0);

    // Early out if there's only one option; no need for search
    if (options.length == 1)
        return options[0](setup, output_state);

    // Try each option and track which ends up with the best expected damage
    const(SimulationState) initial_state = output_state;
    SimulationState best_state = initial_state;
    double best_expected_damage = minimize_damage ? 100000.0f : -1.0f;
    StateFork best_state_fork = StateForkNone();

    //debug log_message("Forward search on %s (%s options):",
    //                  output_state.attack_dice, options.length, max_state_rerolls);

    foreach (option; options)
    {
        // Do any requested rerolls; note that instead of appending states we simple do a depth
        // first search of each result one by one. This keeps forward searches somewhat more efficient
        SimulationState state = initial_state;
        StateFork fork = option(setup, state);

        // Assert that delegate actually changed the state in some way; otherwise potential infinite loop!
        assert(fork.required() || state != initial_state);

        // TODO: Experiment with epsilon; this is to prefer earlier options when equivalent
        immutable double epsilon = 1e-9;

        bool new_best = false;
        double expected_damage = search_expected_damage(setup, state, fork);
        if ((!minimize_damage && expected_damage > (best_expected_damage + epsilon)) ||
            ( minimize_damage && expected_damage < (best_expected_damage - epsilon)))
        {
            new_best = true;
            best_expected_damage = expected_damage;
            best_state = state;
            best_state_fork = fork;
        }

        //debug log_message("Option %s (reroll %s) expected damage: %s %s",
        //                  i, reroll_count, expected_damage, new_best ? "(new best)" : "");
    }

    output_state = best_state;
    return best_state_fork;
}
