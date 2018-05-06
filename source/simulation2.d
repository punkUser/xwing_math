import simulation_state2;
import dice;

import std.algorithm;
import std.stdio;
import std.datetime;

import vibe.core.core;

// TODO: We can probably unify this with 1.0
struct SimulationResult2
{
    double probability = 0.0f;
    double hits = 0;
    double crits = 0;

    // TODO: Tokens
    //TokenDelta attack_token_delta;
    //TokenDelta defense_token_delta;
};

SimulationResult2 accumulate_result(SimulationResult2 a, SimulationResult2 b)
{
    a.probability += b.probability;
    a.hits += b.hits;
    a.crits += b.crits;
    //a.attack_token_delta  += b.attack_token_delta;
    //a.defense_token_delta += b.defense_token_delta;
    return a;
}

struct SimulationResults2
{
    SimulationResult2[] total_hits_pdf;
    SimulationResult2 total_sum;
    double at_least_one_crit_probability = 0.0;
};

//-----------------------------------------------------------------------------------




class Simulation
{
    // Returns full set of states after result comparison (results put into state.final_hits, etc)
    private SimulationStateMap2 simulate_single_attack(TokenState2 attack_tokens,
                                                       TokenState2 defense_tokens) const
    {
        SimulationState2 initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;

        SimulationStateMap2 states;
        states[initial_state] = 1.0f;

        // TODO

        return states;
    }

    public this(TokenState2 attack_tokens, TokenState2 defense_tokens)
    {
        m_initial_attack_tokens  = attack_tokens;
        m_initial_defense_tokens = defense_tokens;

        // Set up the initial state
        SimulationState2 initial_state;
        initial_state.attack_tokens  = attack_tokens;
        initial_state.defense_tokens = defense_tokens;
        m_states[initial_state] = 1.0f;
    }

    // Replaces the attack tokens on *all* current states with the given ones
    // Generally this is done in preparation for simulating another attack *from a different attacker*
    // Note that this also replaces the "initial" attack tokens so that the deltas are at least meaningful for any following attacks.
    public void replace_attack_tokens(TokenState2 attack_tokens)
    {
        m_initial_attack_tokens = attack_tokens;

        SimulationStateMap2 new_states;
        foreach (state, probability; m_states)
        {
            state.attack_tokens = attack_tokens;
            append_state(new_states, state, probability);
        }
        m_states = new_states;
    }

    // Main entry point for simulating a new attack following any previously simulated results
    //
    // If "final attack" is set for either attacker or defender, it may use tokens or abilities that it
    // would otherwise save. Usually this is only for minor things like changing hits to crits or similar since
    // the attacker will always try and get as many hits as possible and so on.
    //
    public void simulate_attack(
                                bool attacker_final_attack,
                                bool defender_final_attack)
    {
        // Update internal state (just more convenient than passing it around every time)
        m_attacker_final_attack = attacker_final_attack;
        m_defender_final_attack = defender_final_attack;

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

        SimulationStateMap2 new_states;
        int second_attack_evaluations = 0;

        // Sort our states by tokens so that any matching sets are back to back in the list
        SimulationState2[] initial_states_list = m_states.keys.dup;
        multiSort!("a.attack_tokens < b.attack_tokens", "a.defense_tokens < b.defense_tokens")(initial_states_list);

        TokenState2 last_attack_tokens;
        TokenState2 last_defense_tokens;
        // Hacky just to ensure these don't match the first element
        last_attack_tokens.focus = initial_states_list[0].attack_tokens.focus;
        ++last_attack_tokens.focus;

        SimulationStateMap2 second_attack_states;

        foreach (ref initial_state; initial_states_list)
        {
            // If our tokens are the same as the previous simulation (we sorted), we don't have to simulate again
            if (initial_state.attack_tokens != last_attack_tokens ||
                initial_state.defense_tokens != last_defense_tokens)
            {
                // This can be expensive for lots of states so worth allowing other things to run occasionally
                vibe.core.core.yield();

                //auto sw = StopWatch(AutoStart.yes);

                // New token state set, so run a new simulation
                last_attack_tokens = initial_state.attack_tokens;
                last_defense_tokens = initial_state.defense_tokens;

                second_attack_states = simulate_single_attack(last_attack_tokens, last_defense_tokens);
                ++second_attack_evaluations;

                //writefln("Second attack in %s msec", sw.peek().msecs());
            }

            // Compose all of the results from the second attack set with this one
            auto initial_probability = m_states[initial_state];
            foreach (ref second_attack_state, second_probability; second_attack_states)
            {
                // NOTE: Important to keep the token state and such from after the second attack, not initial one
                SimulationState2 new_state = second_attack_state;
                new_state.final_hits  += initial_state.final_hits;
                new_state.final_crits += initial_state.final_crits;
                append_state(new_states, new_state, initial_probability * second_probability);
            }
        }

        // Update our simulation with the new results
        m_states = new_states;
    }
 
    public SimulationResults2 compute_results() const
    {
        SimulationResults2 results;

        // TODO: Could scan through m_states to see the required size, but this is good enough for now
        results.total_hits_pdf = new SimulationResult2[1];
        foreach (ref i; results.total_hits_pdf)
            i = SimulationResult2.init;

        foreach (ref state, probability; m_states)
        {
            // Compute final results of this simulation step
            SimulationResult2 result;
            result.probability = probability;

            result.hits  = probability * cast(double)state.final_hits;
            result.crits = probability * cast(double)state.final_crits;

            // TODO: Sort out tokens for 1.0 vs 2.0
            //result.attack_token_delta  = TokenDelta(probability, m_initial_attack_tokens,  state.attack_tokens);
            //result.defense_token_delta = TokenDelta(probability, m_initial_defense_tokens, state.defense_tokens);
        
            // Accumulate into the total results structure
            results.total_sum = accumulate_result(results.total_sum, result);

            // Accumulate into the right bin of the total hits PDF
            int total_hits = state.final_hits + state.final_crits;
            if (total_hits >= results.total_hits_pdf.length)
                results.total_hits_pdf.length = total_hits + 1;
            results.total_hits_pdf[total_hits] = accumulate_result(results.total_hits_pdf[total_hits], result);

            // If there was at least one uncanceled crit, accumulate probability
            if (state.final_crits > 0)
                results.at_least_one_crit_probability += probability;
        }

        return results;
    }

    // These are the core states that are updated as attacks chain
    private SimulationStateMap2 m_states;

    // Copies of the initial tokens
    private TokenState2 m_initial_attack_tokens;
    private TokenState2 m_initial_defense_tokens;

    // Store copies of the constant state for the current attack
    private bool m_attacker_final_attack = true;
    private bool m_defender_final_attack = true;
};
