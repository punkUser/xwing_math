import dice;

import std.math;
import core.stdc.string;

import vibe.utils.hashmap;

// TODO: Can generalize this but okay for now
// Do it in floating point since for our purposes we always end up converting immediately anyways
private static immutable double[] k_factorials_table = [
    1,                  // 0!
    1,                  // 1!
    2,                  // 2!
    6,                  // 3!
    24,                 // 4!
    120,                // 5!
    720,                // 6!
    5040,               // 7!
    40320,              // 8!
    362880,             // 9!
    3628800,            // 10!
    39916800,			// 11!
    479001600,			// 12!
    6227020800,			// 13!
    87178291200,		// 14!
];

private pure double factorial(int n)
{
    assert(n < k_factorials_table.length);
    return k_factorials_table[n];
}


// Multinomial distribution: https://en.wikipedia.org/wiki/Multinomial_distribution
// roll_probability = n! / (x_1! * ... * x_k!) * p_1^x_1 * ... p_k^x_k
// NOTE: Can optimize power functions into a table fairly easily as well but performance
// improvement is negligable and readability is greater this way.

private pure double compute_attack_roll_probability(int blank, int focus, int hit, int crit)
{
    // P(blank) = 2/8
    // P(focus) = 2/8
    // P(hit)   = 3/8
    // P(crit)  = 1/8
    double nf = factorial(blank + focus + hit + crit);
    double xf = (factorial(blank) * factorial(focus) * factorial(hit) * factorial(crit));
    double p = pow(0.25, blank + focus) * pow(0.375, hit) * pow(0.125, crit);

    double roll_probability = (nf / xf) * p;

    assert(roll_probability >= 0.0 && roll_probability <= 1.0);
    return roll_probability;
}

private pure double compute_defense_roll_probability(int blank, int focus, int evade)
{
    // P(blank) = 3/8
    // P(focus) = 2/8
    // P(evade) = 3/8
    double nf = factorial(blank + focus + evade);
    double xf = (factorial(blank) * factorial(focus) * factorial(evade));
    double p = pow(0.375, blank + evade) * pow(0.25, focus);

    double roll_probability = (nf / xf) * p;

    assert(roll_probability >= 0.0 && roll_probability <= 1.0);
    return roll_probability;
}



public struct TokenState
{
    int focus = 0;
    int evade = 0;
    int target_lock = 0;
    int stress = 0;

	// Available once per turn abilities
	bool amad_any_to_hit = false;
	bool amad_any_to_crit = false;

    int opCmp(ref const TokenState s) const
    {
        return memcmp(&this, &s, TokenState.sizeof);
    }
}

public struct SimulationState
{
    DiceState attack_dice;
    TokenState attack_tokens;
    DiceState defense_dice;
    TokenState defense_tokens;

    // Information for next stage of iteration
    int dice_to_reroll = 0;

    // Final results (multi-attack, etc)
    int completed_attack_count = 0;
    int final_hits = 0;
    int final_crits = 0;

    // TODO: Since this is such an important part of the simulation process now, we should compress
    // the size of this structure and implement (and test!) a proper custom hash function.
}

// Maps state -> probability
public alias SimulationStateMap = double[SimulationState];
//public alias SimulationStateMap = HashMap!(SimulationState, double);

public alias ForkDiceDelegate = SimulationState delegate(SimulationState state);

// Utility to either insert a new state into the map, or accumualte probability if already present
public void append_state(ref SimulationStateMap map, SimulationState state, double probability)
{
    auto i = (state in map);
    if (i)
    {
        //writefln("Append state: %s", state);
        *i += probability;
    }
    else
    {
        //writefln("New state: %s", state);
        map[state] = probability;
    }
}

// Take all previous states, roll state.dice_roll attack dice, call "cb" delegate on each of them,
// accumulate into new states depending on uniqueness of the key and return the new map.
// TODO: Probably makes sense to have a cleaner division between initial roll and rerolls at this point
// considering it complicates the calling code a bit too (having to put things into state.dice_to_roll)
public SimulationStateMap exhaustive_roll_attack_dice(bool initial_roll)(
    ref const(SimulationStateMap) prev_states,
    ForkDiceDelegate cb,
    int initial_roll_dice = 0)
{
    SimulationStateMap next_states;
    foreach (state, state_probability; prev_states)
    {
        int count = initial_roll ? initial_roll_dice : state.dice_to_reroll;

        double total_fork_probability = 0.0f;            // Just for debug
        for (int crit = 0; crit <= count; ++crit)
        {
            for (int hit = 0; hit <= (count - crit); ++hit)
            {
                for (int focus = 0; focus <= (count - crit - hit); ++focus)
                {
                    int blank = count - crit - hit - focus;
                    assert(blank >= 0);

                    // Add dice to the relevant pool
                    SimulationState new_state = state;
                    new_state.dice_to_reroll = 0;
                    if (initial_roll)
                    {
                        new_state.attack_dice.results[DieResult.Crit]  += crit;
                        new_state.attack_dice.results[DieResult.Hit]   += hit;
                        new_state.attack_dice.results[DieResult.Focus] += focus;
                        new_state.attack_dice.results[DieResult.Blank] += blank;
                    }
                    else
                    {
                        new_state.attack_dice.rerolled_results[DieResult.Crit]  += crit;
                        new_state.attack_dice.rerolled_results[DieResult.Hit]   += hit;
                        new_state.attack_dice.rerolled_results[DieResult.Focus] += focus;
                        new_state.attack_dice.rerolled_results[DieResult.Blank] += blank;
                    }

                    double roll_probability = compute_attack_roll_probability(blank, focus, hit, crit);
                    
                    total_fork_probability += roll_probability;
                    assert(total_fork_probability >= 0.0 && total_fork_probability <= 1.0);

                    double next_state_probability = roll_probability * state_probability;
                    append_state(next_states, cb(new_state), next_state_probability);
                }
            }
        }

        // Total probability of our fork loop should be very close to 1, modulo numeric precision
        assert(abs(total_fork_probability - 1.0) < 1e-6);
    }

    //writefln("After %s attack states: %s", initial_roll ? "initial" : "reroll", next_states.length);
    return next_states;
}

public SimulationStateMap exhaustive_roll_defense_dice(bool initial_roll)(
    ref const(SimulationStateMap) prev_states,
    ForkDiceDelegate cb, 
    int initial_roll_dice = 0)
{
    SimulationStateMap next_states;
    foreach (state, state_probability; prev_states)
    {
        int count = initial_roll ? initial_roll_dice : state.dice_to_reroll;

        double total_fork_probability = 0.0f;            // Just for debug
        for (int evade = 0; evade <= count; ++evade)
        {
            for (int focus = 0; focus <= (count - evade); ++focus)
            {
                int blank = count - focus - evade;
                assert(blank >= 0);

                // Add dice to the relevant pool
                SimulationState new_state = state;
                new_state.dice_to_reroll = 0;
                if (initial_roll)
                {
                    new_state.defense_dice.results[DieResult.Evade] += evade;
                    new_state.defense_dice.results[DieResult.Focus] += focus;
                    new_state.defense_dice.results[DieResult.Blank] += blank;
                }
                else
                {
                    new_state.defense_dice.rerolled_results[DieResult.Evade] += evade;
                    new_state.defense_dice.rerolled_results[DieResult.Focus] += focus;
                    new_state.defense_dice.rerolled_results[DieResult.Blank] += blank;
                }                

                double roll_probability = compute_defense_roll_probability(blank, focus, evade);
                
                total_fork_probability += roll_probability;
                assert(total_fork_probability >= 0.0 && total_fork_probability <= 1.0);

                double next_state_probability = roll_probability * state_probability;
                append_state(next_states, cb(new_state), next_state_probability);
            }
        }

        // Total probability of our fork loop should be very close to 1, modulo numeric precision
        assert(abs(total_fork_probability - 1.0) < 1e-6);
    }

    //writefln("After %s defense states: %s", initial_roll ? "initial" : "reroll", next_states.length);
    return next_states;
}