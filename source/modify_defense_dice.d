import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;


// Handles a subset of the stuff that neutralize results does because in general we still want to try and
// cancel everything even in cases where weird effects happen there (tractor beam, biggs, etc)
// DOES consider reinforce though, so be careful where you use this vs. other options
public int compute_uncanceled_damage(const(SimulationSetup) setup, SimulationState state)
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


private int after_rolling(const(SimulationSetup) setup, ref SimulationState state)
{
    // Base case
    if (state.defense_temp.finished_after_rolling)
        return 0;

    // C-3P0 has to happen right after rolling, so do it immediately and mark it "used" unconditionally
    // TODO: sometimes we don't want to c3p0 if we are reinforced
    if (setup.defense.c3p0)
    {
        // The only case we don't use C-3P0 is if there's only one hit in the first place
        // Since we have to "call" it before we see the defense roll we're not allowed to see it first :)
        // TODO: Unify how we handle evades_target stuff...
        int evades_target = state.attack_dice.final_results[DieResult.Hit] + state.attack_dice.final_results[DieResult.Crit];
        if (state.defense_tokens.calculate > 0 && evades_target > 1)
        {
            if (state.defense_dice.count(DieResult.Evade) == 1)     // Always guess 1
                ++state.defense_dice.results[DieResult.Evade];

            state.defense_tokens.calculate = state.defense_tokens.calculate - 1;
            state.defense_tokens.spent_calculate = true;
            state.defense_temp.used_c3p0 = true;
        }
    }


    SearchDelegate[16] search_options;
    size_t search_options_count = 0;
    search_options[search_options_count++] = do_defense_finish_after_rolling();

    int rerollable_results = state.defense_dice.results[DieResult.Blank] + state.defense_dice.results[DieResult.Focus];
    if (rerollable_results > 0)
    {
        // Lando pilot rerolls (all blanks)
        if (setup.defense.scum_lando_pilot && !state.defense_temp.used_scum_lando_pilot &&
            state.defense_tokens.stress == 0 && state.defense_dice.results[DieResult.Blank] > 0) {
            search_options[search_options_count++] = do_defense_scum_lando_pilot();
        }

        // Lando crew rerolls (logic similar to attack - see notes there)
        if (setup.defense.scum_lando_crew && !state.defense_temp.used_scum_lando_crew && rerollable_results > 0) {
            bool at_least_two_blanks = state.defense_dice.results[DieResult.Blank] > 1;
            // NOTE/TODO: Hard code this to not spend reinforce on defense for now as generally it will contribute more
            // value each attack.
            foreach (immutable token; [GreenToken.Calculate, GreenToken.Focus, GreenToken.Evade]) {
                if (state.defense_tokens.count(token) == 0) continue;
                if (rerollable_results > 1)
                    search_options[search_options_count++] = do_defense_scum_lando_crew(2, token);
                if (!at_least_two_blanks)
                    search_options[search_options_count++] = do_defense_scum_lando_crew(1, token);
            }
        }
    }

    int dice_to_reroll = search_defense(setup, state, search_options[0..search_options_count]);
    if (dice_to_reroll > 0)
        return dice_to_reroll;
    else
        return after_rolling(setup, state);      // Continue after rolling
}



// NOTE: This function has the same semantics as modify_defense_dice.
// It exists entirely to track the root of the recursive tree before returning back to the
// caller for the purpose of effects that we may want to apply after we see the final results,
// but we do *not* want to affect the search. Ex. Iden.
// Since this function sits at the root of the recursive call tree it can decide to unwind or otherwise
// elide any choices made by the children, other than rerolls (which are handled by the caller, and it
// would be cheating to change!)
public int modify_defense_dice_root(
    const(SimulationSetup) setup,
    ref SimulationState state)
{
    const(SimulationState) initial_state = state;

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
                state.defense_tokens.iden_used = true;
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
    const(SimulationSetup) setup,
    ref SimulationState state)
{
    // First have to do any "after rolling" abilities
    if (!state.defense_temp.finished_after_rolling)
    {
        int reroll_count = after_rolling(setup, state);
        if (reroll_count > 0)
            return reroll_count;
        assert(state.defense_temp.finished_after_rolling);
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
    if (!state.defense_temp.used_add_results)
    {
        state.defense_dice.results[DieResult.Blank] += setup.defense.add_blank_count;
        state.defense_dice.results[DieResult.Focus] += setup.defense.add_focus_count;
        state.defense_dice.results[DieResult.Evade] += setup.defense.add_evade_count;
        state.defense_temp.used_add_results = true;
    }

    // Base case and early outs
    // TODO: compute_uncanceled_damage() == 0 instead? Since our search logic relies on that it's probably "safe"
    int evades_target = state.attack_dice.final_results[DieResult.Hit] + state.attack_dice.final_results[DieResult.Crit];
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

    // Similar logic to attack rerolls - see documentation there (modify_attack_dice.d)
    if (setup.defense.heroic && state.defense_dice.are_all_blank() &&
        state.defense_dice.count(DieResult.Blank) > 1 && rerollable_blank_results > 0)
    {
        search_options[search_options_count++] = do_defense_heroic();
    }
    else
    {
        const int max_dice_to_reroll = rerollable_blank_results + rerollable_focus_results;
        foreach_reverse (const dice_to_reroll; 1 .. (max_dice_to_reroll+1))
        {
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
                if (setup.defense.rebel_millennium_falcon && state.defense_tokens.evade > 0 && !state.defense_temp.used_rebel_millennium_falcon)
                    search_options[search_options_count++] = do_defense_rebel_millennium_falcon();
                else if (setup.defense.reroll_1_count > state.defense_temp.used_reroll_1_count)
                    search_options[search_options_count++] = do_defense_reroll_1();
                else if (setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count)
                    search_options[search_options_count++] = do_defense_reroll_2(dice_to_reroll);
                else if (setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                    search_options[search_options_count++] = do_defense_reroll_3(dice_to_reroll);
                else 
                {
                    if (state.defense_tokens.elusive)
                        search_options[search_options_count++] = do_defense_elusive();
                    else if (state.defense_tokens.lone_wolf)
                        search_options[search_options_count++] = do_defense_lone_wolf();
                }
            }
        }
    }

    // Search modifies the state to execute the best of the provided options
    SimulationState before_search_state = state;
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
private SimulationState spend_focus_calculate_force(
    const(SimulationSetup) setup, SimulationState state, int focus_results_to_change, bool prefer_spend_calculate = true)
{
    int initial_calculate_tokens = state.defense_tokens.calculate;

    // Should never ask us to change more results than we have
    assert(state.defense_dice.count_mutable(DieResult.Focus) >= focus_results_to_change);

    if (focus_results_to_change > 0)
    {
        bool ezra_available = setup.defense.ezra_pilot && state.defense_tokens.stress > 0 && state.defense_tokens.force > 0;
        bool brilliant_evasion_available = setup.defense.brilliant_evasion && state.defense_tokens.force > 0;

        bool force_calculate_available = (state.defense_tokens.calculate + state.defense_tokens.force) > 0;
        int change_with_one_token_count = (ezra_available || brilliant_evasion_available) ? 2 : (force_calculate_available > 0 ? 1 : 0);

        if (state.defense_tokens.focus > 0 && (focus_results_to_change > change_with_one_token_count))
        {
            int changed = state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit);
            assert(changed > 0);
            state.defense_tokens.focus = state.defense_tokens.focus - 1;
        }
        else
        {
            // NOTE: Have to re-check token counts and dice here for each effect we apply
            if (ezra_available && focus_results_to_change > 1 && state.defense_tokens.force > 0)
            {
                state.defense_dice.change_dice(DieResult.Focus, DieResult.Evade, 2);
                state.defense_tokens.force = state.defense_tokens.force - 1;
                focus_results_to_change -= 2;
            }
            if (brilliant_evasion_available && focus_results_to_change > 1 && state.defense_tokens.force > 0)
            {
                state.defense_dice.change_dice(DieResult.Focus, DieResult.Evade, 2);
                state.defense_tokens.force = state.defense_tokens.force - 1;
                focus_results_to_change -= 2;
            }

            // Regular force/calculate effect
            if (prefer_spend_calculate)
            {
                state.defense_tokens.calculate = state.defense_tokens.calculate - state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit, state.defense_tokens.calculate);
                state.defense_tokens.force     = state.defense_tokens.force     - state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit, state.defense_tokens.force);
            }
            else
            {
                state.defense_tokens.force     = state.defense_tokens.force     - state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit, state.defense_tokens.force);
                state.defense_tokens.calculate = state.defense_tokens.calculate - state.defense_dice.change_dice(DieResult.Focus, DieResult.Hit, state.defense_tokens.calculate);
            }
        }
    }

    // Flag if calculate was spent here (for leebo, etc)
    if (state.defense_tokens.calculate != initial_calculate_tokens)
        state.defense_tokens.spent_calculate = true;

    return state;
}





alias int delegate(const(SimulationSetup) setup, ref SimulationState) SearchDelegate;

// After rolling (before attacker modifies)
private SearchDelegate do_defense_finish_after_rolling()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.defense_temp.finished_after_rolling);
        // Nothing to do here currently...
        state.defense_temp.finished_after_rolling = true;
        return 0;
    };
}

// Spend green token to reroll up to 2 results.
private SearchDelegate do_defense_scum_lando_crew(int count, GreenToken token)
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.defense_temp.used_scum_lando_crew);
        assert(count > 0 && count <= 2);        
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(count);
        assert(dice_to_reroll > 0);

        switch (token) {
            case GreenToken.Focus:      state.defense_tokens.focus      = state.defense_tokens.focus - 1;      break;            
            case GreenToken.Evade:      state.defense_tokens.evade      = state.defense_tokens.evade - 1;      break;
            case GreenToken.Reinforce:  state.defense_tokens.reinforce  = state.defense_tokens.reinforce - 1;  break;
            case GreenToken.Calculate:
                state.defense_tokens.calculate = state.defense_tokens.calculate - 1;
                state.defense_tokens.spent_calculate = true;
                break;
            default: assert(false);
        }

        state.defense_temp.used_scum_lando_crew = true;
        return dice_to_reroll;
    };
}

// Reroll all blanks, gain stress
private SearchDelegate do_defense_scum_lando_pilot()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.defense_temp.used_scum_lando_pilot);
        assert(state.defense_tokens.stress == 0);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll(DieResult.Blank);
        assert(dice_to_reroll > 0);
        state.defense_tokens.stress = state.defense_tokens.stress + 1;
        state.defense_temp.used_scum_lando_pilot = true;
        return dice_to_reroll;
    };
}



private SearchDelegate do_defense_finish_dmdd(int evades_target)
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(!state.defense_temp.finished_dmdd);

        // Free changes
        state.defense_dice.change_dice(DieResult.Focus, DieResult.Evade, setup.defense.focus_to_evade_count);

        if (setup.defense.captain_feroph_pilot && state.attack_tokens.green_token_count() == 0)
            state.defense_dice.change_blank_focus(DieResult.Evade, 1);

        state.defense_dice.change_blank_focus(DieResult.Evade, setup.defense.any_to_evade_count);

        int needed_evades = max(0, evades_target - state.defense_dice.count(DieResult.Evade));
        if (needed_evades > 0)
        {
            state = spend_focus_calculate_force(setup, state, min(state.defense_dice.count_mutable(DieResult.Focus), needed_evades));
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

private SearchDelegate do_defense_heroic()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(setup.defense.heroic);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll(DieResult.Blank);
        assert(dice_to_reroll > 0);     // One or more of the 2+ blanks may not be rerollable in theory
        return dice_to_reroll;
    };
}

// Rerolls a blank if present, otherwise focus
private SearchDelegate do_defense_reroll_1()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
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
    return (const(SimulationSetup) setup, ref SimulationState state)
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
    return (const(SimulationSetup) setup, ref SimulationState state)
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
private SearchDelegate do_defense_elusive()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(state.defense_tokens.elusive);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(1);
        assert(dice_to_reroll == 1);
        state.defense_tokens.elusive = false;
        return dice_to_reroll;
    };
}

// Rerolls a blank if present or a focus otherwise
private SearchDelegate do_defense_lone_wolf()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(state.defense_tokens.lone_wolf);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(1);
        assert(dice_to_reroll == 1);
        state.defense_tokens.lone_wolf = false;
        return dice_to_reroll;
    };
}

// Rerolls a blank if present or a focus otherwise
private SearchDelegate do_defense_rebel_millennium_falcon()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
    {
        assert(setup.defense.rebel_millennium_falcon);
        assert(state.defense_tokens.evade > 0);
        assert(!state.defense_temp.used_rebel_millennium_falcon);
        int dice_to_reroll = state.defense_dice.remove_dice_for_reroll_blank_focus(1);
        assert(dice_to_reroll == 1);
        state.defense_temp.used_rebel_millennium_falcon = true;
        return dice_to_reroll;
    };
}

// Spend lock to add a focus result
private SearchDelegate do_defense_shara_bey()
{
    return (const(SimulationSetup) setup, ref SimulationState state)
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



private double search_expected_damage(const(SimulationSetup) setup, SimulationState state, int reroll_count)
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
    const(SimulationSetup) setup,
    ref SimulationState output_state,
    SearchDelegate[] options)
{
    assert(options.length > 0);

    // Early out if there's only one option; no need for search
    if (options.length == 1)
        return options[0](setup, output_state);

    // Try each option and track which ends up with the best expected damage
    const(SimulationState) initial_state = output_state;
    SimulationState min_state = initial_state;
    double min_expected_damage = 100000.0f;
    int min_state_rerolls = 0;

    foreach (option; options)
    {
        SimulationState state = initial_state;
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