import dice;
import math;
import simulation_results;

import std.math;
import core.stdc.string;
import std.bitmanip;
import std.container.array;
import std.algorithm;
import std.stdio;
import std.conv;

// Real tokens/charges/etc. State that needs to be tracked between attacks.
public struct TokenState2
{
    mixin(bitfields!(
        uint, "lock",               3,
        uint, "force",              3,

        // Green tokens
        uint, "focus",              3,        
        uint, "calculate",          3,
        uint, "evade",              3,
        uint, "reinforce",          3,

        // Red tokens
        uint, "stress",             3,
        //uint, "jam",                3,
        // Jam, tractor, disarm not currently used. Ion below

        bool, "lone_wolf",          1,
        bool, "spent_calculate",    1,       // tracking for Leebo... TODO: want to move this to a temp state, but needs to stick around until end of attack
        bool, "stealth_device",     1,

        // NOTE: Instead of tracking a single field ion token count, we basically track whether
        // the ship has 1, 2, or 3 ion tokens via 3 bits. The advantage of this is that the token results
        // will automatically tell us the chance of ending up with each of the 3 numbers of tokens, which
        // is really what we want more than the average number, as the 3 counts correspond to the number of
        // required tokens to ionize a small/medium/large base ship respectively.
        // NOTE: if ion_2 is set, ion_1 must be set. Similarly if ion_3 is set ion_2 and ion_1 must both be set.
        // Generally use "add_ion_tokens" helper to manipulate these.
        bool, "ion_1",              1,
        bool, "ion_2",              1,
        bool, "ion_3",              1,

        bool, "iden",               1,
        uint, "iden_total_damage",  2,       // tracking for Iden

        bool, "l337",               1,

        uint, "",                   1,
        )
    );

    // Utilities
    void add_ion_tokens(int count)
    {
        while (count > 0)
        {
            if      (ion_2) ion_3 = true;
            else if (ion_1) ion_2 = true;
            else            ion_1 = true;
            --count;
        }
    }
}
//pragma(msg, "sizeof(TokenState2) = " ~ to!string(TokenState2.sizeof));

// For TokenResults
// Order here is the order they will be shown in the chart and table
public static immutable TokenResults.Field[] k_token_results2_fields = [
    { "lock",                               "Lock"              },
    { "force",                              "Force"             },
    { "focus",                              "Focus"             },
    { "calculate",                          "Calculate"         },
    { "evade",                              "Evade"             },
    { "reinforce",                          "Reinforce"         },
    { "stress",                             "Stress"            },
    { "lone_wolf",                          "Lone Wolf"         },
    { "stealth_device",                     "Stealth Device"    },
    { "iden",                               "Iden"              },
    { "l337",                               "L3-37"             },
    { "ion_1",                              "Ionized (1)"       },
    { "ion_2",                              "Ionized (2)"       },
    { "ion_3",                              "Ionized (3)"       },
];

// These fields are for tracking "once per opportunity" or other stuff that gets
// reset after modding completes and does not carry on to the next phase/attack.
// NOTE: In practice these fields get reset for the attacker after attack dice modding is done, and similar for defender.
// NOTE: Some of these fields are technically not required to be tracked for simulation purposes (usually because
// they only ever happen at a fixed point in the modify step, once), but we sometimes still track them for the
// purpose of outputting more useful modify_tree states.

struct AttackTempState2
{
    mixin(bitfields!(
        bool, "finished_after_rolling",                 1,      // finished opportunity to do "after rolling" abilities
        bool, "finished_dmad",                          1,      // finished defender modding attack dice
        bool, "finished_amad",                          1,      // finished attacker modding attack dice
        bool, "cannot_spend_lock",                      1,      // ex. after using fire-control system
        bool, "used_advanced_targeting_computer",       1,
        uint, "used_reroll_1_count",                    3,
        uint, "used_reroll_2_count",                    3,      // Up to 2 dice
        uint, "used_reroll_3_count",                    3,      // Up to 3 dice
        uint, "used_any_to_hit_count",                  3,
        uint, "used_hit_to_crit_count",                 3,
        bool, "used_shara_bey_pilot",                   1,
        uint,  "",                                     11,
    ));

    void reset()
    {
        this = AttackTempState2.init;
    }
}

struct DefenseTempState2
{
    mixin(bitfields!(
        bool, "finished_after_rolling",                 1,      // finished opportunity to do "after rolling" abilities
        bool, "finished_amdd",                          1,      // finished attacker modding defense dice
        bool, "finished_dmdd",                          1,      // finished defender modding defense dice
        bool, "used_c3p0",                              1,
        uint, "used_reroll_1_count",                    3,
        uint, "used_reroll_2_count",                    3,      // Up to 2 dice
        uint, "used_reroll_3_count",                    3,      // Up to 3 dice
        uint, "used_any_to_evade_count",                3,
        uint, "used_add_evade_count",                   3,
        bool, "used_shara_bey_pilot",                   1,
        uint, "",                                      12,
        ));

    void reset()
    {
        this = DefenseTempState2.init;
    }
}



public struct SimulationState2
{
    struct Key
    {
        // TODO: Can move the "_temp" stuff out the key to make comparison/sorting slightly faster,
        // but need to ensure that they are reset at exactly the right places.
        DiceState         attack_dice;
        TokenState2       attack_tokens;
        AttackTempState2  attack_temp;
        DiceState         defense_dice;
        TokenState2       defense_tokens;
        DefenseTempState2 defense_temp;

        // Final results
        ubyte final_hits = 0;
        ubyte final_crits = 0;
    }

    Key key;
    double probability = 1.0;

    // Convenient to allow fields from the key to be accessed directly as state.X rather than state.key.X
    alias key this;

    // Compare only the key portion of the state
    int opCmp(ref const SimulationState2 s) const
    {
        // TODO: Optimize this more for common early outs?
        return memcmp(&this.key, &s.key, Key.sizeof);
    }
    bool opEquals(ref const SimulationState2 s) const
    { 
        // TODO: Optimize this more for common early outs?
        return (this.key == s.key);
    }
}
//pragma(msg, "sizeof(SimulationState2) = " ~ to!string(SimulationState2.sizeof));

public class SimulationStateSet2
{
    public this()
    {
        // TODO: Experiment with this
        m_states.reserve(50);
    }

    // Replaces the attack tokens on *all* current states with the given ones
    // Generally this is done in preparation for simulating another attack *from a different attacker*
    public void replace_attack_tokens(TokenState2 attack_tokens)
    {
        foreach (ref state; m_states)
            state.attack_tokens = attack_tokens;
        compress();
    }

    // Re-sorts the array by tokens, ensuring that any states with matching tokens are sequential
    public void sort_by_tokens()
    {
        multiSort!(
            (a, b) => memcmp(&a.attack_tokens,  &b.attack_tokens,  TokenState2.sizeof) < 0,
            (a, b) => memcmp(&a.defense_tokens, &b.defense_tokens, TokenState2.sizeof) < 0,
            SwapStrategy.unstable)(m_states[]);
    }

    // Compresses and simplifies the state set by combining any elements that match and
    // adding their probabilities together. This is very important for performance and states
    // should be simplified as much as possible before calling this to allow as many state collapses
    // as possible.
    public void compress()
    {
        if (m_states.empty()) return;

        // TODO: Some debug/profiling

        // First sort so that any matching keys are back to back
        sort!((a, b) => memcmp(&a.key, &b.key, a.key.sizeof) < 0)(m_states[]);

        // Then walk through the array and combine elements that match their predecessors
        SimulationState2 write_state = m_states.front();
        size_t write_count = 0;
        foreach (i; 1..m_states.length)
        {
            if (m_states[i] == write_state)
            {
                // State matches, combine
                write_state.probability += m_states[i].probability;
            }
            else
            {
                // State does not match; store the current write state and move on
                m_states[write_count] = write_state;
                ++write_count;
                write_state = m_states[i];
            }
        }
        // Write last element and readjust length
        m_states[write_count++] = write_state;
        m_states.length = write_count;
    }

    // If "reroll" is set the dice will be put into the "rerolled_results" pool, otherwise into the regular "results" pool.
    public void roll_attack_dice(bool reroll)(SimulationState2 prev_state, int dice_count)
    {
        dice.roll_attack_dice(dice_count, (int blank, int focus, int hit, int crit, double probability) {
            SimulationState2 next_state = prev_state;
            static if (reroll)
            {
                next_state.attack_dice.rerolled_results[DieResult.Crit]  += crit;
                next_state.attack_dice.rerolled_results[DieResult.Hit]   += hit;
                next_state.attack_dice.rerolled_results[DieResult.Focus] += focus;
                next_state.attack_dice.rerolled_results[DieResult.Blank] += blank;
            }
            else
            {
                next_state.attack_dice.results[DieResult.Crit]  += crit;
                next_state.attack_dice.results[DieResult.Hit]   += hit;
                next_state.attack_dice.results[DieResult.Focus] += focus;
                next_state.attack_dice.results[DieResult.Blank] += blank;
            }
            next_state.probability *= probability;
            push_back(next_state);
        });
    }

    // If "reroll" is set the dice will be put into the "rerolled_results" pool, otherwise into the regular "results" pool.
    public void roll_defense_dice(bool reroll)(SimulationState2 prev_state, int dice_count)
    {
        dice.roll_defense_dice(dice_count, (int blank, int focus, int evade, double probability) {
            SimulationState2 next_state = prev_state;
            static if (reroll)
            {
                next_state.defense_dice.rerolled_results[DieResult.Evade] += evade;
                next_state.defense_dice.rerolled_results[DieResult.Focus] += focus;
                next_state.defense_dice.rerolled_results[DieResult.Blank] += blank;
            }
            else
            {
                next_state.defense_dice.results[DieResult.Evade] += evade;
                next_state.defense_dice.results[DieResult.Focus] += focus;
                next_state.defense_dice.results[DieResult.Blank] += blank;
            }
            next_state.probability *= probability;
            push_back(next_state);
        });
    }

    public SimulationResults compute_results() const
    {
        SimulationResults results;

        // TODO: Could scan through m_states to see the required size, but this is good enough for now
        results.total_hits_pdf = new SimulationResult[1];
        foreach (ref i; results.total_hits_pdf)
            i = SimulationResult.init;

        foreach (i; 0 .. m_states.length)
        {
            SimulationState2 state = m_states[i];

            // Compute final results of this simulation step
            SimulationResult result;
            result.probability  = state.probability;
            result.hits         = state.probability * cast(double)state.final_hits;
            result.crits        = state.probability * cast(double)state.final_crits;
            result.attack_tokens.initialize !k_token_results2_fields(state.probability, state.attack_tokens);
            result.defense_tokens.initialize!k_token_results2_fields(state.probability, state.defense_tokens);

            // Accumulate into the total results structure
            results.total_sum = accumulate_result(results.total_sum, result);

            // Accumulate into the right bin of the total hits PDF
            int total_hits = state.final_hits + state.final_crits;
            if (total_hits >= results.total_hits_pdf.length)
                results.total_hits_pdf.length = total_hits + 1;
            results.total_hits_pdf[total_hits] = accumulate_result(results.total_hits_pdf[total_hits], result);

            // If there was at least one uncanceled crit, accumulate probability
            if (state.final_crits > 0)
                results.at_least_one_crit_probability += state.probability;
        }

        return results;
    }

    public @property size_t length() const { return m_states.length; }
    public bool empty() const { return m_states.empty(); }
    public void clear_for_reuse() { m_states.length = 0; }

    public SimulationState2 pop_back()
    {
        SimulationState2 back = m_states.back();
        m_states.removeBack();
        return back;
    }
    public void push_back(SimulationState2 v)
    {
        m_states.insertBack(v);
    }

    // Support foreach over m_states, but read only
    int opApply(int delegate(ref const(SimulationState2)) operations) const
    {
        int result = 0;
        foreach (ref const(SimulationState2) state; m_states) {
            result = operations(state);
            if (result) {
                break;
            }
        }
        return result;
    }

    private Array!SimulationState2 m_states;
};

