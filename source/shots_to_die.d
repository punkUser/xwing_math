import simulation2;
import simulation_setup2;
import simulation_state2;
import simulation_results;
import defense_form;
import attack_form;
import form;
import log;
import attack_preset_form;

import std.stdio;
import std.algorithm;
import std.container.array;
import std.datetime;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.array;

public struct ShotsToDieResult
{
    string label;
    double mean_shots_to_die;
    bool converged;                             // If false, mean_shots_to_die is an approximate lower bound
    bool precomputed;
    immutable(double)[] shots_cdf;              // NOTE: Not filled if precomputed = true
};

ShotsToDieResult simulate_shots_to_die(ref const(AttackPresetForm) attack_form,
                                       ref const(DefenseForm) defense_form,
                                       bool precomputed = false,
                                       string label = "")
{
    TokenState attack_tokens = to_attack_tokens2(attack_form);
    TokenState defense_tokens = to_defense_tokens2(defense_form);
    SimulationSetup setup = to_simulation_setup(attack_form, defense_form);

    // Set up the initial state
    auto states = new SimulationStateSet();
    SimulationState initial_state = SimulationState.init;
    initial_state.defense_tokens  = defense_tokens;
    initial_state.probability     = 1.0;
    states.push_back(initial_state);
    
    immutable int ship_health = defense_form.ship_hull + defense_form.ship_shields;
    
    double remaining_p = 1.0;
    double mean_shots_to_die_sum = 0.0;
    double mean_shots_to_die = 0.0;
    bool converged = false;

    immutable max_shots = 200;
    double[max_shots] cdf;
    cdf[0] = 0.0;

    int shots_to_die = 1;
    for (; shots_to_die < max_shots; ++shots_to_die)
    {
        states.replace_attack_tokens(attack_tokens);
        // NOTE: Can't just do this here right now as stuff like Iden is mixed into
        // tokens and we don't want to refresh that every attack!
        //states.replace_defense_tokens(defense_tokens);
        states = simulate_attack(setup, states);

        double removed_p = states.remove_if_total_hits_ge(ship_health);
        remaining_p -= removed_p;
        cdf[shots_to_die] = cdf[shots_to_die - 1] + removed_p;

        mean_shots_to_die_sum += cast(double)shots_to_die * removed_p;
        // Predict remaining tail (underestimate by design)
        mean_shots_to_die = mean_shots_to_die_sum + cast(double)(shots_to_die + 1) * remaining_p;

        //writefln("%s: %s states, mean_shots_to_die = %s, remaining_p = %s",
        //         shots_to_die, states.length(), mean_shots_to_die, remaining_p);

        // Termination conditions
        if (states.empty() || remaining_p < 1e-6)
        {
            converged = true;
            break;
        }
        if (mean_shots_to_die > 50.0)
        {
            mean_shots_to_die = 50.0;
            converged = false;
            break;
        }
    }

    //writefln("mean_shots_to_die: %s shots%s", mean_shots_to_die, converged ? "" : " (didn't converge)");

    ShotsToDieResult result;
    result.label = label;
    result.mean_shots_to_die = mean_shots_to_die;
    result.converged = converged;
    result.precomputed = precomputed;

    // TODO: Consider clipping the PDF tail more than we do for computation of the mean (for UI, etc)
    if (!precomputed)
        result.shots_cdf = cdf[0..shots_to_die].idup;

    return result;
}

private ShotsToDieResult precompute_result(ref const(AttackPresetForm) attack_form, string label, string defense_form_url)
{
    auto defense_form = create_form_from_url!DefenseForm(defense_form_url);
    auto result = simulate_shots_to_die(attack_form, defense_form, true, label);
    return result;
}

private struct PrecomputedShotsToDieResults
{
    immutable(ShotsToDieResult)[] results;
}

public PrecomputedShotsToDieResults precompute_shots_to_die(ref const(AttackPresetForm) attack_form)
{
    auto results = appender!(ShotsToDieResult[])();
    results ~= precompute_result(attack_form, "RZ-1 A-Wing",                    "AwAAAAAAgBA");
    results ~= precompute_result(attack_form, "B-Wing",                         "AQAAAAAAACE");
    results ~= precompute_result(attack_form, "T-65 X-Wing",                    "AgAAAAAAABE");
    results ~= precompute_result(attack_form, "TIE/ln Fighter",                 "AwAAAAAAwAA");
    results ~= precompute_result(attack_form, "TIE Advanced x1",                "AwAAAAAAwBA");
    results ~= precompute_result(attack_form, "Alpha-Class Star Wing",          "AgAAAAAAABk");
    results ~= precompute_result(attack_form, "VT-49 Decimator",                "AAAAAAAAACM");
    results ~= precompute_result(attack_form, "VT-49 Decimator w/ Reinforce",   "AAABAAAAACM");
    results ~= precompute_result(attack_form, "Firespray",                      "AgAAAAAAgCE");
    results ~= precompute_result(attack_form, "Aggressor (Scum)",               "AwAAAAAAACE");
    results ~= precompute_result(attack_form, "YV-666",                         "AQAAAAAAQBo");
    results ~= precompute_result(attack_form, "YV-666 w/ Reinforce",            "AQABAAAAQBo");
    results ~= precompute_result(attack_form, "TIE Striker",                    "AgAAAAAAAAE");
    results ~= precompute_result(attack_form, "E-Wing",                         "AwAAAAAAwBg");
    results ~= precompute_result(attack_form, "K-Wing",                         "AQAAAAAAgBk");
    results ~= precompute_result(attack_form, "HWK-290",                        "AgAAAAAAwBA");
    results ~= precompute_result(attack_form, "JumpMaster 5000",                "AgAAAAAAgBk");
    results ~= precompute_result(attack_form, "Scurrg H-6 Bomber",              "AQAAAAAAgCE");
    results ~= precompute_result(attack_form, "U-Wing",                         "AgAAAAAAQBk");
    results ~= precompute_result(attack_form, "YT-1300 (Rebel)",                "AQAAAAAAACo");
    results ~= precompute_result(attack_form, "YT-1300 (Scum)",                 "AQAAAAAAABo");
    
    //results ~= precompute_result(attacker, "TIE/D Defender",                "AwAAAAAAwCA");   // People might get confused about evade tokens...
    //results ~= precompute_result(attacker, "TIE Bomber",                    "AgAAAAAAgAE");   // Same as T-65 X-Wing w/o crits
    //results ~= precompute_result(attacker, "StarViper",                     "AwAAAAAAAAk");   // Same as TIE Advanced x1 w/o crits
    //results ~= precompute_result(attack_form, "TIE Reaper",                 "AQAAAAAAgBE");   // Same as B-Wing w/o crits
    //results ~= precompute_result(attack_form, "Sheathipede-Class Shuttle",  "AgAAAAAAAAk");   // Same as HWK-290 w/o crits

    PrecomputedShotsToDieResults r;
    r.results = results.data.idup;
    return r;
}

public class ShotsToDiePrecomputed
{
    public this()
    {
    }

    // Simulate a new case and return the full list including precomputed comparisons, sorted appropriately
    // If this case has not yet been precomputed, compute it and memoize
    ShotsToDieResult[] simulate(const(AttackPresetForm) attack_form, const(DefenseForm) defense_form)
    {
        string url = serialize_form_to_url(attack_form);

        if (attack_form !in m_results)
        {
            auto sw = StopWatch(AutoStart.yes);
            log_message("Precomputing shots to die for %s...", url);
            auto result = precompute_shots_to_die(attack_form);     // NOTE: BLOCKS/FIBER SWITCH POSSIBLE
            log_message("Done precomputing in %s ms", sw.peek().total!"msecs");
            m_results[attack_form] = result;
        }

        auto result = m_results[attack_form].results.dup;
        result ~= simulate_shots_to_die(attack_form, defense_form, false, "Your Ship");
        sort!((a, b) => a.mean_shots_to_die < b.mean_shots_to_die)(result);

        return result;
    }

    // Regular warnings on mutable state here... be careful around any points that can block!
    private PrecomputedShotsToDieResults[AttackPresetForm] m_results;
};
