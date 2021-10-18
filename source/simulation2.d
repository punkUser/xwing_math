import simulation_state2;
import simulation_setup2;
import modify_attack_dice : modify_attack_dice;
import modify_defense_dice : modify_defense_dice_root;
import simulation_results;
import dice;
import math;
import log;

import std.algorithm;
import std.stdio;
import std.datetime;

import vibe.core.core;

//-----------------------------------------------------------------------------------

public SimulationState neutralize_results(const(SimulationSetup) setup, SimulationState state)
{
    // TODO: Do this earlier as well for state compression reasons
    state.attack_dice.finalize();
    state.defense_dice.finalize();

    // Convenience
    ubyte[DieResult.Num] attack_results  = state.attack_dice.final_results;
    ubyte[DieResult.Num] defense_results = state.defense_dice.final_results;

    // Compare results
    int total_hits   = attack_results[DieResult.Hit] + attack_results[DieResult.Crit];
    int total_evades = defense_results[DieResult.Evade];

    // Selfless, then Biggs
    if (setup.defense.selfless && attack_results[DieResult.Crit] > 0)
        --attack_results[DieResult.Crit];

    if (setup.defense.biggs)
    {
        if (attack_results[DieResult.Crit] > 0)
            --attack_results[DieResult.Crit];
        else if (attack_results[DieResult.Hit] > 0)
            --attack_results[DieResult.Hit];
    }

    int excess_hits = max(0, total_hits - (total_evades + 1));
    defense_results[DieResult.Evade] += min(state.defense_tokens.reinforce, excess_hits);

    // Cancel pairs of hits/crits and evades
    {
        // Zeb cancels crits first
        if (setup.defense.zeb_pilot)
        {
            int canceled_crits = min(attack_results[DieResult.Crit], defense_results[DieResult.Evade]);
            attack_results[DieResult.Crit]   -= canceled_crits;
            defense_results[DieResult.Evade] -= canceled_crits;
        }

        int canceled_hits = min(attack_results[DieResult.Hit], defense_results[DieResult.Evade]);
        attack_results[DieResult.Hit]    -= canceled_hits;
        defense_results[DieResult.Evade] -= canceled_hits;

        if (!setup.defense.zeb_pilot)
        {
            int canceled_crits = min(attack_results[DieResult.Crit], defense_results[DieResult.Evade]);
            attack_results[DieResult.Crit]   -= canceled_crits;
            defense_results[DieResult.Evade] -= canceled_crits;
        }
    }

    int total_damage = attack_results[DieResult.Hit] + attack_results[DieResult.Crit];

    // If Iden was used, the attack is considered to have hit
    bool attack_hit = total_damage > 0 || state.defense_tokens.iden_used;

    if (setup.attack.plasma_torpedoes && attack_hit)
    {
        state.final_hits += 1;
    }

    if (setup.attack.ion_weapon && total_damage > 0)
    {
        // Ions deal the first hit as a regular damage and any excess hits as ion tokens
        state.defense_tokens.add_ion_tokens(total_damage - 1);
        attack_results[DieResult.Hit] = 1;
        attack_results[DieResult.Crit] = 0;
        total_damage = 1;
    }

    // Stealth device drops if we suffer any damage (after above effects)
    if (total_damage > 0)
        state.defense_tokens.stealth_device = false;

    // Transfer to final states and clear out state vector
    state.final_hits  += attack_results[DieResult.Hit];
    state.final_crits += attack_results[DieResult.Crit];
    
    // Trigger Hate if present and regen capped by maximum force
    if (setup.defense.hate && state.defense_tokens.force < setup.defense.max_force_count)
    {
        state.defense_tokens.force = min(state.defense_tokens.force + total_damage, setup.defense.max_force_count);
    }

    // Calculate Damage taken for Iden
    // NOTE: Only do this when Iden is present as it diverges the entire simulation per attack!
    if (state.defense_tokens.iden)
        state.defense_tokens.iden_total_damage = min(3, state.defense_tokens.iden_total_damage + total_damage);

    // After attack stuff
    if (setup.attack.leebo_pilot && state.attack_tokens.spent_calculate)
        state.attack_tokens.calculate = state.attack_tokens.calculate + 1;
    if (setup.defense.leebo_pilot && state.defense_tokens.spent_calculate)
        state.defense_tokens.calculate = state.defense_tokens.calculate + 1;

    if (setup.defense.laetin_pilot && !attack_hit)
        state.defense_tokens.evade = state.defense_tokens.evade + 1;

    // Simplify/clear out irrelevant states
    // Keep tokens and final results, discard the rest
    {
        state.attack_dice.cancel_all();
        state.defense_dice.cancel_all();

        state.attack_temp.reset();
        state.attack_tokens.spent_calculate = false;
        assert(state.attack_tokens.iden_used == false);

        state.defense_temp.reset();
        state.defense_tokens.spent_calculate = false;
        state.defense_tokens.iden_used = false;
    }

    return state;
}

// Returns full set of states after result comparison (results put into state.final_hits, etc)
private SimulationStateSet simulate_single_attack(
    const(SimulationSetup) setup,
    TokenState attack_tokens,
    TokenState defense_tokens)
{
    auto states = new SimulationStateSet();
    auto finished_states = new SimulationStateSet();

    // Before attack stuff
    // TODO: We might need a better way for these paths to get hit even during stuff like "How to Modify" forms
    // Currently the effects that happen here are mostly inapplicable to those cases though.
    if (setup.attack.predictive_shot && attack_tokens.force > 0)
    {
        attack_tokens.predictive_shot_used = true;
        attack_tokens.force = attack_tokens.force - 1;
    }

    // NOTE: Respect the max force they selected even if it is inconsistent with Luke's current capabilities (2)
    if (setup.defense.luke_pilot && defense_tokens.force < setup.defense.max_force_count)
        defense_tokens.force = defense_tokens.force + 1;

    // Roll attack dice
    {
        SimulationState initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;
        initial_state.probability    = 1.0;

        // NOTE: 0-6 dice rolled after modifiers, as per the rules
        int attack_dice_count = clamp(setup.attack.dice, 0, 6);

        // If "roll all hits" is set just statically add that single option
        if (setup.attack.roll_all_hits)
        {
            initial_state.attack_dice.results[DieResult.Hit] = cast(ubyte)attack_dice_count;
            states.push_back(initial_state);
        }
        else
        {
            // Regular roll
            states.roll_attack_dice(initial_state, attack_dice_count);
        }
    }

    // Modify attack dice (loop until done modifying)
    {
        while (!states.empty())
        {
            SimulationState state = states.pop_back();
            StateFork fork = modify_attack_dice(setup, state);
            if (fork.required())
            {
                states.fork_attack_state(state, fork);
            }
            else
            {
                // After modify dice effects
                if (setup.attack.heavy_laser_cannon)
                    state.attack_dice.change_dice(DieResult.Crit, DieResult.Hit);

                // NOTE: No lightweight frame or equivalent in 2.0 so safe to cancel all non-result dice
                state.attack_dice.finalize();
                state.attack_dice.final_results[DieResult.Focus] = 0;
                state.attack_dice.final_results[DieResult.Blank] = 0;

                // Reset any "once per opportunity" token tracking states (i.e. "did we use this effect yet")
                state.attack_temp.reset();

                finished_states.push_back(state);
            }
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();

        states.compress();
        //writeln(states.length);
    }

    // Roll defense dice        
    {
        while (!states.empty())
        {
            SimulationState state = states.pop_back();

            int defense_dice_count = setup.defense.dice + setup.attack.defense_dice_diff;
            if (state.defense_tokens.stealth_device)
                ++defense_dice_count;

            // If predictive shot was used, clamp defense dice appropriately
            if (state.attack_tokens.predictive_shot_used)
            {
                int hits_crits_count = state.attack_dice.final_results[DieResult.Hit] + state.attack_dice.final_results[DieResult.Crit];
                defense_dice_count = min(defense_dice_count, hits_crits_count);
            }

            // NOTE: 0-6 dice rolled after modifiers, as per the rules
            defense_dice_count = clamp(defense_dice_count, 0, 6);

            finished_states.roll_defense_dice(state, defense_dice_count);
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();

        // No additional states to compress since dice rolling will always be pure divergence
        //writeln(states.length);
    }

    // Modify defense dice (loop until done modifying)
    {
        while (!states.empty())
        {
            SimulationState state = states.pop_back();
            StateFork fork = modify_defense_dice_root(setup, state);
            if (fork.required())
            {
                states.fork_defense_state(state, fork);
            }
            else
            {
                // NOTE: No lightweight frame or equivalent in 2.0 so safe to cancel all non-result dice
                state.defense_dice.finalize();
                state.defense_dice.final_results[DieResult.Focus] = 0;
                state.defense_dice.final_results[DieResult.Blank] = 0;

                // Reset any "once per opportunity" token tracking states (i.e. "did we use this effect yet")
                state.defense_temp.reset();

                finished_states.push_back(state);
            }
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();
        states.compress();
        //writeln(states.length);
    }

    // Neutralize results and "after attack"
    {
        while (!states.empty())
        {
            SimulationState state = neutralize_results(setup, states.pop_back());
            finished_states.push_back(state);
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();
        states.compress();
        //writeln(states.length);
    }

    return states;
}

// Main entry point for simulating a new attack following any previously simulated results
//
// NOTE: Takes the initial state set as non-constant since it needs to sort it, but does not otherwise
// modify the contents. Returns a new state set after this additional attack.
public SimulationStateSet simulate_attack(const(SimulationSetup) setup, SimulationStateSet states)
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

    // Sort our states by tokens so that any matching sets are back to back in the list
    states.sort_by_tokens();

    // There's ways to do this in place but it's simpler for now to just do it to a new state set
    // This function is only called once per attack, so it's not the end of the world
    SimulationStateSet new_states = new SimulationStateSet();

    SimulationStateSet second_attack_states;
    SimulationState second_attack_initial_state;

    foreach (initial_state; states)
    {
        // If our tokens are the same as the previous simulation (we sorted), we don't have to simulate again
        if (initial_state.attack_tokens != second_attack_initial_state.attack_tokens ||
            initial_state.defense_tokens != second_attack_initial_state.defense_tokens ||
            !second_attack_states)
        {
            //auto sw = StopWatch(AutoStart.yes);

            // New token state set, so run a new simulation
            second_attack_initial_state = initial_state;
            second_attack_states = simulate_single_attack(setup,
                                                          second_attack_initial_state.attack_tokens, 
                                                          second_attack_initial_state.defense_tokens);

            //writefln("Second attack in %s msec", sw.peek().msecs());
        }

        // Compose all of the results from the second attack set with this one
        foreach (const second_state; second_attack_states)
        {
            // NOTE: Important to keep the token state and such from after the second attack, not initial one
            SimulationState new_state = second_state;
            new_state.final_hits  += initial_state.final_hits;
            new_state.final_crits += initial_state.final_crits;
            new_state.probability *= initial_state.probability;
            new_states.push_back(new_state);
        }
    }

    // Update our simulation with the new results
    new_states.compress();
    return new_states;
}
