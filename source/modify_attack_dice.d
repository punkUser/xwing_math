import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;


private StateFork after_rolling(const(SimulationSetup) setup, ref SimulationState state)
{
    // Nothing to do here for now
    return StateForkNone();
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
    // NOTE: Nothing to do here for now
    //if (!state.attack_temp.finished_after_rolling)
    //{
    //    StateFork fork = after_rolling(setup, state);
    //    if (fork.required())
    //        return fork;
    //    assert(state.attack_temp.finished_after_rolling);
    //}

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
    SearchDelegate[64] search_options;
    size_t search_options_count = 0;

    // First check and "free" stuff that might avoid spending tokens but otherwise give the same expected results
    if (setup.attack.rebel_han_pilot && !state.attack_temp.used_rebel_han_pilot)
    {
        // Only consider if we have blanks or focus to reroll
        if ((state.attack_dice.count_mutable(DieResult.Blank) + state.attack_dice.count_mutable(DieResult.Focus)) > 0)
            search_options[search_options_count++] = do_attack_rebel_han_pilot();
    }

    // "Free" rerolls that don't involve token spending. Check these before we finish up the attack as they might avoid token spending.
    const int max_dice_to_reroll = state.attack_dice.results[DieResult.Blank] + state.attack_dice.results[DieResult.Focus];

    if (max_dice_to_reroll > 0)
    {
        // If we can use heroic that's the only option we need for rerolls; optimal effect to reroll all dice if all are blank
        if (setup.attack.heroic && state.attack_dice.are_all_blank() && state.attack_dice.count(DieResult.Blank) > 1)
        {
            search_options[search_options_count++] = do_attack_heroic();
        }
        else
        {
            foreach_reverse (const dice_to_reroll; 1 .. (max_dice_to_reroll+1))
            {
                // NOTE: Can use "reroll up to 2/3" abilities to reroll just one if needed as well, but less desirable
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
                }
            }
        }
    }

    // Now check finishing up attack mods and stopping
    search_options[search_options_count++] = do_attack_finish_amad();

    // Now do abilities that spend tokens or charges

    if (setup.attack.shara_bey_pilot && state.attack_tokens.lock > 0 && !state.attack_temp.cannot_spend_lock && !state.attack_temp.used_shara_bey_pilot)
        search_options[search_options_count++] = do_attack_shara_bey();

    if (setup.attack.advanced_optics && state.attack_tokens.focus > 0 && state.attack_dice.count(DieResult.Blank) > 0 && !state.attack_temp.used_advanced_optics)
        search_options[search_options_count++] = do_attack_advanced_optics();

    // Paid rerolls
    if (max_dice_to_reroll > 0)
    {
        // Lando pilot rerolls (all blanks)
        if (setup.attack.scum_lando_pilot && !state.attack_temp.used_scum_lando_pilot &&
            state.attack_tokens.stress == 0 && state.attack_dice.results[DieResult.Blank] > 0) {
            search_options[search_options_count++] = do_attack_scum_lando_pilot();
        }
    
        if (state.attack_tokens.lone_wolf) {
            search_options[search_options_count++] = do_attack_lone_wolf();
        }

        // Lando crew rerolls
        if (setup.attack.scum_lando_crew && !state.attack_temp.used_scum_lando_crew) {
            // Try rerolling 1 or 2 results with each green token we have (in order of general preference)
            // NOTE: Always reroll blanks, so only try 1 if it's a focus
            bool at_least_two_blanks = state.attack_dice.results[DieResult.Blank] > 1;
            foreach (immutable token; [GreenToken.Reinforce, GreenToken.Evade, GreenToken.Calculate, GreenToken.Focus]) {
                if (state.attack_tokens.count(token) == 0) continue;
                if (max_dice_to_reroll > 1)
                    search_options[search_options_count++] = do_attack_scum_lando_crew(2, token);
                if (!at_least_two_blanks)
                    search_options[search_options_count++] = do_attack_scum_lando_crew(1, token);
            }
        }

        // Lock can always reroll arbitrary sets of dice
        if (state.attack_tokens.lock > 0 && !state.attack_temp.cannot_spend_lock)
        {
            // NOTE: Currently no effects that change blanks *but not focus* to hits, so safe to always reroll all blanks
            foreach_reverse (const dice_to_reroll; max(1, state.attack_dice.results[DieResult.Blank]) .. (max_dice_to_reroll+1))
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
        // so we ignore them (i.e. don't reroll them) for now.
        
        // NOTE: We keep track of which dice have already been rerolled "through" Han's reroll. We don't yet have a ruling
        // on whether this is correct but it's likely the most consistent with the current rules.

        int roll_count =
            state.attack_dice.results[DieResult.Blank] + 
            state.attack_dice.results[DieResult.Focus] +
            state.attack_dice.results[DieResult.Hit] +
            state.attack_dice.results[DieResult.Crit];
        int reroll_count =
            state.attack_dice.rerolled_results[DieResult.Blank] + 
            state.attack_dice.rerolled_results[DieResult.Focus] +
            state.attack_dice.rerolled_results[DieResult.Hit] +
            state.attack_dice.rerolled_results[DieResult.Crit];
        assert((roll_count + reroll_count) > 0);

        state.attack_dice.cancel_mutable();        
        state.attack_temp.used_rebel_han_pilot = true;

        return StateForkRollAndReroll(roll_count, reroll_count);
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

        // NOTE: Order matters here! Use Rey greedily on a blank if available first rather than wasting
        // the force to change an eyeball below, etc.
        if (setup.attack.rey_pilot && state.attack_tokens.force > 0)
        {
            if (state.attack_dice.change_dice(DieResult.Blank, DieResult.Hit, 1) > 0)
                state.attack_tokens.force = state.attack_tokens.force - 1;
        }

        // If we have other uses for a given token, it's sometimes better to prefer to spend the other here
        bool prefer_spend_calculate = true;
        state = spend_focus_calculate_force(setup, state, prefer_spend_calculate);

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

private SearchDelegate do_attack_advanced_optics()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(setup.attack.advanced_optics);
        assert(!state.attack_temp.used_advanced_optics);
        assert(state.attack_tokens.focus > 0);

        int dice_changed = state.attack_dice.change_dice(DieResult.Blank, DieResult.Hit, 1);
        assert(dice_changed == 1);

        state.attack_temp.used_advanced_optics = true;
        state.attack_tokens.focus = state.attack_tokens.focus - 1;
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
