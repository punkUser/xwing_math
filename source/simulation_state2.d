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

public enum GreenToken
{
    Focus = 0,
    Calculate,
    Evade,
    Reinforce
};

// Real tokens/charges/etc. State that needs to be tracked between attacks.
public struct TokenState
{
    mixin(bitfields!(
        uint, "lock",                 2,
        uint, "force",                4,
                                      
        // Green tokens               
        uint, "focus",                4,        
        uint, "calculate",            4,
        uint, "evade",                4,
        uint, "reinforce",            2,
                                      
        // Red tokens                 
        uint, "stress",               4,
                                      
        bool, "lone_wolf",            1,      // Recurrent
        bool, "stealth_device",       1,

        // NOTE: Instead of tracking a single field ion token count, we basically track whether
        // the ship has 1, 2, or 3 ion tokens via 3 bits. The advantage of this is that the token results
        // will automatically tell us the chance of ending up with each of the 3 numbers of tokens, which
        // is really what we want more than the average number, as the 3 counts correspond to the number of
        // required tokens to ionize a small/medium/large base ship respectively.
        // NOTE: if ion_2 is set, ion_1 must be set. Similarly if ion_3 is set ion_2 and ion_1 must both be set.
        // Generally use "add_ion_tokens" helper to manipulate these.
        bool, "ion_1",                1,
        bool, "ion_2",                1,
        bool, "ion_3",                1,
                                      
        bool, "iden",                 1,
        uint, "iden_total_damage",    2,      // tracking for Iden (persistent)
                                      
        bool, "l337",                 1,
        bool, "elusive",              1,

        // TODO: want to move this to a temp state, but needs to stick around until end of attack
        bool, "spent_calculate",      1,      // tracking for Leebo
        bool, "iden_used",            1,      // tracking so we can treat the attack as "hitting"
        bool, "predictive_shot_used", 1,      // tracking for Predictive Shot use at start of attack

        uint, "",                    27,
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

    uint count(GreenToken token) const
    {
        switch (token) {
            case GreenToken.Focus:      return focus;
            case GreenToken.Calculate:  return calculate;
            case GreenToken.Evade:      return evade;
            case GreenToken.Reinforce:  return reinforce;
            default: assert(false);
        }
    }

    uint green_token_count() const
    {
        return focus + calculate + evade + reinforce;
    }
}
//pragma(msg, "sizeof(TokenState) = " ~ to!string(TokenState.sizeof));

// For TokenResults
// Order here is the order they will be shown in the chart and table
public static immutable TokenResults.Field[] k_token_results2_fields = [
    { "lock",                "Lock"              },
    { "force",               "Force"             },
    { "focus",               "Focus"             },
    { "calculate",           "Calculate"         },
    { "evade",               "Evade"             },
    { "reinforce",           "Reinforce"         },
    { "stress",              "Stress"            },
    { "elusive",             "Elusive"           },
    { "iden",                "Iden"              },
    { "l337",                "L3-37"             },
    { "lone_wolf",           "Lone Wolf"         },    
    { "stealth_device",      "Stealth Device"    },
    { "ion_1",               "Ionized (1)"       },
    { "ion_2",               "Ionized (2)"       },
    { "ion_3",               "Ionized (3)"       },
];

// These fields are for tracking "once per opportunity" or other stuff that gets
// reset after modding completes and does not carry on to the next phase/attack.
// NOTE: In practice these fields get reset for the attacker after attack dice modding is done, and similar for defender.
// NOTE: Some of these fields are technically not required to be tracked for simulation purposes (usually because
// they only ever happen at a fixed point in the modify step, once), but we sometimes still track them for the
// purpose of outputting more useful modify_tree states.

struct AttackTempState
{
    mixin(bitfields!(
        bool, "finished_after_rolling",                 1,      // finished opportunity to do "after rolling" abilities
        bool, "finished_dmad",                          1,      // finished defender modding attack dice
        bool, "finished_amad",                          1,      // finished attacker modding attack dice
        bool, "cannot_spend_lock",                      1,      // ex. after using fire-control system
        bool, "used_advanced_targeting_computer",       1,
        bool, "used_add_results",                       1,
        uint, "used_reroll_1_count",                    3,
        uint, "used_reroll_2_count",                    3,      // Up to 2 dice
        uint, "used_reroll_3_count",                    3,      // Up to 3 dice
        bool, "used_shara_bey_pilot",                   1,
        bool, "used_scum_lando_crew",                   1,
        bool, "used_scum_lando_pilot",                  1,
        uint,  "",                                     14,
    ));

    void reset()
    {
        this = AttackTempState.init;
    }
}

struct DefenseTempState
{
    mixin(bitfields!(
        bool, "finished_after_rolling",                 1,      // finished opportunity to do "after rolling" abilities
        bool, "finished_amdd",                          1,      // finished attacker modding defense dice
        bool, "finished_dmdd",                          1,      // finished defender modding defense dice
        bool, "used_c3p0",                              1,
        bool, "used_add_results",                       1,
        uint, "used_reroll_1_count",                    3,
        uint, "used_reroll_2_count",                    3,      // Up to 2 dice
        uint, "used_reroll_3_count",                    3,      // Up to 3 dice
        bool, "used_shara_bey_pilot",                   1,
        bool, "used_scum_lando_crew",                   1,
        bool, "used_rebel_millennium_falcon",           1,
        bool, "used_scum_lando_pilot",                  1,
        uint, "",                                      14,
        ));

    void reset()
    {
        this = DefenseTempState.init;
    }
}


// Useful structure for indicating how to fork state to a caller
public enum StateForkType : int
{
    None = 0,       // No fork needed
    Reroll,         // Reroll dice into _rerolled pool (most common!)
    Roll,           // Roll dice into regular dice pool that can be rerolled (stuff like rebel Han pilot)
};

public struct StateFork
{
    bool required() const { return type != StateForkType.None; }

    // TODO: Could be a more complicated Variant enum or similar in the long run but this is fine for now
    StateForkType type = StateForkType.None;
    int roll_count = 0;         // for Reroll and Roll
};

// Associated factor methods for convenience
public StateFork StateForkNone()
{   
    return StateFork();
}
public StateFork StateForkReroll(int count)
{   
    assert(count > 0);
    StateFork fork;
    fork.type = StateForkType.Reroll;
    fork.roll_count = count;
    return fork;
}
public StateFork StateForkRoll(int count)
{
    assert(count > 0);
    StateFork fork;
    fork.type = StateForkType.Roll;
    fork.roll_count = count;
    return fork;
}


public struct SimulationState
{
    struct Key
    {
        // TODO: Can move the "_temp" stuff out the key to make comparison/sorting slightly faster,
        // but need to ensure that they are reset at exactly the right places.
        DiceState        attack_dice;
        TokenState       attack_tokens;
        AttackTempState  attack_temp;
        DiceState        defense_dice;
        TokenState       defense_tokens;
        DefenseTempState defense_temp;

        // Final results
        ubyte final_hits = 0;
        ubyte final_crits = 0;
    }

    Key key;
    double probability = 1.0;

    // Convenient to allow fields from the key to be accessed directly as state.X rather than state.key.X
    alias key this;

    // Compare only the key portion of the state
    int opCmp(ref const SimulationState s) const
    {
        // TODO: Optimize this more for common early outs?
        return memcmp(&this.key, &s.key, Key.sizeof);
    }
    bool opEquals(ref const SimulationState s) const
    { 
        // TODO: Optimize this more for common early outs?
        return (this.key == s.key);
    }
}
//pragma(msg, "sizeof(SimulationState) = " ~ to!string(SimulationState.sizeof));



// State forking utilities

// delegate params are next_state, probability (also already baked into next_state probability)
public void roll_attack_dice(bool reroll)(SimulationState prev_state, int dice_count, void delegate(SimulationState, double) dg)
{
    dice.roll_attack_dice(dice_count, (int blank, int focus, int hit, int crit, double probability) {
        SimulationState next_state = prev_state;
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
        dg(next_state, probability);
    });
}

// delegate params are next_state, probability (also already baked into next_state probability)
public void roll_defense_dice(bool reroll)(SimulationState prev_state, int dice_count, void delegate(SimulationState, double) dg)
{
    dice.roll_defense_dice(dice_count, (int blank, int focus, int evade, double probability) {
        SimulationState next_state = prev_state;
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
        dg(next_state, probability);
    });
}









public class SimulationStateSet
{
    public this()
    {
        // TODO: Experiment with this
        m_states.reserve(50);
    }

    // Replaces the attack tokens on *all* current states with the given ones
    // Generally this is done in preparation for simulating another attack *from a different attacker*
    public void replace_attack_tokens(TokenState attack_tokens)
    {
        foreach (ref state; m_states)
            state.attack_tokens = attack_tokens;
        compress();
    }

    // Re-sorts the array by tokens, ensuring that any states with matching tokens are sequential
    public void sort_by_tokens()
    {
        multiSort!(
            (a, b) => memcmp(&a.attack_tokens,  &b.attack_tokens,  TokenState.sizeof) < 0,
            (a, b) => memcmp(&a.defense_tokens, &b.defense_tokens, TokenState.sizeof) < 0,
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
        SimulationState write_state = m_states.front();
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
        // Write last element and read just length
        m_states[write_count++] = write_state;
        m_states.length = write_count;
    }

    // Removes any states that have total hits >= the given value and returns their combined probability
    // NOTE: We could generalize this to take an arbitrary predicate, but this is all we need for now.
    double remove_if_total_hits_ge(int target_hits)
    {
        // Partition into states to keep on the left and states to drop on the right        
        bool total_hits_less(ref const(SimulationState) s) { return s.final_hits + s.final_crits < target_hits; }
        auto remove_elements = partition!(total_hits_less)(m_states[]);

        double removed_p = 0.0;
        foreach (ref s; remove_elements)
            removed_p += s.probability;

        m_states.length = m_states.length - remove_elements.length;
        return removed_p;
    }

    // If "reroll" is set the dice will be put into the "rerolled_results" pool, otherwise into the regular "results" pool.
    public void roll_attack_dice(bool reroll)(SimulationState prev_state, int dice_count)
    {
        .roll_attack_dice!reroll(prev_state, dice_count, (SimulationState next_state, double probability) {
            push_back(next_state);
        });
    }

    // If "reroll" is set the dice will be put into the "rerolled_results" pool, otherwise into the regular "results" pool.
    public void roll_defense_dice(bool reroll)(SimulationState prev_state, int dice_count)
    {
        .roll_defense_dice!reroll(prev_state, dice_count, (SimulationState next_state, double probability) {
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
            SimulationState state = m_states[i];

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

    public SimulationState pop_back()
    {
        SimulationState back = m_states.back();
        m_states.removeBack();
        return back;
    }
    public void push_back(SimulationState v)
    {
        m_states.insertBack(v);
    }

    // Support foreach over m_states, but read only
    int opApply(int delegate(ref const(SimulationState)) operations) const
    {
        int result = 0;
        foreach (ref const(SimulationState) state; m_states) {
            result = operations(state);
            if (result) {
                break;
            }
        }
        return result;
    }

    private Array!SimulationState m_states;
};

