import dice;
import math;
import simulation_results;

import std.math;
import core.stdc.string;
import std.bitmanip;

public struct TokenState
{
    ubyte focus = 0;
    ubyte evade = 0;
    ubyte target_lock = 0;
    ubyte stress = 0;

    // Available once per round/turn abilities
    // Bitfield since it's important this structure remain small as it is part of the hashes...
    mixin(bitfields!(
        bool, "amad_any_to_hit",                      1,
        bool, "amad_any_to_crit",                     1,
        bool, "sunny_bounder",                        1,        // Both attack and defense
        bool, "c3p0",                                 1,
        bool, "palpatine",                            1,        // Both attack (crit) and defense (evade)
        bool, "crack_shot",                           1,
        bool, "stealth_device",                       1,
        int,  "",                                     1)
    );

    mixin(bitfields!(
        uint, "harpooned",                            3,        // Harpooned condition count (0..7)
        int, "",                                      5)
    );

    int opCmp(ref const TokenState s) const
    {
        return memcmp(&this, &s, TokenState.sizeof);
    }
}

// For TokenResults
// Order here is the order they will be shown in the chart and table
public static immutable TokenResults.Field[] k_token_results_fields = [
    { "focus",                  "Focus"             },
    { "evade",                  "Evade"             },
    { "target_lock",            "Target Lock"       },
    { "stress",                 "Stress"            },
    { "amad_any_to_hit",        "Chips (hit)"       },
    { "amad_any_to_crit",       "Chips (crit)"      },
    { "crack_shot",             "Crack Shot"        },
    { "harpooned",              "Harpooned!"        },
    { "palpatine",              "Palpatine"         },
    { "c3p0",                   "C-3P0"             },
    { "stealth_device",         "Stealth Device"    },
];


public struct SimulationState
{
    DiceState attack_dice;
    DiceState defense_dice;

    TokenState attack_tokens;
    TokenState defense_tokens;

    // Information for next stage
    // NOTE: Remember to reset this between stages as appropriate!
    ubyte dice_to_reroll = 0;

    // Final results (multi-attack, etc)
    ubyte final_hits = 0;
    ubyte final_crits = 0;
    bool attack_hit = false;

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
    if (i !is null)
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
public SimulationStateMap roll_attack_dice(bool initial_roll)(
    ref const(SimulationStateMap) prev_states,
    ForkDiceDelegate cb,
    ubyte initial_roll_dice = 0)
{
    SimulationStateMap next_states;
    foreach (ref state, state_probability; prev_states)
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

public SimulationStateMap roll_defense_dice(bool initial_roll)(
    ref const(SimulationStateMap) prev_states,
    ForkDiceDelegate cb, 
    ubyte initial_roll_dice = 0)
{
    SimulationStateMap next_states;

    foreach (ref state, state_probability; prev_states)
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