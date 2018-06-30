import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;


// Handles a subset of the stuff that neutralize results does because in general we still want to try and
// cancel everything even in cases where weird effects happen there (tractor beam, biggs, etc)
// DOES consider reinforce though, so be careful where you use this vs. other options
public int compute_uncanceled_damage(const(SimulationSetup2) setup, SimulationState2 state)
{
    state.attack_dice.finalize();
    state.defense_dice.finalize();

    int total_damage = state.attack_dice.final_results[DieResult.Hit] + state.attack_dice.final_results[DieResult.Crit];
    int total_evades = state.defense_dice.final_results[DieResult.Evade];

    // Reinforce
    int excess_hits = max(0, total_damage - (total_evades + 1));
    total_evades += min(state.defense_tokens.reinforce, excess_hits);

    // TODO: Crack shot likely

    return max(0, total_damage - total_evades);
}

// NOTE: This function has the same semantics as modify_defense_dice.
// It exists entirely to track the root of the recursive tree before returning back to the
// caller for the purpose of effects that we may want to apply after we see the final results,
// but we do *not* want to affect the search. Ex. Iden.
// Since this function sits at the root of the recursive call tree it can decide to unwind or otherwise
// elide any choices made by the children, other than rerolls (which are handled by the caller, and it
// would be cheating to change!)
public int modify_defense_dice_root(
    const(SimulationSetup2) setup,
    ref SimulationState2 state)
{
    const(SimulationState2) initial_state = state;

    int dice_to_reroll = modify_defense_dice(setup, state);
    if (dice_to_reroll > 0)
        return dice_to_reroll;
    else
    {
        // If we get here this is the root of the final modify chain after any rerolls
        int uncancelled_damage = compute_uncanceled_damage(setup, state);

        // Check if we should just Iden instead of actually doing the final chain of mods
        if (state.defense_tokens.iden && uncancelled_damage > 0)
        {
            // NOTE: TIE/ln's have 3 HP and Iden only works on them
            if (uncancelled_damage > 1 || state.defense_tokens.iden_total_damage >= 2)
            {                
                // Reset to before the final chain of modding
                state = initial_state;
                state.defense_tokens.iden = false;
                state.attack_dice.cancel_all();
                state.defense_dice.cancel_all();
                return 0;
            }
        }

        return 0;
    }
}


// Returns number of dice to reroll, or 0 when done modding
// Modifies state in place
// NOTE: see public function above
private int modify_defense_dice(
    const(SimulationSetup2) setup,
    ref SimulationState2 state)
{
    // TODO: Take into account crack shot if present (+1 this, etc)
    // NOTE: See reinforce logic below for modifying search. Ideally something like that should also be present in any
    // effects that use this evades_target "after rolling" as well, but gets a bit complex in the general case.
    int evades_target = state.attack_dice.final_results[DieResult.Hit] + state.attack_dice.final_results[DieResult.Crit];

    // First have to do any "after rolling" abilities
    if (!state.defense_temp.finished_after_rolling)
    {
        // C-3P0 has to happen right after rolling, so do it immediately and mark it "used" unconditionally
        // TODO: sometimes we don't want to c3p0 if we are reinforced
        if (setup.defense.c3p0)
        {
            // The only case we don't use C-3P0 is if there's only one hit in the first place
            // Since we have to "call" it before we see the defense roll we're not allowed to see it first :)
            if (state.defense_tokens.calculate > 0 && evades_target > 1)
            {
                if (state.defense_dice.count(DieResult.Evade) == 1)     // Always guess 1
                    ++state.defense_dice.results[DieResult.Evade];

                state.defense_tokens.calculate = state.defense_tokens.calculate - 1;
                state.defense_tokens.spent_calculate = true;
                state.defense_temp.used_c3p0 = true;
            }
        }

        state.defense_temp.finished_after_rolling = true;
    }

    // Next the attacker modifies the dice
    if (!state.defense_temp.finished_amdd)
    {
        if (setup.attack.juke && state.attack_tokens.evade > 0)
            state.defense_dice.change_dice(DieResult.Evade, DieResult.Focus, 1);

        state.defense_temp.finished_amdd = true;
    }

    // Defender modifies dice

    // Add results
    // Currently no reason to not just unconditionally add everything at the start, but track it in case that changes
    if (setup.defense.add_evade_count > state.defense_temp.used_add_evade_count)
    {
        int count = setup.defense.add_evade_count - state.defense_temp.used_add_evade_count;
        state.defense_dice.results[DieResult.Evade] += count;
        state.defense_temp.used_add_evade_count = setup.defense.add_evade_count;
    }    

    // Base case and early outs
    if (state.defense_dice.count(DieResult.Evade) >= evades_target || state.defense_temp.finished_dmdd)
        return 0;

    // Search from all our potential token spending and rerolling options to find the optimal one
    SearchDelegate[16] search_options;
    size_t search_options_count = 0;

    // First option to try is just finishing up our defense mods (spending focus and things like that) and terminating

    // NOTE: If we have any reinforce tokens, first try aiming for lower evades targets... if they produce the
    // same expected damage as aiming to dodge everything it's better to just rely on that and likely spend fewer tokens.
    if (state.defense_tokens.reinforce > 0)
    {
        int evades_that_matter = evades_target - state.defense_tokens.reinforce - 1;
        if (evades_that_matter >= 0)
            search_options[search_options_count++] = do_defense_finish_dmdd(evades_that_matter);
    }
    // Regular modding to attempt to avoid all damage
    search_options[search_options_count++] = do_defense_finish_dmdd(evades_target);

    // Any token spending options we might want to do before reroll, such as those that add results
    if (setup.defense.shara_bey_pilot && state.defense_tokens.lock > 0 && !state.defense_temp.used_shara_bey_pilot)
        search_options[search_options_count++] = do_defense_shara_bey();

    // Rerolls - see comments in modify_attack_dice2 as the logic is similar
    int rerollable_focus_results = state.defense_dice.results[DieResult.Focus];
    int rerollable_blank_results = state.defense_dice.results[DieResult.Blank];

    const int max_dice_to_reroll = rerollable_blank_results + rerollable_focus_results;
    foreach_reverse (const dice_to_reroll; 1 .. (max_dice_to_reroll+1))
    {
        const int blanks_to_reroll = min(rerollable_blank_results, dice_to_reroll);
        const int focus_to_reroll = dice_to_reroll - blanks_to_reroll;

        // Similar logic to attack rerolls - see documentation there (modify_attack_dice.d)

        if (dice_to_reroll == 3)
        {
            if (setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                search_options[search_options_count++] = do_defense_reroll_3(dice_to_reroll);
        }
        else if (dice_to_reroll == 2)
        {
            if (setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count)
                search_options[search_options_count++] = do_defense_reroll_2(dice_to_reroll);
            else if (setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                search_options[search_options_count++] = do_defense_reroll_3(dice_to_reroll);
        }
        else if (dice_to_reroll == 1)
        {
            if (setup.defense.reroll_1_count > state.defense_temp.used_reroll_1_count)
                search_options[search_options_count++] = do_defense_reroll_1();
            else if (setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count)
                search_options[search_options_count++] = do_defense_reroll_2(dice_to_reroll);
            else if (setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                search_options[search_options_count++] = do_defense_reroll_3(dice_to_reroll);
            else 
            {
                if (state.defense_tokens.lone_wolf)
                    search_options[search_options_count++] = do_defense_lone_wolf();
            }
        }
    }

    // Search modifies the state to execute the best of the provided options
    SimulationState2 before_search_state = state;
    int dice_to_reroll = search_defense(setup, state, search_options[0..search_options_count]);
    if (dice_to_reroll > 0)
        return dice_to_reroll;
    else
    {
        // Continue modifying
        return modify_defense_dice(setup, state);
    }
}

// Logic is:
// - If there's >1 focus results, spend focus if able
// - Otherwise spend calculate, then force (by default, see parameter to swap)
private SimulationState2 spend_focus_calculate_force(
    SimulationState2 state, int focus_results_to_change, bool prefer_spend_calculate = true)
{
    int initial_calculate_tokens = state.defense_tokens.calculate;

    // Should never ask us to change more results than we have
    assert(state.defense_dice.count_mutable(DieResult.Focus) >= focus_results_to_change);

    if (focus_results_to_change > 0)
    {
        int single_focus_token_mods = state.defense_tokens.calculate + state.defense_tokens.force;
        if (state.defense_tokens.focus > 0 && (focus_results_to_change > 1 || single_focus_token_mods == 0))
        {
            int changed = state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit);
            assert(changed > 0);
            state.defense_tokens.focus = state.defense_tokens.focus - 1;
        }
        else
        {
            int change_with_calculate = state.defense_tokens.calculate;
            int change_with_force     = state.defense_tokens.force;
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
            state.defense_tokens.calculate = state.defense_tokens.calculate - state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit, change_with_calculate);
            state.defense_tokens.force     = state.defense_tokens.force     - state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit, change_with_force);
        }
    }

    // Flag if calculate was spent here (for leebo, etc)
    if (state.defense_tokens.calculate != initial_calculate_tokens)
        state.defense_tokens.spent_calculate = true;

    return state;
}





alias int delegate(const(SimulationSetup2) setup, ref SimulationState2) SearchDelegate;

private SearchDelegate do_defense_finish_dmdd(int evades_target)
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(!state.defense_temp.finished_dmdd);

        // Free dice changes
        int any_to_evade = cast(int)setup.defense.any_to_evade_count - cast(int)state.defense_temp.used_any_to_evade_count;
        state.defense_temp.used_any_to_evade_count = state.defense_temp.used_any_to_evade_count +
            state.defense_dice.change_blank_focus(DieResult.Evade, any_to_evade);

        int needed_evades = max(0, evades_target - state.defense_dice.count(DieResult.Evade));
        if (needed_evades > 0)
        {
            state = spend_focus_calculate_force(state, min(state.defense_dice.count_mutable(DieResult.Focus), needed_evades));
            needed_evades = max(0, evades_target - state.defense_dice.count(DieResult.Evade));

            // If we still need evades, spend evade tokens (if there are dice to convert)
            if (needed_evades > 0)
            {
                int evades_to_spend = min(needed_evades, state.defense_tokens.evade);
                int evades_spent = state.defense_dice.change_dice(DieResult.Blank, DieResult.Evade, evades_to_spend);
                evades_spent    += state.defense_dice.change_dice(DieResult.Focus, DieResult.Evade, evades_to_spend - evades_spent);
                state.defense_tokens.evade = state.defense_tokens.evade - evades_spent;
            }
        }
        
        state.defense_temp.finished_dmdd = true;
        return 0;
    };
}

// Rerolls a blank if present, otherwise focus
private SearchDelegate do_defense_reroll_1()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(setup.defense.reroll_1_count > state.defense_temp.used_reroll_1_count);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(1);
        state.defense_temp.used_reroll_1_count = state.defense_temp.used_reroll_1_count + 1;
        assert(dice_to_reroll == 1);
        return dice_to_reroll;
    };
}
private SearchDelegate do_defense_reroll_2(int count = 2)
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(count > 0 && count <= 2);
        assert(setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(count);
        state.defense_temp.used_reroll_2_count = state.defense_temp.used_reroll_2_count + 1;
        assert(dice_to_reroll == count);
        return dice_to_reroll;
    };
}
private SearchDelegate do_defense_reroll_3(int count = 3)
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(count > 0 && count <= 3);
        assert(setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(count);
        state.defense_temp.used_reroll_3_count = state.defense_temp.used_reroll_3_count + 1;
        assert(dice_to_reroll == count);
        return dice_to_reroll;
    };
}


// Rerolls a blank if present or a focus otherwise
private SearchDelegate do_defense_lone_wolf()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(state.defense_tokens.lone_wolf);

        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll(DieResult.Blank, 1);
        if (dice_to_reroll == 0)
            dice_to_reroll = state.defense_dice.remove_dice_for_reroll(DieResult.Focus, 1);
        assert(dice_to_reroll == 1);

        state.defense_tokens.lone_wolf = false;
        return dice_to_reroll;
    };
}

// Spend lock to add a focus result
private SearchDelegate do_defense_shara_bey()
{
    return (const(SimulationSetup2) setup, ref SimulationState2 state)
    {
        assert(setup.defense.shara_bey_pilot);
        assert(!state.defense_temp.used_shara_bey_pilot);
        assert(state.defense_tokens.lock > 0);

        ++state.defense_dice.results[DieResult.Focus];

        state.defense_temp.used_shara_bey_pilot = true;
        state.defense_tokens.lock = state.defense_tokens.lock - 1;
        return 0;
    };
}



private double search_expected_damage(const(SimulationSetup2) setup, SimulationState2 state, int reroll_count)
{
    if (reroll_count == 0)
    {
        reroll_count = modify_defense_dice(setup, state);
        if (reroll_count == 0)
        {
            // Base case; done modifying defense dice
            return cast(double)compute_uncanceled_damage(setup, state);
        }
    }

    // Reroll and recurse
    double expected_damage = 0.0f;
    assert(reroll_count > 0);
    roll_defense_dice(reroll_count, (int blank, int focus, int evade, double probability) {
        auto new_state = state;
        new_state.defense_dice.rerolled_results[DieResult.Evade] += evade;
        new_state.defense_dice.rerolled_results[DieResult.Focus] += focus;
        new_state.defense_dice.rerolled_results[DieResult.Blank] += blank;
        new_state.probability *= probability;
        expected_damage += probability * search_expected_damage(setup, new_state, 0);
    });

    return expected_damage;
}

// Attempts to minimize the expected damage after a simplified neutralize results step
// (See compute_uncanceled_damage for the details.)
// NOTE: Will prefer options earlier in the list if equivalent, so put stuff that spends more
// or more valuable tokens later in the options list.
private int search_defense(
    const(SimulationSetup2) setup,
    ref SimulationState2 output_state,
    SearchDelegate[] options)
{
    assert(options.length > 0);

    // Early out if there's only one option; no need for search
    if (options.length == 1)
        return options[0](setup, output_state);

    // Try each option and track which ends up with the best expected damage
    const(SimulationState2) initial_state = output_state;
    SimulationState2 min_state = initial_state;
    double min_expected_damage = 100000.0f;
    int min_state_rerolls = 0;

    foreach (option; options)
    {
        SimulationState2 state = initial_state;
        int reroll_count = option(setup, state);
        assert(reroll_count > 0 || state != initial_state);

        double expected_damage = search_expected_damage(setup, state, reroll_count);
        if (expected_damage < (min_expected_damage - 1e-9))
        {
            min_expected_damage = expected_damage;
            min_state = state;
            min_state_rerolls = reroll_count;
        }
    }

    output_state = min_state;
    return min_state_rerolls;
}
